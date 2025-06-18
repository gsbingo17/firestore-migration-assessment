#!/bin/bash
# MongoDB Sample Data Collection Wrapper Script
# This script runs both export_sample_data.js and export_index.js MongoDB scripts
# to collect sample data and index definitions from MongoDB databases.

# Set the output directory
OUTPUT_DIR="sample_data"

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Check if mongosh is installed
if ! command -v mongosh &> /dev/null; then
    echo "Error: mongosh is not installed or not in the PATH."
    echo "Please install MongoDB Shell (mongosh) to use this script."
    exit 1
fi

# Display start message
echo "Starting MongoDB data collection..."
echo "Step 1: Collecting sample documents..."
echo "Samples will be saved to the $OUTPUT_DIR directory"

# Run the MongoDB script and process its output
mongosh --quiet --file export_sample_data.js | awk '
  /^__FILE_START__:/ {
    file=substr($0, 16)
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
file_count=$(find "$OUTPUT_DIR" -name "*_sample.json" | wc -l)

if [ "$file_count" -eq 0 ]; then
    echo "Warning: No sample data files were created. Check MongoDB connection and permissions."
    sample_success=false
else
    echo ""
    echo "Sample data collection complete!"
    echo "$file_count collection sample files created in $OUTPUT_DIR directory."
    sample_success=true
fi

# Step 2: Collect index definitions
echo ""
echo "Step 2: Collecting index definitions..."

# Run the MongoDB index script and save the output
index_file="$OUTPUT_DIR/indexes_output.json"
index_metadata_file="$OUTPUT_DIR/indexes_output.metadata.json"

# Create a metadata file with timestamp
echo "{\"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\", \"source\": \"MongoDB\"}" > "$index_metadata_file"

# Run the index export script
if mongosh --quiet --file export_index.js > "$index_file"; then
    echo "Index definitions saved to $index_file"
    index_success=true
else
    echo "Warning: Failed to collect index definitions. Check MongoDB connection and permissions."
    index_success=false
fi

# Summary
echo ""
echo "MongoDB data collection summary:"
if [ "$sample_success" = true ]; then
    echo "✓ Sample data: $file_count collection files in $OUTPUT_DIR"
else
    echo "✗ Sample data: Failed to collect"
fi

if [ "$index_success" = true ]; then
    echo "✓ Index definitions: Saved to $index_file"
else
    echo "✗ Index definitions: Failed to collect"
fi

echo ""
if [ "$sample_success" = true ]; then
    echo "To analyze these samples with the data type checker, run:"
    echo "./firestore_datatype_checker.sh --dir $OUTPUT_DIR"
fi

if [ "$sample_success" = true ] || [ "$index_success" = true ]; then
    exit 0
else
    echo "Error: Both sample data and index collection failed."
    exit 1
fi
