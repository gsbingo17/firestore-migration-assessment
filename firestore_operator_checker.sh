#!/bin/bash

# Firestore Operator Compatibility Checker
# This script checks MongoDB code/logs for operators that may not be supported in Firestore

# Redirect stderr to /dev/null to suppress grep error messages
exec 2>/dev/null

# Use the external compatibility data file
cp mongodb_compat_data.txt /tmp/mongodb_compat_data.txt

# Remove comments from the data file
grep -v "^#" /tmp/mongodb_compat_data.txt > /tmp/mongodb_compat_clean.txt

# Function to display usage information
function show_usage {
    echo "Usage: firestore_operator_checker.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --mode=SCAN|CSV            Operation mode (default: SCAN)"
    echo "  --dir=DIR                  Directory to scan (alias for --directory)"
    echo "  --directory=DIR            Directory to scan"
    echo "  --file=FILE                Specific file to scan"
    echo "  --excluded-extensions=EXT  Comma-separated list of extensions to exclude (default: none)"
    echo "  --included-extensions=EXT  Comma-separated list of extensions to include (default: all)"
    echo "  --excluded-directories=DIR Comma-separated list of directories to exclude (default: none)"
    echo "  --show-supported           Show supported operators in report"
    echo "  --help                     Display this help message"
    echo ""
    echo "Examples:"
    echo "  ./firestore_operator_checker.sh --mode=scan --dir=./src"
    echo "  ./firestore_operator_checker.sh --mode=csv"
}

# Function to check if an operator is supported
function is_supported {
    local operator="$1"
    
    # Get the operator line from the data file
    local operator_line=$(grep "^\\$operator:" /tmp/mongodb_compat_clean.txt)
    
    # If operator not found, assume not supported
    if [ -z "$operator_line" ]; then
        echo "No"
        return
    fi
    
    # Extract the support status
    local support_status=$(echo "$operator_line" | cut -d':' -f2 | tr -d ' ')
    
    # Return the support status
    echo "$support_status"
}

# Function to scan files for MongoDB operators
function scan_mode {
    local dir="$1"
    local file="$2"
    local excluded_exts="$3"
    local included_exts="$4"
    local excluded_dirs="$5"
    local show_supported="$6"
    
    # Create a temporary file to store unsupported operator locations
    rm -f /tmp/mongodb_compat_locations.txt
    touch /tmp/mongodb_compat_locations.txt
    
    # Create file list
    local file_list=""
    
    if [ -n "$file" ]; then
        # Single file mode
        if [ ! -f "$file" ]; then
            echo "Error: File not found: $file"
            exit 1
        fi
        file_list="$file"
        echo "Scanning file: $file"
    else
        # Directory mode
        if [ ! -d "$dir" ]; then
            echo "Error: Directory not found: $dir"
            exit 1
        fi
        
        echo "Scanning directory: $dir"
        
        # Build find command
        local find_cmd="find \"$dir\" -type f"
        
        # Add excluded extensions if specified
        if [ -n "$excluded_exts" ] && [ "$excluded_exts" != "none" ]; then
            local exclude_pattern=""
            IFS=',' read -ra EXTS <<< "$excluded_exts"
            for ext in "${EXTS[@]}"; do
                if [ -n "$exclude_pattern" ]; then
                    exclude_pattern="$exclude_pattern -o"
                fi
                exclude_pattern="$exclude_pattern -name \"*.$ext\""
            done
            
            if [ -n "$exclude_pattern" ]; then
                find_cmd="$find_cmd -not \\( $exclude_pattern \\)"
            fi
        fi
        
        # Add included extensions if specified
        if [ -n "$included_exts" ] && [ "$included_exts" != "all" ]; then
            local include_pattern=""
            IFS=',' read -ra EXTS <<< "$included_exts"
            for ext in "${EXTS[@]}"; do
                if [ -n "$include_pattern" ]; then
                    include_pattern="$include_pattern -o"
                fi
                include_pattern="$include_pattern -name \"*.$ext\""
            done
            
            if [ -n "$include_pattern" ]; then
                find_cmd="$find_cmd -and \\( $include_pattern \\)"
            fi
        fi
        
        # Add excluded directories if specified
        if [ -n "$excluded_dirs" ] && [ "$excluded_dirs" != "none" ]; then
            IFS=',' read -ra DIRS <<< "$excluded_dirs"
            for excluded_dir in "${DIRS[@]}"; do
                find_cmd="$find_cmd -not -path \"$excluded_dir/*\""
            done
        fi
        
        # Execute find command and store results
        file_list=$(eval "$find_cmd")
        
        echo "Found $(echo "$file_list" | wc -l) files to scan"
    fi
    
    # Process each file
    local processed_files=0
    local skipped_files=0
    
    for current_file in $file_list; do
        echo "Processing file: $current_file"
        processed_files=$((processed_files + 1))
        
        # Check if we can read the file
        if [ ! -r "$current_file" ]; then
            echo "  Warning: Cannot read file, skipping"
            skipped_files=$((skipped_files + 1))
            continue
        fi
        
        # Process the file
        scan_file_for_operators "$current_file" "$show_supported"
    done
    
    # Generate summary report
    echo ""
    echo "Firestore Operator Compatibility Summary:"
    echo "----------------------------------------------"
    echo "Processed $processed_files files, skipped $skipped_files files"
    
    # Count unique operator combinations
    local unique_operators=$(cut -d':' -f1 /tmp/mongodb_compat_locations.txt | sort | uniq | wc -l)
    
    if [ "$unique_operators" -eq 0 ]; then
        echo "No unsupported operators found."
    else
        echo "Found $unique_operators unsupported operators:"
        
        # Process each unique operator
        for operator in $(cut -d':' -f1 /tmp/mongodb_compat_locations.txt | sort | uniq); do
            echo ""
            
            # Special handling for array operators
            if [ "$operator" = "array_all_positional" ]; then
                echo "Operator: \$[]"
            elif [ "$operator" = "array_filtered_positional" ]; then
                echo "Operator: \$[<identifier>]"
            else
                echo "Operator: \$${operator}"
            fi
            
            # Count total occurrences
            local total_occurrences=$(grep "^${operator}:" /tmp/mongodb_compat_locations.txt | wc -l)
            
            echo "Total occurrences: $total_occurrences"
            echo "Locations:"
            
            # Display each location
            grep "^${operator}:" /tmp/mongodb_compat_locations.txt | while read -r line; do
                local file=$(echo "$line" | cut -d':' -f2)
                local line_num=$(echo "$line" | cut -d':' -f3)
                echo "  $file (line $line_num)"
            done
        done
    fi
}

# Function to scan a single file for MongoDB operators
function scan_file_for_operators {
    local file="$1"
    local show_supported="$2"
    
    # Create a temporary file to store $sort operators in aggregation pipeline context
    rm -f /tmp/mongodb_sort_stage_lines.txt
    touch /tmp/mongodb_sort_stage_lines.txt
    
    # Create a temporary file to store lines to exclude from unsupported operators
    rm -f /tmp/mongodb_excluded_lines.txt
    touch /tmp/mongodb_excluded_lines.txt
    
    # First, identify and exclude comment lines
    grep -n "^[[:space:]]*\/\/" "$file" 2>/dev/null | cut -d':' -f1 >> /tmp/mongodb_excluded_lines.txt
    
    # Special handling for $sort operator in aggregation pipeline
    # Check if $sort:stage is supported
    local sort_stage_support=$(grep "^\$sort:stage:" /tmp/mongodb_compat_clean.txt | cut -d':' -f2 | tr -d ' ')
    if [ "$sort_stage_support" = "Yes" ]; then
        # Look for $sort in aggregation pipeline context
        if grep -q "\$sort" "$file"; then
            # Get the line numbers of all lines containing $sort
            grep -n "\$sort" "$file" | while read -r match; do
                local line_num=$(echo "$match" | cut -d':' -f1)
                local line_content=$(echo "$match" | cut -d':' -f2-)
                
                # Skip comment lines
                if echo "$line_content" | grep -q "^[[:space:]]*//"; then
                    continue
                fi
                
                # Check if this is in an aggregation pipeline context
                # Look for aggregate or pipeline keywords in the surrounding context (10 lines before)
                local context_before=$(head -n "$line_num" "$file" | tail -n 10)
                if echo "$context_before" | grep -q -E "aggregate|pipeline"; then
                    # This is a $sort in aggregation context, which is supported
                    if [ "$show_supported" = "true" ]; then
                        echo "  Found supported operator: \$sort (in stage context)"
                        echo "      Line $line_num: $line_content"
                    fi
                    
                    # Store this line number to exclude it from unsupported operators
                    echo "$line_num" >> /tmp/mongodb_excluded_lines.txt
                fi
            done
        fi
    fi
    
    # Special handling for $push in accumulator context
    # Check if $push:accumulator is supported
    local push_accumulator_support=$(grep "^\$push:accumulator:" /tmp/mongodb_compat_clean.txt | cut -d':' -f2 | tr -d ' ')
    if [ "$push_accumulator_support" = "Yes" ]; then
        # Look for $push in accumulator context
        if grep -q "\$push" "$file"; then
            # Get the line numbers of all lines containing $push
            grep -n "\$push" "$file" | while read -r match; do
                local line_num=$(echo "$match" | cut -d':' -f1)
                local line_content=$(echo "$match" | cut -d':' -f2-)
                
                # Skip comment lines
                if echo "$line_content" | grep -q "^[[:space:]]*//"; then
                    continue
                fi
                
                # Check the context of this $push operator
                local context_before=$(head -n "$line_num" "$file" | tail -n 10)
                
                # First check if this is in an update context (which should be flagged as unsupported)
                if echo "$context_before" | grep -q -E "update\(|updateOne\(|updateMany\(|findAndModify"; then
                    # This is $push in update context, which is unsupported
                    # Do not add to excluded lines, so it will be flagged as unsupported
                    continue
                # Check if this is in an accumulator context (which is supported)
                elif echo "$context_before" | grep -q -E "\$group|accumulator"; then
                    # This is a $push in accumulator context, which is supported
                    if [ "$show_supported" = "true" ]; then
                        echo "  Found supported operator: \$push (in accumulator context)"
                        echo "      Line $line_num: $line_content"
                    fi
                    
                    # Store this line number to exclude it from unsupported operators
                    echo "$line_num" >> /tmp/mongodb_excluded_lines.txt
                fi
            done
        fi
    fi
    
    # Special handling for $slice in projection context
    # Check if $slice:projection is supported
    local slice_projection_support=$(grep "^\$slice:projection:" /tmp/mongodb_compat_clean.txt | cut -d':' -f2 | tr -d ' ')
    if [ "$slice_projection_support" = "Yes" ]; then
        # Look for $slice in projection context
        if grep -q "\$slice" "$file"; then
            # Get the line numbers of all lines containing $slice
            grep -n "\$slice" "$file" | while read -r match; do
                local line_num=$(echo "$match" | cut -d':' -f1)
                local line_content=$(echo "$match" | cut -d':' -f2-)
                
                # Skip comment lines
                if echo "$line_content" | grep -q "^[[:space:]]*//"; then
                    continue
                fi
                
                # Check if this is in a projection context
                # Look for find, project, or projection keywords in the surrounding context (10 lines before)
                local context_before=$(head -n "$line_num" "$file" | tail -n 10)
                
                # First check if this is in an update context (which takes precedence)
                if echo "$context_before" | grep -q -E "update\(|updateOne\(|updateMany\(|findAndModify"; then
                    # This is likely in an update context, not a projection context
                    continue
                # Check if this is inside a $push operator (nested context)
                elif echo "$line_content" | grep -q -E "\$push.*\$slice|\{\s*\$each.*\$slice"; then
                    # This is $slice inside $push, which is in update context
                    continue
                # Now check for projection context
                elif echo "$context_before" | grep -q -E "find\(|project|projection|\$project"; then
                    # This is a $slice in projection context, which is supported
                    if [ "$show_supported" = "true" ]; then
                        echo "  Found supported operator: \$slice (in projection context)"
                        echo "      Line $line_num: $line_content"
                    fi
                    
                    # Store this line number to exclude it from unsupported operators
                    echo "$line_num" >> /tmp/mongodb_excluded_lines.txt
                fi
            done
        fi
    fi
    
    # Special handling for $[] operator (all positional operator)
    # Check if $[] is supported
    local array_all_positional_support=$(grep "^\$\[\]:" /tmp/mongodb_compat_clean.txt | cut -d':' -f2 | tr -d ' ')
    if [ "$array_all_positional_support" = "No" ]; then
        # Look for $[] pattern in the file using standard grep with escaped characters
        if grep -q '\$\[\]' "$file" 2>/dev/null; then
            echo "  Found unsupported operator: \$[]"
            echo "    Line numbers:"
            
            # Use standard grep to find lines with $[] pattern
            grep -n '\$\[\]' "$file" 2>/dev/null | while read -r match; do
                local line_num=$(echo "$match" | cut -d':' -f1)
                local line_content=$(echo "$match" | cut -d':' -f2-)
                
                # Skip comment lines
                if echo "$line_content" | grep -q "^[[:space:]]*//"; then
                    continue
                fi
                
                echo "      Line $line_num: $line_content"
                # Store for summary report
                echo "array_all_positional:$file:$line_num" >> /tmp/mongodb_compat_locations.txt
            done
        fi
    fi
    
    # Special handling for $[<identifier>] operator (filtered positional operator)
    # Check if $[<identifier>] is supported
    local array_filtered_positional_support=$(grep "^\$\[<identifier>\]:" /tmp/mongodb_compat_clean.txt 2>/dev/null | cut -d':' -f2 | tr -d ' ')
    if [ "$array_filtered_positional_support" = "No" ]; then
        # Look for $[element] pattern in the file using standard grep
        # We'll use a simpler pattern first to find potential matches
        if grep -q '\$\[' "$file" 2>/dev/null; then
            # Then filter out the $[] matches to only get $[identifier] matches
            if grep -v '\$\[\]' "$file" 2>/dev/null | grep -q '\$\[' 2>/dev/null; then
                echo "  Found unsupported operator: \$[<identifier>]"
                echo "    Line numbers:"
                
                # Get all lines with $[ but not $[]
                grep -n '\$\[' "$file" 2>/dev/null | grep -v '\$\[\]' 2>/dev/null | while read -r match; do
                    local line_num=$(echo "$match" | cut -d':' -f1)
                    local line_content=$(echo "$match" | cut -d':' -f2-)
                    
                    # Skip comment lines
                    if echo "$line_content" | grep -q "^[[:space:]]*//"; then
                        continue
                    fi
                    
                    echo "      Line $line_num: $line_content"
                    # Store for summary report
                    echo "array_filtered_positional:$file:$line_num" >> /tmp/mongodb_compat_locations.txt
                done
            fi
        fi
    fi
    
    # Get all MongoDB operators
    cat /tmp/mongodb_compat_clean.txt | while read -r line; do
        # Extract full operator (including any context tag)
        local full_operator=$(echo "$line" | cut -d':' -f1)
        
        # Check if this is an operator with context tag
        local has_context=false
        local context=""
        local base_operator=""
        if [[ "$full_operator" == *":"* ]]; then
            has_context=true
            context=$(echo "$full_operator" | cut -d':' -f2)
            # Extract base operator without context
            base_operator=$(echo "$full_operator" | cut -d':' -f1)
        else
            # No context tag
            base_operator="$full_operator"
        fi
        
        # Skip $sort:stage as we've already handled it specially
        if [ "$base_operator" = "\$sort" ] && [ "$context" = "stage" ]; then
            continue
        fi
        
        # Extract support status
        local support=$(echo "$line" | cut -d':' -f2 | tr -d ' ')
        
        # Skip if support status couldn't be determined
        if [ -z "$support" ]; then
            continue
        fi
        
        # Use the base operator for searching in files
        local operator="$base_operator"
        
        # Remove the $ from the operator for grep
        local operator_name=${operator#$}
        
        # Special handling for the bare $ operator
        local search_pattern="\$${operator_name}"
        if [ -z "$operator_name" ]; then
            # For the bare $ operator, use a pattern that looks for the positional operator
            # This pattern looks for field references ending with $, which is how the positional operator is typically used
            search_pattern=\"[^\"]*\.\\\$[^\"]*\"
        fi
        
        # Check if operator is unsupported
        if [ "$support" = "No" ]; then
            # Search for this operator in the file
            if grep -q "$search_pattern" "$file"; then
                # Create a temporary file to store matching lines for this operator
                rm -f /tmp/mongodb_operator_matches.txt
                touch /tmp/mongodb_operator_matches.txt
                
                # Get line numbers with grep
                grep -n "\$${operator_name}" "$file" | while read -r match; do
                    # Extract line number and content
                    local line_num=$(echo "$match" | cut -d':' -f1)
                    local line_content=$(echo "$match" | cut -d':' -f2-)
                    
                    # Skip comment lines (lines starting with //)
                    if echo "$line_content" | grep -q "^[[:space:]]*//"; then
                        continue
                    fi
                    
                    # Special handling for the bare $ operator
                    if [ -z "$operator_name" ]; then
                        # For the bare $ operator, directly check for the positional operator pattern
                        # and skip all context verification
                        if echo "$line_content" | grep -q -E "\"[^\"]*\.\\\$[^\"]*\""; then
                            # Store for temporary display
                            echo "      Line $line_num: $line_content" >> /tmp/mongodb_operator_matches.txt
                            # Store for summary report
                            echo "${operator_name}:$file:$line_num" >> /tmp/mongodb_compat_locations.txt
                        fi
                    else
                        # For all other operators, verify it's a real operator match (not part of another word)
                        local verification_pattern="[^a-zA-Z0-9_]\\\$${operator_name}[^a-zA-Z0-9_]|^\\\$${operator_name}[^a-zA-Z0-9_]|[^a-zA-Z0-9_]\\\$${operator_name}$"
                        local context_match=true
                        
                        # Check if this line is in our excluded list
                        if grep -q "^$line_num$" /tmp/mongodb_excluded_lines.txt; then
                            # This line is excluded (either a comment or a supported operator in context)
                            context_match=false
                        fi
                        
                        if echo "$line_content" | grep -q -E "$verification_pattern" && [ "$context_match" = "true" ]; then
                        # For operators with context, check if they're used in the right context
                        if [ "$has_context" = "true" ]; then
                            # Special handling for $sort operator
                            if [ "$operator_name" = "sort" ]; then
                                # Check if this is in an aggregation pipeline context
                                if echo "$line_content" | grep -q -E "aggregate|pipeline|\$match|\$group|\$project|\$limit"; then
                                    # This is a $sort in aggregation context, should match $sort:stage
                                    if [ "$context" != "stage" ]; then
                                        context_match=false
                                    fi
                                # Check if this is in an update context
                                elif echo "$line_content" | grep -q -E "update|findAndModify|\$push"; then
                                    # This is a $sort in update context, should match $sort:update
                                    if [ "$context" != "update" ]; then
                                        context_match=false
                                    fi
                                else
                                    # If we can't determine the context, default to not matching
                                    context_match=false
                                fi
                            # Handle other context-specific operators
                            elif [ "$context" = "update" ]; then
                                # Check if this is in an update context
                                # Look for update patterns like updateOne, updateMany, update, etc.
                                if ! echo "$line_content" | grep -q -E "update|findAndModify|\$set|\$push|\$pull|\$addToSet"; then
                                    context_match=false
                                fi
                            elif [ "$context" = "projection" ]; then
                                # Check if this is in a projection context
                                # Look for find or aggregate with projection
                                if ! echo "$line_content" | grep -q -E "find\s*\(.*\{\s*\$${operator_name}|project"; then
                                    context_match=false
                                fi
                            elif [ "$context" = "stage" ]; then
                                # Check if this is in a stage context
                                # Look for aggregation pipeline
                                if ! echo "$line_content" | grep -q -E "aggregate|pipeline|\$match|\$group|\$project"; then
                                    context_match=false
                                fi
                            elif [ "$context" = "accumulator" ]; then
                                # Check if this is in an accumulator context
                                # Look for aggregation with $group
                                if ! echo "$line_content" | grep -q -E "\$group|\$project|aggregate"; then
                                    context_match=false
                                fi
                            fi
                        fi
                            
                            # Only report if context matches or no context specified
                            if [ "$context_match" = "true" ]; then
                                # Store for temporary display
                                echo "      Line $line_num: $line_content" >> /tmp/mongodb_operator_matches.txt
                                
                                # Store for summary report
                                echo "${operator_name}:$file:$line_num" >> /tmp/mongodb_compat_locations.txt
                            fi
                        fi
                    fi
                done
                
                # Check if we found any actual occurrences
                if [ -s /tmp/mongodb_operator_matches.txt ]; then
                    # Display with context if available
                    if [ "$has_context" = "true" ]; then
                        echo "  Found unsupported operator: \$${operator_name} (in ${context} context)"
                    else
                        echo "  Found unsupported operator: \$${operator_name}"
                    fi
                    
                    echo "    Line numbers:"
                    cat /tmp/mongodb_operator_matches.txt
                fi
            fi
        elif [ "$show_supported" = "true" ]; then
            # Check for supported operators if requested
            if grep -q "\$${operator_name}" "$file"; then
                echo "  Found supported operator: \$${operator_name}"
            fi
        fi
    done
}

# Function to generate CSV report
function csv_mode {
    local output_file="firestore_operator_compatibility.csv"
    
    echo "Generating CSV report: $output_file"
    
    # Create CSV header
    echo "Operator,Firestore Support" > "$output_file"
    
    # Process each operator line directly
    while IFS= read -r line; do
        # Skip empty lines
        if [ -z "$line" ]; then
            continue
        fi
        
        # Extract operator (everything before the first colon)
        local operator="${line%%:*}"
        
        # Extract support status
        local status=$(echo "$line" | cut -d':' -f2 | tr -d ' ')
        
        if [ -n "$status" ]; then
            echo "$operator,$status" >> "$output_file"
        fi
    done < /tmp/mongodb_compat_clean.txt
    
    echo "CSV report generated successfully."
}

# Parse command line arguments
MODE="scan"
DIRECTORY=""
FILE=""
EXCLUDED_EXTENSIONS="none"
INCLUDED_EXTENSIONS="all"
EXCLUDED_DIRECTORIES="none"
SHOW_SUPPORTED="false"

# Process arguments
for arg in "$@"; do
    case $arg in
        --mode=*)
            MODE="${arg#*=}"
            # Convert to lowercase without using ${var,,}
            MODE=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')
            ;;
        --directory=*|--dir=*)
            DIRECTORY="${arg#*=}"
            ;;
        --file=*)
            FILE="${arg#*=}"
            ;;
        --excluded-extensions=*)
            EXCLUDED_EXTENSIONS="${arg#*=}"
            ;;
        --included-extensions=*)
            INCLUDED_EXTENSIONS="${arg#*=}"
            ;;
        --excluded-directories=*)
            EXCLUDED_DIRECTORIES="${arg#*=}"
            ;;
        --show-supported)
            SHOW_SUPPORTED="true"
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            show_usage
            exit 1
            ;;
    esac
done

# Validate mode
case $MODE in
    scan)
        if [ -z "$DIRECTORY" ] && [ -z "$FILE" ]; then
            echo "Error: For scan mode, either --dir/--directory or --file is required"
            show_usage
            exit 1
        fi
        
        if [ -n "$DIRECTORY" ] && [ -n "$FILE" ]; then
            echo "Error: Cannot specify both --dir/--directory and --file"
            show_usage
            exit 1
        fi
        
        scan_mode "$DIRECTORY" "$FILE" "$EXCLUDED_EXTENSIONS" "$INCLUDED_EXTENSIONS" "$EXCLUDED_DIRECTORIES" "$SHOW_SUPPORTED"
        ;;
    csv)
        csv_mode
        ;;
    *)
        echo "Error: Invalid mode: $MODE"
        echo "Supported modes: scan, csv"
        show_usage
        exit 1
        ;;
esac

# Clean up temporary files
rm -f /tmp/mongodb_compat_data.txt
rm -f /tmp/mongodb_compat_clean.txt
rm -f /tmp/mongodb_compat_locations.txt

exit 0
