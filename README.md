# Guidance for Deploying a PoC for Amazon S3 Tables

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Cost](#cost)
4. [Prerequisites](#prerequisites)
5. [Deployment Steps](#deployment-steps)
6. [PoC Methodology and Success Criteria](#poc-methodology-and-success-criteria)
7. [Test Scenarios](#test-scenarios)
8. [SME Guidance](#sme-guidance)
9. [Cleanup](#cleanup)
10. [Notices](#notices)

---

## Overview

### Business Case

Customers evaluating Amazon S3 Tables for analytics workloads face a common challenge: there's no quick, standardized way to deploy a working environment and validate the service against their requirements. Without guidance, customers often misconfigure PoC environments, spend weeks on setup instead of testing, miss key evaluation dimensions, and draw incorrect conclusions from poorly configured evaluations.

This PoC guide solves these problems by:

- **Accelerating time-to-decision** — reduces PoC setup from weeks to hours with a CloudFormation template and step-by-step tested instructions
- **Improving PoC outcomes** — ensures customers evaluate S3 Tables in an optimally configured environment, leading to fair evaluations
- **Reducing AWS engagement overhead** — customers can self-serve the PoC without requiring specialist involvement for setup and configuration
- **Enabling informed architectural decisions** — includes SME guidance comparing S3 Tables vs self-managed Iceberg with a decision framework

### What This Guidance Deploys

This Guidance helps users deploy and configure an optimal proof-of-concept environment for **Amazon S3 Tables**. Amazon S3 Tables deliver the first cloud object store with built-in Apache Iceberg support, providing a fully managed, Iceberg-native storage layer optimized for analytics workloads. S3 Tables automatically handle table maintenance operations such as compaction, snapshot management, and unreferenced file removal — delivering up to 3x faster query performance and up to 10x more transactions per second compared to self-managed Iceberg tables.

Using this Guidance, you can quickly deploy a PoC environment that allows you to:

- Create and manage S3 table buckets and namespaces
- Ingest data into Apache Iceberg tables on S3 Tables
- Query tables using Amazon Athena (via AWS Glue Data Catalog) and Apache Spark (via S3 Tables Iceberg REST endpoint)
- Evaluate automated table maintenance (compaction, snapshot expiry, unreferenced file removal)
- Test compaction strategies (binpack default, sort, z-order)
- Evaluate Intelligent-Tiering for cost optimization on mixed-access-pattern tables

### Target Use Cases

- Data lake analytics with Apache Iceberg
- Streaming and batch data ingestion and analytics
- Data warehouse offloading to open table formats
- Multi-engine analytics (Athena, Spark, EMR Serverless)

### AWS Services Deployed

| Service | Purpose |
|---|---|
| Amazon S3 Tables | Managed Iceberg table storage |
| Amazon Athena | Serverless SQL query engine |
| AWS Glue Data Catalog | Metadata catalog for Athena table discovery |
| Amazon EC2 | Access point for Spark-based testing |
| Amazon VPC | Isolated network environment |
| AWS IAM | Identity and access management |

---

## Architecture

![S3 Tables PoC Architecture Diagram](assets/images/s3tablespoc-architecture-diagram.drawio.png)

The CloudFormation template deploys the following architecture:

1. An EC2 instance is deployed in a **private subnet** with no public IP. Access is via AWS Systems Manager Session Manager.
2. A **NAT Gateway** provides outbound internet access for package downloads (Spark, Iceberg runtime). AWS service traffic uses **VPC endpoints** for private connectivity (S3, S3 Tables, SSM, Glue, Athena).
3. An S3 table bucket is created with a default namespace for organizing Iceberg tables.
4. The table bucket is integrated with **AWS Glue Data Catalog** (via the `s3tablescatalog` federated catalog) for Athena access. Access is controlled by **IAM policies** — no Lake Formation grants required.
5. **Spark** connects directly to S3 Tables via the **Iceberg REST endpoint** (`https://s3tables.<region>.amazonaws.com/iceberg`), authenticated with SigV4. No custom JARs required.
6. Amazon Athena is configured with a dedicated workgroup and S3 results bucket for serverless SQL queries.
7. IAM roles provide least-privilege access to S3 Tables, Glue, and Athena.

---

## Cost

Estimated daily cost for the default configuration (US East, April 2026 pricing):

| Resource | Daily Cost (USD) |
|---|---|
| EC2 (t3.xlarge, on-demand) | ~$4.00 |
| NAT Gateway (fixed + data) | ~$1.10 |
| VPC Interface Endpoints (×6) | ~$1.73 |
| S3 Tables (storage + requests) | ~$0.10 |
| Athena (queries) | ~$0.05 |
| S3 (Athena results bucket) | ~$0.01 |
| **Total** | **~$7.00/day** |

> **Tip**: Stop the EC2 instance when not testing to reduce costs. VPC endpoints and NAT Gateway continue to incur charges while the stack exists.

---

## Prerequisites

### Required Permissions

The IAM principal deploying this stack needs:

- `cloudformation:*` (stack operations)
- `ec2:*` (VPC, subnets, endpoints, instances)
- `iam:CreateRole`, `iam:PutRolePolicy`, `iam:CreateInstanceProfile`, `iam:PassRole`
- `s3:CreateBucket`, `s3:PutBucketEncryption`, `s3:PutBucketPublicAccessBlock`
- `s3tables:CreateTableBucket`
- `glue:CreateCatalog`, `glue:PassConnection`
- `athena:CreateWorkGroup`

### Tools Required

- AWS CLI v2 (latest)
- AWS Systems Manager Session Manager plugin ([install guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html))

### Supported Regions

S3 Tables is available in 35 regions. Deploy the stack in any region where S3 Tables is supported. See [S3 Tables Regions and endpoints](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-tables-regions-quotas.html#s3-tables-regions) for the full list.

---

## Deployment Steps

### Step 1: Deploy the CloudFormation Stack

```bash
# Set your target region
export AWS_REGION="us-east-1"

# Deploy the stack
aws cloudformation deploy \
  --template-file s3-tables-poc.yaml \
  --stack-name s3-tables-poc \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $AWS_REGION
```

<!-- TEST: Verify stack reaches CREATE_COMPLETE -->

### Step 2: Capture Stack Outputs

```bash
# Get all outputs into environment variables
eval $(aws cloudformation describe-stacks \
  --stack-name s3-tables-poc \
  --region $AWS_REGION \
  --query 'Stacks[0].Outputs[].{k:OutputKey,v:OutputValue}' \
  --output text | awk '{print $1"=\""$2"\""}')

# Verify key outputs
echo "Instance ID: $EC2InstanceId"
echo "Table Bucket ARN: $TableBucketARN"
echo "Table Bucket Name: $TableBucketName"
echo "Athena Workgroup: $AthenaWorkgroupName"
echo "Region: $Region"
```

<!-- TEST: All 8 outputs should be non-empty -->

### Step 3: Integrate Table Bucket with AWS Glue Data Catalog

This creates the `s3tablescatalog` federated catalog so Athena can discover your tables. Access is controlled by IAM — no Lake Formation grants required.

```bash
# Create the catalog integration JSON
cat > /tmp/catalog.json << EOF
{
  "Name": "s3tablescatalog",
  "CatalogInput": {
    "FederatedCatalog": {
      "Identifier": "arn:aws:s3tables:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):bucket/*",
      "ConnectionName": "aws:s3tables"
    },
    "CreateDatabaseDefaultPermissions": [
      {
        "Principal": {
          "DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"
        },
        "Permissions": ["ALL"]
      }
    ],
    "CreateTableDefaultPermissions": [
      {
        "Principal": {
          "DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS"
        },
        "Permissions": ["ALL"]
      }
    ],
    "AllowFullTableExternalDataAccess": "True"
  }
}
EOF

# Create the federated catalog
aws glue create-catalog \
  --region $AWS_REGION \
  --cli-input-json file:///tmp/catalog.json

# Verify
aws glue get-catalog --catalog-id s3tablescatalog --region $AWS_REGION
```

<!-- TEST: get-catalog returns the s3tablescatalog with FederatedCatalog populated -->

### Step 4: Create a Namespace

```bash
aws s3tables create-namespace \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data \
  --region $AWS_REGION
```

<!-- TEST: Verify namespace exists -->
```bash
aws s3tables list-namespaces \
  --table-bucket-arn $TableBucketARN \
  --region $AWS_REGION
```

### Step 5: Connect to the EC2 Instance

```bash
aws ssm start-session \
  --target $EC2InstanceId \
  --region $AWS_REGION
```

<!-- TEST: Session opens successfully, prompt appears -->

### Step 6: Create Your First Table via Athena

```bash
# From your local machine (not the EC2 instance)
aws athena start-query-execution \
  --query-string "CREATE TABLE s3tablescatalog.\"${TableBucketName}\".poc_data.test_table (
    id INT,
    name STRING,
    created_at TIMESTAMP
  ) TBLPROPERTIES ('table_type' = 'ICEBERG')" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Query succeeds, table visible in Glue catalog -->
```bash
aws athena start-query-execution \
  --query-string "SELECT * FROM s3tablescatalog.\"${TableBucketName}\".poc_data.test_table LIMIT 1" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

---

## PoC Methodology and Success Criteria

### Evaluation Dimensions

| Dimension | Success Criteria | Scenario |
|---|---|---|
| **Table CRUD** | Create, insert, query, update, delete operations succeed | 1 |
| **Schema Evolution** | Add columns without rewriting data; NULLs backfill correctly | 2 |
| **Automated Compaction** | Small files consolidated automatically; CloudWatch metrics confirm | 3 |
| **Snapshot Management** | Snapshots expire per policy; unreferenced files removed | 3b |
| **Compaction Strategies** | Binpack (default), sort, z-order configurable and observable | 3c |
| **Intelligent-Tiering** | Storage class transitions observable; cost savings projected | 3d |
| **Multi-Engine Access** | Athena and Spark read/write the same tables consistently | 4 |
| **Time Travel** | Query historical snapshots successfully | 1 |
| **Partition Evolution** | Change partitioning without rewriting data | 2 |
| **IAM Access Control** | Permissions enforced at table bucket and table level | All |
| **Query Performance** | Queries return in acceptable time for PoC data volumes | All |
| **Cost Visibility** | CloudWatch metrics provide cost and usage visibility | 3, 3d |

---

## Test Scenarios

### Scenario 1: Basic Table Operations (Athena)

**Objective**: Validate CRUD operations and time travel via Athena.

#### 1a. Insert Data

```bash
aws athena start-query-execution \
  --query-string "INSERT INTO s3tablescatalog.\"${TableBucketName}\".poc_data.test_table VALUES
    (1, 'Alice', current_timestamp),
    (2, 'Bob', current_timestamp),
    (3, 'Charlie', current_timestamp)" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Query state = SUCCEEDED -->

#### 1b. Query Data

```bash
aws athena start-query-execution \
  --query-string "SELECT * FROM s3tablescatalog.\"${TableBucketName}\".poc_data.test_table ORDER BY id" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Returns 3 rows -->

#### 1c. Update Data

```bash
aws athena start-query-execution \
  --query-string "UPDATE s3tablescatalog.\"${TableBucketName}\".poc_data.test_table
    SET name = 'Alice Updated' WHERE id = 1" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Query state = SUCCEEDED, subsequent SELECT shows updated value -->

#### 1d. Delete Data

```bash
aws athena start-query-execution \
  --query-string "DELETE FROM s3tablescatalog.\"${TableBucketName}\".poc_data.test_table WHERE id = 3" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Query state = SUCCEEDED, subsequent SELECT returns 2 rows -->

#### 1e. Time Travel

```bash
# List snapshots to find a previous snapshot ID
aws s3tables get-table \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data \
  --name test_table \
  --region $AWS_REGION
```

```bash
# Query a historical snapshot (replace SNAPSHOT_ID)
aws athena start-query-execution \
  --query-string "SELECT * FROM s3tablescatalog.\"${TableBucketName}\".poc_data.test_table
    FOR SYSTEM_TIME AS OF TIMESTAMP '<snapshot_timestamp>'" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Returns data as it existed at the specified snapshot -->

### Scenario 2: Schema Evolution and Partition Evolution

**Objective**: Validate schema changes and partition evolution without data rewrites.

#### 2a. Add Columns

```bash
aws athena start-query-execution \
  --query-string "ALTER TABLE s3tablescatalog.\"${TableBucketName}\".poc_data.test_table
    ADD COLUMNS (email STRING, department STRING)" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Query state = SUCCEEDED -->

#### 2b. Insert with New Schema

```bash
aws athena start-query-execution \
  --query-string "INSERT INTO s3tablescatalog.\"${TableBucketName}\".poc_data.test_table VALUES
    (4, 'Diana', current_timestamp, 'diana@example.com', 'Engineering')" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Query state = SUCCEEDED -->

#### 2c. Verify NULL Backfill

```bash
aws athena start-query-execution \
  --query-string "SELECT id, name, email, department FROM s3tablescatalog.\"${TableBucketName}\".poc_data.test_table ORDER BY id" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Rows 1-2 show NULL for email and department; row 4 shows values -->

#### 2d. Partition Evolution

```bash
# Create a partitioned table
aws athena start-query-execution \
  --query-string "CREATE TABLE s3tablescatalog.\"${TableBucketName}\".poc_data.events (
    event_id BIGINT,
    event_type STRING,
    event_time TIMESTAMP,
    payload STRING
  ) PARTITIONED BY (day(event_time))
  TBLPROPERTIES ('table_type' = 'ICEBERG')" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Table created with day-level partitioning -->

### Scenario 3: Automated Table Maintenance

**Objective**: Observe S3 Tables automated compaction, snapshot management, and unreferenced file removal.

#### 3a. Generate Small Files (Compaction Target)

```bash
# Insert data in multiple small batches to create small files
for i in $(seq 1 10); do
  aws athena start-query-execution \
    --query-string "INSERT INTO s3tablescatalog.\"${TableBucketName}\".poc_data.events VALUES
      ($((i*100+1)), 'click', current_timestamp, 'payload_${i}_a'),
      ($((i*100+2)), 'view', current_timestamp, 'payload_${i}_b'),
      ($((i*100+3)), 'purchase', current_timestamp, 'payload_${i}_c')" \
    --work-group $AthenaWorkgroupName \
    --region $AWS_REGION
  sleep 2
done
```

<!-- TEST: 10 separate INSERT operations complete successfully -->

#### 3b. Monitor Table Metadata (Pre-Compaction)

```bash
aws s3tables get-table-metadata-location \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data \
  --name events \
  --region $AWS_REGION
```

<!-- TEST: Note the number of data files before compaction runs -->

#### 3c. Observe Compaction via CloudWatch

S3 Tables automatically compacts small files using the **binpack** strategy by default. Monitor compaction activity:

```bash
# Check compaction metrics (allow 15-30 minutes for first compaction cycle)
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3Tables \
  --metric-name CompactionBytesCompacted \
  --dimensions Name=TableBucketName,Value=$TableBucketName Name=Namespace,Value=poc_data Name=TableName,Value=events \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region $AWS_REGION
```

<!-- TEST: After compaction runs, CompactionBytesCompacted > 0 -->

#### 3d. Configure Snapshot Management

```bash
# Set snapshot retention policy
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data \
  --name events \
  --type icebergSnapshotManagement \
  --value '{"status":"enabled","settings":{"icebergSnapshotManagement":{"minSnapshotsToKeep":3,"maxSnapshotAgeHours":72}}}' \
  --region $AWS_REGION
```

<!-- TEST: Configuration accepted without error -->

#### 3e. Configure Unreferenced File Removal

```bash
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data \
  --name events \
  --type icebergUnreferencedFileRemoval \
  --value '{"status":"enabled","settings":{"icebergUnreferencedFileRemoval":{"unreferencedDays":3}}}' \
  --region $AWS_REGION
```

<!-- TEST: Configuration accepted without error -->

#### 3f. Verify Maintenance Configuration

```bash
aws s3tables get-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data \
  --name events \
  --region $AWS_REGION
```

<!-- TEST: Shows compaction (enabled, binpack), snapshot management, and unreferenced file removal configs -->

#### 3g. Configure Sort Compaction (Advanced)

After observing binpack compaction, you can optionally configure sort or z-order compaction for tables with predictable query patterns:

```bash
# Configure sort compaction on a specific column
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data \
  --name events \
  --type icebergCompaction \
  --value '{"status":"enabled","settings":{"icebergCompaction":{"targetFileSizeMB":512,"strategy":"sort","sortOrder":[{"columnName":"event_time","order":"desc"}]}}}' \
  --region $AWS_REGION
```

<!-- TEST: Configuration accepted without error -->

> **Note**: Start with binpack (the default). Only configure sort or z-order compaction after you understand your query access patterns. Sort compaction rewrites data files to physically arrange records by the specified columns, enabling more efficient data skipping. Z-order is useful when queries filter on multiple columns.

#### 3h. Enable Intelligent-Tiering

S3 Tables support the Intelligent-Tiering storage class, which automatically moves data between cost-effective access tiers based on access patterns — without retrieval fees or performance impact.

```bash
# Enable Intelligent-Tiering as the default storage class for the table bucket
# NOTE: Intelligent-Tiering must be specified at table creation or set as the bucket default.
# Existing tables in S3 Standard cannot be moved to Intelligent-Tiering.

# Check current table bucket configuration
aws s3tables get-table-bucket \
  --table-bucket-arn $TableBucketARN \
  --region $AWS_REGION
```

<!-- TEST: Returns table bucket configuration -->

To test Intelligent-Tiering, create a new table with the storage class specified:

```bash
aws athena start-query-execution \
  --query-string "CREATE TABLE s3tablescatalog.\"${TableBucketName}\".poc_data.tiering_test (
    id BIGINT,
    data STRING,
    created_at TIMESTAMP
  ) TBLPROPERTIES (
    'table_type' = 'ICEBERG',
    'write.object-storage.enabled' = 'true'
  )" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TODO: Verify exact TBLPROPERTIES syntax for enabling IT on table creation -->

**How Intelligent-Tiering works with S3 Tables:**

| Tier | Transition | Latency |
|---|---|---|
| Frequent Access (FA) | Default for all new files | Milliseconds |
| Infrequent Access (IA) | After 30 days without access | Milliseconds |
| Archive Instant Access (AIA) | After 90 days without access | Milliseconds |

Key behaviors:
- Compaction only processes files in the **Frequent Access** tier — cold data is not promoted unnecessarily
- Snapshot management and unreferenced file removal run across **all tiers**
- Files smaller than 128 KB remain in FA (compaction can combine them into tiering-eligible sizes)
- When cold data is accessed, it returns to FA and becomes eligible for compaction

<!-- TEST: After 30+ days, verify storage class transitions via CloudWatch metrics -->

### Scenario 4: Multi-Engine Access (Athena + Spark)

**Objective**: Validate that Athena and Spark can read/write the same tables consistently using their respective access paths.

- **Athena** → AWS Glue Data Catalog (`s3tablescatalog`) → IAM authorization
- **Spark** → S3 Tables Iceberg REST endpoint → SigV4 (`s3tables` signing name) → IAM authorization

#### 4a. Start Spark on the EC2 Instance

Connect to the EC2 instance via SSM (Step 5), then launch Spark with the Iceberg REST catalog configuration:

```bash
# Set environment variables (on the EC2 instance)
export AWS_REGION=$(TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") && curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export TABLE_BUCKET_ARN="arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/${TABLE_BUCKET_NAME}"

# Launch spark-shell with Iceberg REST catalog pointing to S3 Tables endpoint
spark-shell \
  --packages "org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.7.1,software.amazon.awssdk:bundle:2.29.38,software.amazon.awssdk:url-connection-client:2.29.38" \
  --conf "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions" \
  --conf "spark.sql.defaultCatalog=s3tables" \
  --conf "spark.sql.catalog.s3tables=org.apache.iceberg.spark.SparkCatalog" \
  --conf "spark.sql.catalog.s3tables.type=rest" \
  --conf "spark.sql.catalog.s3tables.uri=https://s3tables.${AWS_REGION}.amazonaws.com/iceberg" \
  --conf "spark.sql.catalog.s3tables.warehouse=${TABLE_BUCKET_ARN}" \
  --conf "spark.sql.catalog.s3tables.rest.sigv4-enabled=true" \
  --conf "spark.sql.catalog.s3tables.rest.signing-name=s3tables" \
  --conf "spark.sql.catalog.s3tables.rest.signing-region=${AWS_REGION}" \
  --conf "spark.sql.catalog.s3tables.io-impl=org.apache.iceberg.aws.s3.S3FileIO" \
  --conf "spark.sql.catalog.s3tables.rest-metrics-reporting-enabled=false"
```

<!-- TEST: Spark shell starts without errors, catalog initializes successfully -->

#### 4b. Read Athena-Created Table from Spark

```scala
// Read the table created by Athena in Scenario 1
spark.sql("SELECT * FROM s3tables.poc_data.test_table ORDER BY id").show()
```

<!-- TEST: Returns same rows as Athena query (2 rows after delete in 1d) -->

#### 4c. Write Data from Spark

```scala
// Insert rows from Spark
spark.sql("""
  INSERT INTO s3tables.poc_data.test_table VALUES
    (5, 'Eve', current_timestamp(), 'eve@example.com', 'Data Science'),
    (6, 'Frank', current_timestamp(), 'frank@example.com', 'Platform')
""")
```

<!-- TEST: Insert succeeds without error -->

#### 4d. Verify Spark Writes from Athena

```bash
# Back on your local machine
aws athena start-query-execution \
  --query-string "SELECT * FROM s3tablescatalog.\"${TableBucketName}\".poc_data.test_table ORDER BY id" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Returns 4 rows (2 original + 2 from Spark), confirming cross-engine consistency -->

#### 4e. Create a Table from Spark

```scala
// Create a new table entirely from Spark
spark.sql("""
  CREATE TABLE s3tables.poc_data.spark_table (
    sensor_id BIGINT,
    reading DOUBLE,
    recorded_at TIMESTAMP
  ) USING iceberg
""")

// Insert data
spark.sql("""
  INSERT INTO s3tables.poc_data.spark_table VALUES
    (1, 23.5, current_timestamp()),
    (2, 18.7, current_timestamp()),
    (3, 31.2, current_timestamp())
""")
```

<!-- TEST: Table created and data inserted successfully -->

#### 4f. Verify Spark-Created Table from Athena

```bash
aws athena start-query-execution \
  --query-string "SELECT * FROM s3tablescatalog.\"${TableBucketName}\".poc_data.spark_table ORDER BY sensor_id" \
  --work-group $AthenaWorkgroupName \
  --region $AWS_REGION
```

<!-- TEST: Returns 3 rows, confirming Spark-created tables are visible to Athena -->

---

## SME Guidance

### Namespace Organization

Use **namespaces** to logically separate tables within a single table bucket. For example:
- `raw_data` — landing zone for ingested data
- `curated` — cleaned and transformed tables
- `analytics` — aggregated tables for dashboards

Namespaces provide logical isolation without the overhead of managing multiple table buckets.

### Compaction Strategy

S3 Tables automatically compact small files. The default strategy is **auto**, which selects the best approach based on your table's sort order:

| Strategy | When to use |
|---|---|
| **Auto (default)** | Let S3 Tables choose — uses sort compaction if table has a sort order, otherwise binpack |
| **Binpack** | General-purpose; consolidates small files into larger ones without reordering |
| **Sort** | Tables with predictable single-column query filters (e.g., always filter by `event_time`) |
| **Z-order** | Tables queried with filters on multiple columns (e.g., `region` AND `event_type`) |

Start with the default (auto/binpack). Only configure sort or z-order after you understand your query access patterns and have observed binpack behavior.

### Snapshot and File Lifecycle

Configure these three maintenance operations together for complete lifecycle management:

1. **Compaction** — consolidates small files (enabled by default)
2. **Snapshot management** — expires old snapshots based on age and count retention
3. **Unreferenced file removal** — permanently deletes data files no longer referenced by any snapshot

Recommended starting configuration:
- `minSnapshotsToKeep`: 3–5 (balance time travel needs vs storage)
- `maxSnapshotAgeHours`: 72–168 (3–7 days for PoC)
- `unreferencedDays`: 3 (remove orphaned files after 3 days)

### Intelligent-Tiering Optimization

Key behaviors to understand:
- Intelligent-Tiering must be specified at **table creation** or set as the **bucket default** — existing S3 Standard tables cannot be converted
- Compaction only processes files in the **Frequent Access** tier — cold data is not promoted
- Snapshot management and unreferenced file removal run across **all tiers**
- Files smaller than 128 KB remain in FA; compaction can combine them into tiering-eligible sizes
- Delete files on cold data accumulate until the data is accessed and returns to FA

For long-lived tables with mixed access patterns (recent data queried frequently, historical data rarely), Intelligent-Tiering provides automatic cost optimization without performance impact.

### Security Best Practices

**IAM resource-based policies** are the primary access control mechanism for S3 Tables:

- Use IAM identity policies on the EC2 role (or user/role) to grant `s3tables:*` actions
- Scope permissions to specific table bucket ARNs where possible
- For Athena access, IAM policies on Glue catalog resources control who can query which tables
- The `s3tablescatalog` with `IAM_ALLOWED_PRINCIPALS` delegates authorization entirely to IAM

For production environments requiring fine-grained access control (e.g., different teams accessing different namespaces), consider adding **Lake Formation** grants on top of IAM. Lake Formation is optional for this PoC.

### When to Use S3 Tables vs. Self-Managed Iceberg

<!-- TODO: Review against internal FAQ -->

| Dimension | S3 Tables | Self-Managed Iceberg |
|---|---|---|
| **Table maintenance** | Fully automated (compaction, snapshots, file cleanup) | You manage — custom jobs, scheduling, monitoring |
| **Catalog** | Built-in via Glue Data Catalog integration | You deploy and manage (Glue, Hive, Nessie, etc.) |
| **Storage optimization** | Intelligent-Tiering built-in | You implement lifecycle policies manually |
| **Multi-engine access** | Athena, Spark, EMR via standard endpoints | Depends on your catalog implementation |
| **Operational overhead** | Minimal — managed service | Significant — compaction jobs, catalog ops, monitoring |
| **Customization** | Configurable strategies within service boundaries | Full control over every parameter |
| **Cost model** | Per-request + storage (no infrastructure to manage) | Infrastructure costs + operational labor |

**Choose S3 Tables when**: You want managed table maintenance, your team lacks Iceberg operational expertise, or you want to reduce undifferentiated heavy lifting.

**Choose self-managed when**: You need capabilities not yet supported by S3 Tables, require a specific catalog implementation, or have existing Iceberg infrastructure with established operational practices.

---

## Cleanup

### Step 1: Delete Tables and Namespaces

```bash
# List and delete all tables in the namespace
for TABLE in $(aws s3tables list-tables --table-bucket-arn $TableBucketARN --namespace poc_data --query 'tables[].name' --output text --region $AWS_REGION); do
  aws s3tables delete-table \
    --table-bucket-arn $TableBucketARN \
    --namespace poc_data \
    --name $TABLE \
    --region $AWS_REGION
done

# Delete the namespace
aws s3tables delete-namespace \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data \
  --region $AWS_REGION
```

### Step 2: Delete the Federated Catalog

```bash
aws glue delete-catalog \
  --catalog-id s3tablescatalog \
  --region $AWS_REGION
```

### Step 3: Empty the Athena Results Bucket

```bash
aws s3 rm s3://${AthenaResultsBucketName} --recursive --region $AWS_REGION
```

### Step 4: Delete the CloudFormation Stack

```bash
aws cloudformation delete-stack \
  --stack-name s3-tables-poc \
  --region $AWS_REGION

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete \
  --stack-name s3-tables-poc \
  --region $AWS_REGION
```

<!-- TEST: Stack reaches DELETE_COMPLETE, all resources removed -->

---

## Notices

*Customers are responsible for making their own independent assessment of the information in this Guidance. This Guidance: (a) is for informational purposes only, (b) represents AWS current product offerings and practices, which are subject to change without notice, and (c) does not create any commitments or assurances from AWS and its affiliates, suppliers or licensors. AWS products or services are provided "as is" without warranties, representations, or conditions of any kind, whether express or implied. AWS responsibilities and liabilities to its customers are controlled by AWS agreements, and this Guidance is not part of, nor does it modify, any agreement between AWS and its customers.*
