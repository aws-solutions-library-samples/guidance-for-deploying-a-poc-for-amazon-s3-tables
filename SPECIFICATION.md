# Specification — Guidance for Deploying a PoC for Amazon S3 Tables

> **Purpose**: Single source of truth for project scope, deliverables, and current state.
> **Audience**: All contributors. Read before making changes.
> **Last updated**: 2026-05-01

---

## 1. Project Summary

Deploy a self-service PoC environment for Amazon S3 Tables, published to `aws-solutions-library-samples`. Customers deploy a CloudFormation stack, run guided test scenarios (Athena + Spark), and evaluate S3 Tables against a structured success criteria matrix.

---

## 2. Deliverables

| # | Deliverable | Path | Status |
|---|---|---|---|
| 1 | README (main guide) | `README.md` | Draft — updates in progress |
| 2 | CloudFormation template | `assets/code/s3-tables-poc.yaml` | Draft — functional, aligned |
| 3 | Architecture diagram | `assets/images/s3tablespoc-architecture-diagram.drawio.png` | Draft |
| 4 | Threat model | `threat-model.md` | Draft — needs update |
| 5 | Companion doc | `PrescriptiveGuidance_S3Tables.md` | Planned — not yet created |

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│ VPC (10.0.0.0/16)                                               │
│                                                                 │
│  ┌──────────────┐     ┌──────────────────────────────────────┐  │
│  │ Public Subnet│     │ Private Subnet                       │  │
│  │              │     │                                      │  │
│  │  NAT Gateway │     │  EC2 (t3.xlarge, AL2023, SSM-only)  │  │
│  │              │     │  ├─ Java 17 + Spark 3.5              │  │
│  └──────┬───────┘     │  └─ --packages for Iceberg runtime  │  │
│         │             └──────────────────────────────────────┘  │
│         │                          │                            │
│         │              VPC Endpoints (Interface):               │
│         │              SSM, SSMMessages, EC2Messages,           │
│         │              S3Tables, Glue, Athena                   │
│         │              VPC Endpoint (Gateway): S3               │
└─────────┼───────────────────────────┼──────────────────────────┘
          │                           │
          ▼                           ▼
   Internet (Maven)         AWS Services (private)
```

**Access paths:**
- **Athena** → Glue Data Catalog (`s3tablescatalog`) → IAM authorization
- **Spark** → S3 Tables Iceberg REST endpoint → SigV4 (`s3tables` signing) → IAM authorization

---

## 4. CloudFormation Resources

| Resource | Type | Notes |
|---|---|---|
| VPC | `AWS::EC2::VPC` | 10.0.0.0/16 |
| Public Subnet | `AWS::EC2::Subnet` | 10.0.1.0/24 — NAT Gateway only |
| Private Subnet | `AWS::EC2::Subnet` | 10.0.2.0/24 — EC2 instance |
| Internet Gateway | `AWS::EC2::InternetGateway` | For NAT Gateway outbound |
| NAT Gateway + EIP | `AWS::EC2::NatGateway` | Single-AZ, PoC-appropriate |
| S3 Gateway Endpoint | `AWS::EC2::VPCEndpoint` | Gateway type, free |
| 6× Interface Endpoints | `AWS::EC2::VPCEndpoint` | SSM, SSMMessages, EC2Messages, S3Tables, Glue, Athena |
| Endpoint Security Group | `AWS::EC2::SecurityGroup` | HTTPS from VPC CIDR |
| EC2 Security Group | `AWS::EC2::SecurityGroup` | No inbound; outbound 443+80 |
| EC2 Role + Instance Profile | `AWS::IAM::Role` | SSM core + S3Tables, S3, Glue, Athena |
| Athena Results Bucket | `AWS::S3::Bucket` | AES256, public access blocked |
| S3 Table Bucket | `AWS::S3Tables::TableBucket` | Named `{param}-{AccountId}` |
| Athena Workgroup | `AWS::Athena::WorkGroup` | CloudWatch metrics enabled |
| EC2 Instance | `AWS::EC2::Instance` | t3.xlarge, AL2023, 50 GB gp3, private subnet |

### Parameters

| Parameter | Default | Description |
|---|---|---|
| `InstanceType` | `t3.xlarge` | Allowed: t3.large/xlarge/2xlarge, m5.xlarge/2xlarge |
| `TableBucketName` | `s3-tables-poc` | Lowercase alphanumeric + hyphens |
| `DefaultNamespace` | `poc_data` | Informational only (namespace created via CLI) |

### Outputs (8)

`EC2InstanceId`, `SSMSessionCommand`, `TableBucketARN`, `TableBucketName`, `AthenaWorkgroupName`, `AthenaResultsBucketName`, `EC2RoleArn`, `Region`

---

## 5. README Structure (Required Order)

| # | Section | Description |
|---|---|---|
| 1 | Overview | Business case, what it deploys, use cases, services table, cost |
| 2 | Architecture | Diagram + numbered description |
| 3 | Prerequisites | IAM permissions, CLI, SSM plugin, supported regions |
| 4 | Deployment Steps | Stack deploy, outputs, Glue catalog, namespace, SSM connect, first table |
| 5 | Deployment Validation | Explicit "verify CREATE_COMPLETE" section |
| 6 | PoC Methodology | Success criteria matrix (fillable) |
| 7 | Test Scenarios | Scenarios 1–4 (see §6 below) |
| 8 | SME Guidance | Summaries + links to companion doc |
| 9 | Cleanup | Ordered teardown steps |
| 10 | Notices | Standard AWS disclaimer |

---

## 6. Test Scenarios

| Scenario | Title | Engine | Objective |
|---|---|---|---|
| 1 | Basic Table Operations | Athena | CRUD + time travel |
| 2 | Schema & Partition Evolution | Athena | ADD COLUMNS, NULL backfill, partition evolution |
| 3 | Automated Maintenance | Athena + CLI | Compaction, snapshot mgmt, unreferenced file removal, sort/z-order, Intelligent-Tiering |
| 4 | Multi-Engine Access | Athena + Spark | Cross-engine read/write consistency via REST endpoint |

---

## 6.1 Service Limits (Reference)

| Limit | Value | Source |
|---|---|---|
| Tables per table bucket | 10,000 | Internal wiki (current) |
| Compaction target file size | 64 MB – 512 MB | Configurable |
| Data formats | Parquet (full support), ORC/AVRO (all features except compaction) | Internal wiki |
| Encryption | SSE-S3 (default), SSE-KMS with customer-managed keys (April 2025) | Internal wiki |
| Iceberg spec version | V2 (default), V3 supported but Athena-incompatible | Internal wiki |

---

## 7. Threat Model Summary

| Threat | Severity | Mitigation |
|---|---|---|
| Over-privileged EC2 IAM role | Medium | Scoped to PoC table bucket ARN |
| Permissive federated catalog defaults | Medium | Documented as PoC-only; production guidance provided |
| Data exposure via Athena results | Low | Encryption + public access block |
| Resource cost overrun | Low | Cleanup instructions + cost tips |

---

## 8. Known Gaps (To Resolve)

| # | Gap | Impact | Resolution |
|---|---|---|---|
| 1 | Threat model references old architecture (LF, SageMaker Lakehouse, custom JARs) | Misleading | Rewrite to match current architecture |
| 2 | `DefaultNamespace` parameter unused in CFN resources | Cosmetic | Keep as informational output or remove |
| 3 | ~~Intelligent-Tiering contradiction~~ — FAQ stale. IT is GA. Config via S3 Tables API. | Resolved | ✅ Fixed in README Scenario 3h |
| 4 | EMR Serverless scenario (4b) — keep or remove? | Scope decision | Pending team decision |
| 5 | Firehose scenario (5) — keep or remove? | Scope decision | Pending team decision |
| 6 | "Enable column statistics" — GDC offers this on S3 Tables (FAQ #20) but unclear how to enable | SME Guidance accuracy | Pending clarification |
| 7 | Companion doc (`PrescriptiveGuidance_S3Tables.md`) not yet written | Deliverable gap | Create when SME Guidance exceeds ~150 lines |
| 8 | ~~Performance multipliers~~ | Resolved | ✅ Removed specific numbers, using qualitative language |
| 9 | ~~DROP TABLE via Spark~~ | Resolved | ✅ Added to Troubleshooting section |
| 10 | ~~Cost section missing compaction/monitoring fees~~ | Resolved | ✅ Added to Cost section |
| 11 | ~~SSE-KMS not mentioned~~ | Resolved | ✅ Added to Security Best Practices |
| 12 | ~~Table limit (10k) not documented~~ | Resolved | ✅ Added to Service Limits table |

---

## 9. Publication Requirements

**Target repo**: `aws-solutions-library-samples`
**Reference**: [deploy-a-poc-of-aws-backup](https://github.com/aws-solutions-library-samples/deploy-a-poc-of-aws-backup)

### Required Repo Structure

```
assets/
  code/
    s3-tables-poc.yaml
  images/
    s3tablespoc-architecture-diagram.drawio.png
deployment/
source/
CODE_OF_CONDUCT.md
CONTRIBUTING.md
LICENSE                              (MIT-0)
PrescriptiveGuidance_S3Tables.md     (companion doc)
README.md
threat-model.md
```

### Community Files

| File | Standard |
|---|---|
| `CODE_OF_CONDUCT.md` | Amazon Open Source |
| `CONTRIBUTING.md` | Amazon Open Source |
| `LICENSE` | MIT-0 |
