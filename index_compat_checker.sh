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
SUMMARY=true
SUPPORT_2DSPHERE=false

# Unsupported index types (detected in key values or structure)
UNSUPPORTED_INDEX_TYPES=("2d" "2dsphere" "hashed" "text")

# Unsupported index options/features (detected in index properties)
UNSUPPORTED_INDEX_OPTIONS=("storageEngine" "dropDuplicates" 
                          "expireAfterSeconds" "partialFilterExpression"
                          "hidden" "case_insensitive" "wildcard" "vector")

# Unsupported collection options
UNSUPPORTED_COLLECTION_OPTIONS=("capped")

# Temporary files
TEMP_DIR=$(mktemp -d)
ISSUES_FILE="$TEMP_DIR/issues.json"
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
    echo "  --summary              Show a summary of compatibility statistics (default)"
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
        --dir=*)
            DIR="${1#*=}"
            shift
            ;;
        --file)
            FILE="$2"
            shift 2
            ;;
        --file=*)
            FILE="${1#*=}"
            shift
            ;;
        --summary)
            SUMMARY=true
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

# Initialize counters for each type and option
total_indexes=0
incompatible_indexes=0

# Initialize individual counters for backward compatibility
count_2d=0
count_2dsphere=0
count_hashed=0
count_text=0
count_storageEngine=0
count_collation=0
count_dropDuplicates=0
count_unique=0
count_expireAfterSeconds=0
count_partialFilterExpression=0
count_hidden=0
count_case_insensitive=0
count_wildcard=0
count_vector=0

# Initialize JSON files
echo "{}" > "$ISSUES_FILE"

# Create tracking files for each type and option
for type in "${UNSUPPORTED_INDEX_TYPES[@]}"; do
    touch "$TEMP_DIR/${type}_indexes.txt"
done

for option in "${UNSUPPORTED_INDEX_OPTIONS[@]}"; do
    touch "$TEMP_DIR/${option}_indexes.txt"
done

# Legacy file names for backward compatibility
UNSUPPORTED_INDEXES_FILE="$TEMP_DIR/unsupported_indexes.txt"
UNIQUE_INDEXES_FILE="$TEMP_DIR/unique_indexes.txt"
TEXT_INDEXES_FILE="$TEMP_DIR/text_indexes.txt"
TTL_INDEXES_FILE="$TEMP_DIR/ttl_indexes.txt"
PARTIAL_INDEXES_FILE="$TEMP_DIR/partial_indexes.txt"
echo "" > "$UNSUPPORTED_INDEXES_FILE"
echo "" > "$UNIQUE_INDEXES_FILE"
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

# Unified function to process a single index
process_index() {
    local index="$1"
    local db_name="$2"
    local collection_name="$3"
    local namespace="$4"
    
    local index_name=$(jq -r '.name' <<< "$index")
    local has_issue=false
    
    debug "  Processing index: $index_name"
    
    # Get the correct namespace from the index if available
    local index_ns=$(jq -r '.ns // ""' <<< "$index")
    if [[ -n "$index_ns" ]]; then
        namespace="$index_ns"
    fi
    
    # Check for unsupported index types in key values
    local keys=$(jq -r '.key | to_entries[] | "\(.key):\(.value)"' <<< "$index")
    debug "    Index key-value pairs for $index_name: $keys"
    
    while IFS= read -r key_value; do
        IFS=':' read -r key_name key_type <<< "$key_value"
        debug "      Key: $key_name, Type: $key_type"
        
        # Special handling for text indexes
        if [[ "$key_name" == "_fts" && ("$key_type" == "\"text\"" || "$key_type" == "text") ]]; then
            has_issue=true
            local type="text"
            count_text=$((count_text + 1))
            echo "${namespace}.${index_name}" >> "$TEXT_INDEXES_FILE"  # Use legacy file for consistency
            
            # Add to issues file
            jq --arg db "$db_name" --arg coll "$collection_name" --arg idx "$index_name" \
               --arg type "$type" \
               '. + {($db): {($coll): {($idx): {"unsupported_index_type": $type}}}}' "$ISSUES_FILE" > "$TEMP_DIR/temp.json"
            mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
            
            debug "      Found text index: $index_name"
            continue
        fi
        
        # Check other index types
        for type in "${UNSUPPORTED_INDEX_TYPES[@]}"; do
            # Skip text as it's handled separately
            if [[ "$type" == "text" ]]; then
                continue
            fi
            
            debug "        Checking against unsupported type: $type"
            if [[ "$key_type" == "\"$type\"" || "$key_type" == "$type" ]]; then
                debug "        MATCH FOUND: $key_type is an unsupported type ($type)"
                has_issue=true
                
                # Increment appropriate counter
                case "$type" in
                    "2d") count_2d=$((count_2d + 1)) ;;
                    "2dsphere") count_2dsphere=$((count_2dsphere + 1)) ;;
                    "hashed") count_hashed=$((count_hashed + 1)) ;;
                esac
                
                echo "${namespace}.${index_name}" >> "$TEMP_DIR/${type}_indexes.txt"
                echo "${namespace}.${index_name}:${type}" >> "$UNSUPPORTED_INDEXES_FILE"  # Legacy compatibility
                
                # Add to issues file
                jq --arg db "$db_name" --arg coll "$collection_name" --arg idx "$index_name" \
                   --arg type "$type" \
                   '. + {($db): {($coll): {($idx): {"unsupported_index_type": $type}}}}' "$ISSUES_FILE" > "$TEMP_DIR/temp.json"
                mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
                
                debug "        Added $type index $index_name to issues file"
                break
            fi
        done
    done <<< "$keys"
    
    # Check for unsupported index options
    for option in "${UNSUPPORTED_INDEX_OPTIONS[@]}"; do
        local option_found=false
        
        case "$option" in
            "unique")
                if jq -e '.unique == true' <<< "$index" > /dev/null; then
                    option_found=true
                fi
                ;;
                
            "expireAfterSeconds")
                if jq -e '.expireAfterSeconds != null' <<< "$index" > /dev/null; then
                    option_found=true
                fi
                ;;
                
            "partialFilterExpression")
                if jq -e '.partialFilterExpression != null' <<< "$index" > /dev/null; then
                    option_found=true
                fi
                ;;
                
            "hidden")
                if jq -e '.hidden == true' <<< "$index" > /dev/null; then
                    option_found=true
                fi
                ;;
                
            "case_insensitive")
                if jq -e '.collation != null and (.collation.strength == 1 or .collation.strength == 2)' <<< "$index" > /dev/null; then
                    option_found=true
                fi
                ;;
                
            "wildcard")
                # Check for wildcard pattern in key names
                local has_wildcard=false
                local wildcard_keys=$(jq -r '.key | to_entries[] | "\(.key)"' <<< "$index")
                while IFS= read -r key_name; do
                    if [[ "$key_name" == "\$**" || "$key_name" == *".\$**" ]]; then
                        has_wildcard=true
                        break
                    fi
                done <<< "$wildcard_keys"
                
                if [[ "$has_wildcard" == "true" ]]; then
                    option_found=true
                fi
                ;;
                
            "vector")
                if jq -e '.type == "search" and .["$**"].vector != null' <<< "$index" > /dev/null; then
                    option_found=true
                fi
                ;;
                
            *)
                # Standard option check
                if jq -e --arg opt "$option" '.[$opt] != null' <<< "$index" > /dev/null; then
                    option_found=true
                fi
                ;;
        esac
        
        if [[ "$option_found" == "true" ]]; then
            has_issue=true
            
            # Increment appropriate counter
            case "$option" in
                "storageEngine") count_storageEngine=$((count_storageEngine + 1)) ;;
                "collation") count_collation=$((count_collation + 1)) ;;
                "dropDuplicates") count_dropDuplicates=$((count_dropDuplicates + 1)) ;;
                "unique") count_unique=$((count_unique + 1)) ;;
                "expireAfterSeconds") count_expireAfterSeconds=$((count_expireAfterSeconds + 1)) ;;
                "partialFilterExpression") count_partialFilterExpression=$((count_partialFilterExpression + 1)) ;;
                "hidden") count_hidden=$((count_hidden + 1)) ;;
                "case_insensitive") count_case_insensitive=$((count_case_insensitive + 1)) ;;
                "wildcard") count_wildcard=$((count_wildcard + 1)) ;;
                "vector") count_vector=$((count_vector + 1)) ;;
            esac
            
            # Write to tracking files
            case "$option" in
                "unique")
                    echo "${namespace}.${index_name}" >> "$UNIQUE_INDEXES_FILE"
                    ;;
                "expireAfterSeconds")
                    echo "${namespace}.${index_name}" >> "$TTL_INDEXES_FILE"
                    ;;
                "partialFilterExpression")
                    echo "${namespace}.${index_name}" >> "$PARTIAL_INDEXES_FILE"
                    ;;
                *)
                    echo "${namespace}.${index_name}" >> "$TEMP_DIR/${option}_indexes.txt"
                    ;;
            esac
            
            # Add to issues file
            jq --arg db "$db_name" --arg coll "$collection_name" --arg idx "$index_name" \
               --arg option "$option" \
               '. + {($db): {($coll): {($idx): {"unsupported_index_option": $option}}}}' "$ISSUES_FILE" > "$TEMP_DIR/temp.json"
            mv "$TEMP_DIR/temp.json" "$ISSUES_FILE"
            
            debug "      Found $option option in index: $index_name"
        fi
    done
    
    # Return whether this index has issues
    if [[ "$has_issue" == "true" ]]; then
        return 1
    else
        return 0
    fi
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
        
        
        
        # Process this index using unified approach
        process_index "$index" "$db_name" "$collection_name" "$namespace"
        
        # Count incompatible indexes
        if jq -e --arg db "$db_name" --arg coll "$collection_name" --arg idx "$index_name" \
            '.[$db][$coll][$idx] != null' "$ISSUES_FILE" > /dev/null; then
            incompatible_indexes=$((incompatible_indexes + 1))
            debug "Index $index_name is incompatible"
        else
            debug "Index $index_name is compatible"
        fi
    done
    
}

# Main execution
echo "Checking index compatibility with Firestore..."

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
    
    # Report on unsupported index types
    if [[ $count_2d -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "2d indexes found: $count_2d" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/2d_indexes.txt"
    fi
    
    if [[ $count_2dsphere -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "2dsphere indexes found: $count_2dsphere" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/2dsphere_indexes.txt"
    fi
    
    if [[ $count_hashed -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Hashed indexes found: $count_hashed" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/hashed_indexes.txt"
    fi
    
    if [[ $count_text -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Text indexes found: $count_text" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEXT_INDEXES_FILE"
    fi
    
    # Report on unsupported index options
    if [[ $count_unique -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Unique indexes found: $count_unique" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$UNIQUE_INDEXES_FILE"
    fi
    
    if [[ $count_expireAfterSeconds -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "TTL indexes found: $count_expireAfterSeconds" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TTL_INDEXES_FILE"
    fi
    
    if [[ $count_partialFilterExpression -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Partial indexes found: $count_partialFilterExpression" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$PARTIAL_INDEXES_FILE"
    fi
    
    if [[ $count_hidden -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Hidden indexes found: $count_hidden" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/hidden_indexes.txt"
    fi
    
    if [[ $count_case_insensitive -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Case insensitive indexes found: $count_case_insensitive" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/case_insensitive_indexes.txt"
    fi
    
    if [[ $count_wildcard -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Wildcard indexes found: $count_wildcard" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/wildcard_indexes.txt"
    fi
    
    if [[ $count_vector -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Vector indexes found: $count_vector" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/vector_indexes.txt"
    fi
    
    if [[ $count_storageEngine -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Storage engine indexes found: $count_storageEngine" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/storageEngine_indexes.txt"
    fi
    
    if [[ $count_collation -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Collation indexes found: $count_collation" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/collation_indexes.txt"
    fi
    
    if [[ $count_dropDuplicates -gt 0 ]]; then
        echo "" >> "$SUMMARY_FILE"
        echo "Drop duplicates indexes found: $count_dropDuplicates" >> "$SUMMARY_FILE"
        echo "  Affected indexes:" >> "$SUMMARY_FILE"
        while read -r line; do
            if [[ -n "$line" ]]; then
                echo "    * $line" >> "$SUMMARY_FILE"
            fi
        done < "$TEMP_DIR/dropDuplicates_indexes.txt"
    fi
    
    cat "$SUMMARY_FILE"
fi


exit 0
