# Threat Model — Guidance for Deploying a PoC for Amazon S3 Tables

## Q1: What are we building?

This Guidance deploys a proof-of-concept environment for Amazon S3 Tables, consisting of:

- A VPC with a public subnet and internet gateway
- An Amazon EC2 instance (Amazon Linux 2023) serving as a test host with Apache Spark installed
- An Amazon S3 table bucket for storing Apache Iceberg tables (V2 and V3 supported)
- An Amazon Athena workgroup with a dedicated S3 results bucket
- IAM roles and instance profiles granting the EC2 instance access to S3 Tables, Glue Data Catalog, Athena, and Lake Formation

The environment is intended for short-lived PoC testing only, not production workloads. Users deploy the CloudFormation template, create Iceberg tables, ingest sample data, and query it via Athena or Spark. Optional scenarios include testing sort/z-order compaction, Intelligent-Tiering, and streaming ingestion via Firehose.

**Data flow:**
1. User connects to EC2 via SSH or SSM.
2. User creates tables in S3 table bucket via AWS CLI or Spark.
3. User queries tables via Athena (through Glue Data Catalog) or Spark (via S3 Tables catalog).
4. Athena query results are stored in a dedicated S3 bucket.
5. (Optional) User creates an Amazon Data Firehose delivery stream via the console to test streaming ingestion into S3 Tables.

## Q2: What can go wrong?

| Threat | Description | Severity |
|---|---|---|
| Unauthorized SSH access | EC2 instance is in a public subnet with SSH open to the configured CIDR. If set to 0.0.0.0/0, anyone can attempt SSH. | Medium |
| Over-privileged IAM role | EC2 role has broad S3 Tables and Glue permissions. If the instance is compromised, attacker gains access to table data. | Medium |
| Data exposure via Athena results | Athena results bucket could contain query output with sensitive data if users load real data. | Low |
| Unencrypted data in transit | SSH connections are encrypted, but Spark connections to S3 Tables use HTTPS by default. | Low |
| Firehose data ingestion | If Firehose is configured (optional Scenario 5), the delivery stream IAM role has write access to S3 Tables. Misconfigured streams could ingest unintended data. | Low |
| Resource cost overrun | Users may forget to clean up resources (including manually created Firehose streams), leading to ongoing charges. | Low |

## Q3: What can we do about it?

| Threat | Mitigation |
|---|---|
| Unauthorized SSH access | Default parameter prompts users to restrict SSH CIDR to their IP. Documentation recommends using /32 CIDR. SSM access is also available as an alternative. |
| Over-privileged IAM role | IAM policy is scoped to read/write operations needed for PoC. No admin-level permissions. S3 Tables actions are limited to the deployed table bucket where possible. |
| Data exposure via Athena results | Athena results bucket has S3 Block Public Access enabled and AES-256 encryption. Documentation advises against using production data. |
| Unencrypted data in transit | All AWS API calls use HTTPS/TLS. S3 Tables API endpoints enforce TLS. |
| Firehose data ingestion | Firehose is not deployed by the CloudFormation template — it is manually created via the console only if the user opts into Scenario 5. The IAM role created for Firehose is scoped to the specific table bucket and delivery operations. |
| Resource cost overrun | README includes explicit cleanup instructions. Stack deletion removes all stack-managed resources. Documentation reminds users to also delete any manually created resources such as Firehose streams. |

## Q4: Did we do a good enough job (for now)?

Yes, for a PoC-scoped deployment:

- The template follows AWS security best practices for a non-production environment (encryption at rest, public access blocks, security group restrictions).
- The README explicitly states this is not for production use and includes cleanup instructions.
- IAM permissions are scoped to the minimum needed for PoC testing.
- The primary risk (SSH access) is mitigated by parameterization and documentation guidance.
- No sensitive data is included in the template or sample queries.

For production use, additional controls would be needed (private subnets, VPC endpoints, more granular IAM policies, CloudTrail logging, etc.), but these are out of scope for a PoC guide.
