# MongoDB Sample Data and Index Collection for Firestore Migration

This tool collects sample documents and index definitions from MongoDB databases and collections to help assess compatibility with Firestore. It works alongside the Firestore Migration Assessment Suite to identify potential data type issues and index compatibility before migration. It supports authentication via MongoDB URI for connecting to secured MongoDB instances.

## Overview

When migrating from MongoDB to Firestore, certain BSON data types are not supported in Firestore. The `firestore_datatype_checker.sh` script can analyze JSON data to identify these unsupported types, but it needs sample data to work with. These scripts automate the collection of representative sample data from your MongoDB instance.

## Components

1. **`export_sample_data.js`** - MongoDB script that samples documents from all collections
2. **`export_index.js`** - MongoDB script that collects index definitions from all collections
3. **`export_metadata.js`** - MongoDB script that collects comprehensive metadata about the MongoDB instance
4. **`mongodb_collector.sh`** - Shell wrapper script that runs all scripts and processes their output

## Unsupported Types Detected

The collected samples can be analyzed to detect these unsupported BSON types:

- **DBPointer** (`$dbPointer`)
- **DBRef** (`$ref` + `$id`)
- **JavaScript** (`$code` without `$scope`)
- **JavaScript with scope** (`$code` + `$scope`)
- **Symbol** (`$symbol`)
- **Undefined** (`$undefined`)

## Usage

### Prerequisites

- MongoDB Shell (mongosh) installed and in your PATH
- Access to your MongoDB instance
- Bash shell environment

### Basic Usage

1. Run the collection script:

```bash
./mongodb_collector.sh
```

This will:
- Connect to your MongoDB instance
- Sample 10 random documents from each collection
- Create separate JSON files in the `sample_data/data` directory named `{database}_{collection}_sample.json`
- Collect index definitions from all collections and save them to `sample_data/indexes.metadata.json`
- Collect comprehensive MongoDB instance metadata and save it to `sample_data/mongodb_metadata.json`

### With Authentication

To connect to a MongoDB instance that requires authentication:

```bash
./mongodb_collector.sh --uri "mongodb://username:password@host:port/database"
```

For MongoDB Atlas:

```bash
./mongodb_collector.sh --uri "mongodb+srv://username:password@cluster.mongodb.net/database"
```

### Additional Options

```bash
./mongodb_collector.sh --help
```

Shows all available options:

- `--uri URI`: MongoDB connection URI with authentication
- `--output-dir DIR`: Directory to store output files (default: sample_data)
- `--verbose`: Show detailed connection information
- `--help`: Display help message

2. Analyze the samples with the data type checker:

```bash
./firestore_datatype_checker.sh --dir sample_data
```

3. Analyze the indexes with the index compatibility checker:

```bash
./index_compat_checker.sh --file sample_data/indexes.metadata.json
```

### Advanced Usage

#### Direct Script Usage

You can also run the scripts directly with mongosh, which gives you more control over the connection parameters:

#### Without Authentication

```bash
# For indexes and metadata (simple redirection)
mongosh --quiet --file export_index.js > indexes.metadata.json
mongosh --quiet --file export_metadata.js > mongodb_metadata.json

# For sample data (requires AWK processing)
# DO NOT copy-paste this directly - use the wrapper script instead
# The sample data script requires special processing to create multiple files
```

#### With Authentication

```bash
# For indexes and metadata (simple redirection)
mongosh --quiet --eval "const URI='mongodb://username:password@host:port/database'" --file export_index.js > indexes.metadata.json
mongosh --quiet --eval "const URI='mongodb://username:password@host:port/database'" --file export_metadata.js > mongodb_metadata.json

# For sample data, always use the wrapper script:
./mongodb_collector.sh --uri "mongodb://username:password@host:port/database"
```

#### The Actual AWK Script (For Reference Only)

If you're curious about how the sample data processing works, here's the actual AWK script used by the wrapper:

```bash
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
```

This script processes special markers in the output to create multiple files, which is why we recommend using the wrapper script instead of running it directly.

#### Customizing Sample Size

To change the number of documents sampled per collection, edit the `SAMPLE_SIZE` constant in `export_sample_data.js`:

```javascript
// Configuration
const SAMPLE_SIZE = 20;  // Change from default 10 to 20
```

#### Changing Output Directory

The recommended way to change the output directory is to use the `--output-dir` parameter:

```bash
./mongodb_collector.sh --output-dir my_custom_dir
```

This will:
- Create sample files in `my_custom_dir/data/`
- Save index definitions to `my_custom_dir/indexes.metadata.json`
- Save MongoDB metadata to `my_custom_dir/mongodb_metadata.json`

You can also edit the default output directory in the script if needed:

```bash
# In mongodb_collector.sh
OUTPUT_DIR="my_samples"  # Change the default from "sample_data"
```

## Output Format

### Sample Data Files

Each sample file uses the exact same format as mongoexport - NDJSON (Newline Delimited JSON) with one document per line:

```json
{"_id":{"$oid":"507f1f77bcf86cd799439011"},"name":"John","email":"john@example.com"}
{"_id":{"$oid":"507f1f77bcf86cd799439012"},"name":"Jane","email":"jane@example.com"}
```

This format is identical to what mongoexport produces, with BSON types properly represented in extended JSON format:

- **ObjectId**: `{"$oid": "507f1f77bcf86cd799439011"}`
- **Date**: `{"$date": "2020-01-01T00:00:00Z"}`
- **DBRef**: `{"$ref": "collection", "$id": {"$oid": "..."}, "$db": "database"}`
- **Symbol**: `{"$symbol": "symbol-value"}`
- **Binary**: `{"$binary": {"base64": "...", "subType": "00"}}`
- **JavaScript**: `{"$code": "function() { return 1; }"}`
- **JavaScript with Scope**: `{"$code": "...", "$scope": {...}}`
- **Undefined**: `{"$undefined": true}`

### MongoDB Metadata

The metadata file (`mongodb_metadata.json`) contains comprehensive information about your MongoDB instance:

- **MongoDB Version and Build Information**: Version, git version, allocator, JavaScript engine, etc.
- **Server Status**: Host, process, uptime, local time, etc.
- **Storage Engine**: The storage engine used by MongoDB
- **Database Information**: For each database, includes:
  - Size on disk, number of collections, total documents
  - Storage statistics (data size, storage size, index size)
- **Collection Information**: For each collection, includes:
  - Document count, average object size, storage size
  - Capped collection status
  - Index information
- **Index Information**: For each index, includes:
  - Index keys, uniqueness, sparsity
  - Special index properties (text indexes, TTL indexes, etc.)

## Integration with Migration Assessment Suite

These scripts are designed to work with the Firestore Migration Assessment Suite. After collecting samples and indexes, you can run the full assessment:

```bash
./firestore_migration_assessment.sh --dir sample_data --run-datatype --run-index
```

## Troubleshooting

### No Files Created

If no sample files are created:
- Check your MongoDB connection
- Verify you have read permissions on the databases
- Ensure the collections contain documents

### MongoDB Authentication

If your MongoDB instance requires authentication, always use the `--uri` parameter with the wrapper script:

```bash
./mongodb_collector.sh --uri "mongodb://username:password@hostname:port/database"
```

This is the recommended approach as it properly handles authentication for all three scripts (sample data, indexes, and metadata).

## License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
