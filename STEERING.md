# Steering — Guidance for Deploying a PoC for Amazon S3 Tables

> **Purpose**: Authoritative design decisions and constraints. All changes must comply.
> **Audience**: All contributors. Violations are blocking.
> **Last updated**: 2026-05-01

---

## 1. Design Principles

| # | Principle | Rationale |
|---|---|---|
| 1 | **IAM-first** | No Lake Formation grants. No LF admin prerequisite. LF mentioned only as production option in SME Guidance. |
| 2 | **No custom JARs** | Spark uses S3 Tables Iceberg REST endpoint with SigV4. Standard `--packages` from Maven. No `S3TablesCatalog` JAR. |
| 3 | **Two access paths** | Athena via Glue catalog (`s3tablescatalog`). Spark via REST endpoint. Both IAM-authorized. |
| 4 | **Copy-paste fidelity** | Every CLI command runnable as-is. Only clearly marked placeholders. |
| 5 | **Minimal prerequisites** | IAM permissions + AWS CLI v2 + SSM plugin. Nothing else. |
| 6 | **Namespace-centric** | Multiple namespaces within one table bucket. Never recommend multiple table buckets. |
| 7 | **Binpack-first** | Default compaction strategy. Sort/z-order presented as advanced options after binpack is understood. |
| 8 | **Accurate claims only** | Every statement verifiable against current AWS documentation. No specific performance multipliers (e.g., "3x faster") — use qualitative language ("improved query performance and higher TPS") unless citing a specific benchmark. |
| 9 | **AWS SDK/CLI-first** | AWS SDKs, CLI, Apache-licensed or AWS-published Maven artifacts only. No community forks, no unsigned binaries. |
| 10 | **Environment-neutral notebook** | All notebook cells and steps must run identically on SageMaker AI Notebook, SageMaker Studio, or a local IDE (VS Code, PyCharm, JupyterLab). No dependency on SageMaker-specific libraries, kernels, or magic commands. Use only standard Python (`pyiceberg`, `boto3`, `pyarrow`, `pandas`). |
| 11 | **Clone-first workflow** | The PoC starts with `git clone` of the repo. All paths in the README and notebook reference files relative to the repo root. No manual file creation or copy-paste of notebook cells. |

---

## 2. Architecture Decisions

| Decision | Detail |
|---|---|
| IAM-only access control | Eliminates ~6 LF grant steps. Matches AWS default integration path. |
| S3 Tables REST endpoint for Spark | `https://s3tables.<region>.amazonaws.com/iceberg` with SigV4 (`s3tables` signing name). No Glue/LF dependency. AWS recommends Glue IRC endpoint for production multi-service access, but S3 Tables REST is valid for single-bucket PoC and aligns with IAM-first principle. Note: CTAS not supported via this endpoint. |
| Glue catalog for Athena | Required path. `s3tablescatalog` federated catalog + `IAM_ALLOWED_PRINCIPALS` = IAM-only in practice. |
| NAT Gateway + VPC endpoints | EC2 needs internet for `--packages` downloads. VPC endpoints for AWS service traffic. |
| Single table bucket | Namespaces provide logical separation (raw, curated, analytics). |

---

## 3. Constraints

| Constraint | Detail |
|---|---|
| Regional coverage | Must deploy in all 35 supported S3 Tables regions |
| Single-command deploy | `aws cloudformation deploy` — no multi-step infrastructure setup |
| Cost ceiling | Under ~$15/day for default configuration |
| Copy-paste commands | All CLI commands copy-pasteable with marked placeholders |
| No PII | No real customer data in examples |
| Notices required | Standard AWS disclaimer in README |
| Threat model required | Must accompany the guide |
| Lowercase identifiers | All table/column names lowercase (Glue catalog requirement) |

---

## 4. Do NOT

These are hard rules. Violations are blocking.

| # | Rule |
|---|---|
| 1 | Do NOT reference SageMaker Lakehouse anywhere |
| 2 | Do NOT use `S3TablesCatalog` JAR or `software.amazon.s3tables.iceberg.S3TablesCatalog` |
| 3 | Do NOT require Lake Formation admin as a prerequisite |
| 4 | Do NOT include `lakeformation grant-permissions` commands in the main flow |
| 5 | Do NOT recommend Iceberg V3 for this PoC (Athena does not support V3 tables; V3 is valid for EMR Spark + Glue ETL-only workflows) |
| 6 | Do NOT recommend "one table bucket per workload/domain" |
| 7 | Do NOT make unverifiable performance claims or cite specific multipliers without a benchmark source |
| 8 | Do NOT present Iceberg-native features (hidden partitioning, schema evolution) as S3 Tables-specific |
| 9 | Do NOT present engine-agnostic optimizations as Athena-specific |
| 10 | Do NOT use SageMaker-specific APIs, magic commands (`%sm_analytics`), or SageMaker Studio-only features in notebook cells |
| 11 | Do NOT assume the notebook runs in a specific environment — all cells must work with standard `pip install` dependencies |
| 12 | Do NOT instruct users to create files manually — all artifacts come from the cloned repo |

---

## 5. Work Items

### 5.1 High Impact (Structural)

| # | Item | Files Affected |
|---|---|---|
| H1 | Remove all LF grants, LF admin prerequisite from main flow | README, threat model |
| H2 | Replace Spark scenarios to use S3 Tables Iceberg REST endpoint with SigV4 | README (Scenario 4) |
| H3 | Remove SageMaker Lakehouse references | README, threat model |
| H4 | Update EC2 UserData — install Java 17 + Spark, use `--packages` (no JAR pre-install) | CFN template |
| H5 | Fix README/CFN alignment: NAT Gateway exists, is needed, document accurately | README (Architecture) |
| H6 | **Rewrite Scenario 3h**: IT is configured via S3 Tables API (`PutTableBucketStorageClass`), NOT TBLPROPERTIES | README |
| H7 | **Fix Scenario 3g**: Sort order is defined in table metadata (via Spark DDL), not in maintenance config JSON | README |

### 5.2 Medium Impact (Content)

| # | Item | Files Affected |
|---|---|---|
| M1 | Rewrite SME Guidance: compaction (binpack-first), security (IAM-first), comparison table | README |
| M2 | Add snapshot expiry + unreferenced file removal to maintenance guidance | README (Scenario 3) |
| M3 | Incorporate Intelligent-Tiering blog optimizations | README (Scenario 3h) |
| M4 | Rewrite Security Best Practices: IAM resource-based policies lead, LF as optional | README |
| M5 | Review "S3 Tables vs Self-Managed Iceberg" comparison | README |
| M6 | Rewrite threat model to reflect current architecture | threat-model.md |

### 5.3 Low Impact (Wording)

| # | Item | Files Affected |
|---|---|---|
| L1 | Refine V3 language: acknowledge V3 exists, explain why not used in this PoC (Athena incompatibility) | README |
| L2 | Fix "hidden partitioning" language — native to Iceberg, not S3 Tables-specific | README |
| L3 | Remove all specific performance multipliers ("3x faster", "50% faster") — use qualitative language | README |
| L4 | Remove "avoid manual compaction" — state S3 Tables handles it automatically | README |
| L5 | Make "columnar filtering" guidance engine-agnostic | README |
| L6 | Clarify or remove "Enable column statistics" (pending clarification) | README |
| L7 | Fix "partition columns" guidance — add high-cardinality context | README |
| L8 | Add DROP TABLE troubleshooting note (purge=false fails; use `DELETE TABLE` API or `DROP TABLE PURGE`) | README |
| L9 | Add SSE-KMS mention in SME Guidance: supported for production, PoC uses default SSE-S3 | README |
| L10 | Update cost section: mention compaction charges (objects + bytes) and monthly monitoring fee per object | README |
| L11 | Add table limit note: 10,000 tables per table bucket | README (SME Guidance) |
| L12 | Note ORC/AVRO support (all features except compaction) in comparison or SME Guidance | README |
| L13 | Confirm replication is GA; include in companion doc when written | PrescriptiveGuidance_S3Tables.md |

---

## 6. Execution Order

Sequence to minimize rework:

```
1. CFN template ──────► Verify UserData, NAT/endpoints, IAM (no LF actions)
2. README structure ──► Remove LF flow, remove SageMaker Lakehouse, rewrite Step 3
3. Spark scenarios ───► Rewrite Scenario 4 to use REST endpoint
4. SME Guidance ──────► Compaction, security, comparison, snapshot/pruning
5. Wording fixes ─────► All L1–L7 items
6. Threat model ──────► Reflect new architecture
7. Consistency pass ──► Cross-references, step numbers, env variables
```

---

## 7. Open Questions

| # | Question | Owner | Status |
|---|---|---|---|
| 1 | ~~Does S3 Tables REST endpoint require a VPC interface endpoint?~~ | — | ✅ Resolved — Yes, need both: S3 gateway endpoint (data files) + S3 Tables interface endpoint (table ops). Our CFN already has both. |
| 2 | ~~Can Spark `--packages` pull from Maven via NAT Gateway?~~ | — | ✅ Confirmed (UserData installs Spark, `--packages` downloads at runtime via NAT) |
| 3 | ~~What IT blog content to incorporate?~~ | — | ✅ Resolved — IT is configured via S3 Tables API (`PutTableBucketStorageClass` or `CreateTable` header), NOT TBLPROPERTIES. Rewrite Scenario 3h. |
| 4 | Internal FAQ content for S3 Tables vs Self-Managed comparison? | Lee/Fabio | Open |
| 5 | "Enable column statistics" — GDC FAQ #20 confirms GDC offers column stats collection on S3 Tables. Clarify how to enable and whether it's PoC-relevant. | Lee/Fabio | Open |
| 6 | EMR Serverless scenario (4b) — keep? If yes, REST or Glue endpoint? | Lee/Fabio | Open |
| 7 | Firehose scenario (5) — keep? May need LF for Firehose role. | Lee/Fabio | Open |
| 8 | ~~Intelligent-Tiering vs "no storage classes" contradiction~~ — Internal FAQ #21 is stale (written at launch Dec 2024). IT support confirmed GA via published AWS blog. Scenario 3h is valid. | — | ✅ Resolved — FAQ stale |

---

## 8. Companion Document Plan

When README SME Guidance exceeds ~150 lines, extract deep-dive content into `PrescriptiveGuidance_S3Tables.md`:

| Section | Content |
|---|---|
| 1. Namespace Design | Table bucket design patterns, logical separation |
| 2. Compaction Strategies | Binpack vs sort vs z-order, target file size, auto strategy, IT interaction |
| 3. Snapshot & File Lifecycle | Retention tuning, delete file accumulation, time travel vs cost |
| 4. Intelligent-Tiering | Tier transitions, compaction interaction, cost projection |
| 5. Replication | Cross-region table bucket replication (confirmed GA), DR patterns, failed replication troubleshooting, consistency |
| 6. Security & Access Control | IAM policies, LF for fine-grained, VPC endpoint policies, cross-account |
| 7. S3 Tables vs Self-Managed | Comparison matrix, decision framework, hybrid approach, migration |

---

## 9. Leader Feedback Log

| # | Date | Feedback | Resolution |
|---|---|---|---|
| 1 | 2026-04-20 | Remove SageMaker Lakehouse | ✅ Use Glue catalog + IAM |
| 2 | 2026-04-20 | IAM for permissions, remove LF | ✅ IAM-only for Athena and Spark |
| 3 | 2026-04-20 | Remove S3TablesCatalog JAR | ✅ S3 Tables REST endpoint |
| 4 | 2026-04-20 | "More namespaces" not "more table buckets" | ✅ Update guidance |
| 5 | 2026-04-20 | Remove Iceberg V3 recommendation | ✅ Remove |
| 6 | 2026-04-20 | Compaction: start with binpack | ✅ Rewrite guidance |
| 7 | 2026-04-20 | Hidden partitioning is Iceberg-native | ✅ Reword |
| 8 | 2026-04-20 | "Enable column statistics" unclear | ⏳ Pending clarification |
| 9 | 2026-04-20 | Partition columns guidance unclear | ⏳ Needs high-cardinality context |
| 10 | 2026-04-20 | Columnar filtering not Athena-specific | ✅ Make engine-agnostic |
| 11 | 2026-04-20 | Remove "avoid manual compaction" | ✅ Remove |
| 12 | 2026-04-20 | "Performance gap widens" is false | ✅ Remove |
| 13 | 2026-04-20 | Add snapshots and pruning guidance | ⏳ Add to maintenance |
| 14 | 2026-04-20 | Add IT blog optimizations | ⏳ Review blog content |
| 15 | 2026-04-20 | Security: IAM-first, LF optional | ✅ IAM-first |
| 16 | 2026-04-20 | Review comparison against internal FAQ | ⏳ Need FAQ access |
