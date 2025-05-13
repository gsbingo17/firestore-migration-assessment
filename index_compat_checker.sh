#!/bin/bash
# Firestore Index Compatibility Checker
# This script checks MongoDB index metadata for compatibility with Firestore.

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: This script requires jq for JSON processing. Please install it first."
    echo "Installation instructions: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Default values
DEBUG=false
DIR=""
FILE=""
SHOW_ISSUES=false
SHOW_COMPATIBLE=false
SUMMARY=true
SUPPORT_2DSPHERE=false
QUIET=false

# Unsupported features
UNSUPPORTED_INDEX_TYPES=("2d" "2dsphere" "hashed")
UNSUPPORTED_INDEX_OPTIONS=("storageEngine" "collation" "dropDuplicates")
UNSUPPORTED_COLLECTION_OPTIONS=("capped")

# Temporary files
TEMP_DIR=$(mktemp -d)
ISSUES_FILE="$TEMP_DIR/issues.json"
COMPATIBLE_FILE="$TEMP_DIR/compatible.json"
SUMMARY_FILE="$TEMP_DIR/summary.txt"
UNSUPPORTED_INDEXES_FILE="$TEMP_DIR/unsupported_indexes.txt"
UNIQUE_INDEXES_FILE="$TEMP_DIR/unique_indexes.txt"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Set trap for cleanup
trap cleanup EXIT

# Function to print usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --debug                Output debugging information"
    echo "  --dir DIR              Directory containing metadata files to check"
    echo "  --file FILE            Single metadata file to check"
    echo "  --show-issues          Show detailed compatibility issues"
    echo "  --show-compatible      Show compatible indexes only"
    echo "  --summary              Show a summary of compatibility statistics (default)"
    echo "  --quiet                Suppress progress messages"
    echo "  --help                 Show this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG=true
            shift
            ;;
        --dir)
            DIR="$2"
            shift 2
            ;;
        --file)
            FILE="$2"
            shift 2
            ;;
        --show-issues)
            SHOW_ISSUES=true
            SUMMARY=false
            shift
            ;;
        --show-compatible)
            SHOW_COMPATIBLE=true
            SUMMARY=false
            shift
            ;;
        --summary)
            SUMMARY=true
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

# Debug function
debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG: $1"
    fi
}

# Initialize counters
total_indexes=0
incompatible_indexes=0
unsupported_types=()
unique_indexes=0
text_indexes=0
ttl_indexes=0
partial_indexes=0

# Initialize JSON files
echo "{}" > "$ISSUES_FILE"
echo "{}" > "$COMPATIBLE_FILE"
echo "" > "$UNSUPPORTED_INDEXES_FILE"
echo "" > "$UNIQUE_INDEXES_FILE"
TEXT_INDEXES_FILE="$TEMP_DIR/text_indexes.txt"
TTL_INDEXES_FILE="$TEMP_DIR/ttl_indexes.txt"
PARTIAL_INDEXES_FILE="$TEMP_DIR/partial_indexes.txt"
echo "" > "$TEXT_INDEXES_FILE"
echo "" > "$TTL_INDEXES_FILE"
echo "" > "$PARTIAL_INDEXES_FILE"

# Find all metadata files
find_metadata_files() {
    if [[ -n "$FILE" ]]; then
        echo "$FILE"
    else
        find "$DIR" -type f -name "*.metadata.json" | grep -v "system\.indexes\.metadata\.json\|system\.profile\.metadata\.json\|system\.users\.metadata\.json\|system\.views\.metadata\.json"
    fi
}

# Function to check if a value is in an array
contains_element() {
    local element="$1"
    shift
    local array=("$@")
    for i in "${array[@]}"; do
        if [[ "$i" == "$element" ]]; then
            return 0
        fi
    done
    return 1
}

# Process each metadata file
process_metadata_file() {
    local file="$1"
    debug "Processing file: $file"
    
    # Extract database and collection names from the file path or namespace
    local db_name=""
    local collection_name=""
    
    # Try to get namespace from the first index
    local ns=$(jq -r '.indexes[0].ns // ""' "$file")
    if [[ -n "$ns" ]]; then
        db_name=$(echo "$ns" | cut -d. -f1)
        collection_name=$(echo "$ns" | cut -d. -f2-)
    else
        # Fall back to directory structure
        db_name=$(basename "$(dirname "$file")")
        collection_name=$(basename "$file" | sed 's/\.metadata\.json$//')
    fi
    
    debug "Database: $db_name, Collection: $collection_name"
    
    
    # Define namespace
    local namespace="${db_name}.${collection_name}"
    
    # Check collection options
    local options=$(jq -r '.options // {}' "$file")
    for option in "${UNSUPPORTED_COLLECTION_OPTIONS[@]}"; do
        if jq -e --arg opt "$option" '.[$opt] == true' <<< "$options" > /dev/null; then
            jq --arg db "$db_name" --arg coll "$collection_name" --arg opt "$option" \
               '. + {($db): {($coll): {"unsupported_collection_options": [$opt]}}}' "$ISSUES_FILE" > "$TEMP_DIR/temp.json"
            mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
        fi
    done
    
    # Process each index
    local indexes=$(jq -r '.indexes // []' "$file")
    local index_count=$(jq -r '.indexes | length' "$file")
    total_indexes=$((total_indexes + index_count))
    
    for i in $(seq 0 $((index_count - 1))); do
        local index=$(jq -r ".indexes[$i]" "$file")
        local index_name=$(jq -r '.name' <<< "$index")
        debug "Processing index: $index_name"
        
        
        
        # Check for unsupported index options
        for option in "${UNSUPPORTED_INDEX_OPTIONS[@]}"; do
            if jq -e --arg opt "$option" '.[$opt] != null' <<< "$index" > /dev/null; then
                jq --arg db "$db_name" --arg coll "$collection_name" --arg idx "$index_name" --arg opt "$option" \
                   '. + {($db): {($coll): {($idx): {"unsupported_index_options": [$opt]}}}}' "$ISSUES_FILE" > "$TEMP_DIR/temp.json"
                mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
            fi
        done
        
        # Check for unique indexes
        if jq -e '.unique == true' <<< "$index" > /dev/null; then
            debug "    Found unique index: $index_name"
            unique_indexes=$((unique_indexes + 1))
            
            # Add to unique indexes file
            echo "${namespace}.${index_name}" >> "$UNIQUE_INDEXES_FILE"
            
            # Create a new issues file with the updated content
            debug "    Adding unique index $index_name to issues file"
            
            # Create a temporary JSON file with the new issue
            echo "{\"$db_name\":{\"$collection_name\":{\"$index_name\":{\"unsupported_features\":\"unique\"}}}}" > "$TEMP_DIR/new_issue.json"
            
            # Merge the existing issues file with the new issue
            jq -s '.[0] * .[1]' "$ISSUES_FILE" "$TEMP_DIR/new_issue.json" > "$TEMP_DIR/temp.json"
            
            # Replace the issues file with the merged content
            mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
            
            debug "    Successfully updated issues file"
        fi
        
        # Check for text indexes
        if jq -e '.key._fts == "text"' <<< "$index" > /dev/null; then
            debug "    Found text index: $index_name"
            text_indexes=$((text_indexes + 1))
            
            # Get the correct namespace from the index
            local index_ns=$(jq -r '.ns // ""' <<< "$index")
            if [[ -n "$index_ns" ]]; then
                namespace="$index_ns"
            fi
            
            # Add to text indexes file
            echo "${namespace}.${index_name}" >> "$TEXT_INDEXES_FILE"
            
            # Create a new issues file with the updated content
            debug "    Adding text index $index_name to issues file"
            
            # Create a temporary JSON file with the new issue
            echo "{\"$db_name\":{\"$collection_name\":{\"$index_name\":{\"unsupported_features\":\"text\"}}}}" > "$TEMP_DIR/new_issue.json"
            
            # Merge the existing issues file with the new issue
            jq -s '.[0] * .[1]' "$ISSUES_FILE" "$TEMP_DIR/new_issue.json" > "$TEMP_DIR/temp.json"
            
            # Replace the issues file with the merged content
            mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
            
            debug "    Successfully updated issues file"
        fi
        
        # Check for TTL indexes
        if jq -e '.expireAfterSeconds != null' <<< "$index" > /dev/null; then
            debug "    Found TTL index: $index_name"
            ttl_indexes=$((ttl_indexes + 1))
            
            # Get the correct namespace from the index
            local index_ns=$(jq -r '.ns // ""' <<< "$index")
            if [[ -n "$index_ns" ]]; then
                namespace="$index_ns"
            fi
            
            # Add to TTL indexes file
            echo "${namespace}.${index_name}" >> "$TTL_INDEXES_FILE"
            
            # Create a new issues file with the updated content
            debug "    Adding TTL index $index_name to issues file"
            
            # Create a temporary JSON file with the new issue
            echo "{\"$db_name\":{\"$collection_name\":{\"$index_name\":{\"unsupported_features\":\"ttl\"}}}}" > "$TEMP_DIR/new_issue.json"
            
            # Merge the existing issues file with the new issue
            jq -s '.[0] * .[1]' "$ISSUES_FILE" "$TEMP_DIR/new_issue.json" > "$TEMP_DIR/temp.json"
            
            # Replace the issues file with the merged content
            mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
            
            debug "    Successfully updated issues file"
        fi
        
        # Check for partial indexes
        if jq -e '.partialFilterExpression != null' <<< "$index" > /dev/null; then
            debug "    Found partial index: $index_name"
            partial_indexes=$((partial_indexes + 1))
            
            # Get the correct namespace from the index
            local index_ns=$(jq -r '.ns // ""' <<< "$index")
            if [[ -n "$index_ns" ]]; then
                namespace="$index_ns"
            fi
            
            # Add to partial indexes file
            echo "${namespace}.${index_name}" >> "$PARTIAL_INDEXES_FILE"
            
            # Create a new issues file with the updated content
            debug "    Adding partial index $index_name to issues file"
            
            # Create a temporary JSON file with the new issue
            echo "{\"$db_name\":{\"$collection_name\":{\"$index_name\":{\"unsupported_features\":\"partial\"}}}}" > "$TEMP_DIR/new_issue.json"
            
            # Merge the existing issues file with the new issue
            jq -s '.[0] * .[1]' "$ISSUES_FILE" "$TEMP_DIR/new_issue.json" > "$TEMP_DIR/temp.json"
            
            # Replace the issues file with the merged content
            mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
            
            debug "    Successfully updated issues file"
        fi
        
        # Check for unsupported index types
        local has_unsupported_type=false
        local unsupported_type=""
        
        # Extract key-value pairs from the index key
        local keys=$(jq -r '.key | to_entries[] | "\(.key):\(.value)"' <<< "$index")
        debug "Index key-value pairs for $index_name: $keys"
        
        while IFS= read -r key_value; do
            IFS=':' read -r key_name key_type <<< "$key_value"
            debug "  Key: $key_name, Type: $key_type"
            
            # Check if key type is an unsupported index type
            for type in "${UNSUPPORTED_INDEX_TYPES[@]}"; do
                debug "    Checking against unsupported type: $type"
                if [[ "$key_type" == "\"$type\"" || "$key_type" == "$type" ]]; then
                    debug "    MATCH FOUND: $key_type is an unsupported type ($type)"
                    has_unsupported_type=true
                    unsupported_type="$type"
                    
                    # Add to unique unsupported types list
                    if ! contains_element "$type" "${unsupported_types[@]}"; then
                        unsupported_types+=("$type")
                    fi
                    
                    # Add to unsupported indexes file
                    echo "${namespace}.${index_name}:${type}" >> "$UNSUPPORTED_INDEXES_FILE"
                    
                    # Create a new issues file with the updated content
                    debug "    Adding $type index $index_name to issues file"
                    
                    # Create a temporary JSON file with the new issue
                    echo "{\"$db_name\":{\"$collection_name\":{\"$index_name\":{\"unsupported_index_types\":\"$type\"}}}}" > "$TEMP_DIR/new_issue.json"
                    
                    # Merge the existing issues file with the new issue
                    jq -s '.[0] * .[1]' "$ISSUES_FILE" "$TEMP_DIR/new_issue.json" > "$TEMP_DIR/temp.json"
                    
                    # Replace the issues file with the merged content
                    mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
                    
                    debug "    Successfully updated issues file"
                    
                    break
                fi
            done
            
        done <<< "$keys"
        
        # Count incompatible indexes
        if jq -e --arg db "$db_name" --arg coll "$collection_name" --arg idx "$index_name" \
            '.[$db][$coll][$idx] != null' "$ISSUES_FILE" > /dev/null; then
            incompatible_indexes=$((incompatible_indexes + 1))
            debug "Index $index_name is incompatible"
        else
            debug "Index $index_name is compatible"
        fi
    done
    
    # Add to compatible file if needed
    if [[ "$SHOW_COMPATIBLE" == "true" ]]; then
        # Create a temporary file with the full metadata
        jq --arg db "$db_name" --arg coll "$collection_name" --arg file "$file" \
           '. + {($db): {($coll): {"filepath": $file, "indexes": {}, "options": {}}}}' "$COMPATIBLE_FILE" > "$TEMP_DIR/temp_compatible.json"
        mv "$TEMP_DIR/temp_compatible.json" "$COMPATIBLE_FILE"
        
        # Add each compatible index
        for i in $(seq 0 $((index_count - 1))); do
            local index=$(jq -r ".indexes[$i]" "$file")
            local index_name=$(jq -r '.name' <<< "$index")
            
            # Check if this index has issues
            if ! jq -e --arg db "$db_name" --arg coll "$collection_name" --arg idx "$index_name" \
                '.[$db][$coll][$idx] != null' "$ISSUES_FILE" > /dev/null; then
                # This index is compatible, add it to the compatible file
                jq --arg db "$db_name" --arg coll "$collection_name" --arg idx "$index_name" --argjson index "$index" \
                   '.[$db][$coll].indexes += {($idx): $index}' "$COMPATIBLE_FILE" > "$TEMP_DIR/temp_compatible.json"
                mv "$TEMP_DIR/temp_compatible.json" "$COMPATIBLE_FILE"
            fi
        done
        
        # Add options if present
        local options=$(jq -r '.options // {}' "$file")
        if [[ "$options" != "{}" ]]; then
            jq --arg db "$db_name" --arg coll "$collection_name" --argjson opts "$options" \
               '.[$db][$coll].options = $opts' "$COMPATIBLE_FILE" > "$TEMP_DIR/temp_compatible.json"
            mv "$TEMP_DIR/temp_compatible.json" "$COMPATIBLE_FILE"
        fi
    fi
}

# Main execution
if [[ "$QUIET" == "false" ]]; then
    echo "Checking index compatibility with Firestore..."
fi

metadata_files=$(find_metadata_files)

if [[ -z "$metadata_files" ]]; then
    echo "Error: No metadata files found"
    exit 1
fi

# Process each metadata file
for file in $metadata_files; do
    process_metadata_file "$file"
done

# Calculate compatible indexes
compatible_indexes=$((total_indexes - incompatible_indexes))

# Generate summary
if [[ "$SUMMARY" == "true" ]]; then
    echo "Index Compatibility Summary:" > "$SUMMARY_FILE"
    echo "---------------------------" >> "$SUMMARY_FILE"
    echo "Total indexes: $total_indexes" >> "$SUMMARY_FILE"
    
    if [[ $total_indexes -gt 0 ]]; then
        compatible_percent=$(awk "BEGIN {printf \"%.1f\", ($compatible_indexes / $total_indexes) * 100}")
        incompatible_percent=$(awk "BEGIN {printf \"%.1f\", ($incompatible_indexes / $total_indexes) * 100}")
    else
        compatible_percent="0.0"
        incompatible_percent="0.0"
    fi
    
    echo "Compatible indexes: $compatible_indexes ($compatible_percent%)" >> "$SUMMARY_FILE"
    echo "Incompatible indexes: $incompatible_indexes ($incompatible_percent%)" >> "$SUMMARY_FILE"
    
    if [[ $unique_indexes -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Unique indexes found: $unique_indexes" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        
        # Get affected unique indexes
        while read -r line; do
            if [[ -n "$line" ]]; then  # Only process non-empty lines
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$UNIQUE_INDEXES_FILE"
    fi
    
    if [[ $text_indexes -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Text indexes found: $text_indexes" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        
        # Get affected text indexes
        while read -r line; do
            if [[ -n "$line" ]]; then  # Only process non-empty lines
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEXT_INDEXES_FILE"
    fi
    
    if [[ $ttl_indexes -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "TTL indexes found: $ttl_indexes" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        
        # Get affected TTL indexes
        while read -r line; do
            if [[ -n "$line" ]]; then  # Only process non-empty lines
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TTL_INDEXES_FILE"
    fi
    
    if [[ $partial_indexes -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Partial indexes found: $partial_indexes" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        
        # Get affected partial indexes
        while read -r line; do
            if [[ -n "$line" ]]; then  # Only process non-empty lines
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$PARTIAL_INDEXES_FILE"
    fi
    
    if [[ ${#unsupported_types[@]} -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Unsupported index types found:" >> "$SUMMARY_FILE"
        for type in "${unsupported_types[@]}"; do
            echo "  - $type" >> "$SUMMARY_FILE"
            echo "    Affected indexes:" >> "$SUMMARY_FILE"
            
            # Get affected indexes for this type
            grep ":${type}$" "$UNSUPPORTED_INDEXES_FILE" | while read -r line; do
                index_name=${line%:*}
                echo "      * $index_name" >> "$SUMMARY_FILE"
            done
        done
    fi
    
    cat "$SUMMARY_FILE"
fi

# Show issues if requested
if [[ "$SHOW_ISSUES" == "true" ]]; then
    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG: Issues file content:"
        cat "$ISSUES_FILE"
    fi
    
    if jq -e '. == {}' "$ISSUES_FILE" > /dev/null; then
        echo "No incompatibilities found."
    else
        jq '.' "$ISSUES_FILE"
    fi
fi

# Show compatible indexes if requested
if [[ "$SHOW_COMPATIBLE" == "true" ]]; then
    jq '.' "$COMPATIBLE_FILE"
fi

exit 0
