#!/bin/bash

# MongoDB Compatibility Tool
# This script checks MongoDB code/logs for operators that may not be supported in Firestore

# Redirect stderr to /dev/null to suppress grep error messages
exec 2>/dev/null

# Define MongoDB versions we support
MONGODB_VERSIONS="3.6 4.0 5.0 6.0 7.0 8.0"

# Use the external compatibility data file
cp mongodb_compat_data.txt /tmp/mongodb_compat_data.txt

# Remove comments from the data file
grep -v "^#" /tmp/mongodb_compat_data.txt > /tmp/mongodb_compat_clean.txt

# Function to display usage information
function show_usage {
    echo "Usage: firestore_operator_checker.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --mongodb-version=VERSION  MongoDB version to check compatibility for (3.6, 4.0, 5.0, 6.0, 7.0, 8.0, all)"
    echo "  --mode=SCAN|CSV|STATS      Operation mode (default: SCAN)"
    echo "  --dir=DIR                  Directory to scan (alias for --directory)"
    echo "  --directory=DIR            Directory to scan"
    echo "  --file=FILE                Specific file to scan"
    echo "  --excluded-extensions=EXT  Comma-separated list of extensions to exclude (default: none)"
    echo "  --included-extensions=EXT a Comma-separated list of extensions to include (default: all)"
    echo "  --excluded-directories=DIR Comma-separated list of directories to exclude (default: none)"
    echo "  --show-supported           Show supported operators in report"
    echo "  --help                     Display this help message"
    echo ""
    echo "Examples:"
    echo "  ./firestore_operator_checker.sh --mongodb-version=6.0 --mode=scan --dir=./src"
    echo "  ./firestore_operator_checker.sh --mongodb-version=all --mode=csv"
    echo "  ./firestore_operator_checker.sh --mongodb-version=5.0 --mode=stats"
}

# Function to check if an operator is supported in a specific MongoDB version
function is_supported {
    local operator="$1"
    local version="$2"
    
    # Get the operator line from the data file
    local operator_line=$(grep "^\\$operator:" /tmp/mongodb_compat_clean.txt)
    
    # If operator not found, assume not supported
    if [ -z "$operator_line" ]; then
        echo "No"
        return
    fi
    
    # Extract the version-specific support status
    local version_status=$(echo "$operator_line" | grep -o "$version:[^,]*" | cut -d':' -f2)
    
    # If version status not found, assume not supported
    if [ -z "$version_status" ]; then
        echo "No"
    else
        echo "$version_status"
    fi
}

# Function to scan files for MongoDB operators
function scan_mode {
    local dir="$1"
    local file="$2"
    local mongodb_version="$3"
    local excluded_exts="$4"
    local included_exts="$5"
    local excluded_dirs="$6"
    local show_supported="$7"
    
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
        
        # Process the file based on MongoDB version
        if [ "$mongodb_version" = "all" ]; then
            # Check against all versions
            for version in $MONGODB_VERSIONS; do
                scan_file_for_version "$current_file" "$version" "$show_supported"
            done
        else
            # Check against specific version
            scan_file_for_version "$current_file" "$mongodb_version" "$show_supported"
        fi
    done
    
    # Generate summary report
    echo ""
    echo "Firestore Supported MongoDB Operators Summary:"
    echo "----------------------------------------------"
    echo "Processed $processed_files files, skipped $skipped_files files"
    
    if [ "$mongodb_version" = "all" ]; then
        echo "Checked compatibility with all MongoDB versions: $MONGODB_VERSIONS"
    else
        echo "Checked compatibility with MongoDB $mongodb_version"
    fi
    
    # Count unique operator:version combinations
    local unique_operators=$(cut -d':' -f1,2 /tmp/mongodb_compat_locations.txt | sort | uniq | wc -l)
    
    if [ "$unique_operators" -eq 0 ]; then
        echo "No unsupported operators found."
    else
        echo "Found $unique_operators unsupported operators:"
        
        # Process each unique operator:version combination
        for op_ver in $(cut -d':' -f1,2 /tmp/mongodb_compat_locations.txt | sort | uniq); do
            echo ""
            # Extract operator and version
            local operator=$(echo "$op_ver" | cut -d':' -f1)
            local version=$(echo "$op_ver" | cut -d':' -f2)
            
            # Special handling for array operators
            if [ "$operator" = "array_all_positional" ]; then
                echo "Operator: \$[] (MongoDB $version)"
            elif [ "$operator" = "array_filtered_positional" ]; then
                echo "Operator: \$[<identifier>] (MongoDB $version)"
            else
                echo "Operator: \$${operator} (MongoDB $version)"
            fi
            
            # Count total occurrences
            local total_occurrences=$(grep "^${operator}:${version}:" /tmp/mongodb_compat_locations.txt | wc -l)
            
            echo "Total occurrences: $total_occurrences"
            echo "Locations:"
            
            # Display each location
            grep "^${operator}:${version}:" /tmp/mongodb_compat_locations.txt | while read -r line; do
                local file=$(echo "$line" | cut -d':' -f3)
                local line_num=$(echo "$line" | cut -d':' -f4)
                echo "  $file (line $line_num)"
            done
        done
    fi
}

# Function to scan a single file for a specific MongoDB version
function scan_file_for_version {
    local file="$1"
    local version="$2"
    local show_supported="$3"
    
    # Create a temporary file to store $sort operators in aggregation pipeline context
    rm -f /tmp/mongodb_sort_stage_lines.txt
    touch /tmp/mongodb_sort_stage_lines.txt
    
    # Create a temporary file to store lines to exclude from unsupported operators
    rm -f /tmp/mongodb_excluded_lines.txt
    touch /tmp/mongodb_excluded_lines.txt
    
    # First, identify and exclude comment lines
    grep -n "^[[:space:]]*\/\/" "$file" 2>/dev/null | cut -d':' -f1 >> /tmp/mongodb_excluded_lines.txt
    
    # Special handling for $sort operator in aggregation pipeline
    # First check if $sort:stage is supported in this version
    local sort_stage_support=$(grep "^\$sort:stage:" /tmp/mongodb_compat_clean.txt | grep -o "$version:[^,]*" | cut -d':' -f2)
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
                        echo "  Found supported operator: \$sort (in stage context) (MongoDB $version)"
                        echo "      Line $line_num: $line_content"
                    fi
                    
                    # Store this line number to exclude it from unsupported operators
                    echo "$line_num" >> /tmp/mongodb_excluded_lines.txt
                fi
            done
        fi
    fi
    
    # Special handling for $push in accumulator context
    # First check if $push:accumulator is supported in this version
    local push_accumulator_support=$(grep "^\$push:accumulator:" /tmp/mongodb_compat_clean.txt | grep -o "$version:[^,]*" | cut -d':' -f2)
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
                        echo "  Found supported operator: \$push (in accumulator context) (MongoDB $version)"
                        echo "      Line $line_num: $line_content"
                    fi
                    
                    # Store this line number to exclude it from unsupported operators
                    echo "$line_num" >> /tmp/mongodb_excluded_lines.txt
                fi
            done
        fi
    fi
    
    # Special handling for $slice in projection context
    # First check if $slice:projection is supported in this version
    local slice_projection_support=$(grep "^\$slice:projection:" /tmp/mongodb_compat_clean.txt | grep -o "$version:[^,]*" | cut -d':' -f2)
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
                        echo "  Found supported operator: \$slice (in projection context) (MongoDB $version)"
                        echo "      Line $line_num: $line_content"
                    fi
                    
                    # Store this line number to exclude it from unsupported operators
                    echo "$line_num" >> /tmp/mongodb_excluded_lines.txt
                fi
            done
        fi
    fi
    
    # Special handling for $[] operator (all positional operator)
    # Check if $[] is supported in this version
    local array_all_positional_support=$(grep "^\$\[\]:" /tmp/mongodb_compat_clean.txt | grep -o "$version:[^,]*" | cut -d':' -f2)
    if [ "$array_all_positional_support" = "No" ]; then
        # Look for $[] pattern in the file using standard grep with escaped characters
        if grep -q '\$\[\]' "$file" 2>/dev/null; then
            echo "  Found unsupported operator: \$[] (MongoDB $version)"
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
                echo "array_all_positional:$version:$file:$line_num" >> /tmp/mongodb_compat_locations.txt
            done
        fi
    fi
    
    # Special handling for $[<identifier>] operator (filtered positional operator)
    # Check if $[<identifier>] is supported in this version
    local array_filtered_positional_support=$(grep "^\$\[<identifier>\]:" /tmp/mongodb_compat_clean.txt 2>/dev/null | grep -o "$version:[^,]*" 2>/dev/null | cut -d':' -f2)
    if [ "$array_filtered_positional_support" = "No" ]; then
        # Look for $[element] pattern in the file using standard grep
        # We'll use a simpler pattern first to find potential matches
        if grep -q '\$\[' "$file" 2>/dev/null; then
            # Then filter out the $[] matches to only get $[identifier] matches
            if grep -v '\$\[\]' "$file" 2>/dev/null | grep -q '\$\[' 2>/dev/null; then
                echo "  Found unsupported operator: \$[<identifier>] (MongoDB $version)"
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
                    echo "array_filtered_positional:$version:$file:$line_num" >> /tmp/mongodb_compat_locations.txt
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
        
        # Extract support status for this version
        local version_pattern="$version:[^,]*"
        if ! echo "$line" | grep -q "$version_pattern"; then
            # Skip if this version is not listed for this operator
            continue
        fi
        
        local support=$(echo "$line" | grep -o "$version_pattern" | cut -d':' -f2)
        
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
            # search_pattern="\"[^\"]*\.\\\$\""
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
                            echo "${operator_name}:${version}:${file}:${line_num}" >> /tmp/mongodb_compat_locations.txt
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
                                echo "${operator_name}:${version}:${file}:${line_num}" >> /tmp/mongodb_compat_locations.txt
                            fi
                        fi
                    fi
                done
                
                # Check if we found any actual occurrences
                if [ -s /tmp/mongodb_operator_matches.txt ]; then
                    # Display with context if available
                    if [ "$has_context" = "true" ]; then
                        echo "  Found unsupported operator: \$${operator_name} (in ${context} context) (MongoDB $version)"
                    else
                        echo "  Found unsupported operator: \$${operator_name} (MongoDB $version)"
                    fi
                    
                    echo "    Line numbers:"
                    cat /tmp/mongodb_operator_matches.txt
                fi
            fi
        elif [ "$show_supported" = "true" ]; then
            # Check for supported operators if requested
            if grep -q "\$${operator_name}" "$file"; then
                echo "  Found supported operator: \$${operator_name} (MongoDB $version)"
            fi
        fi
    done
}

# Function to generate CSV report
function csv_mode {
    local mongodb_version="$1"
    local output_file="mongodb_firestore_compatibility.csv"
    
    echo "Generating CSV report: $output_file"
    
    # Create CSV header
    if [ "$mongodb_version" = "all" ]; then
        # Header for all versions
        echo -n "Operator,MongoDB Version" > "$output_file"
        for version in $MONGODB_VERSIONS; do
            echo -n ",$version" >> "$output_file"
        done
        echo "" >> "$output_file"
        
        # Process each operator line directly
        while IFS= read -r line; do
            # Skip empty lines
            if [ -z "$line" ]; then
                continue
            fi
            
            # Extract operator (everything before the first colon)
            local operator="${line%%:*}"
            
            # Find MongoDB version where this operator first appeared
            local first_version=""
            for version in $MONGODB_VERSIONS; do
                if echo "$line" | grep -q "$version:"; then
                    first_version="$version"
                    break
                fi
            done
            
            # Write operator and its MongoDB version
            echo -n "$operator,$first_version" >> "$output_file"
            
            # Add compatibility for each MongoDB version
            for version in $MONGODB_VERSIONS; do
                # Extract the version-specific support status using sed
                local status=$(echo "$line" | sed -n "s/.*$version:\([^,]*\).*/\1/p")
                
                if [ -n "$status" ]; then
                    echo -n ",$status" >> "$output_file"
                else
                    echo -n ",N/A" >> "$output_file"
                fi
            done
            
            echo "" >> "$output_file"
        done < /tmp/mongodb_compat_clean.txt
    else
        # CSV for specific version
        echo "Operator,MongoDB Version,Firestore Support" > "$output_file"
        
        # Process each operator line directly
        while IFS= read -r line; do
            # Skip empty lines
            if [ -z "$line" ]; then
                continue
            fi
            
            # Extract operator (everything before the first colon)
            local operator="${line%%:*}"
            
            # Extract support status for this version using sed
            local status=$(echo "$line" | sed -n "s/.*$mongodb_version:\([^,]*\).*/\1/p")
            
            if [ -n "$status" ]; then
                echo "$operator,$mongodb_version,$status" >> "$output_file"
            fi
        done < /tmp/mongodb_compat_clean.txt
    fi
    
    echo "CSV report generated successfully."
}

# Function to show statistics
function stats_mode {
    local mongodb_version="$1"
    
    echo "MongoDB Compatibility Statistics"
    echo "================================"
    
    if [ "$mongodb_version" = "all" ]; then
        # Generate stats for all versions
        for version in $MONGODB_VERSIONS; do
            generate_version_stats "$version"
        done
        
        # Generate comparison stats across versions
        generate_comparison_stats
    else
        # Generate stats for specific version
        generate_version_stats "$mongodb_version"
    fi
}

# Function to generate statistics for a specific MongoDB version
function generate_version_stats {
    local version="$1"
    local total_operators=0
    local supported_operators=0
    local unsupported_operators=0
    local unsupported_list=""
    
    # Count operators for this version
    while read -r line; do
        # Check if this line contains the version
        if echo "$line" | grep -q "$version:"; then
            total_operators=$((total_operators + 1))
            
            # Check support status
            if echo "$line" | grep -q "$version:Yes"; then
                supported_operators=$((supported_operators + 1))
            else
                unsupported_operators=$((unsupported_operators + 1))
                # Extract operator name for the unsupported list
                local operator=$(echo "$line" | cut -d':' -f1)
                unsupported_list="${unsupported_list}${operator}\n"
            fi
        fi
    done < /tmp/mongodb_compat_clean.txt
    
    echo ""
    echo "MongoDB $version Compatibility:"
    echo "-----------------------------"
    
    # Calculate percentages
    local support_percentage=0
    if [ $total_operators -gt 0 ]; then
        support_percentage=$(( (supported_operators * 100) / total_operators ))
    fi
    
    # Display statistics
    echo "Total operators: $total_operators"
    echo "Supported operators: $supported_operators ($support_percentage%)"
    echo "Unsupported operators: $unsupported_operators ($((100 - support_percentage))%)"
    
    # List unsupported operators
    echo ""
    echo "Unsupported operators in MongoDB $version:"
    echo -e "$unsupported_list" | sort | uniq | while read -r operator; do
        if [ -n "$operator" ]; then
            echo "  $operator"
        fi
    done
}

# Function to generate comparison statistics across versions
function generate_comparison_stats {
    echo ""
    echo "Cross-Version Compatibility Comparison:"
    echo "-------------------------------------"
    
    # Get all unique operators
    local operators=$(cut -d':' -f1 /tmp/mongodb_compat_clean.txt | sort | uniq)
    
    # Display compatibility matrix for operators
    echo "Operator compatibility across versions:"
    printf "%-20s" "Operator"
    for version in $MONGODB_VERSIONS; do
        printf "%-10s" "$version"
    done
    echo ""
    
    # Print separator line
    printf "%-20s" "--------------------"
    for version in $MONGODB_VERSIONS; do
        printf "%-10s" "----------"
    done
    echo ""
    
    # Print each operator's compatibility
    for operator in $operators; do
        printf "%-20s" "$operator"
        
        # Get the operator line
        local operator_line=$(grep "^${operator}:" /tmp/mongodb_compat_clean.txt)
        
        for version in $MONGODB_VERSIONS; do
            # Extract the version-specific support status
            local version_pattern="$version:[^,]*"
            if echo "$operator_line" | grep -q "$version_pattern"; then
                local status=$(echo "$operator_line" | grep -o "$version_pattern" | cut -d':' -f2)
                printf "%-10s" "$status"
            else
                # Operator doesn't exist in this version
                printf "%-10s" "N/A"
            fi
        done
        echo ""
    done
    
    # Identify operators that changed compatibility across versions
    echo ""
    echo "Compatibility changes across versions:"
    
    for operator in $operators; do
        # Get the operator line
        local operator_line=$(grep "^${operator}:" /tmp/mongodb_compat_clean.txt)
        local previous_status=""
        local has_change=false
        
        for version in $MONGODB_VERSIONS; do
            # Extract the version-specific support status
            local version_pattern="$version:[^,]*"
            if echo "$operator_line" | grep -q "$version_pattern"; then
                local status=$(echo "$operator_line" | grep -o "$version_pattern" | cut -d':' -f2)
                
                if [ -n "$previous_status" ] && [ -n "$status" ] && [ "$status" != "$previous_status" ]; then
                    has_change=true
                    break
                fi
                
                if [ -n "$status" ]; then
                    previous_status="$status"
                fi
            fi
        done
        
        if [ "$has_change" = "true" ]; then
            echo "  $operator: Changed compatibility across versions"
            
            for version in $MONGODB_VERSIONS; do
                # Extract the version-specific support status
                local version_pattern="$version:[^,]*"
                if echo "$operator_line" | grep -q "$version_pattern"; then
                    local status=$(echo "$operator_line" | grep -o "$version_pattern" | cut -d':' -f2)
                    echo "    MongoDB $version: $status"
                fi
            done
        fi
    done
}

# Parse command line arguments
MONGODB_VERSION=""
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
        --mongodb-version=*)
            MONGODB_VERSION="${arg#*=}"
            ;;
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

# Validate MongoDB version
if [ -z "$MONGODB_VERSION" ]; then
    echo "Error: MongoDB version is required (--mongodb-version)"
    show_usage
    exit 1
fi

if [ "$MONGODB_VERSION" != "all" ]; then
    version_valid=false
    for version in $MONGODB_VERSIONS; do
        if [ "$MONGODB_VERSION" = "$version" ]; then
            version_valid=true
            break
        fi
    done
    
    if [ "$version_valid" = "false" ]; then
        echo "Error: Invalid MongoDB version: $MONGODB_VERSION"
        echo "Supported versions: $MONGODB_VERSIONS or 'all'"
        exit 1
    fi
fi

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
        
        scan_mode "$DIRECTORY" "$FILE" "$MONGODB_VERSION" "$EXCLUDED_EXTENSIONS" "$INCLUDED_EXTENSIONS" "$EXCLUDED_DIRECTORIES" "$SHOW_SUPPORTED"
        ;;
    csv)
        csv_mode "$MONGODB_VERSION"
        ;;
    stats)
        stats_mode "$MONGODB_VERSION"
        ;;
    *)
        echo "Error: Invalid mode: $MODE"
        echo "Supported modes: scan, csv, stats"
        show_usage
        exit 1
        ;;
esac

# Clean up temporary files
rm -f /tmp/mongodb_compat_data.txt
rm -f /tmp/mongodb_compat_clean.txt
rm -f /tmp/mongodb_compat_locations.txt

exit 0
