#!/bin/bash

# Simplified Firestore Operator Compatibility Checker
# This script checks MongoDB code/logs for operators that are not supported in Firestore

# Function to display usage information
function show_usage {
    echo "Usage: firestore_operator_checker_simplified.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --mode SCAN|CSV            Operation mode (default: SCAN)"
    echo "  --dir DIR                  Directory to scan"
    echo "  --file FILE                Specific file to scan"
    echo "  --excluded-extensions EXT  Comma-separated list of extensions to exclude (default: none)"
    echo "  --included-extensions EXT  Comma-separated list of extensions to include (default: all)"
    echo "  --excluded-directories DIR Comma-separated list of directories to exclude (default: none)"
    echo "  --show-supported           Show supported operators in report"
    echo "  --help                     Display this help message"
    echo ""
    echo "Examples:"
    echo "  ./firestore_operator_checker_simplified.sh --mode scan --dir ./src"
    echo "  ./firestore_operator_checker_simplified.sh --mode csv"
}

# Function to scan files for MongoDB operators
function scan_mode {
    local dir="$1"
    local file="$2"
    local excluded_exts="$3"
    local included_exts="$4"
    local excluded_dirs="$5"
    local show_supported="$6"
    
    # Create temporary files for results
    local unsupported_file="/tmp/unsupported_operators.txt"
    local supported_file="/tmp/supported_operators.txt"
    rm -f "$unsupported_file" "$supported_file"
    touch "$unsupported_file" "$supported_file"
    
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
        scan_file_for_operators "$current_file" "$show_supported" "$unsupported_file" "$supported_file"
    done
    
    # Generate summary report
    echo ""
    echo "Firestore Operator Compatibility Summary:"
    echo "----------------------------------------------"
    echo "Processed $processed_files files, skipped $skipped_files files"
    
    # Count unsupported operators
    local unsupported_count=0
    if [ -f "$unsupported_file" ] && [ -s "$unsupported_file" ]; then
        unsupported_count=$(cut -d':' -f1 "$unsupported_file" | sort | uniq | wc -l)
    fi
    
    if [ "$unsupported_count" -eq 0 ]; then
        echo "No unsupported operators found."
    else
        echo "Found $unsupported_count unsupported operators:"
        
        # Process each unique operator
        for operator in $(cut -d':' -f1 "$unsupported_file" | sort | uniq); do
            echo ""
            echo "Operator: $operator"
            
            # Count total occurrences
            local total_occurrences=$(grep "^${operator}:" "$unsupported_file" | wc -l)
            echo "Total occurrences: $total_occurrences"
            echo "Locations:"
            
            # Display each location
            grep "^${operator}:" "$unsupported_file" | while read -r line; do
                local file_path=$(echo "$line" | cut -d':' -f2)
                local line_num=$(echo "$line" | cut -d':' -f3)
                echo "  $file_path (line $line_num)"
            done
        done
    fi
    
    # Show supported operators if requested
    if [ "$show_supported" = "true" ] && [ -f "$supported_file" ] && [ -s "$supported_file" ]; then
        echo ""
        echo "Supported operators found:"
        for operator in $(cut -d':' -f1 "$supported_file" | sort | uniq); do
            local count=$(grep "^${operator}:" "$supported_file" | wc -l)
            echo "  $operator: $count occurrences"
        done
    fi
    
    # Clean up
    rm -f "$unsupported_file" "$supported_file"
}

# Function to scan a single file for MongoDB operators
function scan_file_for_operators {
    local file="$1"
    local show_supported="$2"
    local unsupported_file="$3"
    local supported_file="$4"
    
    # Read compatibility data and process each operator
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^#.* ]]; then
            continue
        fi
        
        # Parse operator and support status more robustly
        if [[ "$line" =~ ^(.+):[[:space:]]*(.+)$ ]]; then
            operator="${BASH_REMATCH[1]}"
            support="${BASH_REMATCH[2]}"
            
            # Clean up whitespace
            operator=$(echo "$operator" | sed 's/[[:space:]]*$//')
            support=$(echo "$support" | tr -d ' ')
        else
            continue
        fi
        
        # Skip if support status couldn't be determined
        if [ -z "$support" ]; then
            continue
        fi
        
        # Determine search pattern based on operator format
        local search_pattern=""
        local operator_display="$operator"
        local use_fixed_string=false
        
        if [[ "$operator" == \$\$* ]]; then
            # System variable: search for $$VARIABLE (use as literal string)
            search_pattern="$operator"
            use_fixed_string=true
        elif [[ "$operator" == \$* ]]; then
            # Standard operator: search for $operator (use as literal string to handle special chars)
            search_pattern="$operator"
            use_fixed_string=true
        else
            # Command/operation: search for command with word boundaries (regex)
            search_pattern="\\b$operator\\b"
            use_fixed_string=false
        fi
        
        # Search for the operator in the file using appropriate method
        local grep_results=""
        if [ "$use_fixed_string" = "true" ]; then
            # Use -F flag for literal string search (faster and handles special characters correctly)
            grep_results=$(grep -n -F "$search_pattern" "$file" 2>/dev/null)
        else
            # Use regex search for commands with word boundaries
            grep_results=$(grep -n -E "$search_pattern" "$file" 2>/dev/null)
        fi
        
        if [ -n "$grep_results" ]; then
            # Process line by line
            echo "$grep_results" | while read -r match; do
                local line_num=$(echo "$match" | cut -d':' -f1)
                local line_content=$(echo "$match" | cut -d':' -f2-)
                
                # Skip comment lines
                if echo "$line_content" | grep -q "^[[:space:]]*//"; then
                    continue
                fi
                
                # Basic pattern verification to avoid false positives
                local is_valid_match=true
                
                # For operators starting with $, ensure they're not part of variable names
                if [[ "$operator" == \$* ]] && [[ "$operator" != \$\$* ]]; then
                    # Check if the operator is followed by alphanumeric characters (indicating a variable name)
                    if echo "$line_content" | grep -q "${operator}[a-zA-Z0-9_]"; then
                        is_valid_match=false
                    fi
                fi
                
                if [ "$is_valid_match" = "true" ]; then
                    if [ "$support" = "No" ]; then
                        echo "  Found unsupported operator: $operator_display"
                        echo "    Line $line_num: $line_content"
                        echo "$operator:$file:$line_num" >> "$unsupported_file"
                    elif [ "$show_supported" = "true" ]; then
                        echo "  Found supported operator: $operator_display"
                        echo "    Line $line_num: $line_content"
                        echo "$operator:$file:$line_num" >> "$supported_file"
                    fi
                fi
            done
        fi
    done < /tmp/mongodb_compat_clean.txt
}

# Function to generate CSV report
function csv_mode {
    local output_file="firestore_operator_compatibility.csv"
    
    echo "Generating CSV report: $output_file"
    
    # Create CSV header
    echo "Operator,Firestore Support" > "$output_file"
    
    # Process each operator line directly
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^#.* ]]; then
            continue
        fi
        
        # Parse operator and support status more robustly
        if [[ "$line" =~ ^(.+):[[:space:]]*(.+)$ ]]; then
            operator="${BASH_REMATCH[1]}"
            support="${BASH_REMATCH[2]}"
            
            # Clean up whitespace
            operator=$(echo "$operator" | sed 's/[[:space:]]*$//')
            support=$(echo "$support" | tr -d ' ')
            
            if [ -n "$support" ]; then
                echo "$operator,$support" >> "$output_file"
            fi
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
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode=*)
            MODE="${1#*=}"
            MODE=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')
            shift
            ;;
        --mode)
            MODE="$2"
            MODE=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')
            shift 2
            ;;
        --directory=*|--dir=*)
            DIRECTORY="${1#*=}"
            shift
            ;;
        --directory|--dir)
            DIRECTORY="$2"
            shift 2
            ;;
        --file=*)
            FILE="${1#*=}"
            shift
            ;;
        --file)
            FILE="$2"
            shift 2
            ;;
        --excluded-extensions=*)
            EXCLUDED_EXTENSIONS="${1#*=}"
            shift
            ;;
        --excluded-extensions)
            EXCLUDED_EXTENSIONS="$2"
            shift 2
            ;;
        --included-extensions=*)
            INCLUDED_EXTENSIONS="${1#*=}"
            shift
            ;;
        --included-extensions)
            INCLUDED_EXTENSIONS="$2"
            shift 2
            ;;
        --excluded-directories=*)
            EXCLUDED_DIRECTORIES="${1#*=}"
            shift
            ;;
        --excluded-directories)
            EXCLUDED_DIRECTORIES="$2"
            shift 2
            ;;
        --show-supported)
            SHOW_SUPPORTED="true"
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Prepare compatibility data
if [ ! -f "mongodb_compat_data.txt" ]; then
    echo "Error: mongodb_compat_data.txt file not found"
    exit 1
fi

# Copy and clean compatibility data
cp mongodb_compat_data.txt /tmp/mongodb_compat_data.txt
grep -v "^#" /tmp/mongodb_compat_data.txt > /tmp/mongodb_compat_clean.txt

# Validate mode and execute
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

exit 0
