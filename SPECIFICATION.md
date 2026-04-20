# Specification — Guidance for Deploying a PoC for Amazon S3 Tables

> Current state snapshot of all deliverables. Updated: 2026-04-20

## Deliverables Inventory

| # | Deliverable | File | Status |
|---|---|---|---|
| 1 | README (main guide) | `README.md` | Draft — pending leader feedback |
| 2 | CloudFormation template | `s3-tables-poc.yaml` | Draft — functional |
| 3 | Architecture diagram | `s3tablespoc-architecture-diagram.drawio.png` | Draft |
| 4 | Threat model | `threat-model.md` | Draft — 4-question format |

## README.md — Section Inventory

| Section | Lines (approx) | Summary |
|---|---|---|
| Overview / Business Case | ~30 | Why this guide exists, what it deploys, target use cases, services table |
| Architecture | ~10 | Diagram reference + 6-point architecture description |
| Cost | ~15 | Daily cost estimate table (US East, March 2026 pricing) |
| Prerequisites | ~40 | Account permissions, CLI, SSM plugin, Lake Formation admin setup, supported regions table (35 regions) |
| Deployment Steps (1–6) | ~150 | Stack deploy, outputs, SageMaker Lakehouse catalog, namespace + LF grants, SSM connect, first Athena table |
| PoC Methodology | ~20 | Success criteria matrix (14 dimensions across Functionality, Performance, Integration, Security, Cost) |
| Scenario 1: Basic Table Ops | ~50 | Insert, query, update, delete, time travel |
| Scenario 2: Schema Evolution | ~15 | ADD COLUMNS, insert with new schema, NULL backfill |
| Scenario 3: Automated Maintenance | ~120 | Partitioned table, 10-insert small-file generation, metadata monitoring, compaction observation, CloudWatch metrics, sort/z-order config via Spark + API, optional 1000-file generation |
| Scenario 3c: Intelligent-Tiering | ~40 | Enable IT on table bucket, storage usage check, cost projection table, CloudWatch verification |
| Scenario 4: Multi-Engine Access | ~60 | Athena insert → Spark read, Spark insert → Athena read |
| Scenario 4b: EMR Serverless | ~80 | IAM role, create app, PySpark script upload, job submit, monitor, review logs, cleanup |
| Scenario 5: Firehose Streaming | ~80 | IAM role, LF grants, console-based stream creation, 10-record CLI send, verify in Athena, troubleshooting table |
| SME Guidance | ~80 | Table bucket design, performance optimization, security, cost optimization, S3 Tables vs self-managed comparison table, decision guide, hybrid approach |
| Cleanup | ~30 | Delete tables/namespaces, empty buckets, delete EMR/Firehose resources, delete catalog, delete stack |
| Notices | ~10 | Standard AWS disclaimer |

## CloudFormation Template — Resource Inventory

| Resource | Type | Notes |
|---|---|---|
| VPC | `AWS::EC2::VPC` | 10.0.0.0/16 |
| PublicSubnet | `AWS::EC2::Subnet` | 10.0.1.0/24 — hosts NAT Gateway only |
| PrivateSubnet | `AWS::EC2::Subnet` | 10.0.2.0/24 — hosts EC2 |
| InternetGateway + Attachment | `AWS::EC2::InternetGateway` | For NAT Gateway outbound |
| NATGateway + EIP | `AWS::EC2::NatGateway` | Single-AZ, PoC-appropriate |
| S3 Gateway Endpoint | `AWS::EC2::VPCEndpoint` (Gateway) | Free |
| 5× Interface Endpoints | `AWS::EC2::VPCEndpoint` (Interface) | SSM, SSMMessages, EC2Messages, S3Tables, Glue, Athena |
| Endpoint Security Group | `AWS::EC2::SecurityGroup` | HTTPS from VPC CIDR |
| EC2 Security Group | `AWS::EC2::SecurityGroup` | No inbound; outbound 443+80 |
| EC2 Role + Instance Profile | `AWS::IAM::Role` | SSM core + S3Tables, S3, Glue, Athena, LakeFormation |
| Athena Results Bucket | `AWS::S3::Bucket` | AES256, public access blocked |
| S3 Table Bucket | `AWS::S3Tables::TableBucket` | Named `{param}-{AccountId}` |
| Athena Workgroup | `AWS::Athena::WorkGroup` | CloudWatch metrics enabled |
| EC2 Instance | `AWS::EC2::Instance` | t3.xlarge default, AL2023, 50GB gp3, private subnet |

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `InstanceType` | `t3.xlarge` | Allowed: t3.large/xlarge/2xlarge, m5.xlarge/2xlarge |
| `TableBucketName` | `s3-tables-poc` | Lowercase alphanumeric + hyphens |
| `DefaultNamespace` | `poc_data` | Not used in resources (namespace created via CLI) |

### Outputs (9)

`EC2InstanceId`, `SSMSessionCommand`, `TableBucketARN`, `TableBucketName`, `AthenaWorkgroupName`, `AthenaResultsBucketName`, `EC2RoleArn`, `LakeFormationCatalogId`, `DefaultNamespace`, `Region`

## Threat Model Summary

Uses the 4-question format (What are we building? What can go wrong? What can we do? Good enough?).

| Threat | Severity | Mitigation |
|---|---|---|
| Over-privileged EC2 IAM role | Medium | Scoped to PoC operations |
| Permissive federated catalog defaults | Medium | Documented as PoC-only |
| Lake Formation admin misconfiguration | Medium | Warning to check existing admins |
| EMR Serverless role + network scope | Medium | Cleanup steps documented |
| Firehose role with broad permissions | Medium | Cleanup steps documented |
| Data exposure via Athena results | Low | Encryption + public access block |
| Resource cost overrun | Low | Cleanup instructions provided |

## Known Gaps / Observations

- **UserData is a stub**: The CFN EC2 UserData only writes a completion marker. It does not install Java 17, Spark, or Iceberg JARs — but the README says it does. This is a mismatch.
- **DefaultNamespace parameter unused**: Declared as a CFN parameter and output but never referenced in any resource. Namespace is created manually via CLI in Step 4.
- **README says "no NAT Gateway"**: The architecture description says "no NAT Gateway or internet gateway required" but the CFN template deploys both an IGW and a NAT Gateway.
- **README says 6 VPC endpoints**: The architecture section says 6, but the CFN template creates 7 (1 gateway + 6 interface).
- **Scenario numbering inconsistency**: Scenario 3c (Intelligent-Tiering) is nested under Scenario 3 but uses a different naming convention than 3a–3k.
- **Step reference mismatch**: Troubleshooting section references "Step 3c" for Lake Formation grants, but the actual grants are in Step 4b.
- **Environment variable inconsistency**: Step 2 sets `WORKGROUP="$WORKGROUP"` (self-referencing) instead of the actual output value.
- **CFN Description mentions public subnet**: Says "public and private subnets" which is accurate for the template but contradicts the README's "no internet gateway" claim.
- **10 outputs listed, 9 declared**: The Outputs section header says 9 but there are actually 10 outputs in the template.
- **Iceberg V3 mentioned in SME Guidance**: "Start with Iceberg V3 for new tables" but no scenario demonstrates V3-specific features (deletion vectors, row lineage).
