#!/bin/bash
# Firestore Migration Assessment Suite
# This script combines the datatype, operator, and index compatibility checkers
# to provide a comprehensive assessment for MongoDB to Firestore migration.

# Set script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DIR=""
LOG_FILE=""
DATA_FILE=""
METADATA_DIR=""
OUTPUT_FORMAT="text"
OUTPUT_FILE=""
RUN_DATATYPE=false
RUN_OPERATOR=false
RUN_INDEX=false
RUN_COLLECT_SAMPLES=false
VERBOSE=false
QUIET=false

# Temporary files for capturing output
TEMP_DIR=$(mktemp -d)
DATATYPE_OUTPUT="$TEMP_DIR/datatype_output.txt"
OPERATOR_OUTPUT="$TEMP_DIR/operator_output.txt"
INDEX_OUTPUT="$TEMP_DIR/index_output.txt"
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
    echo "  --log-file FILE           MongoDB log file to analyze for operator compatibility"
    echo "  --data-file FILE          JSON data file to check for data type compatibility"
    echo "  --metadata-dir DIR        Directory containing index metadata files"
    echo "  --output-format FORMAT    Output format (text, json) [default: text]"
    echo "  --output-file FILE        File to write the report to [default: stdout]"
    echo "  --run-all                 Run all assessment types"
    echo "  --run-datatype            Run only datatype compatibility assessment"
    echo "  --run-operator            Run only operator compatibility assessment"
    echo "  --run-index               Run only index compatibility assessment"
    echo "  --collect-samples         Collect sample data from MongoDB for datatype assessment"
    echo "  --verbose                 Show detailed information"
    echo "  --quiet                   Suppress progress messages and non-essential output"
    echo "  --help                    Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --dir /path/to/project --run-all"
    echo "  $0 --log-file logs/mongodb.log --run-operator"
    echo "  $0 --data-file data.json --run-datatype --verbose"
    echo "  $0 --collect-samples --run-datatype"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            DIR="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --data-file)
            DATA_FILE="$2"
            shift 2
            ;;
        --metadata-dir)
            METADATA_DIR="$2"
            shift 2
            ;;
        --output-format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --collect-samples)
            RUN_COLLECT_SAMPLES=true
            shift
            ;;
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --run-all)
            RUN_DATATYPE=true
            RUN_OPERATOR=true
            RUN_INDEX=true
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
if [[ "$RUN_DATATYPE" == "false" && "$RUN_OPERATOR" == "false" && "$RUN_INDEX" == "false" ]]; then
    echo "Error: At least one assessment type must be selected (--run-datatype, --run-operator, --run-index, or --run-all)"
    usage
fi

if [[ "$RUN_DATATYPE" == "true" && -z "$DATA_FILE" && -z "$DIR" ]]; then
    echo "Error: For datatype assessment, either --data-file or --dir must be specified"
    usage
fi

if [[ "$RUN_OPERATOR" == "true" && -z "$LOG_FILE" && -z "$DIR" ]]; then
    echo "Error: For operator assessment, either --log-file or --dir must be specified"
    usage
fi

if [[ "$RUN_INDEX" == "true" && -z "$METADATA_DIR" && -z "$DIR" ]]; then
    echo "Error: For index assessment, either --metadata-dir or --dir must be specified"
    usage
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
    
    if [[ -n "$DATA_FILE" ]]; then
        datatype_args="--file $DATA_FILE"
    elif [[ -n "$DIR" ]]; then
        datatype_args="--dir $DIR"
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
    
    local operator_args="--mode=scan"
    
    if [[ -n "$LOG_FILE" ]]; then
        operator_args="$operator_args --file=$LOG_FILE"
    elif [[ -n "$DIR" ]]; then
        operator_args="$operator_args --directory=$DIR"
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
    
    if [[ -n "$METADATA_DIR" ]]; then
        index_args="$index_args --dir $METADATA_DIR"
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
        echo "      \"total_files\": $total_files," >> "$json_file"
        echo "      \"files_with_issues\": $issue_files," >> "$json_file"
        echo "      \"total_issues\": $total_issues" >> "$json_file"
        
        # Add comma if there are more sections
        if [[ "$RUN_OPERATOR" == "true" || "$RUN_INDEX" == "true" ]]; then
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
        echo "      \"files_processed\": $processed_files," >> "$json_file"
        echo "      \"unsupported_operators\": $unique_operators" >> "$json_file"
        
        # Add comma if there are more sections
        if [[ "$RUN_INDEX" == "true" ]]; then
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
        echo "      \"total_indexes\": $total_indexes," >> "$json_file"
        echo "      \"compatible_indexes\": $compatible_indexes," >> "$json_file"
        echo "      \"incompatible_indexes\": $incompatible_indexes" >> "$json_file"
        echo "    }" >> "$json_file"
    fi
    
    # Close summary section
    echo "  }" >> "$json_file"
    
    # Add detailed sections if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        echo "  ,\"details\": {" >> "$json_file"
        
        # Add datatype details if applicable
        if [[ "$RUN_DATATYPE" == "true" ]]; then
            # Escape special characters in the output
            local datatype_details=$(cat "$DATATYPE_OUTPUT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')
            echo "    \"datatype\": \"$datatype_details\"" >> "$json_file"
            
            # Add comma if there are more sections
            if [[ "$RUN_OPERATOR" == "true" || "$RUN_INDEX" == "true" ]]; then
                echo "    ," >> "$json_file"
            fi
        fi
        
        # Add operator details if applicable
        if [[ "$RUN_OPERATOR" == "true" ]]; then
            # Escape special characters in the output
            local operator_details=$(cat "$OPERATOR_OUTPUT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')
            echo "    \"operator\": \"$operator_details\"" >> "$json_file"
            
            # Add comma if there are more sections
            if [[ "$RUN_INDEX" == "true" ]]; then
                echo "    ," >> "$json_file"
            fi
        fi
        
        # Add index details if applicable
        if [[ "$RUN_INDEX" == "true" ]]; then
            # Escape special characters in the output
            local index_details=$(cat "$INDEX_OUTPUT" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | tr '\n' ' ')
            echo "    \"index\": \"$index_details\"" >> "$json_file"
        fi
        
        # Close details section
        echo "  }" >> "$json_file"
    fi
    
    # Close JSON
    echo "}" >> "$json_file"
    
    # Output the JSON
    cat "$json_file"
}

# Function to collect sample data from MongoDB
collect_sample_data() {
    if [[ "$OUTPUT_FORMAT" == "text" && "$QUIET" == "false" ]]; then
        echo "Collecting sample data from MongoDB..."
    fi
    
    # Check if the collection script exists
    if [[ ! -f "$SCRIPT_DIR/collect_sample_data.sh" ]]; then
        echo "Error: Sample data collection script not found: $SCRIPT_DIR/collect_sample_data.sh"
        return 1
    fi
    
    # Make sure the script is executable
    chmod +x "$SCRIPT_DIR/collect_sample_data.sh"
    
    # Run the collection script
    "$SCRIPT_DIR/collect_sample_data.sh" > "$TEMP_DIR/sample_collection_output.txt" 2>&1
    
    # Check if the script ran successfully
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to collect sample data from MongoDB"
        cat "$TEMP_DIR/sample_collection_output.txt"
        return 1
    fi
    
    # Extract summary information
    local sample_files=$(grep "collection sample files created" "$TEMP_DIR/sample_collection_output.txt" | awk '{print $1}')
    
    # Add to summary
    echo "MongoDB Sample Data Collection:" >> "$SUMMARY_OUTPUT"
    echo "  Sample files created: $sample_files" >> "$SUMMARY_OUTPUT"
    echo "  Output directory: sample_data" >> "$SUMMARY_OUTPUT"
    echo "" >> "$SUMMARY_OUTPUT"
    
    # Set the directory for datatype assessment
    if [[ -z "$DIR" && -z "$DATA_FILE" ]]; then
        DIR="sample_data"
    fi
    
    # Display output if not quiet
    if [[ "$QUIET" == "false" ]]; then
        cat "$TEMP_DIR/sample_collection_output.txt"
    fi
}

# Run assessments
echo "Starting Firestore Migration Assessment..." > "$SUMMARY_OUTPUT"
echo "" >> "$SUMMARY_OUTPUT"

if [[ "$RUN_COLLECT_SAMPLES" == "true" ]]; then
    collect_sample_data
fi

if [[ "$RUN_DATATYPE" == "true" ]]; then
    run_datatype_assessment
fi

if [[ "$RUN_OPERATOR" == "true" ]]; then
    run_operator_assessment
fi

if [[ "$RUN_INDEX" == "true" ]]; then
    run_index_assessment
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
