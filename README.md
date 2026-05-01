# Guidance for Deploying a PoC for Amazon S3 Tables

> **Status**: Working draft v2 — notebook-based Spark, no EC2/VPC.

---

## What This Deploys

**Core resources (always deployed):**

| Resource | Purpose | Daily Cost |
|---|---|---|
| S3 Table Bucket | Managed Iceberg table storage | ~$0.10 |
| Athena Workgroup + Results Bucket | Serverless SQL queries | ~$0.05 |
| Firehose IAM Role + Backup Bucket | Streaming ingestion support | ~$0.01 |

**SageMaker AI Notebook (deployed by default, optional):**

| Resource | Purpose | Daily Cost |
|---|---|---|
| SageMaker Notebook (ml.t3.medium) | Pre-configured Jupyter environment — IAM role handles auth, PyIceberg pre-installed | ~$1.20 |

| Deploy Mode | What You Get | Daily Cost |
|---|---|---|
| **Default** (`DeployNotebook=Yes`) | Full stack + SageMaker notebook — zero credential setup, open and run | ~$1.36/day |
| **Lightweight** (`DeployNotebook=No`) | Core stack only — use your own IDE with local AWS credentials | ~$0.16/day |

> **Tip**: Stop the notebook instance when not testing (`aws sagemaker stop-notebook-instance`). Athena and S3 Tables are pay-per-use only.

---

## Quick Start

### Step 1: Clone the Repo

```bash
git clone https://github.com/aws-solutions-library-samples/guidance-for-deploying-a-poc-for-amazon-s3-tables.git
cd guidance-for-deploying-a-poc-for-amazon-s3-tables
export AWS_REGION="us-east-1"
```

### Step 2: Deploy the Stack

**Default (with SageMaker notebook)** — recommended for fastest setup:

```bash
aws cloudformation deploy \
  --template-file assets/code/s3-tables-poc.yaml \
  --stack-name s3-tables-poc \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $AWS_REGION
```

This deploys the core resources plus a SageMaker AI notebook instance with:
- Pre-installed PyIceberg, boto3, pyarrow, pandas (via lifecycle config)
- IAM role with S3 Tables, Glue, Athena, and CloudWatch permissions
- No AWS credential configuration needed — the notebook's IAM role handles authentication

**Without notebook (local IDE):**

```bash
aws cloudformation deploy \
  --template-file assets/code/s3-tables-poc.yaml \
  --stack-name s3-tables-poc \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides DeployNotebook=No \
  --region $AWS_REGION
```

This deploys only the core resources. You'll run the notebook from your own environment:
- Install dependencies: `pip install "pyiceberg[s3,pyarrow]" boto3 pandas`
- Ensure AWS credentials are configured (`aws configure`, SSO, or environment variables)
- Your credentials need: `s3tables:*`, `glue:Get*`, `athena:*`, `cloudwatch:GetMetric*`

### Step 3: Capture Stack Outputs

```bash
eval $(aws cloudformation describe-stacks \
  --stack-name s3-tables-poc --region $AWS_REGION \
  --query 'Stacks[0].Outputs[].{k:OutputKey,v:OutputValue}' \
  --output text | awk '{print $1"=\""$2"\""}')

echo "Table Bucket:     $TableBucketARN"
echo "Athena Workgroup: $AthenaWorkgroupName"
echo "Firehose Role:    $FirehoseRoleArn"
echo "Notebook URL:     ${NotebookUrl:-N/A (not deployed)}"
```

---

## Phase 1: Foundation (CLI)

### 1.1 Create Glue Federated Catalog

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

### 1.2 Create Namespace

```bash
aws s3tables create-namespace \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --region $AWS_REGION
```

### 1.3 Basic CRUD via Athena

```bash
# Create table
aws athena start-query-execution \
  --query-string "CREATE TABLE s3tablescatalog.\"${TableBucketName}\".poc_data.customers (
    id INT, name STRING, email STRING, created_at TIMESTAMP
  ) TBLPROPERTIES ('table_type' = 'ICEBERG')" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION

# Insert
aws athena start-query-execution \
  --query-string "INSERT INTO s3tablescatalog.\"${TableBucketName}\".poc_data.customers VALUES
    (1, 'Alice', 'alice@example.com', current_timestamp),
    (2, 'Bob', 'bob@example.com', current_timestamp),
    (3, 'Charlie', 'charlie@example.com', current_timestamp)" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION

# Query
aws athena start-query-execution \
  --query-string "SELECT * FROM s3tablescatalog.\"${TableBucketName}\".poc_data.customers ORDER BY id" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION

# Update
aws athena start-query-execution \
  --query-string "UPDATE s3tablescatalog.\"${TableBucketName}\".poc_data.customers SET name = 'Alice Updated' WHERE id = 1" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION

# Delete
aws athena start-query-execution \
  --query-string "DELETE FROM s3tablescatalog.\"${TableBucketName}\".poc_data.customers WHERE id = 3" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION
```

### 1.4 Multi-Engine Access + Batch Load (Notebook)

This step uses the `assets/code/s3_tables_poc.ipynb` notebook to validate Spark/PyIceberg access and load batch data. The notebook is environment-neutral — same cells, same results, regardless of where you run it.

---

**If you deployed with the notebook (default):**

1. Open the **Notebook URL** from Step 3 outputs, or find the notebook in the [SageMaker console](https://console.aws.amazon.com/sagemaker/home#/notebook-instances)
2. In JupyterLab, click **Upload** and select `assets/code/s3_tables_poc.ipynb` from your cloned repo
3. When prompted for a kernel, select **conda_python3**
4. Update the `AWS_REGION` variable in the first code cell to match your deployment region
5. **Run All Cells** — authentication is automatic via the notebook's IAM role

> Dependencies (PyIceberg, boto3, pyarrow, pandas) are pre-installed by the lifecycle config. No `pip install` needed.

---

**If you deployed without the notebook (local IDE):**

1. Open `assets/code/s3_tables_poc.ipynb` in your IDE (VS Code, PyCharm, JupyterLab)
2. Ensure your AWS credentials are active (`aws sts get-caller-identity` should return your account)
3. Update the `AWS_REGION` variable in the first code cell to match your deployment region
4. **Run All Cells** — PyIceberg uses your local boto3 session for SigV4 signing

> If you haven't installed dependencies: `pip install "pyiceberg[s3,pyarrow]" boto3 pandas`

---

**What the notebook does:**

| Cell | Action | Validates |
|---|---|---|
| 1–2 | Connect to S3 Tables via PyIceberg REST catalog | SigV4 auth, catalog discovery |
| 3 | Read `customers` table (created by Athena in 1.3) | Cross-engine read (Athena → PyIceberg) |
| 4 | Write 2 rows from PyIceberg | Cross-engine write (PyIceberg → verify via Athena) |
| 5 | Create `events` table with day-level partitioning | Table creation via REST endpoint |
| 6 | Generate and load 50,000 synthetic event records | Batch ingestion (5 batches of 10K) |
| 7 | Query aggregates (by event_type, by region) | Batch load verification |
| 8 | Inspect table metadata + maintenance job status | Observability via boto3 |

After the notebook completes, verify cross-engine consistency from your terminal:

```bash
aws athena start-query-execution \
  --query-string "SELECT event_type, count(*) as cnt
    FROM s3tablescatalog.\"${TableBucketName}\".poc_data.events
    GROUP BY event_type ORDER BY cnt DESC" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION
```

**Expected**: ~50,000 rows across 5 event types — confirms PyIceberg-written data is readable by Athena.

---

## Phase 2: Stream Ingestion (CLI)

### 2.1 Grant Firehose Access

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3tables put-table-bucket-policy \
  --table-bucket-arn $TableBucketARN \
  --resource-policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"FirehoseAccess\",
      \"Effect\": \"Allow\",
      \"Principal\": { \"AWS\": \"${FirehoseRoleArn}\" },
      \"Action\": [
        \"s3tables:GetTableData\", \"s3tables:PutTableData\",
        \"s3tables:GetTable\", \"s3tables:GetTableMetadataLocation\",
        \"s3tables:UpdateTableMetadataLocation\",
        \"s3tables:GetNamespace\", \"s3tables:GetTableBucket\"
      ],
      \"Resource\": [
        \"arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/${TableBucketName}\",
        \"arn:aws:s3tables:${AWS_REGION}:${ACCOUNT_ID}:bucket/${TableBucketName}/*\"
      ]
    }]
  }" --region $AWS_REGION
```

### 2.2 Create Firehose Stream

```bash
aws firehose create-delivery-stream \
  --delivery-stream-name s3-tables-poc-stream \
  --delivery-stream-type DirectPut \
  --iceberg-destination-configuration "{
    \"RoleARN\": \"${FirehoseRoleArn}\",
    \"CatalogConfiguration\": {
      \"CatalogARN\": \"arn:aws:glue:${AWS_REGION}:${ACCOUNT_ID}:catalog/s3tablescatalog\"
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

# Wait for ACTIVE
aws firehose describe-delivery-stream \
  --delivery-stream-name s3-tables-poc-stream --region $AWS_REGION \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'
```

### 2.3 Send Test Records

```bash
for i in $(seq 1 20); do
  RECORD=$(echo -n "{\"event_id\":\"stream-$(uuidgen)\",\"event_type\":\"stream_click\",\"user_id\":$((RANDOM % 100 + 1)),\"amount\":$((RANDOM % 500)).$((RANDOM % 99)),\"event_time\":\"$(date -u +%Y-%m-%dT%H:%M:%S)\",\"region\":\"us-east-1\"}" | base64)
  aws firehose put-record \
    --delivery-stream-name s3-tables-poc-stream \
    --record "{\"Data\":\"${RECORD}\"}" --region $AWS_REGION
done
```

Wait 1–2 minutes, then verify:
```bash
aws athena start-query-execution \
  --query-string "SELECT event_type, count(*) as cnt
    FROM s3tablescatalog.\"${TableBucketName}\".poc_data.events
    WHERE event_type = 'stream_click' GROUP BY event_type" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION
```

---

## Phase 3: Observability (CLI)

### 3.1 Table Metadata

```bash
aws s3tables get-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --name events --region $AWS_REGION

aws s3tables get-table-maintenance-job-status \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --name events --region $AWS_REGION
```

### 3.2 CloudWatch — Compaction Metrics

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/S3Tables \
  --metric-name CompactionBytesCompacted \
  --dimensions Name=TableBucketName,Value=$TableBucketName \
    Name=Namespace,Value=poc_data Name=TableName,Value=events \
  --start-time $(date -u -v-2H +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Sum --region $AWS_REGION
```

### 3.3 List All Available Metrics

```bash
aws cloudwatch list-metrics \
  --namespace AWS/S3Tables \
  --dimensions Name=TableBucketName,Value=$TableBucketName \
  --region $AWS_REGION
```

---

## Phase 4: Administration (CLI)

### 4.1 Schema Evolution

```bash
aws athena start-query-execution \
  --query-string "ALTER TABLE s3tablescatalog.\"${TableBucketName}\".poc_data.customers
    ADD COLUMNS (phone STRING, tier STRING)" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION
```

### 4.2 Snapshot Management

```bash
# Defaults: minSnapshotsToKeep=1, maxSnapshotAgeHours=120
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --name events \
  --type icebergSnapshotManagement \
  --value '{"status":"enabled","settings":{"icebergSnapshotManagement":{"minSnapshotsToKeep":3,"maxSnapshotAgeHours":72}}}' \
  --region $AWS_REGION
```

### 4.3 Unreferenced File Removal

```bash
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn $TableBucketARN \
  --namespace poc_data --name events \
  --type icebergUnreferencedFileRemoval \
  --value '{"status":"enabled","settings":{"icebergUnreferencedFileRemoval":{"unreferencedDays":3}}}' \
  --region $AWS_REGION
```

### 4.4 Intelligent-Tiering

```bash
aws s3tables put-table-bucket-storage-class \
  --table-bucket-arn $TableBucketARN \
  --storage-class INTELLIGENT_TIERING --region $AWS_REGION
```

### 4.5 Time Travel

```bash
aws athena start-query-execution \
  --query-string "SELECT * FROM s3tablescatalog.\"${TableBucketName}\".poc_data.customers
    FOR SYSTEM_TIME AS OF TIMESTAMP '<snapshot_timestamp>'" \
  --work-group $AthenaWorkgroupName --region $AWS_REGION
```

---

## Cleanup

```bash
# 1. Firehose
aws firehose delete-delivery-stream \
  --delivery-stream-name s3-tables-poc-stream --region $AWS_REGION 2>/dev/null

# 2. Stop notebook (if deployed — prevents charges during stack deletion)
aws sagemaker stop-notebook-instance \
  --notebook-instance-name s3-tables-poc-notebook --region $AWS_REGION 2>/dev/null

# 3. Tables
for TABLE in $(aws s3tables list-tables --table-bucket-arn $TableBucketARN \
  --namespace poc_data --query 'tables[].name' --output text --region $AWS_REGION); do
  aws s3tables delete-table --table-bucket-arn $TableBucketARN \
    --namespace poc_data --name $TABLE --region $AWS_REGION
done

# 4. Namespace
aws s3tables delete-namespace --table-bucket-arn $TableBucketARN \
  --namespace poc_data --region $AWS_REGION

# 5. Table bucket policy
aws s3tables delete-table-bucket-policy \
  --table-bucket-arn $TableBucketARN --region $AWS_REGION 2>/dev/null

# 6. Catalog
aws glue delete-catalog --catalog-id s3tablescatalog --region $AWS_REGION

# 7. Empty buckets
aws s3 rm s3://${AthenaResultsBucketName} --recursive --region $AWS_REGION
aws s3 rm s3://${FirehoseBackupBucketName} --recursive --region $AWS_REGION

# 8. Stack (deletes notebook instance, IAM roles, buckets, table bucket)
aws cloudformation delete-stack --stack-name s3-tables-poc --region $AWS_REGION
aws cloudformation wait stack-delete-complete --stack-name s3-tables-poc --region $AWS_REGION
```
