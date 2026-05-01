# AIDLC Audit Log — Guidance for Deploying a PoC for Amazon S3 Tables

> Complete audit trail of all interactions and decisions.

---

## Workspace Detection
**Timestamp**: 2026-05-01T00:00:00Z
**User Input**: "Review the repo, initialise as we will build on this AIDLC framework"
**AI Response**: Scanned workspace. Identified brownfield project with existing artifacts: README.md, CloudFormation template (s3-tables-poc.yaml), architecture diagram, threat model, SPECIFICATION.md, and STEERING.md. No prior AIDLC artifacts found. Created aidlc-docs/ directory with state tracking and audit log.
**Context**: Workspace Detection stage — initial project classification

### Findings

- **Classification**: Brownfield — existing codebase with documentation
- **Existing Code**: CloudFormation template (fully functional), README with test scenarios
- **Existing Docs**: SPECIFICATION.md (gap analysis), STEERING.md (design decisions and must-dos)
- **Key Observation**: STEERING.md contains 19 must-do items and 9 don'ts that define the scope of remaining work. The threat model references outdated architecture (Lake Formation, SageMaker Lakehouse, custom JARs) that conflicts with STEERING.md decisions.
- **Rule Details Directory**: Not found at any expected path (.aidlc-rule-details/, .kiro/aws-aidlc-rule-details/, .amazonq/aws-aidlc-rule-details/). Framework will operate with core-workflow.md rules only.

---

## Document Restructuring
**Timestamp**: 2026-05-01T00:01:00Z
**User Input**: "Yeah, but most of the STEERING and SPECIFICATION are verbose dump of my notes. Read them and fix them to become AIDLC standards - so I can commit and everyome on the team is on the same page"
**AI Response**: Rewrote both SPECIFICATION.md and STEERING.md to AIDLC standards. Removed verbose prose, applied structured tables, numbered sections, clear hierarchy. Preserved all decisions, constraints, and open questions. Made both documents scannable and team-ready.
**Context**: Pre-inception document cleanup — making existing artifacts commit-ready for team consumption.

### Changes Made

**SPECIFICATION.md** (was ~200 lines of mixed prose/tables → now 9 clean sections):
- Added ASCII architecture diagram
- Consolidated resource inventory into single table
- Fixed output count (8, not 9 or 10)
- Removed redundant README section inventory (replaced with required order table)
- Consolidated test scenarios into summary table
- Simplified threat model to current-state threats only
- Converted "Known Gaps" to actionable resolution table
- Added publication requirements section

**STEERING.md** (was ~300 lines of mixed prose → now 9 numbered sections):
- Converted design principles to scannable table format
- Consolidated "Must-Dos" into prioritized work items (High/Medium/Low)
- Converted "Don'ts" to numbered hard rules table
- Added execution order as visual sequence
- Simplified leader feedback log (removed verbose status descriptions)
- Kept all open questions intact
- Kept companion document plan intact

---

## Internal Wiki Cross-Reference
**Timestamp**: 2026-05-01T00:02:00Z
**User Input**: User provided internal S3 Tables wiki content (w.amazon.com S3 Tables BasicTroubleshooting page). Asked to identify contradictions/stale content and apply fixes 1,3,4,5,6,7,8,9. Requested more context on fix 2 (IT storage class contradiction).
**AI Response**: Applied 8 fixes to STEERING.md and SPECIFICATION.md. Provided detailed context on IT contradiction (FAQ #21 vs published blog post) — flagged as blocking for Scenario 3h pending team verification.
**Context**: Cross-referencing internal wiki against project artifacts to identify stale/contradictory content.

### Fixes Applied

| Fix | Description | Files Changed |
|---|---|---|
| 1 | Refined V3 rule: "not for this PoC" (Athena incompatible) rather than blanket ban | STEERING §4 rule 5, §5.3 L1 |
| 3 | Remove specific performance multipliers — use qualitative language | STEERING §1 principle 8, §4 rule 7, §5.3 L3 |
| 4 | Added DROP TABLE troubleshooting work item (purge=false fails) | STEERING §5.3 L8, SPECIFICATION §8 gap 9 |
| 5 | Added SSE-KMS mention work item | STEERING §5.3 L9, SPECIFICATION §8 gap 11 |
| 6 | Added compaction/monitoring billing work item | STEERING §5.3 L10, SPECIFICATION §8 gap 10 |
| 7 | Added 10,000 table limit | STEERING §5.3 L11, SPECIFICATION §6.1 |
| 8 | Added ORC/AVRO support note | STEERING §5.3 L12, SPECIFICATION §6.1 |
| 9 | Confirmed replication GA; updated companion doc plan | STEERING §8 section 5, §5.3 L13 |

### Deferred (Fix 2 — IT Contradiction)

Flagged as STEERING §7 Q8 (blocking). Needs team resolution before Scenario 3h can be finalized.

---

## AWS Documentation Verification
**Timestamp**: 2026-05-01T00:03:00Z
**User Input**: "since we are starting fresh, can you verify things we are stating against aws docs before we build or rebuild anything?"
**AI Response**: Verified 9 key claims against public AWS documentation. Found 2 high-severity issues (IT config syntax wrong, sort compaction JSON wrong), 1 decision point (Spark access method), and confirmed several existing decisions. Full findings documented in aidlc-docs/inception/verification-findings.md.
**Context**: Pre-build verification pass — ensuring all technical claims are accurate before construction.

### Key Findings

1. **Spark access**: AWS now recommends Glue IRC endpoint for Spark, but S3 Tables REST is valid for single-bucket PoC. Decision: keep S3 Tables REST (IAM-first, simpler).
2. **VPC endpoints**: Confirmed both S3 gateway + S3 Tables interface needed. Our CFN already correct.
3. **IT config**: Must use S3 Tables API (`PutTableBucketStorageClass`), NOT Athena TBLPROPERTIES. Scenario 3h needs rewrite.
4. **Sort compaction**: Sort order defined in table metadata (Spark DDL), not in maintenance config JSON. Scenario 3g needs fix.
5. **Snapshot defaults**: 1 snapshot / 120 hours (not 3/72 as we recommend — but our recommendation is intentionally more conservative for PoC).
6. **DROP TABLE**: Confirmed purge=false fails. Must add note.
7. **SageMaker Lakehouse**: Removed from docs access page. Confirms our decision.
8. **CTAS not supported** via S3 Tables REST endpoint — must not include CTAS scenarios for Spark path.

### Files Updated
- STEERING.md: Resolved open questions 1 and 3, added H6/H7 work items, updated architecture decision for Spark endpoint
- aidlc-docs/inception/verification-findings.md: Created with full findings

---

## Verification Fixes Applied
**Timestamp**: 2026-05-01T00:04:00Z
**User Input**: "Fix them all"
**AI Response**: Applied all verification fixes to README.md, STEERING.md, and SPECIFICATION.md.
**Context**: Applying fixes identified during AWS documentation verification pass.

### Changes Applied to README.md

| Fix | Section | Change |
|---|---|---|
| Performance claims | Overview | Removed "3x faster" and "10x TPS" — now says "improved query performance and higher TPS" |
| IT configuration | Scenario 3h | Rewrote entirely: uses `put-table-bucket-storage-class` API, not TBLPROPERTIES |
| Sort compaction | Scenario 3g | Removed invalid `sortOrder` array from JSON; added prerequisite steps (define sort order via Spark DDL first) |
| Snapshot defaults | Scenario 3d | Documented actual defaults (1/120h), added failure conditions note |
| Cost section | Cost | Added monitoring fee line item + explanatory note about compaction/monitoring charges |
| DROP TABLE | SME Guidance (new Troubleshooting table) | Added with cause and resolution |
| CTAS limitation | Scenario 4 header | Added note that CTAS not supported via S3 Tables REST endpoint |
| SSE-KMS | SME Guidance (Security) | Added one-liner about SSE-KMS support |
| Table limits | SME Guidance (new Service Limits table) | Added 10,000 tables/bucket, file size range, ORC/AVRO support, V3 status |
| ORC/AVRO | SME Guidance (Service Limits + comparison table) | Noted support with compaction limitation |
| Replication | SME Guidance (comparison table) | Added row for cross-region replication |
| Glue IRC recommendation | SME Guidance (new section) | Added "Multi-Engine Access: Production Considerations" |
| Snapshot management | SME Guidance | Documented actual defaults and API-only configuration |

### Changes Applied to STEERING.md
- Resolved open questions 1 and 3
- Added H6 (IT config rewrite) and H7 (sort compaction fix) to work items
- Updated Spark architecture decision with CTAS limitation and Glue IRC note

### Changes Applied to SPECIFICATION.md
- Marked gaps 3, 8, 9, 10, 11, 12 as resolved

---

## New Stack + Working Guide Created
**Timestamp**: 2026-05-01T00:05:00Z
**User Input**: "cool.. can you build a stack first to align with this and some low level guide for me to follow? We can refine the README to be perfect later. Or best, create a new README to be replaced later"
**AI Response**: Created updated CFN template and README-v2.md with phased scenario structure.
**Context**: Building infrastructure and working guide aligned with new use-case-driven approach.

### CFN Template Changes (assets/code/s3-tables-poc.yaml)
- Added: FirehoseRole (IAM role for Firehose with scoped S3 Tables + Glue + backup bucket permissions)
- Added: FirehoseBackupBucket (S3 bucket for Firehose error records, 7-day lifecycle)
- Added: CloudWatch permissions to EC2 role (GetMetricStatistics, GetMetricData, ListMetrics)
- Added: 3 new outputs (FirehoseBackupBucketName, FirehoseRoleArn, Region)
- Kept: All existing networking, VPC endpoints, EC2, Athena, S3 Table Bucket unchanged

### README-v2.md Structure
- Phase 1: Foundation (deploy, catalog, namespace, CRUD, Spark validation)
- Phase 2: Data Ingestion (batch via Spark 50K rows, stream via Firehose)
- Phase 3: Observability (table metadata, CloudWatch compaction/storage metrics)
- Phase 4: Administration (schema evolution, snapshot mgmt, unreferenced file removal, compaction strategies, IT, time travel)
- Cleanup: Ordered teardown including Firehose stream

### Note
- Firehose delivery stream is created via CLI (not CFN) because it depends on the Glue catalog which is created post-deploy
- The table bucket policy for Firehose access is also set via CLI post-deploy

---

## Architecture Simplification — Remove EC2/VPC
**Timestamp**: 2026-05-01T00:06:00Z
**User Input**: "If spark JAR is gone, why do we need EC2? Is that for spark operations? what is an alternate AWS service or IDE that customers could do that from?" followed by "Maybe a notebook that they could run using SageMaker AI notebook, Studio, or local IDE?"
**AI Response**: Removed EC2, VPC, NAT Gateway, and all 6 VPC endpoints from the stack. Replaced with a PyIceberg notebook that runs on SageMaker AI, Studio, or local IDE. Stack cost dropped from ~$7/day to ~$0.16/day.
**Context**: Major architecture simplification — EC2 existed only as a Spark host. PyIceberg via REST endpoint eliminates the need for JVM/Spark infrastructure entirely.

### Changes
- **CFN template**: Removed VPC, subnets, IGW, NAT, EIP, route tables, 7 VPC endpoints, 2 security groups, EC2 instance, EC2 role, instance profile. Added CloudWatch permissions note removed (not needed — user's own credentials handle this).
- **New file**: `assets/code/s3_tables_poc.ipynb` — Jupyter notebook with PyIceberg REST catalog, multi-engine validation, 50K record batch load, metadata inspection.
- **README-v2.md**: Rewritten for no-EC2 architecture. Phase 1 uses CLI + notebook. Phase 2 uses Firehose CLI. Phases 3-4 use CLI.

### Cost Impact
| Component | Before | After |
|---|---|---|
| EC2 (t3.xlarge) | $4.00/day | $0 |
| NAT Gateway | $1.10/day | $0 |
| VPC Endpoints (×6) | $1.73/day | $0 |
| S3 Tables + Athena | $0.16/day | $0.16/day |
| **Total** | **$7.00/day** | **$0.16/day** |

---

## Conditional SageMaker Notebook
**Timestamp**: 2026-05-01T00:07:00Z
**User Input**: "Can we make CFN with a variable to deploy -- with and without notebook?"
**AI Response**: Added DeployNotebook parameter (Yes/No, default Yes) with CloudFormation Condition. SageMaker notebook instance, IAM role, and lifecycle config only deploy when Yes. Notebook URL output is conditional.
**Context**: Making the notebook optional so customers can choose SageMaker (zero auth setup) or local IDE (bring your own credentials).

### CFN Changes
- Added: Parameters — DeployNotebook (Yes/No), NotebookInstanceType (ml.t3.medium/large/xlarge)
- Added: Condition — CreateNotebook
- Added: NotebookRole (IAM role with s3tables, glue, athena, cloudwatch, cloudformation:DescribeStacks)
- Added: NotebookLifecycleConfig (installs pyiceberg on start)
- Added: NotebookInstance (conditional, AL2 v2, direct internet)
- Added: Outputs — NotebookUrl (conditional), NotebookName (conditional)
- Updated: README-v2.md with Option A/B deploy paths, notebook instructions, cleanup step

---

## Steering: Environment-Neutral + Clone-First Rules
**Timestamp**: 2026-05-01T00:08:00Z
**User Input**: "add to steering doc that whenever we write a new step -- ensure it has to be neutral and without dependency on SageMaker notebook distribution. Also, keep the steps same -- clone the repo"
**AI Response**: Added Design Principles #10 (environment-neutral notebook) and #11 (clone-first workflow). Added Do NOT rules #10-12 (no SageMaker-specific APIs, no environment assumptions, no manual file creation). Updated README-v2 Quick Start to begin with git clone.
**Context**: Ensuring all notebook content is portable and the PoC workflow starts from a repo clone.

---

## README-v2: Clear Notebook vs Local IDE Paths
**Timestamp**: 2026-05-01T00:09:00Z
**User Input**: "yeah -- with clear steps in README on what happens if they chose to deploy with notebook or without. Default should be Yes to keep things simple"
**AI Response**: Rewrote Quick Start (Step 1-3 structure with clone first), What This Deploys (clear default vs lightweight table), and Phase 1.4 (separated notebook vs local IDE paths with step-by-step instructions and a cell-by-cell table of what the notebook does).
**Context**: Making the two deployment paths crystal clear for customers.

---
