# Verification Findings — AWS Docs Cross-Reference

> **Date**: 2026-05-01
> **Purpose**: Verify project claims against current public AWS documentation before building.
> **Sources**: docs.aws.amazon.com (S3 Tables User Guide), AWS blog posts, AWS What's New

---

## Critical Finding: Spark Access Method

### What we claim (STEERING §2, README Scenario 4)

> Spark connects via S3 Tables Iceberg REST endpoint. No custom JARs required.

### What AWS docs actually say

AWS documents **three** access methods for Spark, with a clear recommendation hierarchy:

| Method | Endpoint | Recommended For |
|---|---|---|
| 1. **AWS Glue Iceberg REST endpoint** (recommended) | `https://glue.<region>.amazonaws.com/iceberg` | Spark, PyIceberg, any Iceberg client — unified governance |
| 2. **S3 Tables Iceberg REST endpoint** (direct) | `https://s3tables.<region>.amazonaws.com/iceberg` | APN catalogs, custom catalogs, basic single-bucket read/write |
| 3. **S3 Tables Catalog for Apache Iceberg** (client JAR) | N/A (local JAR) | Open-source Spark only |

**Key quote from the REST endpoint page:**
> "For other access scenarios we recommend using the AWS Glue Iceberg REST endpoint to connect to tables, which provides unified table management, centralized governance, and fine-grained access control."

**Key quote from the access overview page:**
> "We recommend using the AWS Glue Iceberg REST endpoint when you want to access tables from Spark, PyIceberg, or other Iceberg-compatible clients."

### Impact on our project

Our STEERING says "No custom JARs" and uses the S3 Tables REST endpoint. This is **technically valid** but:
1. AWS now recommends the **Glue Iceberg REST endpoint** for Spark (not the S3 Tables endpoint)
2. The S3 Tables REST endpoint is positioned for "basic read/write access to a single table bucket" or APN/custom catalogs
3. The **client catalog JAR** (`s3-tables-catalog-for-iceberg`) still exists and is documented — it uses `software.amazon.s3tables.iceberg.S3TablesCatalog`

**Decision needed**: Do we:
- (A) Use the **Glue Iceberg REST endpoint** (AWS recommended for Spark) — requires Glue catalog integration
- (B) Keep the **S3 Tables REST endpoint** (simpler, IAM-only, no Glue dependency for Spark) — valid but not the recommended path
- (C) Use the **client catalog JAR** (what the Spark-specific docs show) — contradicts our "no custom JARs" rule

Note: Option B aligns with our IAM-first principle. The S3 Tables REST endpoint works fine for a PoC with a single table bucket. The Glue endpoint adds governance features we don't need for a PoC.

---

## Finding: VPC Endpoints — Two Required

### What we claim (CFN template)

We deploy a single `com.amazonaws.${Region}.s3tables` interface endpoint.

### What AWS docs say

The VPC connectivity page states:
> "To access S3 Tables from a VPC, we recommend creating two VPC endpoints (one for S3 and the other for S3 Tables). You can create either a gateway or an interface endpoint to route file (object) level operations to S3 and an interface endpoint to route bucket and table-level operations to S3 Tables."

**Explanation**: S3 Tables operations split across two service endpoints:
- **Table/namespace operations** → `s3tables.<region>.amazonaws.com` (needs S3 Tables interface endpoint)
- **Data file read/write** → `s3.<region>.amazonaws.com` (needs S3 gateway or interface endpoint)

### Impact on our project

Our CFN template already has both: S3 Gateway endpoint + S3 Tables interface endpoint. ✅ Correct.

The Spark `--conf spark.sql.catalog.s3tables.s3tables.endpoint` can be pointed at the VPC endpoint DNS for private connectivity. This resolves **Open Question #1** in STEERING.

---

## Finding: Intelligent-Tiering Configuration

### What we claim (README Scenario 3h)

Uses TBLPROPERTIES at table creation. Syntax unverified.

### What AWS docs say (tables-intelligent-tiering.html)

IT is configured via **S3 Tables API**, not TBLPROPERTIES:
- **Bucket level**: `CreateTableBucket` with `storage-class-configuration` header, or `PutTableBucketStorageClass` to modify
- **Table level**: `CreateTable` with `storage-class-configuration` header
- Cannot be changed after table creation
- Cannot convert existing S3 Standard tables to IT

**Key facts confirmed**:
- IT launched December 2025 (What's New announcement)
- Three tiers: FA (default) → IA (30 days) → AIA (90 days)
- Compaction only processes FA tier files
- Maintenance ops don't affect tier (reads by maintenance don't promote files)
- Files < 128 KB stay in FA
- Delete files on cold data accumulate until data accessed (manual EMR compaction suggested for this case)

### Impact on our project

README Scenario 3h uses wrong syntax (TBLPROPERTIES). Must use S3 Tables API:
```bash
# Set IT as bucket default for new tables
aws s3tables put-table-bucket-storage-class \
  --table-bucket-arn $TableBucketARN \
  --storage-class INTELLIGENT_TIERING \
  --region $AWS_REGION
```

Or at table creation via API header. Athena `CREATE TABLE` with TBLPROPERTIES won't work for this.

---

## Finding: Compaction Configuration

### What we claim (README Scenario 3g)

```json
{"status":"enabled","settings":{"icebergCompaction":{"targetFileSizeMB":512,"strategy":"sort","sortOrder":[{"columnName":"event_time","order":"desc"}]}}}
```

### What AWS docs say

The `PutTableMaintenanceConfiguration` API for sort/z-order:
- Requires a **sort order defined in Iceberg table properties** (not in the maintenance config)
- Requires `s3tables:GetTableData` permission
- Strategy values: `auto`, `binpack`, `sort`, `z-order`
- The `sortOrder` field in the maintenance config is **not documented** — sort order comes from the table metadata

Correct syntax per docs:
```bash
aws s3tables put-table-maintenance-configuration \
  --table-bucket-arn $TABLE_BUCKET_ARN \
  --type icebergCompaction \
  --namespace mynamespace \
  --name testtable \
  --value '{"status":"enabled","settings":{"icebergCompaction":{"strategy":"sort"}}}'
```

The sort order itself must be set via Spark `ALTER TABLE ... WRITE ORDERED BY` or at table creation.

### Impact on our project

README Scenario 3g has incorrect JSON payload. The `sortOrder` array in the maintenance config is wrong. Sort order is defined in table metadata, not the maintenance API.

---

## Finding: Snapshot Management Defaults

### What we claim (README Scenario 3d)

`minSnapshotsToKeep: 3, maxSnapshotAgeHours: 72`

### What AWS docs say

Defaults are:
- `MinimumSnapshots`: **1** (not 3)
- `MaximumSnapshotAge`: **120 hours** (5 days, not 72)

Also critical: snapshot management **fails entirely** if:
- User-defined tags or branches exist on the table
- Iceberg retention table properties (`history.expire.max-snapshot-age-ms` or `history.expire.min-snapshots-to-keep`) are set

### Impact on our project

Our recommended starting config (3/72) is fine as a PoC recommendation — it's more conservative than defaults. But we should document the actual defaults and the failure conditions.

---

## Finding: DROP TABLE Behavior (Confirmed)

### What AWS docs say

From the REST endpoint considerations page:
> "You can only drop tables with purge enabled. Dropping tables with purge=false is not supported and results in a 400 Bad Request error. Some versions of Spark always set this flag to false even when running DROP TABLE PURGE commands."

This matches the internal wiki. The client catalog page also shows `purge=true` is required.

### Impact on our project

Must add troubleshooting note. Users will hit this if they try `DROP TABLE` in Spark.

---

## Finding: Access Page No Longer Mentions SageMaker Lakehouse

### What AWS docs say

The access overview page (`s3-tables-access.html`) now says:
> "You can integrate tables with AWS analytics services using **AWS Glue Data Catalog**"

It mentions "Querying S3 Tables with SageMaker Unified Studio" as one of the services, but the framing is Glue-centric, not Lakehouse-centric.

### Impact on our project

Confirms our STEERING decision to remove SageMaker Lakehouse references. ✅

---

## Finding: Unreferenced File Removal

### What we claim

Two configs: `unreferencedDays`

### What AWS docs say

The internal wiki mentions two configs:
1. **Expire days** — if an object doesn't make it to the table after N days since creation, marked as orphan/noncurrent
2. **Noncurrent days** — objects hard deleted after N days of being noncurrent

The public docs describe it as part of snapshot management: when a snapshot expires, objects referenced only by that snapshot are marked noncurrent, then deleted after `NoncurrentDays`.

### Impact on our project

The `icebergUnreferencedFileRemoval` maintenance type config needs verification. Our README uses `unreferencedDays: 3` — need to confirm this maps to the correct API parameter name.

---

## Finding: Performance Claims

### What AWS docs say (aws.amazon.com/s3/features/tables)

> "faster query performance through continual table optimization... compared to unmanaged Iceberg tables, and up to 10x higher transactions per second compared to Iceberg tables stored in general purpose S3 buckets."

The compaction blog post title says "up to 3 times" improvement from compaction specifically.

### Impact on our project

The "3x" claim is specifically about compaction benefit (compacted vs uncompacted). The "10x TPS" is about S3 Tables vs GP buckets. Per our STEERING principle, we should either cite the specific source or use qualitative language.

---

## Summary: Actions Required

| # | Finding | Severity | Action |
|---|---|---|---|
| 1 | Spark access: AWS recommends Glue IRC endpoint, not S3 Tables REST | **High** | Decision needed — keep S3 Tables REST (simpler for PoC) or switch |
| 2 | VPC endpoints: need both S3 + S3 Tables | ✅ Already correct | No change needed |
| 3 | IT config: uses S3 Tables API, not TBLPROPERTIES | **High** | Rewrite Scenario 3h |
| 4 | Sort compaction: sortOrder not in maintenance config | **Medium** | Fix Scenario 3g JSON |
| 5 | Snapshot defaults: 1/120h not 3/72h | Low | Document actual defaults |
| 6 | DROP TABLE purge behavior | Low | Add troubleshooting note |
| 7 | SageMaker Lakehouse removed from docs | ✅ Confirms our decision | No change |
| 8 | Unreferenced file removal config | Low | Verify API parameter name |
| 9 | Performance claims sourced | Low | Cite specific blog or use qualitative |

---

## Open Decision: Spark Access Method

**Recommendation**: Keep the **S3 Tables Iceberg REST endpoint** for this PoC because:
1. It's IAM-only (aligns with our IAM-first principle)
2. It's simpler (no Glue catalog dependency for Spark path)
3. It's valid for "basic read/write access to a single table bucket" — which is exactly our PoC
4. The Glue IRC endpoint adds governance features unnecessary for a PoC

But we should add a note in SME Guidance: "For production multi-service access, AWS recommends the AWS Glue Iceberg REST endpoint for Spark."

**Also note**: The S3 Tables REST endpoint page says CTAS (`CREATE TABLE AS SELECT`) is NOT supported via this endpoint. This may affect scenarios if we add CTAS operations.
