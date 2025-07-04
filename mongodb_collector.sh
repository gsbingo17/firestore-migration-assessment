#!/bin/bash
# MongoDB Data Collection Script
# This script runs MongoDB scripts to collect sample data, index definitions,
# and instance metadata from MongoDB databases.
# Supports authentication via MongoDB URI.

# Default values
OUTPUT_DIR="sample_data"
MONGODB_URI=""
VERBOSE=false

# Function to display usage information
function show_usage {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --uri URI                MongoDB connection URI with authentication"
    echo "  --output-dir DIR         Directory to store output files (default: sample_data)"
    echo "  --verbose                Show detailed connection information"
    echo "  --help                   Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --uri \"mongodb://username:password@host:port/database\""
    echo "  $0 --uri \"mongodb+srv://user:pass@cluster.mongodb.net/database\""
    echo "  $0 --output-dir my_samples"
    echo ""
    echo "Note: If no URI is provided, the script will use the default MongoDB connection."
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --uri)
            MONGODB_URI="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Create the output directory and data subdirectory if they don't exist
mkdir -p "$OUTPUT_DIR/data"

# Check if mongosh is installed
if ! command -v mongosh &> /dev/null; then
    echo "Error: mongosh is not installed or not in the PATH."
    echo "Please install MongoDB Shell (mongosh) to use this script."
    exit 1
fi

# Display start message
echo "Starting MongoDB data collection..."
if [ -n "$MONGODB_URI" ]; then
    if [ "$VERBOSE" = true ]; then
        echo "Using MongoDB URI: $MONGODB_URI"
    else
        echo "Using provided MongoDB URI for authentication"
    fi
fi
echo "Step 1: Collecting sample documents..."
echo "Samples will be saved to the $OUTPUT_DIR/data directory"

# Prepare the mongosh command with or without URI
MONGOSH_CMD="mongosh --quiet"
if [ -n "$MONGODB_URI" ]; then
    MONGOSH_CMD="$MONGOSH_CMD --eval \"const URI='$MONGODB_URI'\""
fi

# Run the MongoDB script and process its output
eval "$MONGOSH_CMD --eval \"const OUTPUT_DIR='$OUTPUT_DIR'\" --file export_sample_data.js" | awk -v output_dir="$OUTPUT_DIR" '
  /^__FILE_START__:/ {
    original_file=substr($0, 16)
    # Insert "/data" before the filename part
    split(original_file, parts, "/")
    filename=parts[length(parts)]
    file=output_dir "/data/" filename
    in_file=1
    next
  }
  /^__FILE_END__/ {
    in_file=0
    next
  }
  in_file {
    print > file
  }
  !in_file && !/^#/ {
    print
  }
'

# Check if any sample files were created
file_count=$(find "$OUTPUT_DIR/data" -name "*_sample.json" | wc -l)

if [ "$file_count" -eq 0 ]; then
    echo "Warning: No sample data files were created. Check MongoDB connection and permissions."
    sample_success=false
else
    echo "Sample data collection complete!"
    echo "$file_count collection sample files created in $OUTPUT_DIR/data directory."
    sample_success=true
fi

# Step 2: Collect index definitions
echo ""
echo "Step 2: Collecting index definitions..."

# Run the MongoDB index script and save the output
index_file="$OUTPUT_DIR/indexes.metadata.json"

# Run the index export script
if eval "$MONGOSH_CMD --eval \"const OUTPUT_DIR='$OUTPUT_DIR'\" --file export_index.js" > "$index_file"; then
    echo "Index definitions saved to $index_file"
    index_success=true
else
    echo "Warning: Failed to collect index definitions. Check MongoDB connection and permissions."
    index_success=false
fi

# Step 3: Collect MongoDB instance metadata
echo ""
echo "Step 3: Collecting MongoDB instance metadata..."

# Run the MongoDB metadata script and save the output
metadata_file="$OUTPUT_DIR/mongodb_metadata.json"

# Run the metadata export script
if eval "$MONGOSH_CMD --eval \"const OUTPUT_DIR='$OUTPUT_DIR'\" --file export_metadata.js" > "$metadata_file"; then
    echo "MongoDB instance metadata saved to $metadata_file"
    metadata_success=true
else
    echo "Warning: Failed to collect MongoDB metadata. Check MongoDB connection and permissions."
    metadata_success=false
fi

# Summary
echo ""
echo "MongoDB data collection summary:"
if [ "$sample_success" = true ]; then
    echo "✓ Sample data: $file_count collection files in $OUTPUT_DIR/data"
else
    echo "✗ Sample data: Failed to collect"
fi

if [ "$index_success" = true ]; then
    echo "✓ Index definitions: Saved to $index_file"
else
    echo "✗ Index definitions: Failed to collect"
fi

if [ "$metadata_success" = true ]; then
    echo "✓ MongoDB metadata: Saved to $metadata_file"
else
    echo "✗ MongoDB metadata: Failed to collect"
fi

if [ "$metadata_success" = true ]; then
    echo ""
    echo "The metadata file contains comprehensive information about your MongoDB instance:"
    echo "- MongoDB version and build information"
    echo "- Database sizes and statistics"
    echo "- Collection counts, sizes, and document counts"
    echo "- Complete index information with properties"
fi

echo ""
if [ "$sample_success" = true ] || [ "$index_success" = true ] || [ "$metadata_success" = true ]; then
    echo "To run a comprehensive Firestore migration assessment, use:"
    echo "./firestore_migration_assessment.sh --dir $OUTPUT_DIR --run-all"
    echo ""
    echo "For data type compatibility only:"
    echo "./firestore_migration_assessment.sh --dir $OUTPUT_DIR/data --run-datatype"
    echo ""
    echo "For index compatibility only:"
    echo "./firestore_migration_assessment.sh --dir $OUTPUT_DIR --run-index"
    echo ""
    echo "For operator compatibility checking:"
    echo "1. Collect MongoDB operation logs or identify application source code files"
    echo "2. Run: ./firestore_operator_checker.sh --mode=scan --dir=/path/to/logs_or_code"
    echo "   or"
    echo "3. Use with the assessment suite: ./firestore_migration_assessment.sh --dir=/path/to/logs_or_code --run-operator"
    echo ""
    echo "See firestore_operator_checker_README.md for details on collecting operation logs"
fi

if [ "$sample_success" = true ] || [ "$index_success" = true ] || [ "$metadata_success" = true ]; then
    exit 0
else
    echo "Error: All data collection operations failed."
    exit 1
fi
