#!/bin/bash
# Firestore JSON Data Type Compatibility Checker
# This script scans JSON files to identify data types unsupported by Firestore

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: This script requires jq for JSON processing. Please install it first."
    echo "Installation instructions: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Default values
DIR=""
FILE=""
VERBOSE=false
TOTAL_FILES=0
ISSUE_FILES=0
TOTAL_ISSUES=0

# Define unsupported data types based on Firestore compatibility
TYPE_NAMES=(
    "DBPointer"
    "DBRef"
    "JavaScript"
    "JavaScript_with_scope"
    "Symbol"
    "Undefined"
)

TYPE_QUERIES=(
    'paths as $p | select(getpath($p) | type == "object" and has("$dbPointer")) | $p'
    'paths as $p | select(getpath($p) | type == "object" and has("$ref") and has("$id")) | $p'
    'paths as $p | select(getpath($p) | type == "object" and has("$code") and (has("$scope") | not)) | $p'
    'paths as $p | select(getpath($p) | type == "object" and has("$code") and has("$scope")) | $p'
    'paths as $p | select(getpath($p) | type == "object" and has("$symbol")) | $p'
    'paths as $p | select(getpath($p) | type == "object" and has("$undefined")) | $p'
)

# Function to get type name for display
get_type_display_name() {
    local index=$1
    case $index in
        0) echo "DBPointer" ;;
        1) echo "DBRef" ;;
        2) echo "JavaScript" ;;
        3) echo "JavaScript with scope" ;;
        4) echo "Symbol" ;;
        5) echo "Undefined" ;;
        *) echo "Unknown" ;;
    esac
}

# Function to print usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --dir DIR              Directory to scan recursively for JSON files"
    echo "  --file FILE            Single JSON file to check"
    echo "  --verbose              Show detailed information about each issue found"
    echo "  --help                 Display this help message"
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
        --verbose)
            VERBOSE=true
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

# Check required arguments
if [[ -z "$DIR" && -z "$FILE" ]]; then
    echo "Error: Either --dir or --file is required"
    usage
fi

if [[ -n "$DIR" && ! -d "$DIR" ]]; then
    echo "Error: $DIR is not a directory"
    exit 1
fi

if [[ -n "$FILE" && ! -f "$FILE" ]]; then
    echo "Error: $FILE is not a file"
    exit 1
fi

# Function to get approximate line number for a JSON path
get_line_number() {
    local file="$1"
    local path="$2"
    local occurrence="$3"  # Parameter to track which occurrence we're looking for
    local is_ndjson="$4"   # Parameter to indicate if this is an NDJSON file
    
    # For NDJSON files (multiple JSON objects, one per line), use the occurrence to determine which line
    if [[ "$is_ndjson" == "true" ]]; then
        # Return the line number based on occurrence (1-based index)
        echo "$occurrence"
        return
    fi
    
    # For standard JSON files, we need to find the actual line number
    
    # First, try to extract the specific field name from the path
    local last_element=$(echo "$path" | jq -r '.[-1]')
    local parent_element=""
    if [[ ${#path} -gt 2 ]]; then
        parent_element=$(echo "$path" | jq -r '.[-2]')
    fi
    
    # Try different search strategies to find the line number
    
    # Strategy 1: Search for the BSON type with its field name
    local bson_types=('"\$dbPointer"' '"\$ref"' '"\$id"' '"\$code"' '"\$scope"' '"\$symbol"' '"\$undefined"' '"\$geometry"')
    for type in "${bson_types[@]}"; do
        # If we have a field name, search for it near the BSON type
        if [[ -n "$last_element" && "$last_element" != "null" ]]; then
            if [[ "$last_element" =~ ^[0-9]+$ && -n "$parent_element" && "$parent_element" != "null" ]]; then
                # For array indices, use the parent element name
                local line_num=$(grep -n "\"$parent_element\".*$type" "$file" | sed -n "${occurrence}p" | cut -d: -f1)
                if [[ -n "$line_num" ]]; then
                    echo "$line_num"
                    return
                fi
            else
                # For regular fields, use the field name
                local line_num=$(grep -n "\"$last_element\".*$type" "$file" | sed -n "${occurrence}p" | cut -d: -f1)
                if [[ -n "$line_num" ]]; then
                    echo "$line_num"
                    return
                fi
            fi
        fi
    done
    
    # Strategy 2: Extract the value and search for it directly
    local value=$(jq -c "getpath($path)" "$file" 2>/dev/null)
    if [[ -n "$value" && "$value" != "null" ]]; then
        # For simple values, search directly
        if [[ ${#value} -lt 100 ]]; then  # Only for reasonably sized values
            # Escape special characters in the value for grep
            local escaped_value=$(echo "$value" | sed 's/[]\/$*.^[]/\\&/g')
            local line_num=$(grep -n "$escaped_value" "$file" | sed -n "${occurrence}p" | cut -d: -f1)
            if [[ -n "$line_num" ]]; then
                echo "$line_num"
                return
            fi
        fi
        
        # For BSON types, extract and search for the specific type markers
        if [[ "$value" == *"\$dbPointer"* ]]; then
            local line_num=$(grep -n '"\$dbPointer"' "$file" | sed -n "${occurrence}p" | cut -d: -f1)
            if [[ -n "$line_num" ]]; then
                echo "$line_num"
                return
            fi
        elif [[ "$value" == *"\$ref"* && "$value" == *"\$id"* ]]; then
            local line_num=$(grep -n '"\$ref"' "$file" | sed -n "${occurrence}p" | cut -d: -f1)
            if [[ -n "$line_num" ]]; then
                echo "$line_num"
                return
            fi
        elif [[ "$value" == *"\$code"* && "$value" == *"\$scope"* ]]; then
            local line_num=$(grep -n '"\$code"' "$file" | sed -n "${occurrence}p" | cut -d: -f1)
            if [[ -n "$line_num" ]]; then
                echo "$line_num"
                return
            fi
        elif [[ "$value" == *"\$symbol"* ]]; then
            local line_num=$(grep -n '"\$symbol"' "$file" | sed -n "${occurrence}p" | cut -d: -f1)
            if [[ -n "$line_num" ]]; then
                echo "$line_num"
                return
            fi
        elif [[ "$value" == *"\$undefined"* ]]; then
            local line_num=$(grep -n '"\$undefined"' "$file" | sed -n "${occurrence}p" | cut -d: -f1)
            if [[ -n "$line_num" ]]; then
                echo "$line_num"
                return
            fi
        fi
    fi
    
    # Strategy 3: Use jq to extract the path as a string and search for it
    local path_str=$(echo "$path" | jq -c '.')
    if [[ -n "$path_str" ]]; then
        # Convert path to a more readable form for debugging
        local readable_path=$(echo "$path" | jq -r 'map(tostring) | join(".")')
        
        # Try to find the field name in the file
        if [[ -n "$last_element" && "$last_element" != "null" ]]; then
            local line_num=$(grep -n "\"$last_element\"" "$file" | sed -n "${occurrence}p" | cut -d: -f1)
            if [[ -n "$line_num" ]]; then
                echo "$line_num"
                return
            fi
        fi
    fi
    
    # If we still can't find it, return a default
    echo "unknown"
}

# Function to check if a file contains multiple JSON objects
is_multi_json_file() {
    local file="$1"
    
    # First, check if it's a standard NDJSON file (one JSON object per line)
    if grep -q "^{" "$file" && grep -q "}$" "$file"; then
        # Count number of lines that start with { and end with }
        local json_lines=$(grep -c "^{.*}$" "$file")
        local total_lines=$(wc -l < "$file")
        
        # If most lines are complete JSON objects, treat as NDJSON
        if [[ $json_lines -gt 0 && $json_lines -eq $total_lines ]]; then
            echo "ndjson"
            return
        fi
    fi
    
    # Next, check if the file contains multiple complete JSON objects
    # by counting the number of top-level closing braces
    local closing_braces=$(grep -c "^}$" "$file")
    if [[ $closing_braces -gt 1 ]]; then
        echo "multi"
        return
    fi
    
    # If neither condition is met, it's a single JSON object
    echo "single"
}

# Function to check a single JSON file
check_file() {
    local file="$1"
    local issues_found=false
    local file_issues=0
    local issues_array=()
    
    # Determine the file format
    local file_format=$(is_multi_json_file "$file")
    
    # For NDJSON files (one JSON object per line), process each line separately
    if [[ "$file_format" == "ndjson" ]]; then
        TOTAL_FILES=$((TOTAL_FILES + 1))
        local line_number=1
        
        while IFS= read -r line; do
            # Skip empty lines
            if [[ -z "$line" ]]; then
                line_number=$((line_number + 1))
                continue
            fi
            
            # Check if line is valid JSON
            if ! echo "$line" | jq empty 2>/dev/null; then
                echo "Error: Line $line_number in $file is not valid JSON"
                line_number=$((line_number + 1))
                continue
            fi
            
            # Check for each unsupported type
            for i in "${!TYPE_NAMES[@]}"; do
                local type_name=$(get_type_display_name "$i")
                local query="${TYPE_QUERIES[$i]}"
                local paths=$(echo "$line" | jq -c "$query" 2>/dev/null)
                
                if [[ -n "$paths" ]]; then
                    issues_found=true
                    
                    while IFS= read -r path; do
                        if [[ -n "$path" ]]; then
                            # Store the issue in the array with line number as the key
                            issues_array+=("$line_number:$type_name")
                            
                            if [[ "$VERBOSE" == "true" ]]; then
                                local value=$(echo "$line" | jq -c "getpath($path)" 2>/dev/null)
                                issues_array+=("    Path: $path")
                                issues_array+=("    Value: $value")
                            fi
                            
                            file_issues=$((file_issues + 1))
                            TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
                        fi
                    done <<< "$paths"
                fi
            done
            
            line_number=$((line_number + 1))
        done < "$file"
    elif [[ "$file_format" == "multi" ]]; then
        # For files with multiple JSON objects (not one per line), process each object separately
        TOTAL_FILES=$((TOTAL_FILES + 1))
        
        # Use jq to split the file into individual JSON objects
        # First, count how many objects are in the file
        local object_count=$(grep -c "^}$" "$file")
        
        # Process each object separately
        for ((i=0; i<object_count; i++)); do
            # Extract the i-th object using jq
            local temp_file=$(mktemp)
            jq -s ".[$i]" "$file" > "$temp_file" 2>/dev/null
            
            # Check if the extracted object is valid JSON
            if ! jq empty "$temp_file" 2>/dev/null; then
                echo "Error: Object $((i+1)) in $file is not valid JSON"
                rm "$temp_file"
                continue
            fi
            
            # Calculate the line offset for this object
            local line_offset=0
            if [[ $i -gt 0 ]]; then
                # Find the position of the i-th closing brace
                line_offset=$(grep -n "^}$" "$file" | sed -n "$i"p | cut -d: -f1)
            fi
            
            # Check for each unsupported type
            for j in "${!TYPE_NAMES[@]}"; do
                local type_name=$(get_type_display_name "$j")
                local query="${TYPE_QUERIES[$j]}"
                local paths=$(jq -c "$query" "$temp_file" 2>/dev/null)
                
                if [[ -n "$paths" ]]; then
                    issues_found=true
                    
                    local occurrence=1
                    while IFS= read -r path; do
                        if [[ -n "$path" ]]; then
                            # Get the line number within this object
                            local obj_line_num=$(get_line_number "$temp_file" "$path" "$occurrence" "false")
                            
                            # For multi-object files, we need to be more careful about line numbers
                            # First, get the content of the line in the temp file
                            local line_content=""
                            if [[ "$obj_line_num" =~ ^[0-9]+$ ]]; then
                                line_content=$(sed -n "${obj_line_num}p" "$temp_file")
                            fi
                            
                            # If we have line content, search for it in the original file
                            local file_line_num="unknown"
                            if [[ -n "$line_content" ]]; then
                                # Escape special characters in the content
                                local escaped_content=$(echo "$line_content" | sed 's/[]\/$*.^[]/\\&/g')
                                
                                # Find all occurrences of this content in the file
                                local all_matches=($(grep -n "$escaped_content" "$file" | cut -d: -f1))
                                
                                # If we have multiple matches, use the one in the correct object
                                if [[ ${#all_matches[@]} -gt 0 ]]; then
                                    if [[ $i -eq 0 ]]; then
                                        # For the first object, use the first match
                                        file_line_num=${all_matches[0]}
                                    else
                                        # For subsequent objects, use matches after the end of the previous object
                                        local prev_obj_end=$(grep -n "^}$" "$file" | sed -n "$i"p | cut -d: -f1)
                                        for match in "${all_matches[@]}"; do
                                            if [[ $match -gt $prev_obj_end ]]; then
                                                file_line_num=$match
                                                break
                                            fi
                                        done
                                    fi
                                fi
                            fi
                            
                            # If we still don't have a line number, try to find the type marker directly
                            if [[ "$file_line_num" == "unknown" ]]; then
                                local type_marker=""
                                case "$type_name" in
                                    "DBPointer") type_marker='"\$dbPointer"' ;;
                                    "DBRef") type_marker='"\$ref"' ;;
                                    "JavaScript with scope") type_marker='"\$code".*"\$scope"' ;;
                                    "JavaScript") type_marker='"\$code"' ;;
                                    "Symbol") type_marker='"\$symbol"' ;;
                                    "Undefined") type_marker='"\$undefined"' ;;
                                esac
                                
                                if [[ -n "$type_marker" ]]; then
                                    # Find all occurrences of this type marker
                                    local all_lines=($(grep -n "$type_marker" "$file" | cut -d: -f1))
                                    
                                    # Filter the matches to only include those in the current object
                                    local obj_start=1
                                    local obj_end=$(grep -n "^}$" "$file" | sed -n "$((i+1))"p | cut -d: -f1)
                                    if [[ $i -gt 0 ]]; then
                                        obj_start=$(grep -n "^}$" "$file" | sed -n "$i"p | cut -d: -f1)
                                    fi
                                    
                                    local obj_matches=()
                                    for line in "${all_lines[@]}"; do
                                        if [[ $line -gt $obj_start && $line -lt $obj_end ]]; then
                                            obj_matches+=($line)
                                        fi
                                    done
                                    
                                    # Use the occurrence to determine which line to use
                                    if [[ ${#obj_matches[@]} -ge $occurrence ]]; then
                                        file_line_num=${obj_matches[$((occurrence-1))]}
                                    fi
                                fi
                            fi
                            
                            # Store the issue in the array with line number as the key
                            issues_array+=("$file_line_num:$type_name")
                            
                            if [[ "$VERBOSE" == "true" ]]; then
                                local value=$(jq -c "getpath($path)" "$temp_file" 2>/dev/null)
                                issues_array+=("    Path: $path")
                                issues_array+=("    Value: $value")
                            fi
                            
                            file_issues=$((file_issues + 1))
                            TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
                            occurrence=$((occurrence + 1))
                        fi
                    done <<< "$paths"
                fi
            done
            
            # Clean up the temporary file
            rm "$temp_file"
        done
    else
        # Process as a single JSON document
        # Check if file is valid JSON
        if ! jq empty "$file" 2>/dev/null; then
            echo "Error: $file is not a valid JSON file"
            return
        fi
        
        TOTAL_FILES=$((TOTAL_FILES + 1))
        
        # Check for each unsupported type
        for i in "${!TYPE_NAMES[@]}"; do
            local type_name=$(get_type_display_name "$i")
            local query="${TYPE_QUERIES[$i]}"
            local paths=$(jq -c "$query" "$file" 2>/dev/null)
            
            if [[ -n "$paths" ]]; then
                issues_found=true
                
                local occurrence=1
                while IFS= read -r path; do
                    if [[ -n "$path" ]]; then
                        local line_num=$(get_line_number "$file" "$path" "$occurrence" "false")
                        
                        # Store the issue in the array with line number as the key
                        issues_array+=("$line_num:$type_name")
                        
                        if [[ "$VERBOSE" == "true" ]]; then
                            local value=$(jq -c "getpath($path)" "$file" 2>/dev/null)
                            issues_array+=("    Path: $path")
                            issues_array+=("    Value: $value")
                        fi
                        
                        file_issues=$((file_issues + 1))
                        TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
                        occurrence=$((occurrence + 1))
                    fi
                done <<< "$paths"
            fi
        done
    fi
    
    # If issues were found, display them sorted by line number
    if [[ "$issues_found" == "true" ]]; then
        echo "File: $file"
        ISSUE_FILES=$((ISSUE_FILES + 1))
        
        # Sort the issues by line number
        # First, create a temporary file to store the issues
        local temp_file=$(mktemp)
        
        # Write the issues to the temporary file with line numbers as the first field
        for issue in "${issues_array[@]}"; do
            if [[ "$issue" == *":"* ]]; then
                # This is a main issue line with line number
                local line_num=$(echo "$issue" | cut -d: -f1)
                local type_info=$(echo "$issue" | cut -d: -f2-)
                echo "$line_num  - Line $line_num: $type_info detected (unsupported by Firestore)" >> "$temp_file"
            else
                # This is a detail line (for verbose mode)
                echo "0000  $issue" >> "$temp_file"
            fi
        done
        
        # Sort the file numerically by the first field and display the results
        sort -n "$temp_file" | cut -d' ' -f2- | sed 's/^/  /'
        
        # Remove the temporary file
        rm "$temp_file"
        
        echo ""
    fi
}

# Main function to scan directories and process files
main() {
    echo "Firestore Data Type Compatibility Issues:"
    echo "-----------------------------------------"
    
    if [[ -n "$FILE" ]]; then
        check_file "$FILE"
    else
        # Find all JSON files in the directory
        while IFS= read -r file; do
            check_file "$file"
        done < <(find "$DIR" -type f -name "*.json" | sort)
    fi
    
    echo "Summary:"
    echo "  Scanned $TOTAL_FILES files"
    echo "  Found $ISSUE_FILES files with compatibility issues"
    echo "  Detected $TOTAL_ISSUES unsupported data types"
}

# Execute main function
main
