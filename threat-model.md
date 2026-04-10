# Threat Model — Guidance for Deploying a PoC for Amazon S3 Tables

## Q1: What are we building?

This Guidance deploys a proof-of-concept environment for Amazon S3 Tables, consisting of:

- A VPC with a private subnet and VPC endpoints (no internet gateway, no NAT Gateway)
- An Amazon EC2 instance (Amazon Linux 2023) in a **private subnet**, accessible via AWS Systems Manager Session Manager (no SSH, no public IP). Java 17, Apache Spark, and Iceberg JARs are installed automatically via UserData (downloaded via NAT Gateway).
- An Amazon S3 table bucket for storing Apache Iceberg tables (V2 and V3 supported)
- A `s3tablescatalog` federated catalog in AWS Glue Data Catalog (SageMaker Lakehouse integration), enabling unified access from Athena, Redshift, EMR, and other analytics services
- An Amazon Athena workgroup with a dedicated S3 results bucket
- IAM roles and instance profiles granting the EC2 instance access to S3 Tables, Glue Data Catalog, Athena, and Lake Formation

The environment is intended for short-lived PoC testing only, not production workloads. Users deploy the CloudFormation template, create Iceberg tables, ingest sample data, and query it via Athena or Spark. Optional scenarios include testing sort/z-order compaction, Intelligent-Tiering, EMR Serverless, and streaming ingestion via Firehose.

**Prerequisites with security implications:**
- The deploying principal must be registered as a **Lake Formation data lake administrator** before deployment. This is an elevated privilege that grants broad control over data lake permissions in the account/region.

**Federated catalog configuration:**
- The `s3tablescatalog` is created with `AllowFullTableExternalDataAccess: True` and default permissions granting `ALL` to `IAM_ALLOWED_PRINCIPALS`. This is a permissive configuration appropriate for PoC testing but not for production.

**Data flow:**
1. User connects to EC2 via AWS Systems Manager Session Manager (no SSH, no public IP).
2. User creates tables in S3 table bucket via AWS CLI or Spark.
3. User queries tables via Athena (through Glue Data Catalog) or Spark (via S3 Tables catalog).
4. Athena query results are stored in a dedicated S3 bucket.
5. (Optional) User creates an Amazon Data Firehose delivery stream via the console to test streaming ingestion into S3 Tables.
6. (Optional) User creates an Amazon EMR Serverless application (Scenario 4b) with its own IAM role to run Spark jobs against S3 Tables. EMR Serverless runs in an **AWS-managed VPC**, not the PoC's private VPC — network traffic does not flow through the PoC's VPC endpoints.
7. (Optional) User enables S3 Tables Intelligent-Tiering to automatically transition infrequently accessed data to cheaper storage tiers.

## Q2: What can go wrong?

| Threat | Description | Severity |
|---|---|---|
| Over-privileged IAM role | EC2 role has broad S3 Tables and Glue permissions. If the instance is compromised, attacker gains access to table data. | Medium |
| Permissive federated catalog defaults | The `s3tablescatalog` is created with `AllowFullTableExternalDataAccess: True` and `IAM_ALLOWED_PRINCIPALS` granted `ALL` on databases and tables. Any IAM principal in the account with sufficient IAM permissions can access all tables in the catalog. | Medium |
| Lake Formation admin misconfiguration | The prerequisite step uses `put-data-lake-settings` to register the deploying principal as a Lake Formation admin. If run incorrectly, this can overwrite existing Lake Formation admins in the account, breaking permissions for other workloads. | Medium |
| EMR Serverless IAM role and network scope | The optional EMR Serverless scenario (4b) creates an IAM role with `AmazonS3TablesFullAccess` (managed policy) and S3 access. EMR Serverless runs in an AWS-managed VPC outside the PoC's network boundary, so traffic is not constrained by the PoC's VPC endpoints or security groups. | Medium |
| Firehose IAM role with broad permissions | The optional Firehose scenario (5) creates an IAM role with `glue:*` and `s3tables:*` on `Resource: "*"`, which is broader than needed for the PoC. A compromised or misconfigured Firehose stream could access Glue resources and S3 Tables beyond the PoC scope. | Medium |
| Data exposure via Athena results | Athena results bucket could contain query output with sensitive data if users load real data. | Low |
| Resource cost overrun | Users may forget to clean up resources (including VPC endpoints, EMR Serverless applications, manually created Firehose streams, and IAM roles), leading to ongoing charges. | Low |

## Q3: What can we do about it?

| Threat | Mitigation |
|---|---|
| Over-privileged IAM role | IAM policy is scoped to read/write operations needed for PoC. No admin-level permissions. S3 Tables actions are limited to the deployed table bucket where possible. |
| Permissive federated catalog defaults | This is intentional for PoC simplicity — it avoids per-table Lake Formation grant complexity during testing. The README documents this as a PoC-only configuration. For production, replace `IAM_ALLOWED_PRINCIPALS` with explicit principal grants and set `AllowFullTableExternalDataAccess` to `False`. |
| Lake Formation admin misconfiguration | The README includes a warning to check existing Lake Formation admins with `get-data-lake-settings` before running `put-data-lake-settings`, and to append rather than replace. This is a documentation-level mitigation; the risk remains if users skip the note. |
| EMR Serverless IAM role and network scope | The EMR Serverless role uses the `AmazonS3TablesFullAccess` managed policy for PoC convenience. The README includes explicit cleanup steps (stop application, delete application, detach policies, delete role) in both the scenario and the Cleanup section. For production, scope the role to specific table bucket ARNs and use VPC configuration to control network access. |
| Firehose IAM role with broad permissions | The Firehose role uses `glue:*` and `s3tables:*` on `Resource: "*"` because Firehose requires broad Glue permissions for Iceberg catalog operations. The role is manually created (not in the CloudFormation template) and the README includes cleanup steps. For production, scope `glue:*` to specific catalog/database ARNs and `s3tables:*` to the specific table bucket ARN. |
| Data exposure via Athena results | Athena results bucket has S3 Block Public Access enabled and AES-256 encryption. Documentation advises against using production data. |
| Resource cost overrun | README includes explicit cleanup instructions covering stack-managed resources, EMR Serverless applications and IAM roles, Firehose streams, and the federated catalog. Stack deletion removes all CloudFormation-managed resources including VPC endpoints. |

## Q4: Did we do a good enough job (for now)?

Yes, for a PoC-scoped deployment:

- The EC2 instance is in a **private subnet with no public IP, no internet access** — access is exclusively via SSM Session Manager, which is auditable through CloudTrail. All AWS API traffic flows through VPC endpoints, never traversing the public internet.
- The template follows AWS security best practices for a non-production environment (encryption at rest, public access blocks, no inbound security group rules, no internet gateway).
- The README explicitly states this is not for production use and includes cleanup instructions.
- IAM permissions are scoped to the minimum needed for PoC testing.
- No sensitive data is included in the template or sample queries.
- The federated catalog uses permissive defaults (`IAM_ALLOWED_PRINCIPALS`, `AllowFullTableExternalDataAccess: True`) appropriate for PoC testing. Production deployments should use explicit principal grants.
- The Lake Formation admin prerequisite includes a documented warning to preserve existing admins, though the risk of accidental overwrite remains if users skip the note.
- Optional scenarios (EMR Serverless, Firehose) create IAM roles outside the CloudFormation stack. These roles use broader permissions than ideal (`AmazonS3TablesFullAccess`, `glue:*` on `*`) for PoC convenience. Cleanup steps are documented for each. EMR Serverless operates outside the PoC VPC boundary, which is an accepted trade-off for a non-production environment.

For production use, additional controls would be needed (scoped IAM policies per resource ARN, explicit Lake Formation grants instead of `IAM_ALLOWED_PRINCIPALS`, VPC endpoint policies, CloudTrail logging, VPC configuration for EMR Serverless, and resource-scoped Firehose permissions), but these are out of scope for a PoC guide.
