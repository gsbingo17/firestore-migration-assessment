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
    echo "                            Uses subdirectory routing:"
    echo "                            - app/ for operator checking"
    echo "                            - data/ for datatype checking"
    echo "                            - root directory for index checking"
    echo "  --file FILE               File to scan (for any assessment type)"
    echo "                            Use with --run-datatype, --run-operator, --run-index, or --run-all"
    echo "  --output-format FORMAT    Output format (text, json) [default: text]"
    echo "  --output-file FILE        File to write the report to [default: stdout]"
    echo "  --run-all                 Run all assessment types"
    echo "  --run-datatype            Run only datatype compatibility assessment"
    echo "  --run-operator            Run only operator compatibility assessment"
    echo "  --run-index               Run only index compatibility assessment"
    echo "  --verbose                 Show detailed information"
    echo "  --quiet                   Suppress progress messages and non-essential output"
    echo "  --help                    Display this help message"
    echo ""
    echo "Examples:"
    echo "  # Directory-based assessment:"
    echo "  $0 --dir sample_data --run-all"
    echo "  $0 --dir sample_data --run-operator"
    echo ""
    echo "  # File-based assessment:"
    echo "  $0 --file sample.json --run-datatype"
    echo "  $0 --file mongodb.log --run-operator"
    echo "  $0 --file indexes.metadata.json --run-index"
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
        # Check if data subdirectory exists, use it; otherwise use main directory
        if [[ -d "$DIR/data" ]]; then
            datatype_args="--dir $DIR/data"
        else
            datatype_args="--dir $DIR"
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
        # Check if app subdirectory exists, use it; otherwise use main directory
        if [[ -d "$DIR/app" ]]; then
            operator_args="$operator_args --dir $DIR/app"
        else
            operator_args="$operator_args --dir $DIR"
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
        if [[ "$RUN_OPERATOR" == "true" || "$RUN_INDEX" == "true" ]]; then
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
        if [[ "$RUN_INDEX" == "true" ]]; then
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
