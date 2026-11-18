# TCO Sizing & WiredTiger In-Memory Scan-Bloat Diagnostics

## Overview & Use Case

When assessing a MongoDB or DocumentDB workload for migration to **Cloud Firestore Enterprise Edition (with MongoDB compatibility)**, technical teams must evaluate both **functional compatibility** (data types, operators, indexes) and **Total Cost of Ownership (TCO)**.

This enhancement (built directly into `firestore_migration_assessment.sh`, `export_metadata.js`, and `tco_calculator/firestore_pricing_calculator_ram_aware.xlsx`) solves a common, high-impact sizing pitfall: **artificially bloated "As-Is" Firestore TCO estimates (`3x–25x+`) on workloads where unindexed or low-selectivity scans are masked by MongoDB's WiredTiger RAM cache.**

---

## Problem Statement

Standard MongoDB sizing scripts collect `db.serverStatus().metrics.queryExecutor.scannedObjects` (`Documents Examined`) and feed that daily counter directly into the Firestore Enterprise Edition Pricing Calculator.

However, **provisioned MongoDB clusters** and **serverless Firestore** meter reads fundamentally differently:

| Dimension | Provisioned MongoDB (WiredTiger) | Cloud Firestore Enterprise Edition |
| :--- | :--- | :--- |
| **Billing Model** | Fixed hourly node compute + RAM + disk capacity | Serverless, operation-metered (`4 KiB` read tranches, `1 KiB` write tranches) |
| **In-Memory `COLLSCAN` / Filter Waste** | **$0 marginal fee per read** as long as the active working set fits inside WiredTiger RAM | **100% metered**—every document tranche inspected during a scan consumes Read Units |
| **Effect of Missing Indexes** | Masked until RAM saturates or CPU spikes; teams often scale up node tiers instead of adding composite indexes | Directly visible on the monthly bill if migrated without adding composite indexes |

### Why Raw `scannedObjects` Bloats TCO

In MongoDB's architecture, `metrics.queryExecutor.scannedObjects` sits in the **Query Executor layer—above the WiredTiger Storage Engine RAM cache**:

```text
Application Query
       │
       ▼
┌─────────────────────────────────────────────────────────────────┐
│ MongoDB Query Executor Layer                                    │
│  • metrics.queryExecutor.scannedObjects  (Total Docs Examined)  │
│  • metrics.document.returned             (Actual Docs Returned) │
│  --> Counts 100% of inspected docs (RAM hits + Disk reads)      │
└──────────────────────────────┬──────────────────────────────────┘
                               │
               ┌───────────────┴───────────────┐
               ▼                               ▼
┌──────────────────────────────┐ ┌────────────────────────────────┐
│ WiredTiger RAM Cache Hits    │ │ Physical Disk Reads (Misses)   │
│  (Often 85% – 99%+ of ops)   │ │  (Often 1% – 15% of ops)       │
│  Served from memory at $0/op │ │  wiredTiger.cache:             │
│  in provisioned MongoDB      │ │  "pages read into cache"       │
└──────────────────────────────┘ └────────────────────────────────┘
```

When a source MongoDB cluster has:
1. **High WiredTiger Cache Hit Rate (`>= 80%`)**—meaning almost all page requests are served from RAM rather than disk, **AND**
2. **High `DocsExamined : DocsReturned` Ratio (`> 10x`, often `100x–500x`)**—meaning `90%–99.8%` of examined documents are immediately discarded by query predicates due to missing or non-selective indexes,

plugging raw `scannedObjects` into an operation-metered Firestore calculator assumes the customer will lift-and-shift unindexed collection scans permanently into production. That produces a **phantom read charge** that can make Firestore appear multiple times more expensive than the source cluster, even when actual application payload (`Documents Returned`) is modest.

---

## What We Are Solving

Instead of silently outputting a distorted TCO number—or ignoring scan inefficiency—this update introduces a **Two-Gate Diagnostic Guardrail** across both the CLI assessment suite and the pricing calculator spreadsheet:

1. **Detect In-Memory Scan Bloat Automatically**:
   - **Gate 1 (RAM Masking Check):** `WiredTiger Cache Hit Rate >= 80%` (`(pages requested - pages read into cache) / pages requested`)
   - **Gate 2 (Scan Waste Check):** `DocsExamined / DocsReturned > 10x` (`metrics.queryExecutor.scannedObjects / metrics.document.returned`)
2. **Quantify Discarded Scans & Bloat Multiple**:
   - Calculates exact **Discarded Scan %** (`(DocsExamined - DocsReturned) / DocsExamined`), **Estimated In-Memory vs. Disk Docs/Day**, and the **As-Is Read-Unit Bloat Multiple**.
3. **Reframe TCO Presentation**:
   - **Raw "As-Is" TCO (Diagnostic Warning Only):** Retained for transparency to quantify the cost of *not* indexing before cutover.
   - **Index-Normalized Target TCO (Recommended Proposal Baseline):** Models expected Firestore TCO once missing composite indexes bring `DocsExamined : DocsReturned` into a healthy OLTP range (configurable target ratio, default `8.0:1`, plus `3.0:1` covering-index and `1.0:1` point-read sensitivity bounds).

---

## How to Verify Metrics Directly in `mongosh`

If you want to inspect a live MongoDB instance manually, run this read-only one-liner in `mongosh`:

```javascript
const s = db.adminCommand({ serverStatus: 1 });
const wt = s.wiredTiger.cache;
const uptimeDays = Math.max(1, s.uptime) / 86400;

const cacheReq = Number(wt["pages requested from the cache"]);
const diskMiss = Number(wt["pages read into cache"]);
const ramHits  = cacheReq - diskMiss;
const hitPct   = cacheReq > 0 ? (ramHits / cacheReq) * 100 : 0;

const docsExam = Number(s.metrics.queryExecutor.scannedObjects) / uptimeDays;
const docsRet  = Number(s.metrics.document.returned) / uptimeDays;
const ratio    = docsRet > 0 ? (docsExam / docsRet) : 0;

printjson({
  uptimeDays: Number(uptimeDays.toFixed(2)),
  docsExaminedPerDay: Math.round(docsExam),
  docsReturnedPerDay: Math.round(docsRet),
  scanToReturnRatio: Number(ratio.toFixed(2)),
  wiredTigerCacheHitPct: Number(hitPct.toFixed(2)),
  wiredTigerDiskMissPct: Number((100 - hitPct).toFixed(2))
});
```

---

## Usage

### 1. Collect Enhanced Metadata (`mongodb_collector.sh` / `export_metadata.js`)

`export_metadata.js` automatically extracts `workloadMetrics`, `wiredTigerCache`, and `tcoDiagnostics` from `serverStatus` (no additional MongoDB permissions required beyond `serverStatus`):

```bash
./mongodb_collector.sh --uri "mongodb://username:password@host:port/database" --output-dir my_assessment
```

### 2. Run `firestore_migration_assessment.sh` to Get the Bloat View

The TCO & Read-Scan Efficiency Bloat View runs automatically as part of `--run-all` or individually via `--run-tco-check` (accepting either a collected directory, `mongodb_metadata.json`, or a `mongo_stats.js` output file):

```bash
# Run all compatibility checks + TCO scan-bloat view
./firestore_migration_assessment.sh --dir sample_data --run-all

# Run only the TCO & scan-efficiency bloat view with regional pricing (text or JSON)
./firestore_migration_assessment.sh --dir sample_data --run-tco-check --region us-central1
./firestore_migration_assessment.sh --dir sample_data --run-tco-check --region us-central1 --output-format json

# Or run directly against a single metadata JSON or mongo_stats.js .txt file
./firestore_migration_assessment.sh --file my_assessment/mongodb_metadata.json --run-tco-check --region asia-south1 --target-scan-ratio 8.0
./firestore_migration_assessment.sh --file mongo_stats.txt --run-tco-check --region us-central1
```

#### Sample CLI Output (`firestore_migration_assessment.sh`)

```text
TCO & Read-Scan Efficiency Bloat View
-------------------------------------
Source File:                       sample_data/mongodb_metadata.json (mongodb_metadata_json)
Pricing Region & Doc Size:         us-central1 (Iowa) | Avg Doc Size: 0.37 KiB | Stored: 0.02 GiB
Diagnostic Status:                 IN_MEMORY_SCAN_BLOAT_WARNING
Docs Examined vs. Returned/day:    2000000000.00 examined vs. 10000000.00 returned (200.00x ratio; healthy <= 10.0x)
Discarded Unreturned Scans:        99.50% (1990000000.00 docs/day discarded)
WiredTiger Cache Hit / Disk Split: 95.00% In-Memory (RAM) | 5.00% Physical Disk

1. Segregated Operation Breakdown — Raw As-Is Baseline (Cache vs. Disk Reads, Inserts, Updates, Deletes):
   Operation Component                | Units / GiB day |     PAYG /mo |  1Yr CUD /mo |  3Yr CUD /mo
   -----------------------------------+-----------------+--------------+--------------+-------------
   Reads - From Cache (RAM)           |       184371250 | $     276.56 | $     237.84 | $     199.12  <-- Mongo RAM hits
   Reads - From Disk (Misses)         |         9703750 | $      14.56 | $      12.52 | $      10.48
   Reads - Index Entries              |         2500000 | $       3.75 | $       3.23 | $       2.70
   Writes - Inserts                   |          400000 | $       3.12 | $       2.68 | $       2.25
   Writes - Updates                   |          750000 | $       5.85 | $       5.03 | $       4.21
   Writes - Deletes                   |           50000 | $       0.39 | $       0.34 | $       0.28
   Writes - Indexes (3x)              |         3600000 | $      28.08 | $      24.15 | $      20.22
   Storage (GiB)                      |            0.02 | $       0.00 | $       0.00 | $       0.00
   -----------------------------------+-----------------+--------------+--------------+-------------
   Total Raw As-Is TCO                |               — | $     332.31 | $     285.78 | $     239.26

2. Segregated Operation Breakdown — NEW Target TCO (Index-Normalized @ 8.0x):
   Operation Component                | Units / GiB day |     PAYG /mo |  1Yr CUD /mo |  3Yr CUD /mo
   -----------------------------------+-----------------+--------------+--------------+-------------
   Reads - Documents (Indexed)        |        16475000 | $      24.71 | $      21.25 | $      17.79
   Reads - Index Entries              |         2500000 | $       3.75 | $       3.23 | $       2.70
   Writes - Inserts                   |          400000 | $       3.12 | $       2.68 | $       2.25
   Writes - Updates                   |          750000 | $       5.85 | $       5.03 | $       4.21
   Writes - Deletes                   |           50000 | $       0.39 | $       0.34 | $       0.28
   Writes - Indexes (3x)              |         3600000 | $      28.08 | $      24.15 | $      20.22
   Storage (GiB)                      |            0.02 | $       0.00 | $       0.00 | $       0.00
   -----------------------------------+-----------------+--------------+--------------+-------------
   Total NEW Target TCO               |               — | $      65.91 | $      56.68 | $      47.45

3. Scan-Efficiency Sensitivity Summary Across Indexing Scenarios:
   TCO Scenario                                     |       PAYG /mo |    1Yr CUD /mo |    3Yr CUD /mo
   -------------------------------------------------+----------------+----------------+---------------
   Raw As-Is (200.0x Scan Bloat - Do Not Propose)   | $       332.31 | $       285.78 | $       239.26
   NEW Target TCO (Index-Normalized @ 8.0x)         | $        65.91 | $        56.68 | $        47.45
   Tightly Tuned Covering Indexes (@ 3.0x)          | $        58.97 | $        50.71 | $        42.46
   Pure Useful Work Floor (@ 1.0x Exact Match)      | $        56.19 | $        48.33 | $        40.46
```

### 3. Use the RAM-Aware Pricing Calculator (`tco_calculator/firestore_pricing_calculator_ram_aware.xlsx`)

Open `tco_calculator/firestore_pricing_calculator_ram_aware.xlsx` in Google Sheets or Microsoft Excel:

- **Preserves Original Sheets Untouched:** Keeps `Instructions`, `Pricing Calculator` (including its original 4 summary charts), and `Unit Prices` 100% intact for backward compatibility.
- **New Default Tab — `Updated TCO (RAM-Aware)`:**
  - **Section (A) Inputs & Granular Operation Workload:** Enter standard `mongo_stats.js` / `export_metadata.js` metrics—including segregated **`6a. Writes - Inserts`**, **`6b. Writes - Updates`**, and **`6c. Writes - Deletes`**—plus **WiredTiger Cache Hits**, **WiredTiger Cache Misses (Disk Reads)**, **Target Indexed Scan Ratio** (default `8.0x`), and optional **Current Source DB Monthly Spend**.
  - **Section (B) In-Memory & Scan-Bloat Guardrail:** Automatically displays a dynamic warning banner when `Cache Hit Rate >= 80%` and `DocsExamined / DocsReturned > 10x`, breaking down `DocsExamined : DocsReturned`, `Discarded Scan %`, `Segregated As-Is Cache $/mo vs. Disk $/mo`, and the `Raw As-Is TCO Bloat Multiple`.
  - **Section (C) Operation-Segregated Pricing Summary (`C1` Raw As-Is & `C2` New Target TCO):** Breaks down `PAYG ($/mo)`, `1Yr CUD ($/mo)`, and `3Yr CUD ($/mo)` across every operation slice:
    - `Reads - From Cache (RAM)` & `Reads - From Disk (Misses)` (in `C1`) / `Reads - Documents (Indexed)` (in `C2`)
    - `Reads - Index Entries`
    - `Writes - Inserts`, `Writes - Updates`, `Writes - Deletes`, and `Writes - Indexes`
    - `Storage`
  - **Section (D) Sensitivity Matrix:** Compares **Raw As-Is** vs. **New Target TCO (`8:1`)**, **Tightly Tuned Covering Indexes (`3:1`)**, and **Pure Useful Work Floor (`1:1`)**.
  - **Section (E) 6 Interactive TCO Pie Charts (`PAYG`, `1Yr CUD`, `3Yr CUD`):**
    - **Row `E1` (3 Pie Charts):** `New Target TCO — PAYG ($/mo)`, `1Yr CUD ($/mo)`, and `3Yr CUD ($/mo)` segregated by `Reads - Documents (Indexed)`, `Reads - Index Entries`, `Writes - Inserts`, `Writes - Updates`, `Writes - Deletes`, `Writes - Indexes`, and `Storage`.
    - **Row `E2` (3 Pie Charts):** `Raw As-Is TCO — PAYG ($/mo)`, `1Yr CUD ($/mo)`, and `3Yr CUD ($/mo)` highlighting the `Reads - From Cache (RAM)` slice vs. `Reads - From Disk (Misses)`, `Reads - Index Entries`, `Inserts`, `Updates`, `Deletes`, `Index Writes`, and `Storage`.

---

## License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
