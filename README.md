# Guidance for Deploying a PoC for Amazon S3 Tables

Amazon S3 Tables provide fully managed Apache Iceberg tables with automatic compaction, snapshot management, and garbage collection. This PoC validates the end-to-end workflow: table creation, multi-engine access (Athena + PyIceberg), streaming ingestion (Firehose), and table administration.

---

## What This Deploys

| Resource | Purpose | Daily Cost |
|---|---|---|
| S3 Table Bucket | Managed Iceberg table storage with automatic maintenance | ~$0.10 |
| Athena Workgroup + Results Bucket | Serverless SQL queries with a dedicated results location | ~$0.05 |
| Firehose IAM Role + Backup Bucket | Pre-configured role for streaming ingestion; backup bucket for failed records | ~$0.01 |

**Total**: ~$0.16/day (pay-per-use only — no idle compute)

---

## IAM Permissions

The user or role running this PoC needs the following permissions. The CloudFormation stack creates a dedicated Firehose role — these are for **your** IAM principal (the person running the CLI commands and notebook).

| Permission | Why |
|---|---|
| `s3tables:*` | Create/manage table buckets, namespaces, tables, and maintenance config |
| `glue:CreateCatalog`, `glue:GetCatalog`, `glue:DeleteCatalog` | Create the federated catalog that connects S3 Tables to Athena |
| `athena:*` | Run queries, manage workgroups, register data sources |
| `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`, `s3:DeleteObject` | Athena results bucket and Firehose backup bucket access |
| `firehose:CreateDeliveryStream`, `firehose:PutRecord`, `firehose:DeleteDeliveryStream`, `firehose:DescribeDeliveryStream` | Create and test the streaming ingestion path |
| `cloudformation:*` | Deploy and describe the stack |
| `iam:CreateRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy`, `iam:PassRole` | CloudFormation creates the Firehose IAM role |
| `cloudwatch:GetMetricStatistics`, `cloudwatch:ListMetrics` | View S3 Tables maintenance metrics |

**Firehose role** (created by the stack) additionally requires:

| Permission | Why |
|---|---|
| `lakeformation:GetDataAccess` | Required for Firehose to write to S3 Tables via the Glue federated catalog. This is an IAM action — no Lake Formation admin setup or grants are needed. |

> **Minimal policy for the notebook**: If running the PyIceberg notebook with a separate role, it needs `s3tables:*`, `cloudformation:DescribeStacks`, and `cloudwatch:GetMetric*`.

---

## Quick Start

### Step 1: Clone the Repo

```bash
git clone https://github.com/aws-solutions-library-samples/guidance-for-deploying-a-poc-for-amazon-s3-tables.git
cd guidance-for-deploying-a-poc-for-amazon-s3-tables
export AWS_REGION="us-east-1"
```

### Step 2: Deploy the Stack

The CloudFormation stack creates the table bucket, Athena workgroup, and Firehose support resources:

```bash
aws cloudformation deploy \
  --template-file assets/code/s3-tables-poc.yaml \
  --stack-name s3-tables-poc \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $AWS_REGION
```

> `CAPABILITY_NAMED_IAM` is required because the stack creates an IAM role for Firehose.

### Step 3: Capture Stack Outputs

These environment variables are used throughout the remaining steps:

```bash
STACK_NAME="s3-tables-poc"

TableBucketARN=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`TableBucketARN`].OutputValue' --output text)

TableBucketName=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`TableBucketName`].OutputValue' --output text)

AthenaWorkgroupName=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`AthenaWorkgroupName`].OutputValue' --output text)

FirehoseRoleArn=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`FirehoseRoleArn`].OutputValue' --output text)

FirehoseBackupBucketName=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`FirehoseBackupBucketName`].OutputValue' --output text)

echo "Table Bucket ARN:  $TableBucketARN"
echo "Table Bucket Name: $TableBucketName"
echo "Athena Workgroup:  $AthenaWorkgroupName"
echo "Firehose Role:     $FirehoseRoleArn"
echo "Backup Bucket:     $FirehoseBackupBucketName"

STREAM_NAME="${STACK_NAME}-stream"
```

---

## Phase 1: Foundation

This phase sets up the catalog integration and validates basic CRUD operations.

### 1.1 Create Glue Federated Catalog

S3 Tables require a Glue federated catalog for Athena to discover and query tables. This creates the catalog with IAM-based access control (no Lake Formation admin required):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > /tmp/catalog.json << EOF
{
  "Name": "s3tablescatalog",
  "CatalogInput": {
    "FederatedCatalog": {
      "Identifier": "arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/*",
      "ConnectionName": "aws:s3tables"
    },
    "CreateDatabaseDefaultPermissions": [
      {
        "Principal": { "DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS" },
        "Permissions": ["ALL"]
      }
    ],
    "CreateTableDefaultPermissions": [
      {
        "Principal": { "DataLakePrincipalIdentifier": "IAM_ALLOWED_PRINCIPALS" },
        "Permissions": ["ALL"]
      }
    ],
    "AllowFullTableExternalDataAccess": "True"
  }
}
EOF

aws glue create-catalog --region $AWS_REGION --cli-input-json file:///tmp/catalog.json
aws glue get-catalog --catalog-id s3tablescatalog --region $AWS_REGION
```

> If you get `AlreadyExistsException`, that's fine — the catalog already exists from a previous setup. The `get-catalog` command confirms it's configured correctly.

Next, register the catalog as an Athena data source so it appears in the Athena console. We register the bucket-level sub-catalog directly (avoids issues with stale bucket references in the parent catalog):

```bash
aws athena create-data-catalog \
  --name $TableBucketName \
  --type GLUE \
  --parameters catalog-id=s3tablescatalog/$TableBucketName \
  --region $AWS_REGION
```

> If you get `AlreadyExistsException`, the catalog is already registered.

### 1.2 Create Namespace

Namespaces are logical groupings within a table bucket (similar to databases). Create one for the PoC data:

```bash
aws s3tables create-namespace \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --region $AWS_REGION
```

### 1.3 Basic CRUD via Athena

This validates that Athena can create, read, update, and delete data in S3 Tables — confirming the catalog integration works end-to-end.

Open the Athena console and configure your query editor:

1. Navigate to the [Athena Query Editor](https://console.aws.amazon.com/athena/home#/query-editor)
2. Select the workgroup from the stack outputs (`AthenaWorkgroupName`)
3. In the **Data source** dropdown, select `s3-tables-poc-<account-id>` (your `$TableBucketName`)
4. Under **Database**, select `poc_data`

Once the catalog is selected, queries don't need the catalog prefix. Run the following queries one at a time:

**Create table** — S3 Tables are Iceberg by default, no `TBLPROPERTIES` needed:

```sql
CREATE TABLE customers (
  id INT,
  name STRING,
  email STRING,
  created_at TIMESTAMP
)
```

**Insert data:**

```sql
INSERT INTO customers VALUES
  (1, 'Alice', 'alice@example.com', current_timestamp),
  (2, 'Bob', 'bob@example.com', current_timestamp),
  (3, 'Charlie', 'charlie@example.com', current_timestamp)
```

**Query:**

```sql
SELECT * FROM customers ORDER BY id
```

**Update** — Iceberg supports row-level updates (no need to rewrite entire partitions):

```sql
UPDATE customers SET name = 'Alice Updated' WHERE id = 1
```

**Delete:**

```sql
DELETE FROM customers WHERE id = 3
```

### 1.4 Multi-Engine Access + Batch Load (Notebook)

This step validates that PyIceberg can read/write the same tables Athena uses — confirming true multi-engine interoperability via the S3 Tables REST endpoint.

**Option A: SageMaker AI Notebook (recommended for PoC)**

Create a managed notebook instance with credentials pre-configured — no local setup needed.

First, create the IAM role for the notebook:

```bash
# Create the SageMaker execution role
aws iam create-role --role-name ${STACK_NAME}-notebook-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"sagemaker.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

# Substitute stack name into policy and attach
sed "s/\${STACK_NAME}/${STACK_NAME}/g" assets/code/notebook-role-policy.json > assets/code/notebook-role-policy-resolved.json
aws iam put-role-policy --role-name ${STACK_NAME}-notebook-role \
  --policy-name S3TablesNotebookAccess \
  --policy-document file://assets/code/notebook-role-policy-resolved.json
```

Then create the notebook instance:

1. Open the [SageMaker console](https://console.aws.amazon.com/sagemaker/home#/notebook-instances/create)
2. Configure the instance:
   - **Name**: `s3-tables-poc`
   - **Instance type**: `ml.t3.medium`
   - **IAM role**: Select `s3-tables-poc-notebook-role` from the dropdown
3. Click **Create notebook instance**
4. Once status is **InService**, click **Open JupyterLab**
5. Upload `assets/code/s3_tables_poc.ipynb` from this repo into JupyterLab (drag and drop or use the Upload button)
6. Select the **conda_python3** kernel
7. Update `AWS_REGION` and `STACK_NAME` in the first code cell, then **Run All Cells**

> **Cost**: ~$0.05/hr for `ml.t3.medium`. Stop the instance from the SageMaker console when done to avoid charges.

**Option B: Local IDE (VS Code, PyCharm, JupyterLab)**

1. Open `assets/code/s3_tables_poc.ipynb` in your preferred environment
2. Install dependencies: `pip install "pyiceberg[s3,pyarrow]" boto3 pyarrow pandas`
3. Ensure AWS credentials are active (`aws sts get-caller-identity` should return your account)
4. Update the `AWS_REGION` and `STACK_NAME` variables in the first code cell
5. **Run All Cells**

**What the notebook does:**

| Step | Action | Validates |
|---|---|---|
| 1 | Connect to S3 Tables via PyIceberg REST catalog | SigV4 auth, catalog discovery |
| 2 | Read `customers` table (created by Athena in 1.3) | Cross-engine read (Athena → PyIceberg) |
| 3 | Write 2 rows from PyIceberg | Cross-engine write (PyIceberg → verify via Athena) |
| 4 | Create `events` table with day-level partitioning | Table creation via REST endpoint |
| 5 | Generate and load 50,000 synthetic event records | Batch ingestion (5 batches of 10K) |
| 6 | Query aggregates (by event_type, by region) | Batch load verification |
| 7 | Cross-engine verification — query via Athena | Multi-engine interoperability (PyIceberg → Athena) |
| 8 | Inspect table metadata + maintenance job status | Observability via boto3 |

After the notebook completes, verify cross-engine consistency back in the Athena query editor (with your `$TableBucketName` data source and `poc_data` database selected):

```sql
SELECT event_type, count(*) as cnt FROM events
GROUP BY event_type ORDER BY cnt DESC
```

**Expected**: ~50,000 rows across 5 event types — confirms PyIceberg-written data is readable by Athena.

---

## Phase 2: Stream Ingestion

This phase validates real-time data ingestion via Amazon Data Firehose writing directly to S3 Tables in Iceberg format.

### 2.1 Create Firehose Stream

Create a delivery stream that writes JSON records directly to the `events` Iceberg table. The `CatalogARN` must reference the bucket-level sub-catalog:

```bash
aws firehose create-delivery-stream \
  --delivery-stream-name $STREAM_NAME \
  --delivery-stream-type DirectPut \
  --iceberg-destination-configuration "{
    \"RoleARN\": \"${FirehoseRoleArn}\",
    \"CatalogConfiguration\": {
      \"CatalogARN\": \"arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:catalog/s3tablescatalog/${TableBucketName}\"
    },
    \"S3Configuration\": {
      \"RoleARN\": \"${FirehoseRoleArn}\",
      \"BucketARN\": \"arn:aws:s3:::${FirehoseBackupBucketName}\"
    },
    \"BufferingHints\": { \"SizeInMBs\": 128, \"IntervalInSeconds\": 60 },
    \"DestinationTableConfigurationList\": [{
      \"DestinationDatabaseName\": \"poc_data\",
      \"DestinationTableName\": \"events\",
      \"UniqueKeys\": [\"event_id\"]
    }]
  }" --region $AWS_REGION
```

Wait for the stream to become active:

```bash
aws firehose describe-delivery-stream \
  --delivery-stream-name $STREAM_NAME --region $AWS_REGION \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'
```

### 2.2 Send Test Records

Send 50 sample events spread across the past 24 hours to validate the end-to-end streaming path:

```bash
for i in $(seq 1 50); do
  OFFSET_SECONDS=$((RANDOM % 86400))
  EVENT_TIME=$(date -u -d "-${OFFSET_SECONDS} seconds" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-${OFFSET_SECONDS}S +%Y-%m-%dT%H:%M:%S)
  RECORD=$(echo -n "{\"event_id\":\"stream-$(uuidgen)\",\"event_type\":\"stream_click\",\"user_id\":$((RANDOM % 100 + 1)),\"amount\":$((RANDOM % 500)).$((RANDOM % 99)),\"event_time\":\"${EVENT_TIME}\",\"region\":\"us-east-1\"}" | base64)
  aws firehose put-record \
    --delivery-stream-name $STREAM_NAME \
    --record "{\"Data\":\"${RECORD}\"}" --region $AWS_REGION
done
```

### 2.3 Verify Stream Ingestion

Wait 1–2 minutes for Firehose to buffer and commit, then run these queries in the Athena console (with your `$TableBucketName` data source and `poc_data` database selected):

**Count streamed records:**

```sql
SELECT event_type, count(*) as cnt, round(sum(amount),2) as total_amount
FROM events
WHERE event_type = 'stream_click'
GROUP BY event_type
```

**Time-series query — verify event distribution across the past 24 hours:**

```sql
SELECT date_trunc('hour', event_time) as hour,
       count(*) as events_per_hour,
       round(avg(amount),2) as avg_amount
FROM events
WHERE event_type = 'stream_click'
GROUP BY date_trunc('hour', event_time)
ORDER BY hour DESC
```

**Combined view — compare batch (PyIceberg) vs stream (Firehose) ingestion:**

```sql
SELECT event_type, count(*) as cnt, round(sum(amount),2) as total
FROM events
GROUP BY event_type
ORDER BY cnt DESC
```

**Expected**: ~50 `stream_click` records from Firehose alongside ~50,000 records from the PyIceberg batch load — confirms both ingestion paths write to the same Iceberg table.

> If no `stream_click` results appear after 2 minutes, check the backup bucket for failed records: `aws s3 ls s3://$FirehoseBackupBucketName/ --recursive`

---

## Phase 3: Observability

S3 Tables automatically runs maintenance jobs (compaction, snapshot management). This phase shows how to monitor them.

### 3.1 Table Maintenance Status

> **Note**: If you just deployed the PoC, maintenance jobs will show a status of `Not_Yet_Run`. S3 Tables triggers maintenance asynchronously — compaction typically runs within 1 hour of data being written. This is expected; check back later using the Follow-On Validation schedule below.

1. Open the [S3 console](https://console.aws.amazon.com/s3/home) → **Table buckets**
2. Select your table bucket → **Tables** → select `events`
3. View the **Maintenance** tab — shows compaction, snapshot management, and unreferenced file removal status

Alternatively via CLI:

```bash
aws s3tables get-table-maintenance-job-status \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --name events --region $AWS_REGION
```

### 3.2 CloudWatch Metrics

1. Open the [CloudWatch Metrics console](https://console.aws.amazon.com/cloudwatch/home#metricsV2)
2. Search for namespace `AWS/S3Tables`
3. Filter by dimension `TableBucketName` = your bucket name
4. Key metrics to observe:
   - `CompactionBytesCompacted` — data compacted by auto-maintenance
   - `CompactionFilesCompacted` — number of files merged
   - `SnapshotsExpired` — snapshots cleaned up

> **Note**: The `AWS/S3Tables` namespace only appears after S3 Tables runs its first maintenance job (compaction, snapshot expiry). With small datasets this may take several hours. Check the **Maintenance** tab in the S3 console first to confirm jobs have run.

---

## Phase 4: Administration

These commands configure table maintenance policies and demonstrate Iceberg features.

### 4.1 Schema Evolution

Iceberg supports adding columns without rewriting data. Run in the Athena console (with your `$TableBucketName` data source and `poc_data` database selected):

```sql
ALTER TABLE customers ADD COLUMNS (phone STRING, tier STRING)
```

> **Idempotency note**: If you get `Cannot add column, name already exists: phone`, the columns were already added in a previous run. This is safe to ignore — Iceberg does not support `IF NOT EXISTS` for `ADD COLUMNS`, so re-running this statement is expected to fail once the columns exist.

### 4.2 Snapshot Management

Control how many snapshots are retained and for how long. Expired snapshots are automatically cleaned up:

```bash
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --name events \
  --type icebergSnapshotManagement \
  --value '{"status":"enabled","settings":{"icebergSnapshotManagement":{"minSnapshotsToKeep":3,"maxSnapshotAgeHours":72}}}' \
  --region $AWS_REGION
```

### 4.3 Compaction Configuration

Compaction merges small files into larger ones for better query performance. S3 Tables runs this automatically — here you can tune the target file size:

```bash
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --name events \
  --type icebergCompaction \
  --value '{"status":"enabled","settings":{"icebergCompaction":{"targetFileSizeMB":256}}}' \
  --region $AWS_REGION
```

### 4.4 Intelligent-Tiering

Enable S3 Intelligent-Tiering on the table bucket to automatically move infrequently accessed data to lower-cost storage tiers:

```bash
aws s3tables put-table-bucket-storage-class \
  --table-bucket-arn $TableBucketARN \
  --storage-class-configuration '{"storageClass":"INTELLIGENT_TIERING"}' \
  --region $AWS_REGION
```

### 4.5 Time Travel

Iceberg maintains snapshot history, allowing you to query data as it existed at a previous point in time. Run in the Athena console:

```sql
SELECT * FROM customers FOR TIMESTAMP AS OF TIMESTAMP '2026-05-06 06:00:00 UTC'
```

> Replace with a UTC timestamp from before your UPDATE/DELETE operations. Use `SELECT current_timestamp` to see the current time.

---

## Follow-On Validation

S3 Tables runs maintenance jobs asynchronously — compaction, snapshot expiry, and tiering transitions happen in the background after data is written. Come back at these intervals to confirm they're working:

| When | What to Check | How |
|---|---|---|
| **+1 hour** | Compaction job triggered | S3 console → Table buckets → `events` → Maintenance tab |
| **+1 hour** | Snapshot count stabilized | `aws s3tables get-table-maintenance-job-status` — snapshot management should show `lastRunStatus: successful` |
| **+24 hours** | `AWS/S3Tables` CloudWatch namespace appears | CloudWatch Metrics → search `AWS/S3Tables` |
| **+24 hours** | Compaction metrics populated | `CompactionBytesCompacted`, `CompactionFilesCompacted` should have datapoints |
| **+24 hours** | File count reduced | Query `SELECT count(*) FROM events` should return same rows but with fewer underlying files (visible in table metadata) |
| **+72 hours** | Snapshot expiry runs | If you set `maxSnapshotAgeHours: 72` in Phase 4.2, old snapshots should be removed |
| **+72 hours** | Time travel window closes | Queries with `FOR TIMESTAMP AS OF` older than 72h should fail (snapshots expired) |
| **+7 days** | Intelligent-Tiering transitions | If enabled in Phase 4.4, infrequently accessed data moves to lower-cost tiers (visible in S3 storage class metrics) |

> **Tip**: If compaction hasn't run after 1 hour, your dataset may be too small to trigger it. Load more data via the notebook (increase `NUM_RECORDS` to 500K) or send more Firehose records.

---

## Cleanup

Remove all resources in reverse dependency order.

> **Why CLI + CloudFormation?** The CloudFormation stack only manages the table bucket, Athena workgroup, IAM role, and S3 buckets. Resources created via CLI during the PoC (Firehose stream, tables, namespace, bucket policy, Glue catalog, Athena data source) live outside the stack and must be deleted via CLI first. Additionally, CloudFormation cannot delete non-empty S3 buckets, so the Athena results and Firehose backup buckets must be emptied before stack deletion.

```bash
# 0. Delete SageMaker notebook (if created in Phase 1.4 Option A)
aws sagemaker stop-notebook-instance --notebook-instance-name s3-tables-poc --region $AWS_REGION 2>/dev/null
aws sagemaker wait notebook-instance-stopped --notebook-instance-name s3-tables-poc --region $AWS_REGION 2>/dev/null
aws sagemaker delete-notebook-instance --notebook-instance-name s3-tables-poc --region $AWS_REGION 2>/dev/null
aws iam delete-role-policy --role-name ${STACK_NAME}-notebook-role --policy-name S3TablesNotebookAccess 2>/dev/null
aws iam delete-role --role-name ${STACK_NAME}-notebook-role 2>/dev/null

# 1. Delete Firehose stream (must be removed before table bucket policy)
aws firehose delete-delivery-stream \
  --delivery-stream-name $STREAM_NAME --region $AWS_REGION 2>/dev/null

# 2. Delete all tables (required before namespace/bucket can be deleted)
for TABLE in $(aws s3tables list-tables --table-bucket-arn $TableBucketARN \
  --namespace poc_data --query 'tables[].name' --output text --region $AWS_REGION); do
  aws s3tables delete-table --table-bucket-arn $TableBucketARN \
    --namespace poc_data --name $TABLE --region $AWS_REGION
done

# 3. Delete namespace
aws s3tables delete-namespace --table-bucket-arn $TableBucketARN \
  --namespace poc_data --region $AWS_REGION

# 5. Delete Athena data source registration
aws athena delete-data-catalog --name $TableBucketName --region $AWS_REGION 2>/dev/null

# 6. Delete Glue catalog (skip if shared with other projects)
aws glue delete-catalog --catalog-id s3tablescatalog --region $AWS_REGION

# 7. Empty S3 buckets (CloudFormation cannot delete non-empty buckets)
ATHENA_BUCKET=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $AWS_REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`AthenaResultsBucketName`].OutputValue' --output text)
aws s3 rm s3://${ATHENA_BUCKET} --recursive --region $AWS_REGION 2>/dev/null
aws s3 rm s3://${FirehoseBackupBucketName} --recursive --region $AWS_REGION 2>/dev/null

# 8. Delete Athena workgroup (must be empty before CloudFormation can delete it)
aws athena delete-work-group --work-group ${STACK_NAME}-workgroup \
  --recursive-delete-option --region $AWS_REGION 2>/dev/null

# 9. Delete CloudFormation stack (removes table bucket, IAM roles, S3 buckets)
aws cloudformation delete-stack --stack-name $STACK_NAME --region $AWS_REGION
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $AWS_REGION
```

> **If stack deletion fails**: This usually means a resource still has dependencies (e.g., table bucket not fully empty, or a bucket with residual objects). Open the [CloudFormation console](https://console.aws.amazon.com/cloudformation), select the failed stack, click **Delete**, and check "Retain" for the blocking resource. Then manually delete that resource from its respective console (S3 or S3 Tables).
