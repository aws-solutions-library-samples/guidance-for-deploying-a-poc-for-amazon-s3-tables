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

This Guidance helps users deploy and configure an optimal proof-of-concept (PoC) environment for **Amazon S3 Tables**. Amazon S3 Tables deliver the first cloud object store with built-in Apache Iceberg support, providing a fully managed, Iceberg-native storage layer optimized for analytics workloads. S3 Tables automatically handle table maintenance operations such as compaction, snapshot management, and unreferenced file removal — delivering up to 3x faster query performance and up to 10x more transactions per second compared to self-managed Iceberg tables.

Using this Guidance, you can quickly deploy a PoC environment that allows you to:

- Create and manage S3 table buckets and namespaces
- Ingest data into Apache Iceberg tables (V2 and V3) on S3 Tables
- Query tables using Amazon Athena, Amazon EMR, or Apache Spark
- Evaluate automated table maintenance (compaction, snapshot expiry, unreferenced file removal, record expiration)
- Test sort order and z-order compaction strategies
- Test integration with AWS analytics services via Amazon SageMaker Lakehouse
- Evaluate Intelligent-Tiering for cost optimization on mixed-access-pattern tables

### Target Use Cases

- Data lake analytics with Apache Iceberg
- Streaming data ingestion and analytics
- Data warehouse offloading to open table formats
- Multi-engine analytics (Athena, Redshift, EMR, Spark)

### AWS Services Deployed

| Service | Purpose |
|---|---|
| Amazon S3 Tables | Managed Iceberg table storage |
| Amazon Athena | Serverless SQL query engine |
| AWS Glue Data Catalog | Metadata catalog for table discovery |
| AWS Lake Formation | Fine-grained access control |
| Amazon EC2 | Access point for Spark-based testing |
| Amazon VPC | Isolated network environment |
| AWS IAM | Identity and access management |

---

## Architecture

The CloudFormation template deploys the following architecture:

```
┌─────────────────────────────────────────────────────────┐
│                        VPC                              │
│  ┌───────────────────────────────────────────────────┐  │
│  │              Public Subnet                        │  │
│  │  ┌─────────────-┐                                 │  │
│  │  │  EC2 Instance│ ◄── Spark / AWS CLI access      │  │
│  │  │  (Test Host) │     point for PoC testing       │  │
│  │  └──────┬─────-─┘                                 │  │
│  └─────────┼─────────────────────────────────────────┘  │
│            │                                            │
└────────────┼────────────────────────────────────────────┘
             │
             ▼
┌────────────────────────┐    ┌──────────────────────────┐
│  Amazon S3 Tables      │◄──►│  AWS Glue Data Catalog   │
│  (Table Bucket)        │    │  (SageMaker Lakehouse    │
│  - Namespace           │    │   Integration)           │
│  - Iceberg Tables      │    └──────────┬───────────────┘
└────────────────────────┘               │
                                         ▼
                              ┌──────────────────────┐
                              │   Amazon Athena      │
                              │   (Query Workgroup)  │
                              └──────────────────────┘
```

1. An EC2 instance is deployed in a public subnet as the primary access point for PoC testing (Spark sessions, AWS CLI operations).
2. An S3 table bucket is created with a default namespace for organizing Iceberg tables.
3. The table bucket is integrated with AWS Glue Data Catalog via SageMaker Lakehouse for unified access.
4. Amazon Athena is configured with a dedicated workgroup and S3 results bucket for serverless SQL queries.
5. IAM roles provide least-privilege access to S3 Tables, Glue, Athena, and Lake Formation.

---

## Cost

You are responsible for the cost of the AWS services used while running this PoC. As of March 2026, the estimated cost for running this PoC in **US East (N. Virginia)** with default settings is approximately **$5–15 per day**, depending on usage patterns.

| Service | Estimated Daily Cost | Notes |
|---|---|---|
| Amazon S3 Tables | ~$0.50–$2.00 | Storage + PUT/GET requests |
| Amazon Athena | ~$0–$5.00 | $5 per TB scanned |
| Amazon EC2 (t3.xlarge) | ~$4.00 | On-demand pricing |
| Amazon EMR (optional) | ~$6.50 | 2x m5.xlarge, only if running Scenario 4b |
| AWS Glue Data Catalog | ~$0.00 | Free tier covers most PoC usage |

> **Tip:** Stop or terminate the EC2 instance when not actively testing to minimize costs.

---

## Prerequisites

- An AWS account with permissions to create IAM roles, VPCs, EC2 instances, S3 table buckets, Athena workgroups, and Glue resources.
- An EC2 key pair in the target Region for SSH access.
- AWS CLI v2 installed locally (for deployment).
- Familiarity with SQL and Apache Iceberg concepts is helpful but not required.

### Supported Regions

As of March 2026, Amazon S3 Tables is available in the following AWS Regions. For the latest availability, see [Amazon S3 Tables endpoints](https://docs.aws.amazon.com/general/latest/gr/s3.html#s3_region).

| Region Name | Region Code |
|---|---|
| US East (N. Virginia) | `us-east-1` |
| US East (Ohio) | `us-east-2` |
| US West (N. California) | `us-west-1` |
| US West (Oregon) | `us-west-2` |
| Africa (Cape Town) | `af-south-1` |
| Asia Pacific (Hong Kong) | `ap-east-1` |
| Asia Pacific (Hyderabad) | `ap-south-2` |
| Asia Pacific (Jakarta) | `ap-southeast-3` |
| Asia Pacific (Malaysia) | `ap-southeast-5` |
| Asia Pacific (Melbourne) | `ap-southeast-4` |
| Asia Pacific (Mumbai) | `ap-south-1` |
| Asia Pacific (Osaka) | `ap-northeast-3` |
| Asia Pacific (Seoul) | `ap-northeast-2` |
| Asia Pacific (Singapore) | `ap-southeast-1` |
| Asia Pacific (Sydney) | `ap-southeast-2` |
| Asia Pacific (Thailand) | `ap-southeast-7` |
| Asia Pacific (Tokyo) | `ap-northeast-1` |
| Canada (Central) | `ca-central-1` |
| Canada West (Calgary) | `ca-west-1` |
| Europe (Frankfurt) | `eu-central-1` |
| Europe (Ireland) | `eu-west-1` |
| Europe (London) | `eu-west-2` |
| Europe (Milan) | `eu-south-1` |
| Europe (Paris) | `eu-west-3` |
| Europe (Spain) | `eu-south-2` |
| Europe (Stockholm) | `eu-north-1` |
| Europe (Zurich) | `eu-central-2` |
| Israel (Tel Aviv) | `il-central-1` |
| Mexico (Central) | `mx-central-1` |
| Middle East (Bahrain) | `me-south-1` |
| Middle East (UAE) | `me-central-1` |
| South America (São Paulo) | `sa-east-1` |
| AWS GovCloud (US-East) | `us-gov-east-1` |
| AWS GovCloud (US-West) | `us-gov-west-1` |

---

## Deployment Steps

### Step 1: Deploy the CloudFormation Stack

Deploy using the AWS CLI:

```bash
aws cloudformation deploy \
  --template-file s3-tables-poc.yaml \
  --stack-name s3-tables-poc \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    KeyPairName=<your-key-pair> \
    AllowedSSHCidr=<your-ip>/32 \
  --region us-east-1
```

Or deploy via the AWS Console:
1. Navigate to **CloudFormation** → **Create stack** → **With new resources**.
2. Upload `s3-tables-poc.yaml`.
3. Provide your EC2 key pair name and SSH CIDR.
4. Acknowledge IAM resource creation and deploy.

### Step 2: Retrieve Stack Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name s3-tables-poc \
  --query "Stacks[0].Outputs" \
  --output table \
  --region us-east-1
```

Key outputs:
- `EC2PublicIP` — SSH access point
- `TableBucketARN` — Your S3 table bucket ARN
- `AthenaWorkgroupName` — Athena workgroup for queries
- `TableBucketName` — Table bucket name

### Step 3: Connect to the EC2 Instance

```bash
ssh -i <your-key>.pem ec2-user@<EC2PublicIP>
```

### Step 4: Create a Table and Insert Data via AWS CLI

From the EC2 instance:

```bash
# List your table bucket
aws s3tables list-table-buckets --region us-east-1

# Create a namespace
aws s3tables create-namespace \
  --table-bucket-arn <TableBucketARN> \
  --namespace poc_data \
  --region us-east-1

# Create a table
aws s3tables create-table \
  --table-bucket-arn <TableBucketARN> \
  --namespace poc_data \
  --name sensor_readings \
  --format ICEBERG \
  --region us-east-1
```

### Step 5: Query Tables with Amazon Athena

1. Open the **Athena** console.
2. Select the workgroup created by the stack (e.g., `s3-tables-poc-workgroup`).
3. In the Data Source panel, select the AWS Glue Data Catalog — your table bucket and namespace should appear.
4. Run queries:

```sql
-- List tables in your namespace
SHOW TABLES IN poc_data;

-- Insert sample data
INSERT INTO poc_data.sensor_readings
VALUES
  (1, 'sensor-a', 23.5, current_timestamp),
  (2, 'sensor-b', 18.2, current_timestamp),
  (3, 'sensor-a', 24.1, current_timestamp);

-- Query data
SELECT * FROM poc_data.sensor_readings
WHERE sensor_id = 'sensor-a';

-- Time travel query (Iceberg snapshot)
SELECT * FROM poc_data.sensor_readings
FOR TIMESTAMP AS OF TIMESTAMP '2026-03-15 00:00:00';
```

### Step 6 (Optional): Query with Spark on EC2

From the EC2 instance, launch a Spark shell connected to your table bucket:

```bash
spark-shell \
  --packages software.amazon.s3tables:s3-tables-catalog-for-iceberg-runtime:0.1.8 \
  --conf spark.sql.catalog.s3tablesbucket=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.s3tablesbucket.catalog-impl=software.amazon.s3tables.iceberg.S3TablesCatalog \
  --conf spark.sql.catalog.s3tablesbucket.warehouse=<TableBucketARN> \
  --conf spark.sql.defaultCatalog=s3tablesbucket \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
```

Then run Spark SQL:

```scala
spark.sql("SHOW NAMESPACES").show()
spark.sql("SHOW TABLES IN poc_data").show()
spark.sql("SELECT * FROM poc_data.sensor_readings").show()
```

---

## PoC Methodology and Success Criteria

Use the following matrix to define and track your PoC success criteria:

| Dimension | Test Area | Success Criteria | Result |
|---|---|---|---|
| **Functionality** | Table CRUD | Create, read, update, delete tables via CLI and SQL | ☐ |
| **Functionality** | Schema evolution | Add/rename columns without rewriting data | ☐ |
| **Functionality** | Time travel | Query historical snapshots | ☐ |
| **Functionality** | Hidden partitioning | Partition evolution without rewriting data | ☐ |
| **Performance** | Query latency | Athena queries return in < X seconds for Y GB dataset | ☐ |
| **Performance** | Compaction | Automated compaction reduces file count after ingestion | ☐ |
| **Performance** | Sort compaction | Sort-order compaction improves filtered query performance | ☐ |
| **Integration** | Athena | Query tables from Athena via Glue catalog | ☐ |
| **Integration** | Spark | Query tables from Spark via S3 Tables catalog | ☐ |
| **Integration** | Firehose | Stream data into tables via Amazon Data Firehose | ☐ |
| **Integration** | Multi-engine | Same data readable from Athena and Spark concurrently | ☐ |
| **Security** | Access control | Lake Formation permissions restrict table access | ☐ |
| **Security** | Table-level policies | IAM resource-based policies on individual tables | ☐ |
| **Cost** | Storage efficiency | Compare storage costs vs. self-managed Iceberg | ☐ |
| **Cost** | Intelligent-Tiering | Verify automatic tiering on infrequently accessed data | ☐ |

---

## Test Scenarios

### Scenario 1: Basic Table Operations

Test creating namespaces, tables, inserting data, and querying via Athena. Validates core functionality.

### Scenario 2: Schema Evolution

```sql
-- Add a new column
ALTER TABLE poc_data.sensor_readings ADD COLUMNS (location STRING);

-- Insert data with new schema
INSERT INTO poc_data.sensor_readings
VALUES (4, 'sensor-c', 19.8, current_timestamp, 'building-a');

-- Query — old rows have NULL for new column
SELECT * FROM poc_data.sensor_readings;
```

### Scenario 3: Automated Table Maintenance

S3 Tables automatically performs compaction, snapshot expiry, and unreferenced file removal. To observe this:

1. Insert data in multiple small batches (creates many small files).
2. Wait for automated compaction (typically runs within hours).
3. Check that file count is reduced and query performance improves.
4. Monitor compaction activity via CloudWatch metrics.

### Scenario 3b: Sort Order Compaction

Define a sort order on a table to enable automatic sort compaction for predictable query patterns:

```sql
-- Create a table with a sort order defined
CREATE TABLE poc_data.sorted_readings (
  id INT,
  sensor_id STRING,
  temperature DOUBLE,
  reading_time TIMESTAMP,
  location STRING
)
USING iceberg
PARTITIONED BY (days(reading_time))
TBLPROPERTIES (
  'write.target-file-size-bytes' = '536870912'
);

-- Insert data — S3 Tables will automatically sort-compact
-- based on the defined sort order
INSERT INTO poc_data.sorted_readings VALUES
  (1, 'sensor-a', 23.5, current_timestamp, 'building-a'),
  (2, 'sensor-b', 18.2, current_timestamp, 'building-b');
```

### Scenario 3c: Intelligent-Tiering

Enable Intelligent-Tiering on a table to automatically reduce storage costs on infrequently accessed data:

- Data not accessed for 30 days moves to Infrequent Access tier (~40% cheaper)
- Data not accessed for 90 days moves to Archive Instant Access tier (~68% cheaper)

This is configured at the table bucket level and is ideal for tables with mixed access patterns.

### Scenario 4: Multi-Engine Access

1. Insert data via Athena.
2. Query the same data via Spark on EC2.
3. Verify data consistency across engines.

### Scenario 4b: Query with Amazon EMR

Test querying S3 Tables from an EMR cluster with Apache Spark.

1. Create an EMR cluster with Iceberg enabled:

```bash
# Create configurations.json
cat > /tmp/configurations.json << 'EOF'
[{
  "Classification": "iceberg-defaults",
  "Properties": {"iceberg.enabled": "true"}
}]
EOF

# Create the cluster
aws emr create-cluster \
  --release-label emr-7.5.0 \
  --applications Name=Spark \
  --configurations file:///tmp/configurations.json \
  --region us-east-1 \
  --name S3-Tables-PoC-Cluster \
  --log-uri s3://<AthenaResultsBucket>/emr-logs/ \
  --instance-type m5.xlarge \
  --instance-count 2 \
  --service-role EMR_DefaultRole \
  --ec2-attributes \
    InstanceProfile=EMR_EC2_DefaultRole,SubnetId=<PublicSubnetId>,KeyName=<your-key-pair>
```

> **Note:** Ensure `EMR_DefaultRole` and `EMR_EC2_DefaultRole` exist in your account. If not, create them with `aws emr create-default-roles`. Attach the `AmazonS3TablesFullAccess` policy to `EMR_EC2_DefaultRole`.

2. SSH into the EMR primary node and launch a Spark shell connected to your table bucket:

```bash
spark-shell \
  --packages software.amazon.s3tables:s3-tables-catalog-for-iceberg-runtime:0.1.8 \
  --conf spark.sql.catalog.s3tablesbucket=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.s3tablesbucket.catalog-impl=software.amazon.s3tables.iceberg.S3TablesCatalog \
  --conf spark.sql.catalog.s3tablesbucket.warehouse=<TableBucketARN> \
  --conf spark.sql.defaultCatalog=s3tablesbucket \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
```

3. Query the same tables you created via Athena:

```scala
spark.sql("SELECT * FROM poc_data.sensor_readings").show()
spark.sql("SELECT sensor_id, avg(temperature) FROM poc_data.sensor_readings GROUP BY sensor_id").show()
```

4. Verify data consistency — results should match Athena queries exactly.

5. When done, terminate the EMR cluster to avoid ongoing charges:

```bash
aws emr terminate-clusters --cluster-ids <ClusterId> --region us-east-1
```

### Scenario 5: Streaming Ingestion with Amazon Data Firehose

Test real-time data ingestion into S3 Tables using Amazon Data Firehose.

1. Create a Firehose delivery stream targeting your S3 table bucket via the AWS Console:
   - Navigate to **Amazon Data Firehose** → **Create Firehose stream**.
   - Source: **Direct PUT**.
   - Destination: **Apache Iceberg Tables**.
   - Select your table bucket and configure the destination table (e.g., `poc_data.sensor_readings`).
   - Under **Iceberg table configuration**, set the unique keys and timestamp column for upsert behavior, or use append mode.
   - Assign an IAM role with `s3tables:*` and `glue:Get*` permissions.

2. Send test records using the AWS CLI:

```bash
# Send a single test record
aws firehose put-record \
  --delivery-stream-name <your-stream-name> \
  --record '{"Data":"eyJpZCI6NSwic2Vuc29yX2lkIjoic2Vuc29yLWQiLCJ0ZW1wZXJhdHVyZSI6MjEuMywibG9jYXRpb24iOiJidWlsZGluZy1iIn0="}' \
  --region us-east-1

# The Data field is base64-encoded JSON:
# {"id":5,"sensor_id":"sensor-d","temperature":21.3,"location":"building-b"}
```

3. Send a batch of records:

```bash
aws firehose put-record-batch \
  --delivery-stream-name <your-stream-name> \
  --records \
    '{"Data":"eyJpZCI6Niwic2Vuc29yX2lkIjoic2Vuc29yLWUiLCJ0ZW1wZXJhdHVyZSI6MTcuOH0="}' \
    '{"Data":"eyJpZCI6Nywic2Vuc29yX2lkIjoic2Vuc29yLWYiLCJ0ZW1wZXJhdHVyZSI6MjIuMX0="}' \
  --region us-east-1
```

4. Wait 1–2 minutes for Firehose to buffer and deliver, then verify in Athena:

```sql
SELECT * FROM poc_data.sensor_readings ORDER BY id DESC;
```

> **Note:** Firehose buffers records before delivery (default: 60 seconds or 1 MB). For PoC testing, you can lower the buffer interval to 60 seconds in the stream configuration to see results faster.

---

## SME Guidance

### Table Bucket Design

- Use **one table bucket per workload or domain** (e.g., IoT, clickstream, financial).
- Organize tables into **namespaces** by logical grouping (e.g., `raw`, `curated`, `aggregated`).
- Use **lowercase for all table names and definitions** to ensure compatibility across all AWS analytics services.
- Start with **Iceberg V3** for new tables to take advantage of deletion vectors and row lineage.

### Performance Optimization

- **Define sort orders** on tables with predictable query patterns to enable automatic sort compaction. S3 Tables supports binpack (default), sort, and z-order strategies.
- Use **hidden partitioning** to decouple physical data layout from query syntax — this lets you change partitioning without rewriting data.
- **Enable column statistics** for better query planning and scan optimization.
- Use **partition columns** aligned with your most common query filters for large datasets.
- Athena queries benefit from columnar filtering — select only needed columns.
- S3 Tables automatically compacts small files — avoid manual compaction. Monitor compaction metrics through **CloudWatch** to understand maintenance patterns and costs.
- The performance gap between S3 Tables and self-managed Iceberg widens as data volume and write frequency increase. Workloads with high-velocity data ingestion (streaming, frequent ETL) will see the most benefit.

### Security Best Practices

- Integrate with **SageMaker Lakehouse** for centralized governance across multiple table buckets and query engines.
- S3 Tables support **table-level IAM policies** — attach resource-based policies directly to individual tables and table buckets for granular security.
- Use **Lake Formation** for fine-grained column-level and row-level access control.
- Encryption: SSE-S3 (default) or SSE-KMS with customer-managed keys. Note: HTTPS only, no HTTP requests supported.
- Enable **AWS CloudTrail** for auditing table access.

### Cost Optimization

- Enable **Intelligent-Tiering** for tables with mixed access patterns — automatically reduces storage costs on cold data (40% cheaper after 30 days, 68% cheaper after 90 days).
- S3 Tables pricing includes storage, requests, object monitoring ($0.025 per 1,000 objects/month), and compaction charges. Monitor costs via **AWS Cost Explorer** with the `s3tables` service filter.
- S3 Tables compaction pricing is significantly cheaper than provisioning Glue compute for the same work — for a 1 TB table with daily ETL, S3 Tables can save ~23% vs. self-managed with Glue optimizers.
- Delete test tables and namespaces when no longer needed.

### When to Use S3 Tables vs. Self-Managed Iceberg

| Consideration | S3 Tables | Self-Managed Iceberg on S3 |
|---|---|---|
| Table maintenance | Fully automated (compaction, snapshot expiry, orphan cleanup, record expiration) | Manual or semi-managed via Glue optimizers |
| Query performance | Up to 3x faster (purpose-built storage layer) | Depends on maintenance discipline |
| Transactions/sec | Up to 10x higher | Standard Iceberg TPS |
| Compaction strategies | Binpack, sort, z-order (automatic) | Binpack, sort, z-order (via Glue optimizers or custom jobs) |
| Catalog integration | Native Iceberg REST Catalog + Glue/Lake Formation | Glue Data Catalog (AWS-specific config per engine) |
| Storage classes | S3 Standard, Intelligent-Tiering | All S3 storage classes (Standard-IA, Glacier, etc.) |
| Cross-region replication | Built-in table-aware replication | Object-level S3 CRR (not table-aware) |
| Access control | Table-level IAM policies | Bucket/prefix-level policies |
| Cost model | Storage + requests + object monitoring + compaction per GB | Storage + requests + Glue DPU-hours for maintenance |
| Best for | Zero-ops teams, high write throughput, growing table count | Archival workloads, maximum flexibility, existing mature platforms |

### Decision Guide

Choose **S3 Tables** when:
- You want zero-ops table maintenance
- You have high write throughput (streaming, frequent ETL, concurrent writers)
- You're managing many tables (10+) and don't want per-table maintenance overhead
- Query performance matters for interactive dashboards
- Your team has limited data engineering capacity (1–3 data engineers)

Choose **Self-Managed Iceberg** when:
- You need storage classes beyond Standard and Intelligent-Tiering (e.g., Glacier)
- Your target region doesn't support S3 Tables
- You have an existing well-tuned Iceberg platform
- You need to co-locate Iceberg tables with non-tabular data (images, logs, ML artifacts)
- You have multi-cloud or hybrid requirements needing presigned URLs

### Hybrid Approach

Many organizations benefit from using both:
- **S3 Tables** for active, frequently queried tables (production analytics, dashboards, real-time reporting)
- **Self-Managed** for archival and cost-optimized storage (historical data, compliance archives)
- **S3 Tables for new projects** to avoid building maintenance infrastructure
- **Self-Managed for existing workloads** until migration makes sense

---

## Cleanup

To avoid ongoing charges, delete the CloudFormation stack:

```bash
# First, delete any tables and namespaces you created
aws s3tables delete-table \
  --table-bucket-arn <TableBucketARN> \
  --namespace poc_data \
  --name sensor_readings \
  --region us-east-1

aws s3tables delete-namespace \
  --table-bucket-arn <TableBucketARN> \
  --namespace poc_data \
  --region us-east-1

# Empty the Athena results bucket
aws s3 rm s3://<AthenaResultsBucket> --recursive

# Terminate EMR cluster if created (Scenario 4b)
aws emr terminate-clusters --cluster-ids <ClusterId> --region us-east-1

# Delete the stack
aws cloudformation delete-stack \
  --stack-name s3-tables-poc \
  --region us-east-1
```

---

## Notices

*Customers are responsible for making their own independent assessment of the information in this Guidance. This Guidance: (a) is for informational purposes only, (b) represents AWS current product offerings and practices, which are subject to change without notice, and (c) does not create any commitments or assurances from AWS and its affiliates, suppliers or licensors. AWS products or services are provided "as is" without warranties, representations, or conditions of any kind, whether express or implied. AWS responsibilities and liabilities to its customers are controlled by AWS agreements, and this Guidance is not part of, nor does it modify, any agreement between AWS and its customers.*

*The sample code; software libraries; command line tools; proofs of concept; templates; or other related technology (including any of the foregoing that are provided by our personnel) is provided to you as AWS Content under the AWS Customer Agreement, or the relevant written agreement between you and AWS (whichever applies). You should not use this AWS Content in your production accounts, or on production or other critical data. You are responsible for testing, securing, and optimizing the AWS Content, such as sample code, as appropriate for production grade use based on your specific quality control practices and standards. Deploying AWS Content may incur AWS charges for creating or using AWS chargeable resources, such as running Amazon EC2 instances or using Amazon S3 storage.*
