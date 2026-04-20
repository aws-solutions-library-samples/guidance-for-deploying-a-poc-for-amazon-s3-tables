# Steering — Guidance for Deploying a PoC for Amazon S3 Tables

> Development steering document. Directs all current and future changes.
> Last updated: 2026-04-20

---

## Design Principles

1. **IAM-first**: The PoC runs entirely on IAM permissions. No Lake Formation grants, no LF admin prerequisite. LF is mentioned only as a production option in SME Guidance.
2. **No custom JARs**: Spark connects via the S3 Tables Iceberg REST endpoint (`https://s3tables.<region>.amazonaws.com/iceberg`) using standard Iceberg REST catalog config + SigV4. No `S3TablesCatalog` JAR.
3. **Athena via Glue catalog, Spark via REST endpoint**: Two distinct access paths, both IAM-authorized, both documented clearly.
4. **Copy-paste fidelity**: Every CLI command and SQL statement must be runnable as-is (with only clearly marked placeholder substitution).
5. **Minimal prerequisites**: Deploy should require only IAM permissions to create resources + AWS CLI v2 + SSM plugin. Nothing else.
6. **Namespace-centric organization**: Guide users toward multiple namespaces within a single table bucket — not multiple table buckets.
7. **Binpack-first compaction**: Default compaction strategy is binpack. Sort and z-order are advanced options presented after binpack is understood.
8. **Accurate claims only**: No unsubstantiated performance claims. Every statement about S3 Tables behavior must be verifiable against current documentation.
9. **AWS SDK/CLI-first**: Default to AWS SDKs, CLI, and signed AWS-distributed libraries. Avoid third-party JARs, community packages, or dependencies with license ambiguity. If Spark packages are needed, use only Apache-licensed or AWS-published Maven coordinates.

---

## Architecture Decisions

| Decision | Rationale |
|---|---|
| IAM-only access control | Simplifies PoC from ~6 LF grant steps to zero. Matches current AWS default integration path. LF is optional governance layer for production. |
| S3 Tables REST endpoint for Spark | Eliminates JAR dependency, uses standard Iceberg REST catalog protocol, IAM-authorized via SigV4 (`s3tables` signing name). No Glue/LF dependency for Spark. |
| Glue catalog for Athena | Required — Athena queries S3 Tables through the `s3tablescatalog` federated catalog in Glue. IAM_ALLOWED_PRINCIPALS makes this IAM-only in practice. |
| NAT Gateway + VPC endpoints | EC2 needs internet for Spark package downloads (via `--packages`). VPC endpoints for AWS service traffic. README must accurately reflect this (not claim "no internet"). |
| AWS SDK/CLI and signed libraries only | PoC must not introduce license risk or unsigned dependencies. Use AWS CLI, AWS SDKs, and Apache/AWS-published Maven artifacts only. No custom JARs, no community forks, no unsigned binaries. |
| Single table bucket, multiple namespaces | Aligns with service team guidance. Namespaces = logical separation (raw, curated, etc). |

---

## Must-Dos

1. Remove all SageMaker Lakehouse references — use "AWS Glue Data Catalog integration" or "AWS analytics services integration"
2. Remove all `lakeformation grant-permissions` commands and LF admin prerequisite
3. Replace Spark scenarios (4, 4b) to use S3 Tables Iceberg REST endpoint with SigV4
4. Remove `software.amazon.s3tables.iceberg.S3TablesCatalog` JAR and all references to downloading/uploading JARs
5. Update EC2 UserData — no longer needs to pre-install Iceberg JARs (Spark uses `--packages` with Maven coordinates)
6. Fix README/CFN mismatch: README says "no NAT Gateway" but CFN deploys one — align both to reality (NAT exists, is needed)
7. Replace "one table bucket per workload" with "use namespaces to organize tables within a table bucket"
8. Remove Iceberg V3 recommendation (Athena doesn't support it)
9. Rewrite compaction guidance: binpack is default and sufficient for most workloads → sort/z-order are advanced optimizations for specific access patterns
10. Add snapshot expiry and unreferenced file removal to maintenance guidance (currently only mentions compaction)
11. Remove false claim: "performance gap widens with data volume and write frequency"
12. Remove "avoid manual compaction" — just state that S3 Tables handles compaction automatically
13. Incorporate optimizations from the [S3 Tables Intelligent-Tiering blog](https://aws.amazon.com/blogs/storage/optimize-data-management-on-s3-tables-with-intelligent-tiering/)
14. Rewrite Security Best Practices: lead with IAM resource-based policies on table buckets and tables, mention LF as optional for Athena fine-grained access
15. Review and update "S3 Tables vs Self-Managed Iceberg" comparison against internal FAQ
16. Fix "hidden partitioning" language — it's native to Iceberg, not something you enable
17. Clarify or remove "Enable column statistics" (unclear guidance)
18. Fix "partition columns" guidance — only relevant for high-cardinality scenarios, needs context
19. Make "columnar filtering" guidance engine-agnostic (not Athena-specific)

---

## Don'ts

1. Do NOT reference SageMaker Lakehouse anywhere
2. Do NOT use the `S3TablesCatalog` JAR or `software.amazon.s3tables.iceberg.S3TablesCatalog`
3. Do NOT require Lake Formation admin as a prerequisite
4. Do NOT include `lakeformation grant-permissions` commands in the main flow
5. Do NOT recommend Iceberg V3 (Athena incompatible)
6. Do NOT recommend "one table bucket per workload/domain"
7. Do NOT make unverifiable performance claims
8. Do NOT present Iceberg-native features (hidden partitioning, schema evolution) as S3 Tables-specific features
9. Do NOT present engine-agnostic optimizations as Athena-specific

---

## Constraints

- Must deploy in all 35 supported S3 Tables regions
- Must work with a single `aws cloudformation deploy` command
- Cost must remain under ~$15/day for default configuration
- All CLI commands must be copy-pasteable with clearly marked placeholders
- No real customer data or PII in examples
- Must include standard AWS Notices/disclaimer
- Threat model must accompany the guide
- All table names and column names must be lowercase (Glue catalog requirement)

---

## Publication Format (Target: aws-solutions-library-samples)

Reference: https://github.com/aws-solutions-library-samples/deploy-a-poc-of-aws-backup

### Required Repo Structure

```
assets/
  code/
    s3-tables-poc.yaml          ← CloudFormation template
  images/
    s3tablespoc-architecture-diagram.drawio.png
deployment/                     ← (placeholder for future deployment docs)
source/                         ← (placeholder for future source code)
CODE_OF_CONDUCT.md
CONTRIBUTING.md
LICENSE                         ← MIT-0
PrescriptiveGuidance_S3Tables.md  ← Deep-dive companion (extracted from SME Guidance)
README.md
threat-model.md
```

### README Sections (required order)

1. Overview (business case, what it deploys, target use cases, services table, cost)
2. Architecture (diagram + description)
3. Prerequisites
4. Deployment Steps
5. Deployment Validation (explicit "verify CREATE_COMPLETE" section)
6. PoC Methodology (numbered steps + fillable success criteria matrix)
7. Running the Guidance / Test Scenarios
8. Next Steps (themes for deeper exploration after baseline)
9. Cleanup
10. Notices

### Companion Document: PrescriptiveGuidance_S3Tables.md

Split guidance by depth — README has "what to do for the PoC", companion doc has "how to think about it for production".

**README SME Guidance (keep short — summaries + links to companion doc):**
- Namespace organization (brief)
- Compaction: "start with binpack" + link
- Snapshot/file lifecycle: recommended starting config + link
- Intelligent-Tiering: key behaviors summary + link
- Security: IAM-first for PoC + link
- S3 Tables vs Self-Managed: decision summary + link

**PrescriptiveGuidance_S3Tables.md (deep-dive, production-oriented):**
- Section 1: Namespace and table bucket design patterns
- Section 2: Compaction strategies in depth
  - When binpack is sufficient (most workloads)
  - When to use sort (single-column filter patterns, time-series)
  - When to use z-order (multi-column filter patterns)
  - Target file size tuning
  - How auto strategy selects between them
  - Interaction with Intelligent-Tiering (only compacts FA tier)
- Section 3: Snapshot and file lifecycle management
  - Retention tuning (minSnapshots, maxAge, unreferencedDays)
  - Delete file accumulation on cold data
  - Balancing time travel needs vs storage cost
- Section 4: Intelligent-Tiering optimization
  - Tier transition mechanics (FA → IA → AIA)
  - Compaction interaction (FA-only processing)
  - When to enable vs stay on S3 Standard
  - Cost projection methodology
- Section 5: Replication
  - Cross-region table bucket replication
  - Disaster recovery patterns
  - Consistency considerations
- Section 6: Security and access control
  - IAM resource-based policies (table bucket + table level)
  - When to add Lake Formation (Athena fine-grained, multi-team)
  - VPC endpoint policies for network-level control
  - Cross-account access patterns
- Section 7: S3 Tables vs Self-Managed Iceberg
  - Detailed comparison matrix
  - Decision framework
  - Hybrid approach (some tables managed, some self-managed)
  - Migration path from self-managed to S3 Tables

**Trigger to create the companion doc:** When README SME Guidance exceeds ~150 lines or any section above needs to be written. For now, keep as a planned structure.

### Cost Section Requirements

- Per-service table with: service, dimensions, example sizing, example monthly cost
- Pricing links to official pages
- "What drives cost" explanation
- Important cost considerations (what continues to charge when idle)

### Success Criteria Matrix

Provide a fillable matrix (like the Backup PoC) that customers populate during testing:
- Workload configuration table
- S3 Tables configuration table (compaction strategy, snapshot policy, IT enabled)
- Functional testing outcomes table
- Performance observations table

### Community Files

- `CODE_OF_CONDUCT.md` — standard Amazon Open Source
- `CONTRIBUTING.md` — standard Amazon Open Source
- `LICENSE` — MIT-0 (standard for AWS samples)

---

## Impact Assessment

### High-impact changes (structural)

| Change | Files affected | Effort |
|---|---|---|
| Remove LF from main flow | README (Steps 3–4, troubleshooting, prerequisites), CFN (IAM policy), threat model | High |
| Replace Spark integration with REST endpoint | README (Scenarios 4, 4b, 3j), CFN (UserData, VPC endpoints) | High |
| Remove SageMaker Lakehouse framing | README (Step 3, architecture, services table) | Medium |

### Medium-impact changes (content)

| Change | Files affected | Effort |
|---|---|---|
| Rewrite SME Guidance (compaction, security, comparison table) | README | Medium |
| Add snapshot/pruning/IT blog content | README | Medium |
| Fix README/CFN mismatches (NAT, endpoints, UserData) | README, CFN | Medium |

### Low-impact changes (wording)

| Change | Files affected | Effort |
|---|---|---|
| Remove V3 recommendation | README | Low |
| Fix hidden partitioning language | README | Low |
| Make columnar filtering engine-agnostic | README | Low |
| Remove false performance claim | README | Low |

---

## Execution Order

Recommended sequence to minimize rework:

1. **CFN template first** — fix UserData (remove JAR installs, add `--packages` approach or keep minimal), verify NAT/endpoint setup, remove LF-specific IAM actions if not needed
2. **README structural changes** — remove LF flow, remove SageMaker Lakehouse, rewrite Step 3 as pure Glue catalog integration with IAM
3. **Spark scenarios** — rewrite Scenarios 4 and 3j to use S3 Tables REST endpoint
4. **SME Guidance rewrite** — compaction, security, comparison table, add snapshot/pruning
5. **Wording fixes** — all the low-impact items
6. **Threat model update** — reflect new architecture (no LF, no JAR, REST endpoint)
7. **Final consistency pass** — verify all cross-references, step numbers, environment variables

---

## Open Questions

| # | Question | Owner | Status |
|---|---|---|---|
| 1 | Does the S3 Tables REST endpoint require a VPC interface endpoint, or does it work via the existing `s3tables` endpoint? | To verify | Open |
| 2 | Can Spark use `--packages` to pull Iceberg runtime from Maven when behind a NAT Gateway (no custom JAR upload needed)? | To verify | Open |
| 3 | What specific content from the IT blog should be incorporated? (full walkthrough or just the optimization tips?) | Lee/Fabio | Open |
| 4 | What does the internal FAQ say about the S3 Tables vs Self-Managed comparison? Need access to review. | Lee/Fabio | Open |
| 5 | "Enable column statistics" — is this a valid S3 Tables feature or should it be removed entirely? | Lee/Fabio | Open |
| 6 | EMR Serverless scenario (4b) — does it stay? If so, does it also use the REST endpoint or Glue endpoint? | Lee/Fabio | Open |
| 7 | Firehose scenario (5) — does it stay as-is? It uses Glue catalog which may still need LF for the Firehose role. | Lee/Fabio | Open |

---

## Leader Feedback Log

| # | Date | Source | Feedback | Status |
|---|---|---|---|---|
| 1 | 2026-04-20 | Lee & Fabio | Remove SageMaker Lakehouse, use Lake Formation | Resolved → use Glue catalog integration with IAM, no LF grants |
| 2 | 2026-04-20 | Lee & Fabio | Use IAM for permissions, remove LF (except Spark) | Resolved → IAM-only for both Athena and Spark (different endpoints) |
| 3 | 2026-04-20 | Lee & Fabio | Remove S3TablesCatalog JAR, use endpoints or Glue | Resolved → S3 Tables REST endpoint for Spark |
| 4 | 2026-04-20 | Lee & Fabio | "More namespaces" not "more table buckets" | Resolved → update SME Guidance |
| 5 | 2026-04-20 | Lee & Fabio | Remove Iceberg V3 recommendation | Resolved → remove |
| 6 | 2026-04-20 | Lee & Fabio | Compaction: start with binpack | Resolved → rewrite guidance |
| 7 | 2026-04-20 | Lee & Fabio | Hidden partitioning is native to Iceberg | Resolved → reword |
| 8 | 2026-04-20 | Lee & Fabio | "Enable column statistics" unclear | Open → need clarification |
| 9 | 2026-04-20 | Lee & Fabio | Partition columns guidance unclear | Open → needs context for high-cardinality |
| 10 | 2026-04-20 | Lee & Fabio | Columnar filtering not Athena-specific | Resolved → make engine-agnostic |
| 11 | 2026-04-20 | Lee & Fabio | Remove "avoid manual compaction" | Resolved → remove phrase |
| 12 | 2026-04-20 | Lee & Fabio | "Performance gap widens" is NOT TRUE | Resolved → remove |
| 13 | 2026-04-20 | Lee & Fabio | Add snapshots and pruning of reference files | Open → add to maintenance section |
| 14 | 2026-04-20 | Lee & Fabio | Add IT blog optimizations | Open → need to review blog content |
| 15 | 2026-04-20 | Lee & Fabio | Security: lean into IAM, LF only for Athena | Resolved → IAM-first, LF as optional production add-on |
| 16 | 2026-04-20 | Lee & Fabio | Review comparison table against internal FAQ | Open → need FAQ access |
