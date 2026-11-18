#!/bin/bash
# Firestore Migration Assessment Suite
# This script combines the datatype, operator, and index compatibility checkers
# to provide a comprehensive assessment for MongoDB to Firestore migration.

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DIR=""
FILE=""
OUTPUT_FORMAT="text"
OUTPUT_FILE=""
RUN_DATATYPE=false
RUN_OPERATOR=false
RUN_INDEX=false
RUN_TCO=false
REGION="us-central1"
CACHE_THRESHOLD=80.0
SCAN_RATIO_THRESHOLD=10.0
TARGET_SCAN_RATIO=8.0
VERBOSE=false
QUIET=false

# Temporary files for capturing output
TEMP_DIR=$(mktemp -d)
DATATYPE_OUTPUT="$TEMP_DIR/datatype_output.txt"
OPERATOR_OUTPUT="$TEMP_DIR/operator_output.txt"
INDEX_OUTPUT="$TEMP_DIR/index_output.txt"
TCO_OUTPUT="$TEMP_DIR/tco_output.txt"
TCO_JSON_OUTPUT="$TEMP_DIR/tco_output.json"
SUMMARY_OUTPUT="$TEMP_DIR/summary_output.txt"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Set trap for cleanup
trap cleanup EXIT

# Function to print usage
usage() {
    echo "Firestore Migration Assessment Suite"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --dir DIR                 Directory to scan (for all assessment types)"
    echo "                            Uses subdirectory routing:"
    echo "                            - app/ for operator checking"
    echo "                            - data/ for datatype checking"
    echo "                            - root directory for index & TCO scan-bloat checking"
    echo "  --file FILE               File to scan (for any assessment type)"
    echo "                            Use with --run-datatype, --run-operator, --run-index, --run-tco-check, or --run-all"
    echo "  --output-format FORMAT    Output format (text, json) [default: text]"
    echo "  --output-file FILE        File to write the report to [default: stdout]"
    echo "  --run-all                 Run all assessment types (datatype, operator, index, and TCO bloat check)"
    echo "  --run-datatype            Run only datatype compatibility assessment"
    echo "  --run-operator            Run only operator compatibility assessment"
    echo "  --run-index               Run only index compatibility assessment"
    echo "  --run-tco-check           Run only WiredTiger RAM-cache vs. disk & Firestore TCO bloat check"
    echo "  --region REGION           Target Firestore Enterprise region for TCO pricing [default: us-central1]"
    echo "                            (us-central1, us-east1, us-east4, us-west1, us-west2, asia-south1, nam5, nam7, eur3)"
    echo "  --target-scan-ratio NUM   Target post-index DocsExamined:DocsReturned ratio [default: 8.0]"
    echo "  --verbose                 Show detailed information"
    echo "  --quiet                   Suppress progress messages and non-essential output"
    echo "  --help                    Display this help message"
    echo ""
    echo "Examples:"
    echo "  # Directory-based assessment:"
    echo "  $0 --dir sample_data --run-all"
    echo "  $0 --dir sample_data --run-tco-check --region us-central1"
    echo ""
    echo "  # File-based assessment:"
    echo "  $0 --file sample.json --run-datatype"
    echo "  $0 --file mongodb.log --run-operator"
    echo "  $0 --file indexes.metadata.json --run-index"
    echo "  $0 --file sample_data/mongodb_metadata.json --run-tco-check --region asia-south1"
    echo ""
    echo "  # Output options:"
    echo "  $0 --dir sample_data --run-all --output-format json --output-file report.json"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            DIR="$2"
            shift 2
            ;;
        --file)
            FILE="$2"
            shift 2
            ;;
        --log-file|--data-file|--metadata-dir)
            echo "Warning: Legacy parameter $1 is deprecated. Please use --file instead."
            FILE="$2"
            shift 2
            ;;
        --output-format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --run-all)
            RUN_DATATYPE=true
            RUN_OPERATOR=true
            RUN_INDEX=true
            RUN_TCO=true
            shift
            ;;
        --run-datatype)
            RUN_DATATYPE=true
            shift
            ;;
        --run-operator)
            RUN_OPERATOR=true
            shift
            ;;
        --run-index)
            RUN_INDEX=true
            shift
            ;;
        --run-tco-check)
            RUN_TCO=true
            shift
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --target-scan-ratio)
            TARGET_SCAN_RATIO="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate arguments
if [[ "$RUN_DATATYPE" == "false" && "$RUN_OPERATOR" == "false" && "$RUN_INDEX" == "false" && "$RUN_TCO" == "false" ]]; then
    echo "Error: At least one assessment type must be selected (--run-datatype, --run-operator, --run-index, --run-tco-check, or --run-all)"
    usage
fi

if [[ -n "$DIR" && -n "$FILE" ]]; then
    echo "Error: Cannot specify both --dir and --file. Use either directory-based or file-based assessment."
    usage
fi

if [[ -z "$DIR" && -z "$FILE" ]]; then
    echo "Error: Either --dir or --file must be specified"
    usage
fi

if [[ -n "$FILE" && ! -f "$FILE" ]]; then
    echo "Error: File not found: $FILE"
    exit 1
fi

if [[ -n "$DIR" && ! -d "$DIR" ]]; then
    echo "Error: Directory not found: $DIR"
    exit 1
fi

# Validate output format
if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
    echo "Error: Invalid output format. Supported formats: text, json"
    usage
fi

# Function to run datatype assessment
run_datatype_assessment() {
    if [[ "$OUTPUT_FORMAT" == "text" && "$QUIET" == "false" ]]; then
        echo "Running datatype compatibility assessment..."
    fi
    
    local datatype_args=""
    
    if [[ -n "$FILE" ]]; then
        datatype_args="--file $FILE"
    elif [[ -n "$DIR" ]]; then
        # Check if data subdirectory exists
        if [[ -d "$DIR/data" ]]; then
            datatype_args="--dir $DIR/data"
        else
            echo "Warning: No data/ subdirectory found in $DIR. Skipping datatype assessment."
            echo "  Use --file to specify a specific file for datatype checking."
            echo "Datatype assessment skipped: No data/ subdirectory found in $DIR" > "$DATATYPE_OUTPUT"
            echo "" >> "$SUMMARY_OUTPUT"
            echo "Datatype Compatibility:" >> "$SUMMARY_OUTPUT"
            echo "  Skipped: No data/ subdirectory found in $DIR" >> "$SUMMARY_OUTPUT"
            echo "" >> "$SUMMARY_OUTPUT"
            return
        fi
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        datatype_args="$datatype_args --verbose"
    fi
    
    # Run datatype checker and capture output
    "$SCRIPT_DIR/firestore_datatype_checker.sh" $datatype_args > "$DATATYPE_OUTPUT" 2>&1
    
    # Extract summary information
    local total_files=$(grep "Scanned" "$DATATYPE_OUTPUT" | awk '{print $2}')
    local issue_files=$(grep "Found" "$DATATYPE_OUTPUT" | awk '{print $2}')
    local total_issues=$(grep "Detected" "$DATATYPE_OUTPUT" | awk '{print $2}')
    
    # Add to summary
    echo "Datatype Compatibility:" >> "$SUMMARY_OUTPUT"
    echo "  Total files scanned: $total_files" >> "$SUMMARY_OUTPUT"
    echo "  Files with issues: $issue_files" >> "$SUMMARY_OUTPUT"
    echo "  Total issues detected: $total_issues" >> "$SUMMARY_OUTPUT"
    echo "" >> "$SUMMARY_OUTPUT"
}

# Function to run operator assessment
run_operator_assessment() {
    if [[ "$OUTPUT_FORMAT" == "text" && "$QUIET" == "false" ]]; then
        echo "Running operator compatibility assessment..."
    fi
    
    local operator_args="--mode scan"
    
    if [[ -n "$FILE" ]]; then
        operator_args="$operator_args --file $FILE"
    elif [[ -n "$DIR" ]]; then
        # Check if app subdirectory exists
        if [[ -d "$DIR/app" ]]; then
            operator_args="$operator_args --dir $DIR/app"
        else
            echo "Warning: No app/ subdirectory found in $DIR. Skipping operator assessment."
            echo "  Use --file to specify a specific file for operator checking."
            echo "Operator assessment skipped: No app/ subdirectory found in $DIR" > "$OPERATOR_OUTPUT"
            echo "" >> "$SUMMARY_OUTPUT"
            echo "Operator Compatibility:" >> "$SUMMARY_OUTPUT"
            echo "  Skipped: No app/ subdirectory found in $DIR" >> "$SUMMARY_OUTPUT"
            echo "" >> "$SUMMARY_OUTPUT"
            return
        fi
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        operator_args="$operator_args --show-supported"
    fi
    
    # Run operator checker and capture output
    "$SCRIPT_DIR/firestore_operator_checker.sh" $operator_args > "$OPERATOR_OUTPUT" 2>&1
    
    # Extract summary information
    local processed_files=$(grep "Processed" "$OPERATOR_OUTPUT" | head -1 | awk '{print $2}')
    local unique_operators=$(grep "Found.*unsupported operators" "$OPERATOR_OUTPUT" | head -1 | awk '{print $2}')
    
    # Add to summary
    echo "Operator Compatibility:" >> "$SUMMARY_OUTPUT"
    echo "  Files processed: $processed_files" >> "$SUMMARY_OUTPUT"
    echo "  Unsupported operators found: $unique_operators" >> "$SUMMARY_OUTPUT"
    echo "" >> "$SUMMARY_OUTPUT"
}

# Function to run index assessment
run_index_assessment() {
    if [[ "$OUTPUT_FORMAT" == "text" && "$QUIET" == "false" ]]; then
        echo "Running index compatibility assessment..."
    fi
    
    local index_args="--summary"
    
    if [[ -n "$FILE" ]]; then
        index_args="$index_args --file $FILE"
    elif [[ -n "$DIR" ]]; then
        index_args="$index_args --dir $DIR"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        index_args="$index_args --debug"
    fi
    
    # Run index checker and capture output
    "$SCRIPT_DIR/index_compat_checker.sh" $index_args > "$INDEX_OUTPUT" 2>&1
    
    # Extract summary information
    local total_indexes=$(grep "Total indexes:" "$INDEX_OUTPUT" | awk '{print $3}')
    local compatible_indexes=$(grep "Compatible indexes:" "$INDEX_OUTPUT" | awk '{print $3}')
    local incompatible_indexes=$(grep "Incompatible indexes:" "$INDEX_OUTPUT" | awk '{print $3}')
    
    # Add to summary
    echo "Index Compatibility:" >> "$SUMMARY_OUTPUT"
    echo "  Total indexes: $total_indexes" >> "$SUMMARY_OUTPUT"
    echo "  Compatible indexes: $compatible_indexes" >> "$SUMMARY_OUTPUT"
    echo "  Incompatible indexes: $incompatible_indexes" >> "$SUMMARY_OUTPUT"
    echo "" >> "$SUMMARY_OUTPUT"
}

# Function to run WiredTiger RAM-cache & scan-to-return TCO bloat assessment (built-in)
run_tco_assessment() {
    if [[ "$OUTPUT_FORMAT" == "text" && "$QUIET" == "false" ]]; then
        echo "Running WiredTiger RAM-cache & scan-bloat TCO assessment..."
    fi

    local target_file=""
    if [[ -n "$FILE" ]]; then
        target_file="$FILE"
    elif [[ -n "$DIR" ]]; then
        if [[ -f "$DIR/mongodb_metadata.json" ]] && grep -q '"workloadMetrics"' "$DIR/mongodb_metadata.json" 2>/dev/null; then
            target_file="$DIR/mongodb_metadata.json"
        else
            local stats_candidate
            stats_candidate=$(find "$DIR" -maxdepth 2 -type f \( -name "*mongo_stats*.txt" -o -name "*mongo-stats*.txt" \) | sort | head -n 1)
            if [[ -n "$stats_candidate" ]]; then
                target_file="$stats_candidate"
            elif [[ -f "$DIR/mongodb_metadata.json" ]]; then
                target_file="$DIR/mongodb_metadata.json"
            fi
        fi
    fi

    if [[ -z "$target_file" || ! -f "$target_file" ]]; then
        echo "Skipped: No mongodb_metadata.json or mongo_stats output found." > "$TCO_OUTPUT"
        echo '{"status":"SKIPPED","reason":"No mongodb_metadata.json or mongo_stats output found"}' > "$TCO_JSON_OUTPUT"
        echo "TCO & Read-Scan Efficiency:" >> "$SUMMARY_OUTPUT"
        echo "  Status: Skipped (No mongodb_metadata.json or mongo_stats output found)" >> "$SUMMARY_OUTPUT"
        echo "" >> "$SUMMARY_OUTPUT"
        return
    fi

    local docs_examined="" docs_returned="" keys_examined="" writes_per_day="" stored_gib="" avg_doc_kib="1.0"
    local inserts_per_day="" updates_per_day="" deletes_per_day=""
    local cache_hits="" cache_misses="" cache_hit_rate="" source_type=""

    if grep -q "Pricing estimator values:" "$target_file" 2>/dev/null || grep -q "DocsExamined:" "$target_file" 2>/dev/null; then
        source_type="mongo_stats_txt"
        docs_examined=$(awk '/Documents Examined:/ {print $3; exit} /DocsExamined:/ {print $2; exit}' "$target_file")
        docs_returned=$(awk '/Documents Returned:/ {print $3; exit} /^Reads:/ {print $2; exit}' "$target_file")
        keys_examined=$(awk '/Index Entries Scanned:/ {print $4; exit} /KeysExamined:/ {print $2; exit}' "$target_file")
        inserts_per_day=$(awk '/^Inserts:/ {print $2; exit}' "$target_file")
        updates_per_day=$(awk '/^Updates:/ {print $2; exit}' "$target_file")
        deletes_per_day=$(awk '/^Deletes:/ {print $2; exit}' "$target_file")
        writes_per_day=$(awk '/^Writes:/ {print $2; exit}' "$target_file")
        if [[ -z "$writes_per_day" ]]; then
            writes_per_day=$(awk '/^Inserts:/ {i=$2} /^Updates:/ {u=$2} /^Deletes:/ {d=$2} END {if (i+u+d > 0) printf "%.2f", i+u+d}' "$target_file")
        fi
        stored_gib=$(awk '/Stored Data:/ {print $3; exit} /storage size:/ {print $5; exit}' "$target_file")
        avg_doc_kib=$(awk '/Average Document Size:/ {print $4; exit}' "$target_file")
        cache_hits=$(awk '/Cache Hits:/ {print $3; exit}' "$target_file")
        cache_misses=$(awk '/Cache Misses:/ {print $3; exit}' "$target_file")
        cache_hit_rate=$(awk '/Cache Hit Rate:/ {gsub(/%/,"",$4); print $4; exit}' "$target_file")
    else
        source_type="mongodb_metadata_json"
        local clean_json
        clean_json=$(awk '/^\{/{flag=1} flag{buf = buf $0 "\n"} /^\}$/{if(flag){last=buf; flag=0}} END{if(last!="") printf "%s", last; else printf "%s", buf}' "$target_file")
        if ! echo "$clean_json" | jq -e '.mongodb.workloadMetrics' >/dev/null 2>&1; then
            echo "Skipped: $target_file does not contain workloadMetrics / wiredTigerCache counters. Re-collect with updated export_metadata.js or pass mongo_stats.js output." > "$TCO_OUTPUT"
            echo '{"status":"SKIPPED","reason":"Metadata lacks workloadMetrics/wiredTigerCache counters"}' > "$TCO_JSON_OUTPUT"
            echo "TCO & Read-Scan Efficiency:" >> "$SUMMARY_OUTPUT"
            echo "  Status: Skipped (Metadata lacks workloadMetrics/wiredTigerCache counters)" >> "$SUMMARY_OUTPUT"
            echo "" >> "$SUMMARY_OUTPUT"
            return
        fi
        docs_examined=$(echo "$clean_json" | jq -r '.mongodb.workloadMetrics.dailyAverage.docsExaminedPerDay // 0')
        docs_returned=$(echo "$clean_json" | jq -r '.mongodb.workloadMetrics.dailyAverage.docsReturnedPerDay // 0')
        keys_examined=$(echo "$clean_json" | jq -r '.mongodb.workloadMetrics.dailyAverage.keysExaminedPerDay // 0')
        inserts_per_day=$(echo "$clean_json" | jq -r '.mongodb.workloadMetrics.dailyAverage.insertsPerDay // 0')
        updates_per_day=$(echo "$clean_json" | jq -r '.mongodb.workloadMetrics.dailyAverage.updatesPerDay // 0')
        deletes_per_day=$(echo "$clean_json" | jq -r '.mongodb.workloadMetrics.dailyAverage.deletesPerDay // 0')
        writes_per_day=$(echo "$clean_json" | jq -r '.mongodb.workloadMetrics.dailyAverage.writesPerDay // 0')
        local total_data_bytes total_storage_bytes total_docs
        total_data_bytes=$(echo "$clean_json" | jq -r '.summary.totalDataSize // 0')
        total_storage_bytes=$(echo "$clean_json" | jq -r '.summary.totalSize // 0')
        total_docs=$(echo "$clean_json" | jq -r '[.databases[]?.summary.totalDocuments // 0] | add // 0')
        stored_gib=$(awk -v b="$total_storage_bytes" 'BEGIN {printf "%.2f", b / (1024.0*1024.0*1024.0)}')
        avg_doc_kib=$(awk -v b="$total_data_bytes" -v d="$total_docs" 'BEGIN {if (d > 0 && b > 0) printf "%.2f", (b / d) / 1024.0; else print "1.00"}')
        cache_hits=$(echo "$clean_json" | jq -r '.mongodb.wiredTigerCache.cacheHits // 0')
        cache_misses=$(echo "$clean_json" | jq -r '.mongodb.wiredTigerCache.cacheMisses // 0')
        cache_hit_rate=$(echo "$clean_json" | jq -r '.mongodb.wiredTigerCache.cacheHitRatePct // 0')
    fi

    # Map Firestore Enterprise Region Unit Prices (Read $/1M, Write $/1M, Storage $/GiB-mo)
    local region_norm read_price="0.0500" write_price="0.2600" storage_price="0.2400" region_label="us-central1 (Iowa)"
    region_norm=$(echo "$REGION" | tr '[:upper:]' '[:lower:]')
    case "$region_norm" in
        *nam5*)       read_price="0.1000"; write_price="0.5200"; storage_price="0.3200";     region_label="nam5 (North America 5)" ;;
        *nam7*)       read_price="0.1000"; write_price="0.5200"; storage_price="0.3200";     region_label="nam7 (North America 7)" ;;
        *eur3*)       read_price="0.1000"; write_price="0.5200"; storage_price="0.3200";     region_label="eur3 (Europe 3)" ;;
        *us-east4*)   read_price="0.0500"; write_price="0.2600"; storage_price="0.2640";     region_label="us-east4 (Northern Virginia)" ;;
        *us-east1*)   read_price="0.0500"; write_price="0.2600"; storage_price="0.2400";     region_label="us-east1 (South Carolina)" ;;
        *us-west2*)   read_price="0.0601"; write_price="0.3125"; storage_price="0.2880";     region_label="us-west2 (Los Angeles)" ;;
        *us-west1*)   read_price="0.0500"; write_price="0.2600"; storage_price="0.2400";     region_label="us-west1 (Oregon)" ;;
        *asia-south1*|*mumbai*) read_price="0.0520"; write_price="0.2700"; storage_price="0.27689995"; region_label="asia-south1 (Mumbai)" ;;
        *)            read_price="0.0500"; write_price="0.2600"; storage_price="0.2400";     region_label="us-central1 (Iowa)" ;;
    esac

    awk \
        -v src_file="$target_file" \
        -v src_type="$source_type" \
        -v text_out="$TCO_OUTPUT" \
        -v json_out="$TCO_JSON_OUTPUT" \
        -v reg_label="$region_label" \
        -v r_price="$read_price" \
        -v w_price="$write_price" \
        -v s_price="$storage_price" \
        -v docs_exam="${docs_examined:-0}" \
        -v docs_ret="${docs_returned:-0}" \
        -v keys_exam="${keys_examined:-0}" \
        -v ins_day="${inserts_per_day:-0}" \
        -v upd_day="${updates_per_day:-0}" \
        -v del_day="${deletes_per_day:-0}" \
        -v writes_day="${writes_per_day:-0}" \
        -v stored_gib="${stored_gib:-0}" \
        -v avg_doc_kib="${avg_doc_kib:-1.0}" \
        -v cache_hits="${cache_hits:-0}" \
        -v cache_misses="${cache_misses:-0}" \
        -v cache_rate="${cache_hit_rate:-0}" \
        -v cache_thresh="$CACHE_THRESHOLD" \
        -v ratio_thresh="$SCAN_RATIO_THRESHOLD" \
        -v target_ratio="$TARGET_SCAN_RATIO" \
    'function ceil_int(x,   i) {
        i = int(x);
        return (x > i) ? (i + 1) : i;
    }
    function cud_1y(m) { return (m * 0.70 * 0.80) + (m * 0.30); }
    function cud_3y(m) { return (m * 0.70 * 0.60) + (m * 0.30); }
    BEGIN {
        docs_exam += 0; docs_ret += 0; keys_exam += 0; stored_gib += 0;
        ins_day += 0; upd_day += 0; del_day += 0; writes_day += 0;
        if ((ins_day + upd_day + del_day) > 0) {
            writes_day = ins_day + upd_day + del_day;
        } else if (writes_day > 0) {
            ins_day = writes_day; upd_day = 0; del_day = 0;
        }
        avg_doc_kib += 0; if (avg_doc_kib <= 0) avg_doc_kib = 1.0;
        r_price += 0; w_price += 0; s_price += 0;
        cache_hits += 0; cache_misses += 0; cache_rate += 0;

        if ((cache_hits + cache_misses) > 0) {
            cache_rate = (cache_hits / (cache_hits + cache_misses)) * 100.0;
        }
        disk_rate = (cache_rate > 0 || (cache_hits + cache_misses) > 0) ? (100.0 - cache_rate) : 0.0;
        p_ram = cache_rate / 100.0;
        p_disk = disk_rate / 100.0;

        scan_ratio = (docs_ret > 0) ? (docs_exam / docs_ret) : 0.0;
        unreturned_docs = (docs_exam > docs_ret) ? (docs_exam - docs_ret) : 0.0;
        discarded_pct = (docs_exam > 0) ? ((unreturned_docs / docs_exam) * 100.0) : 0.0;

        ram_docs_day = docs_exam * p_ram;
        disk_docs_day = docs_exam * p_disk;

        # Read Tranches (4 KiB) & Index Entry Size (0.2 KiB)
        doc_read_tranches = ceil_int(avg_doc_kib / 4.0);
        if (doc_read_tranches < 1) doc_read_tranches = 1;

        ret_units = docs_ret * doc_read_tranches;
        asis_scan_units = ceil_int((unreturned_docs * avg_doc_kib) / 4.0);
        key_units = ceil_int((keys_exam * 0.2) / 4.0);

        # Segregate As-Is Document Read Units & Cost into Cache (RAM) vs. Disk
        total_asis_doc_units = ret_units + asis_scan_units;
        cache_doc_units = total_asis_doc_units * p_ram;
        disk_doc_units = total_asis_doc_units * p_disk;

        m_ret = (r_price / 1000000.0) * ret_units * 30.0;
        m_scan_asis = (r_price / 1000000.0) * asis_scan_units * 30.0;
        m_keys = (r_price / 1000000.0) * key_units * 30.0;

        m_cache_reads = (m_ret + m_scan_asis) * p_ram;
        m_disk_reads = (m_ret + m_scan_asis) * p_disk;
        m_reads_asis = m_ret + m_scan_asis + m_keys;

        # Normalized Target Scan Ratio (default 8.0x), Tightly Tuned (3.0x), Pure Floor (1.0x)
        norm_docs_exam = (docs_exam < (docs_ret * target_ratio)) ? docs_exam : (docs_ret * target_ratio);
        norm_unreturned = (norm_docs_exam > docs_ret) ? (norm_docs_exam - docs_ret) : 0.0;
        norm_scan_units = ceil_int((norm_unreturned * avg_doc_kib) / 4.0);
        m_scan_norm = (r_price / 1000000.0) * norm_scan_units * 30.0;
        m_doc_reads_norm = m_ret + m_scan_norm;
        m_reads_norm = m_doc_reads_norm + m_keys;

        tuned3_docs_exam = (docs_exam < (docs_ret * 3.0)) ? docs_exam : (docs_ret * 3.0);
        tuned3_unreturned = (tuned3_docs_exam > docs_ret) ? (tuned3_docs_exam - docs_ret) : 0.0;
        tuned3_scan_units = ceil_int((tuned3_unreturned * avg_doc_kib) / 4.0);
        m_reads_3x = m_ret + ((r_price / 1000000.0) * tuned3_scan_units * 30.0) + m_keys;

        m_reads_1x = m_ret + m_keys;

        # Segregated Writes (Inserts, Updates, Deletes in 1 KiB tranches + 3x Index Writes) & Storage
        doc_write_tranches = ceil_int(avg_doc_kib / 1.0);
        if (doc_write_tranches < 1) doc_write_tranches = 1;
        w_ins_units = ins_day * doc_write_tranches;
        w_upd_units = upd_day * doc_write_tranches;
        w_del_units = del_day * doc_write_tranches;
        w_doc_units = w_ins_units + w_upd_units + w_del_units;
        w_idx_units = (writes_day * 3.0) * 1.0;
        w_total_units = w_doc_units + w_idx_units;

        m_w_ins = (w_price / 1000000.0) * w_ins_units * 30.0;
        m_w_upd = (w_price / 1000000.0) * w_upd_units * 30.0;
        m_w_del = (w_price / 1000000.0) * w_del_units * 30.0;
        m_w_idx = (w_price / 1000000.0) * w_idx_units * 30.0;
        m_writes = m_w_ins + m_w_upd + m_w_del + m_w_idx;

        m_storage = stored_gib * s_price;

        # Monthly Total TCO across scenarios (PAYG, 1Yr CUD, 3Yr CUD)
        m_tot_asis = m_reads_asis + m_writes + m_storage;
        m_tot_asis_1y = cud_1y(m_reads_asis) + cud_1y(m_writes) + m_storage;
        m_tot_asis_3y = cud_3y(m_reads_asis) + cud_3y(m_writes) + m_storage;

        m_tot_norm = m_reads_norm + m_writes + m_storage;
        m_tot_norm_1y = cud_1y(m_reads_norm) + cud_1y(m_writes) + m_storage;
        m_tot_norm_3y = cud_3y(m_reads_norm) + cud_3y(m_writes) + m_storage;

        m_tot_3x = m_reads_3x + m_writes + m_storage;
        m_tot_3x_1y = cud_1y(m_reads_3x) + cud_1y(m_writes) + m_storage;
        m_tot_3x_3y = cud_3y(m_reads_3x) + cud_3y(m_writes) + m_storage;

        m_tot_1x = m_reads_1x + m_writes + m_storage;
        m_tot_1x_1y = cud_1y(m_reads_1x) + cud_1y(m_writes) + m_storage;
        m_tot_1x_3y = cud_3y(m_reads_1x) + cud_3y(m_writes) + m_storage;

        asis_read_units = total_asis_doc_units + key_units;
        norm_read_units = ret_units + norm_scan_units + key_units;
        read_bloat_mult = (norm_read_units > 0) ? (asis_read_units / norm_read_units) : 1.0;
        tco_bloat_mult = (m_tot_norm > 0) ? (m_tot_asis / m_tot_norm) : 1.0;

        if (cache_rate >= cache_thresh && scan_ratio > ratio_thresh) {
            status = "IN_MEMORY_SCAN_BLOAT_WARNING";
        } else if (scan_ratio > ratio_thresh) {
            status = "HIGH_SCAN_RATIO_WARNING";
        } else {
            status = "HEALTHY";
        }

        # Write structured JSON output
        printf "{\n" > json_out;
        printf "  \"source_file\": \"%s\",\n", src_file > json_out;
        printf "  \"source_type\": \"%s\",\n", src_type > json_out;
        printf "  \"region\": \"%s\",\n", reg_label > json_out;
        printf "  \"status\": \"%s\",\n", status > json_out;
        printf "  \"metrics\": {\n" > json_out;
        printf "    \"average_doc_size_kib\": %.2f,\n", avg_doc_kib > json_out;
        printf "    \"docs_examined_per_day\": %.2f,\n", docs_exam > json_out;
        printf "    \"docs_returned_per_day\": %.2f,\n", docs_ret > json_out;
        printf "    \"unreturned_docs_scanned_per_day\": %.2f,\n", unreturned_docs > json_out;
        printf "    \"inserts_per_day\": %.2f,\n", ins_day > json_out;
        printf "    \"updates_per_day\": %.2f,\n", upd_day > json_out;
        printf "    \"deletes_per_day\": %.2f,\n", del_day > json_out;
        printf "    \"scan_to_return_ratio\": %.2f,\n", scan_ratio > json_out;
        printf "    \"discarded_scan_pct\": %.2f,\n", discarded_pct > json_out;
        printf "    \"wiredtiger_cache_hit_rate_pct\": %.2f,\n", cache_rate > json_out;
        printf "    \"wiredtiger_disk_miss_rate_pct\": %.2f,\n", disk_rate > json_out;
        printf "    \"reads_from_cache_docs_per_day\": %.2f,\n", ram_docs_day > json_out;
        printf "    \"reads_from_disk_docs_per_day\": %.2f,\n", disk_docs_day > json_out;
        printf "    \"asis_read_units_per_day\": %.0f,\n", asis_read_units > json_out;
        printf "    \"normalized_read_units_per_day\": %.0f,\n", norm_read_units > json_out;
        printf "    \"estimated_read_unit_bloat_multiple\": %.2f,\n", read_bloat_mult > json_out;
        printf "    \"estimated_total_tco_bloat_multiple\": %.2f\n", tco_bloat_mult > json_out;
        printf "  },\n" > json_out;
        printf "  \"pricing_monthly_usd\": {\n" > json_out;
        printf "    \"segregated_asis_components\": {\n" > json_out;
        printf "      \"reads_from_cache_ram_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_cache_reads, cud_1y(m_cache_reads), cud_3y(m_cache_reads) > json_out;
        printf "      \"reads_from_disk_misses_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_disk_reads, cud_1y(m_disk_reads), cud_3y(m_disk_reads) > json_out;
        printf "      \"reads_index_entries_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_keys, cud_1y(m_keys), cud_3y(m_keys) > json_out;
        printf "      \"writes_inserts_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_w_ins, cud_1y(m_w_ins), cud_3y(m_w_ins) > json_out;
        printf "      \"writes_updates_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_w_upd, cud_1y(m_w_upd), cud_3y(m_w_upd) > json_out;
        printf "      \"writes_deletes_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_w_del, cud_1y(m_w_del), cud_3y(m_w_del) > json_out;
        printf "      \"writes_indexes_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_w_idx, cud_1y(m_w_idx), cud_3y(m_w_idx) > json_out;
        printf "      \"storage_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f}\n", m_storage, m_storage, m_storage > json_out;
        printf "    },\n" > json_out;
        printf "    \"segregated_target_components\": {\n" > json_out;
        printf "      \"reads_documents_indexed_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_doc_reads_norm, cud_1y(m_doc_reads_norm), cud_3y(m_doc_reads_norm) > json_out;
        printf "      \"reads_index_entries_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_keys, cud_1y(m_keys), cud_3y(m_keys) > json_out;
        printf "      \"writes_inserts_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_w_ins, cud_1y(m_w_ins), cud_3y(m_w_ins) > json_out;
        printf "      \"writes_updates_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_w_upd, cud_1y(m_w_upd), cud_3y(m_w_upd) > json_out;
        printf "      \"writes_deletes_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_w_del, cud_1y(m_w_del), cud_3y(m_w_del) > json_out;
        printf "      \"writes_indexes_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_w_idx, cud_1y(m_w_idx), cud_3y(m_w_idx) > json_out;
        printf "      \"storage_usd\": {\"payg\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f}\n", m_storage, m_storage, m_storage > json_out;
        printf "    },\n" > json_out;
        printf "    \"raw_asis_tco\": {\"on_demand\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_tot_asis, m_tot_asis_1y, m_tot_asis_3y > json_out;
        printf "    \"new_target_normalized_tco\": {\"target_scan_ratio\": %.1f, \"on_demand\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", target_ratio, m_tot_norm, m_tot_norm_1y, m_tot_norm_3y > json_out;
        printf "    \"tightly_tuned_3x_tco\": {\"on_demand\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f},\n", m_tot_3x, m_tot_3x_1y, m_tot_3x_3y > json_out;
        printf "    \"pure_useful_work_1x_tco\": {\"on_demand\": %.2f, \"cud_1yr\": %.2f, \"cud_3yr\": %.2f}\n", m_tot_1x, m_tot_1x_1y, m_tot_1x_3y > json_out;
        printf "  }\n" > json_out;
        printf "}\n" > json_out;
        close(json_out);

        # Write detailed human-readable TCO & Operation-Segregated Breakdown View
        print "TCO & Read-Scan Efficiency Bloat View" > text_out;
        print "-------------------------------------" > text_out;
        printf "Source File:                       %s (%s)\n", src_file, src_type > text_out;
        printf "Pricing Region & Doc Size:         %s | Avg Doc Size: %.2f KiB | Stored: %.2f GiB\n", reg_label, avg_doc_kib, stored_gib > text_out;
        printf "Diagnostic Status:                 %s\n", status > text_out;
        printf "Docs Examined vs. Returned/day:    %.2f examined vs. %.2f returned (%.2fx ratio; healthy <= %.1fx)\n", docs_exam, docs_ret, scan_ratio, ratio_thresh > text_out;
        printf "Discarded Unreturned Scans:        %.2f%% (%.2f docs/day discarded)\n", discarded_pct, unreturned_docs > text_out;
        printf "WiredTiger Cache Hit / Disk Split: %.2f%% In-Memory (RAM) | %.2f%% Physical Disk\n", cache_rate, disk_rate > text_out;
        print "" > text_out;
        print "1. Segregated Operation Breakdown — Raw As-Is Baseline (Cache vs. Disk Reads, Inserts, Updates, Deletes):" > text_out;
        printf "   %-34s | %15s | %12s | %12s | %12s\n", "Operation Component", "Units / GiB day", "PAYG /mo", "1Yr CUD /mo", "3Yr CUD /mo" > text_out;
        printf "   -----------------------------------+-----------------+--------------+--------------+-------------\n" > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f  <-- Mongo RAM hits\n", "Reads - From Cache (RAM)", cache_doc_units, m_cache_reads, cud_1y(m_cache_reads), cud_3y(m_cache_reads) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Reads - From Disk (Misses)", disk_doc_units, m_disk_reads, cud_1y(m_disk_reads), cud_3y(m_disk_reads) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Reads - Index Entries", key_units, m_keys, cud_1y(m_keys), cud_3y(m_keys) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Writes - Inserts", w_ins_units, m_w_ins, cud_1y(m_w_ins), cud_3y(m_w_ins) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Writes - Updates", w_upd_units, m_w_upd, cud_1y(m_w_upd), cud_3y(m_w_upd) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Writes - Deletes", w_del_units, m_w_del, cud_1y(m_w_del), cud_3y(m_w_del) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Writes - Indexes (3x)", w_idx_units, m_w_idx, cud_1y(m_w_idx), cud_3y(m_w_idx) > text_out;
        printf "   %-34s | %15.2f | $%11.2f | $%11.2f | $%11.2f\n", "Storage (GiB)", stored_gib, m_storage, m_storage, m_storage > text_out;
        printf "   -----------------------------------+-----------------+--------------+--------------+-------------\n" > text_out;
        printf "   %-34s | %15s | $%11.2f | $%11.2f | $%11.2f\n", "Total Raw As-Is TCO", "—", m_tot_asis, m_tot_asis_1y, m_tot_asis_3y > text_out;
        print "" > text_out;
        printf "2. Segregated Operation Breakdown — NEW Target TCO (Index-Normalized @ %.1fx):\n", target_ratio > text_out;
        printf "   %-34s | %15s | %12s | %12s | %12s\n", "Operation Component", "Units / GiB day", "PAYG /mo", "1Yr CUD /mo", "3Yr CUD /mo" > text_out;
        printf "   -----------------------------------+-----------------+--------------+--------------+-------------\n" > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Reads - Documents (Indexed)", (ret_units + norm_scan_units), m_doc_reads_norm, cud_1y(m_doc_reads_norm), cud_3y(m_doc_reads_norm) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Reads - Index Entries", key_units, m_keys, cud_1y(m_keys), cud_3y(m_keys) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Writes - Inserts", w_ins_units, m_w_ins, cud_1y(m_w_ins), cud_3y(m_w_ins) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Writes - Updates", w_upd_units, m_w_upd, cud_1y(m_w_upd), cud_3y(m_w_upd) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Writes - Deletes", w_del_units, m_w_del, cud_1y(m_w_del), cud_3y(m_w_del) > text_out;
        printf "   %-34s | %15.0f | $%11.2f | $%11.2f | $%11.2f\n", "Writes - Indexes (3x)", w_idx_units, m_w_idx, cud_1y(m_w_idx), cud_3y(m_w_idx) > text_out;
        printf "   %-34s | %15.2f | $%11.2f | $%11.2f | $%11.2f\n", "Storage (GiB)", stored_gib, m_storage, m_storage, m_storage > text_out;
        printf "   -----------------------------------+-----------------+--------------+--------------+-------------\n" > text_out;
        printf "   %-34s | %15s | $%11.2f | $%11.2f | $%11.2f\n", "Total NEW Target TCO", "—", m_tot_norm, m_tot_norm_1y, m_tot_norm_3y > text_out;
        print "" > text_out;
        print "3. Scan-Efficiency Sensitivity Summary Across Indexing Scenarios:" > text_out;
        printf "   %-48s | %14s | %14s | %14s\n", "TCO Scenario", "PAYG /mo", "1Yr CUD /mo", "3Yr CUD /mo" > text_out;
        printf "   -------------------------------------------------+----------------+----------------+---------------\n" > text_out;
        printf "   %-48s | $%13.2f | $%13.2f | $%13.2f\n", sprintf("Raw As-Is (%.1fx Scan Bloat - Do Not Propose)", scan_ratio), m_tot_asis, m_tot_asis_1y, m_tot_asis_3y > text_out;
        printf "   %-48s | $%13.2f | $%13.2f | $%13.2f\n", sprintf("NEW Target TCO (Index-Normalized @ %.1fx)", target_ratio), m_tot_norm, m_tot_norm_1y, m_tot_norm_3y > text_out;
        printf "   %-48s | $%13.2f | $%13.2f | $%13.2f\n", "Tightly Tuned Covering Indexes (@ 3.0x)", m_tot_3x, m_tot_3x_1y, m_tot_3x_3y > text_out;
        printf "   %-48s | $%13.2f | $%13.2f | $%13.2f\n", "Pure Useful Work Floor (@ 1.0x Exact Match)", m_tot_1x, m_tot_1x_1y, m_tot_1x_3y > text_out;
        print "" > text_out;
        if (status == "IN_MEMORY_SCAN_BLOAT_WARNING") {
            printf "[WARNING] IN-MEMORY SCAN BLOAT DETECTED (Total TCO Bloated %.1fx | Read Units Bloated %.1fx):\n", tco_bloat_mult, read_bloat_mult > text_out;
            printf "  - %.1f%% of reads ($%.2f/mo of raw As-Is cost) come from WiredTiger RAM hits ($%.2f/mo from disk reads),\n", cache_rate, m_cache_reads, m_disk_reads > text_out;
            printf "    validated by DocsExamined = %.1fx DocsReturned (%.1f%% of scanned docs discarded).\n", scan_ratio, discarded_pct > text_out;
            printf "  - Action: Present the NEW Index-Normalized Target TCO ($%.2f/mo On-Demand | $%.2f/mo 3Yr CUD)\n", m_tot_norm, m_tot_norm_3y > text_out;
            printf "    paired with pre-migration composite index tuning.\n" > text_out;
        } else if (status == "HIGH_SCAN_RATIO_WARNING") {
            printf "[WARNING] HIGH SCAN-TO-RETURN RATIO DETECTED (%.1fx > %.1fx): Raw As-Is TCO ($%.2f/mo) drops to $%.2f/mo after indexing.\n", scan_ratio, ratio_thresh, m_tot_asis, m_tot_norm > text_out;
        } else {
            printf "[OK] Read scan efficiency (%.2fx) and cache profile are within healthy sizing bounds (Estimated TCO: $%.2f/mo).\n", scan_ratio, m_tot_asis > text_out;
        }
        close(text_out);
    }'

    local tco_status=$(jq -r '.status // "SKIPPED"' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local scan_ratio=$(jq -r '.metrics.scan_to_return_ratio // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local cache_hit_pct=$(jq -r '.metrics.wiredtiger_cache_hit_rate_pct // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local tco_bloat_mult=$(jq -r '.metrics.estimated_total_tco_bloat_multiple // 1' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local cache_usd=$(jq -r '.pricing_monthly_usd.segregated_asis_components.reads_from_cache_ram_usd.payg // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local disk_usd=$(jq -r '.pricing_monthly_usd.segregated_asis_components.reads_from_disk_misses_usd.payg // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local asis_usd=$(jq -r '.pricing_monthly_usd.raw_asis_tco.on_demand // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local norm_usd=$(jq -r '.pricing_monthly_usd.new_target_normalized_tco.on_demand // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local norm_1y_usd=$(jq -r '.pricing_monthly_usd.new_target_normalized_tco.cud_1yr // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
    local norm_3y_usd=$(jq -r '.pricing_monthly_usd.new_target_normalized_tco.cud_3yr // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)

    echo "TCO & Read-Scan Efficiency ($region_label):" >> "$SUMMARY_OUTPUT"
    echo "  Diagnostic status: $tco_status" >> "$SUMMARY_OUTPUT"
    echo "  Scan-to-return ratio (DocsExamined:DocsReturned): ${scan_ratio}x" >> "$SUMMARY_OUTPUT"
    echo "  WiredTiger cache split: ${cache_hit_pct}% In-Memory (\$$cache_usd/mo As-Is) vs. Disk (\$$disk_usd/mo As-Is)" >> "$SUMMARY_OUTPUT"
    echo "  Raw As-Is TCO (Bloated ${tco_bloat_mult}x): \$$asis_usd/mo PAYG" >> "$SUMMARY_OUTPUT"
    echo "  New Target TCO (Index-Normalized @ ${TARGET_SCAN_RATIO}x): \$$norm_usd/mo PAYG | \$$norm_1y_usd/mo 1Yr CUD | \$$norm_3y_usd/mo 3Yr CUD" >> "$SUMMARY_OUTPUT"
    echo "" >> "$SUMMARY_OUTPUT"
}

# Function to generate text report
generate_text_report() {
    echo "=========================================================="
    echo "           FIRESTORE MIGRATION ASSESSMENT REPORT          "
    echo "=========================================================="
    echo ""
    
    # Print summary
    if [[ -f "$SUMMARY_OUTPUT" ]]; then
        echo "SUMMARY:"
        echo "--------"
        cat "$SUMMARY_OUTPUT"
        echo ""
    fi
    
    # Print detailed results
    if [[ "$RUN_DATATYPE" == "true" ]]; then
        echo "DATATYPE COMPATIBILITY DETAILS:"
        echo "-------------------------------"
        cat "$DATATYPE_OUTPUT"
        echo ""
    fi
    
    if [[ "$RUN_OPERATOR" == "true" ]]; then
        echo "OPERATOR COMPATIBILITY DETAILS:"
        echo "-------------------------------"
        cat "$OPERATOR_OUTPUT"
        echo ""
    fi
    
    if [[ "$RUN_INDEX" == "true" ]]; then
        echo "INDEX COMPATIBILITY DETAILS:"
        echo "----------------------------"
        cat "$INDEX_OUTPUT"
        echo ""
    fi

    if [[ "$RUN_TCO" == "true" ]]; then
        echo "TCO & READ-SCAN EFFICIENCY DETAILS:"
        echo "-----------------------------------"
        cat "$TCO_OUTPUT"
        echo ""
    fi
    
    echo "=========================================================="
    echo "                      END OF REPORT                       "
    echo "=========================================================="
}

# Function to generate JSON report
generate_json_report() {
    # Create a temporary JSON file
    local json_file="$TEMP_DIR/report.json"
    
    # Start building the JSON
    echo "{" > "$json_file"
    echo "  \"summary\": {" >> "$json_file"
    
    # Add datatype section if applicable
    if [[ "$RUN_DATATYPE" == "true" ]]; then
        local total_files=$(grep "Scanned" "$DATATYPE_OUTPUT" | awk '{print $2}')
        local issue_files=$(grep "Found" "$DATATYPE_OUTPUT" | awk '{print $2}')
        local total_issues=$(grep "Detected" "$DATATYPE_OUTPUT" | awk '{print $2}')
        
        echo "    \"datatype_compatibility\": {" >> "$json_file"
        echo "      \"total_files\": ${total_files:-0}," >> "$json_file"
        echo "      \"files_with_issues\": ${issue_files:-0}," >> "$json_file"
        echo "      \"total_issues\": ${total_issues:-0}" >> "$json_file"
        
        # Add comma if there are more sections
        if [[ "$RUN_OPERATOR" == "true" || "$RUN_INDEX" == "true" || "$RUN_TCO" == "true" ]]; then
            echo "    }," >> "$json_file"
        else
            echo "    }" >> "$json_file"
        fi
    fi
    
    # Add operator section if applicable
    if [[ "$RUN_OPERATOR" == "true" ]]; then
        local processed_files=$(grep "Processed" "$OPERATOR_OUTPUT" | head -1 | awk '{print $2}')
        local unique_operators=$(grep "Found.*unsupported operators" "$OPERATOR_OUTPUT" | head -1 | awk '{print $2}')
        
        echo "    \"operator_compatibility\": {" >> "$json_file"
        echo "      \"files_processed\": ${processed_files:-0}," >> "$json_file"
        echo "      \"unsupported_operators\": ${unique_operators:-0}" >> "$json_file"
        
        # Add comma if there are more sections
        if [[ "$RUN_INDEX" == "true" || "$RUN_TCO" == "true" ]]; then
            echo "    }," >> "$json_file"
        else
            echo "    }" >> "$json_file"
        fi
    fi
    
    # Add index section if applicable
    if [[ "$RUN_INDEX" == "true" ]]; then
        local total_indexes=$(grep "Total indexes:" "$INDEX_OUTPUT" | awk '{print $3}')
        local compatible_indexes=$(grep "Compatible indexes:" "$INDEX_OUTPUT" | awk '{print $3}')
        local incompatible_indexes=$(grep "Incompatible indexes:" "$INDEX_OUTPUT" | awk '{print $3}')
        
        echo "    \"index_compatibility\": {" >> "$json_file"
        echo "      \"total_indexes\": ${total_indexes:-0}," >> "$json_file"
        echo "      \"compatible_indexes\": ${compatible_indexes:-0}," >> "$json_file"
        echo "      \"incompatible_indexes\": ${incompatible_indexes:-0}" >> "$json_file"
        if [[ "$RUN_TCO" == "true" ]]; then
            echo "    }," >> "$json_file"
        else
            echo "    }" >> "$json_file"
        fi
    fi

    # Add TCO scan efficiency section if applicable
    if [[ "$RUN_TCO" == "true" ]]; then
        local tco_status=$(jq -r '.status // "SKIPPED"' "$TCO_JSON_OUTPUT" 2>/dev/null)
        local scan_ratio=$(jq -r '.metrics.scan_to_return_ratio // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
        local cache_hit_pct=$(jq -r '.metrics.wiredtiger_cache_hit_rate_pct // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
        local tco_bloat_mult=$(jq -r '.metrics.estimated_total_tco_bloat_multiple // 1' "$TCO_JSON_OUTPUT" 2>/dev/null)
        local cache_usd=$(jq -r '.pricing_monthly_usd.segregated_asis_components.reads_from_cache_ram_usd // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
        local disk_usd=$(jq -r '.pricing_monthly_usd.segregated_asis_components.reads_from_disk_misses_usd // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
        local asis_usd=$(jq -r '.pricing_monthly_usd.raw_asis_tco.on_demand // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
        local norm_usd=$(jq -r '.pricing_monthly_usd.new_target_normalized_tco.on_demand // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)
        local norm_3y_usd=$(jq -r '.pricing_monthly_usd.new_target_normalized_tco.cud_3yr // 0' "$TCO_JSON_OUTPUT" 2>/dev/null)

        echo "    \"tco_scan_efficiency\": {" >> "$json_file"
        echo "      \"status\": \"$tco_status\"," >> "$json_file"
        echo "      \"scan_to_return_ratio\": $scan_ratio," >> "$json_file"
        echo "      \"wiredtiger_cache_hit_rate_pct\": $cache_hit_pct," >> "$json_file"
        echo "      \"reads_from_cache_monthly_usd\": $cache_usd," >> "$json_file"
        echo "      \"reads_from_disk_monthly_usd\": $disk_usd," >> "$json_file"
        echo "      \"raw_asis_monthly_tco_usd\": $asis_usd," >> "$json_file"
        echo "      \"new_target_normalized_monthly_tco_usd\": $norm_usd," >> "$json_file"
        echo "      \"new_target_3yr_cud_monthly_tco_usd\": $norm_3y_usd," >> "$json_file"
        echo "      \"estimated_total_tco_bloat_multiple\": $tco_bloat_mult" >> "$json_file"
        echo "    }" >> "$json_file"
    fi
    
    # Close summary section
    echo "  }" >> "$json_file"
    
    # Always add detailed sections for JSON format
    echo "  ,\"details\": {" >> "$json_file"
    
    # Add datatype details if applicable
    if [[ "$RUN_DATATYPE" == "true" ]]; then
        # Create structured JSON for datatype details
        echo "    \"datatype\": {" >> "$json_file"
        echo "      \"files_with_issues\": [" >> "$json_file"
        
        # Process datatype output to extract file issues
        local current_file=""
        local first_file=true
        
        # Read the datatype output line by line
        while IFS= read -r line; do
            # Check if this is a file line
            if [[ "$line" =~ ^File:\ (.+)$ ]]; then
                # Extract the filename
                local filename="${BASH_REMATCH[1]}"
                
                # If we were processing a previous file, close its JSON object
                if [[ -n "$current_file" && "$first_file" == "false" ]]; then
                    echo "          ]" >> "$json_file"
                    echo "        }," >> "$json_file"
                elif [[ -n "$current_file" && "$first_file" == "true" ]]; then
                    echo "          ]" >> "$json_file"
                    echo "        }" >> "$json_file"
                    first_file=false
                fi
                
                # Start a new file object
                if [[ "$first_file" == "true" ]]; then
                    echo "        {" >> "$json_file"
                    first_file=false
                else
                    echo "        {" >> "$json_file"
                fi
                
                echo "          \"file\": \"$filename\"," >> "$json_file"
                echo "          \"issues\": [" >> "$json_file"
                
                current_file="$filename"
                first_issue=true
            
            # Check if this is an issue line
            elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]Line[[:space:]]([0-9]+): ]]; then
                # Extract line number from regex match
                local line_num="${BASH_REMATCH[1]}"
                
                # Extract type and description using simpler string operations
                local rest_of_line="${line#*Line $line_num: }"
                local issue_type="${rest_of_line%% detected*}"
                local description="unsupported by Firestore"
                
                # Add the issue to the current file
                if [[ "$first_issue" == "true" ]]; then
                    echo "            {" >> "$json_file"
                    first_issue=false
                else
                    echo "            ,{" >> "$json_file"
                fi
                
                echo "              \"line\": $line_num," >> "$json_file"
                echo "              \"type\": \"$issue_type\"," >> "$json_file"
                echo "              \"description\": \"$description\"" >> "$json_file"
                echo "            }" >> "$json_file"
            fi
        done < "$DATATYPE_OUTPUT"
        
        # Close the last file object if there was one
        if [[ -n "$current_file" ]]; then
            echo "          ]" >> "$json_file"
            echo "        }" >> "$json_file"
        fi
        
        # Close the files_with_issues array
        echo "      ]" >> "$json_file"
        echo "    }" >> "$json_file"
        
        # Add comma if there are more sections
        if [[ "$RUN_OPERATOR" == "true" || "$RUN_INDEX" == "true" || "$RUN_TCO" == "true" ]]; then
            echo "    ," >> "$json_file"
        fi
    fi
    
    # Add operator details if applicable
    if [[ "$RUN_OPERATOR" == "true" ]]; then
        # Create structured JSON for operator details
        echo "    \"operator\": {" >> "$json_file"
        echo "      \"unsupported_operators\": [" >> "$json_file"
        
        # Process operator output to extract operator issues
        local current_operator=""
        local first_operator=true
        local in_locations=false
        
        # Read the operator output line by line
        while IFS= read -r line; do
            # Check if this is an operator line
            if [[ "$line" =~ ^Operator:[[:space:]]\\\$([^[:space:]]+)$ ]]; then
                # Extract the operator name
                local operator_name="${BASH_REMATCH[1]}"
                
                # If we were processing a previous operator, close its JSON object
                if [[ -n "$current_operator" && "$first_operator" == "false" ]]; then
                    echo "          ]" >> "$json_file"
                    echo "        }," >> "$json_file"
                elif [[ -n "$current_operator" && "$first_operator" == "true" ]]; then
                    echo "          ]" >> "$json_file"
                    echo "        }" >> "$json_file"
                    first_operator=false
                fi
                
                # Start a new operator object
                if [[ "$first_operator" == "true" ]]; then
                    echo "        {" >> "$json_file"
                    first_operator=false
                else
                    echo "        {" >> "$json_file"
                fi
                
                echo "          \"operator\": \"\$$operator_name\"," >> "$json_file"
                current_operator="$operator_name"
                in_locations=false
            
            # Check if this is an occurrences line
            elif [[ "$line" =~ ^Total[[:space:]]occurrences:[[:space:]]+([0-9]+)$ ]]; then
                # Extract the occurrences count
                local occurrences="${BASH_REMATCH[1]}"
                echo "          \"occurrences\": $occurrences," >> "$json_file"
                echo "          \"locations\": [" >> "$json_file"
                in_locations=true
                first_location=true
            
            # Check if this is a location line
            elif [[ "$in_locations" == "true" && "$line" =~ ^[[:space:]]+([^[:space:]]+)[[:space:]]\(line[[:space:]]([0-9]+)\)$ ]]; then
                # Extract file and line number
                local file="${BASH_REMATCH[1]}"
                local line_num="${BASH_REMATCH[2]}"
                
                # Add the location to the current operator
                if [[ "$first_location" == "true" ]]; then
                    echo "            {" >> "$json_file"
                    first_location=false
                else
                    echo "            ,{" >> "$json_file"
                fi
                
                echo "              \"file\": \"$file\"," >> "$json_file"
                echo "              \"line\": $line_num" >> "$json_file"
                echo "            }" >> "$json_file"
            fi
        done < <(grep -A 100 "Firestore Operator Compatibility Summary" "$OPERATOR_OUTPUT")
        
        # Close the last operator object if there was one
        if [[ -n "$current_operator" ]]; then
            echo "          ]" >> "$json_file"
            echo "        }" >> "$json_file"
        fi
        
        # Close the unsupported_operators array
        echo "      ]" >> "$json_file"
        echo "    }" >> "$json_file"
        
        # Add comma if there are more sections
        if [[ "$RUN_INDEX" == "true" || "$RUN_TCO" == "true" ]]; then
            echo "    ," >> "$json_file"
        fi
    fi
    
    # Add index details if applicable
    if [[ "$RUN_INDEX" == "true" ]]; then
        # Create structured JSON for index details
        echo "    \"index\": {" >> "$json_file"
        echo "      \"incompatible_indexes\": [" >> "$json_file"
        
        # Process index output to extract index issues
        local current_type=""
        local first_type=true
        local in_affected=false
        
        # Read the index output line by line
        while IFS= read -r line; do
            # Check if this is an index type line
            if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]indexes[[:space:]]found:[[:space:]]([0-9]+)$ ]]; then
                # Extract the index type and count
                local index_type="${BASH_REMATCH[1]}"
                local count="${BASH_REMATCH[2]}"
                
                # If we were processing a previous type, close its JSON object
                if [[ -n "$current_type" && "$first_type" == "false" ]]; then
                    echo "          ]" >> "$json_file"
                    echo "        }," >> "$json_file"
                elif [[ -n "$current_type" && "$first_type" == "true" ]]; then
                    echo "          ]" >> "$json_file"
                    echo "        }" >> "$json_file"
                    first_type=false
                fi
                
                # Start a new type object
                if [[ "$first_type" == "true" ]]; then
                    echo "        {" >> "$json_file"
                    first_type=false
                else
                    echo "        {" >> "$json_file"
                fi
                
                echo "          \"type\": \"$index_type\"," >> "$json_file"
                echo "          \"count\": $count," >> "$json_file"
                echo "          \"indexes\": [" >> "$json_file"
                
                current_type="$index_type"
                in_affected=true
                first_index=true
            
            # Check if this is an affected index line
            elif [[ "$in_affected" == "true" && "$line" =~ ^[[:space:]]+\*[[:space:]](.+)$ ]]; then
                # Extract the index name
                local index_name="${BASH_REMATCH[1]}"
                
                # Add the index to the current type
                if [[ "$first_index" == "true" ]]; then
                    echo "            \"$index_name\"" >> "$json_file"
                    first_index=false
                else
                    echo "            ,\"$index_name\"" >> "$json_file"
                fi
            
            # Check if we're done with affected indexes
            elif [[ "$in_affected" == "true" && "$line" =~ ^$ ]]; then
                in_affected=false
            fi
        done < <(grep -A 100 "Index Compatibility Summary" "$INDEX_OUTPUT")
        
        # Close the last type object if there was one
        if [[ -n "$current_type" ]]; then
            echo "          ]" >> "$json_file"
            echo "        }" >> "$json_file"
        fi
        
        # Close the incompatible_indexes array
        echo "      ]" >> "$json_file"
        echo "    }" >> "$json_file"

        if [[ "$RUN_TCO" == "true" ]]; then
            echo "    ," >> "$json_file"
        fi
    fi

    # Add TCO scan efficiency details if applicable
    if [[ "$RUN_TCO" == "true" ]]; then
        echo -n "    \"tco_scan_efficiency\": " >> "$json_file"
        if [[ -s "$TCO_JSON_OUTPUT" ]]; then
            cat "$TCO_JSON_OUTPUT" >> "$json_file"
        else
            echo "{\"status\":\"SKIPPED\"}" >> "$json_file"
        fi
    fi
    
    # Close details section
    echo "  }" >> "$json_file"
    
    # Close JSON
    echo "}" >> "$json_file"
    
    # Output the JSON
    cat "$json_file"
}


# Run assessments
echo "Starting Firestore Migration Assessment..." > "$SUMMARY_OUTPUT"
echo "" >> "$SUMMARY_OUTPUT"

if [[ "$RUN_DATATYPE" == "true" ]]; then
    run_datatype_assessment
fi

if [[ "$RUN_OPERATOR" == "true" ]]; then
    run_operator_assessment
fi

if [[ "$RUN_INDEX" == "true" ]]; then
    run_index_assessment
fi

if [[ "$RUN_TCO" == "true" ]]; then
    run_tco_assessment
fi

# Generate report
if [[ "$OUTPUT_FORMAT" == "text" ]]; then
    if [[ -n "$OUTPUT_FILE" ]]; then
        generate_text_report > "$OUTPUT_FILE"
        echo "Report saved to $OUTPUT_FILE"
    else
        generate_text_report
    fi
elif [[ "$OUTPUT_FORMAT" == "json" ]]; then
    if [[ -n "$OUTPUT_FILE" ]]; then
        generate_json_report > "$OUTPUT_FILE"
        echo "Report saved to $OUTPUT_FILE"
    else
        generate_json_report
    fi
fi

exit 0
