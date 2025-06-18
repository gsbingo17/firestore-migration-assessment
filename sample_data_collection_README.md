# MongoDB Sample Data and Index Collection for Firestore Migration

This tool collects sample documents and index definitions from MongoDB databases and collections to help assess compatibility with Firestore. It works alongside the Firestore Migration Assessment Suite to identify potential data type issues and index compatibility before migration.

## Overview

When migrating from MongoDB to Firestore, certain BSON data types are not supported in Firestore. The `firestore_datatype_checker.sh` script can analyze JSON data to identify these unsupported types, but it needs sample data to work with. These scripts automate the collection of representative sample data from your MongoDB instance.

## Components

1. **`export_sample_data.js`** - MongoDB script that samples documents from all collections
2. **`export_index.js`** - MongoDB script that collects index definitions from all collections
3. **`collect_sample_data.sh`** - Shell wrapper script that runs both scripts and processes their output

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
./collect_sample_data.sh
```

This will:
- Connect to your MongoDB instance
- Sample 10 random documents from each collection
- Create separate JSON files in the `sample_data` directory named `{database}_{collection}_sample.json`
- Collect index definitions from all collections and save them to `indexes_output.json`
- Create a metadata file for the index definitions at `indexes_output.metadata.json`

2. Analyze the samples with the data type checker:

```bash
./firestore_datatype_checker.sh --dir sample_data
```

3. Analyze the indexes with the index compatibility checker:

```bash
./index_compat_checker.sh --file sample_data/indexes_output.json
```

### Advanced Usage

#### MongoDB Connection Options

To connect to a specific MongoDB instance, use the standard MongoDB connection options:

```bash
mongosh --host mongodb.example.com --port 27017 --username user --password pass --quiet --file export_sample_data.js | ./collect_sample_data.sh
```

#### Customizing Sample Size

To change the number of documents sampled per collection, edit the `SAMPLE_SIZE` constant in `export_sample_data.js`:

```javascript
// Configuration
const SAMPLE_SIZE = 20;  // Change from default 10 to 20
```

#### Changing Output Directory

To change the output directory, edit the `OUTPUT_DIR` constant in both scripts:

```javascript
// In export_sample_data.js
const OUTPUT_DIR = "my_samples";
```

```bash
# In collect_sample_data.sh
OUTPUT_DIR="my_samples"
```

## Output Format

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

If your MongoDB instance requires authentication, use the appropriate connection string:

```bash
mongosh "mongodb://username:password@hostname:port/database" --quiet --file export_sample_data.js | ./collect_sample_data.sh
```

## License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
