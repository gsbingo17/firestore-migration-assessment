# Firestore Migration Assessment Suite

This tool combines the three Firestore compatibility checkers (datatype, operator, and index) into a unified assessment suite for evaluating MongoDB to Firestore migration compatibility.

## Overview

The Firestore Migration Assessment Suite provides a comprehensive analysis of potential compatibility issues when migrating from MongoDB to Firestore. It evaluates:

1. **Data Type Compatibility**: Identifies MongoDB data types that are not supported by Firestore
2. **Operator Compatibility**: Identifies MongoDB query operators that are not supported in Firestore
3. **Index Compatibility**: Checks MongoDB index structures for compatibility with Firestore

## Supported Databases

- Self-hosted MongoDB
- MongoDB Atlas
- AWS DocumentDB (with MongoDB compatibility)

## Directory Structure and Default Behavior

The assessment suite uses a smart subdirectory routing system to organize different types of files:

```
sample_data/
├── app/                          # Application code OR MongoDB logs (for operator checking)
│   ├── app.js                    # Option A: Your MongoDB application source code
│   └── mongod.log                # Option B: MongoDB log file with profiler output
├── data/                         # Sample documents (for datatype checking)
│   ├── dbname_collection1_sample.json
│   └── dbname_collection2_sample.json
├── indexes.metadata.json         # Index definitions (for index checking)
└── mongodb_metadata.json         # Comprehensive metadata for MongoDB instance
```

When you specify a directory with the `--dir` parameter, the assessment suite automatically:

- Uses the `app/` subdirectory for operator checking (scans for MongoDB operators in code or logs)
- Uses the `data/` subdirectory for datatype checking (analyzes JSON documents for unsupported types)
- Uses the root directory for index checking (reads `*.metadata.json` files)

This organization helps each checker focus on relevant files and reduces scanning overlap. **If a required subdirectory doesn't exist, the corresponding assessment is skipped with a warning** — the checker will NOT fall back to scanning the main directory, which prevents scanning irrelevant files.

**Note:** With this directory structure, you only need to specify the `--dir` parameter. There's no need to use `--log-file`, `--data-file`, or `--metadata-dir` separately, as the subdirectory routing handles file organization automatically.

## Requirements

- Bash shell
- jq (JSON processor for Bash)
- The individual compatibility checker scripts:
  - `firestore_datatype_checker.sh`
  - `firestore_operator_checker.sh`
  - `index_compat_checker.sh`

## Installation

1. Make sure all the required scripts are in the same directory
2. Make the scripts executable:

```bash
chmod +x firestore_migration_assessment.sh
chmod +x firestore_datatype_checker.sh
chmod +x firestore_operator_checker.sh
chmod +x index_compat_checker.sh
```

## Usage

```
Usage: ./firestore_migration_assessment.sh [options]

Options:
  --dir DIR                 Directory to scan (for all assessment types)
                            Uses subdirectory routing:
                            - app/ for operator checking
                            - data/ for datatype checking
                            - root directory for index checking
  --file FILE               File to scan (for any assessment type)
                            Use with --run-datatype, --run-operator, --run-index, or --run-all
  --output-format FORMAT    Output format (text, json) [default: text]
  --output-file FILE        File to write the report to [default: stdout]
  --run-all                 Run all assessment types
  --run-datatype            Run only datatype compatibility assessment
  --run-operator            Run only operator compatibility assessment
  --run-index               Run only index compatibility assessment
  --verbose                 Show detailed information
  --quiet                   Suppress progress messages and non-essential output
  --help                    Display this help message
```

> **Note:** You must use either `--dir` for directory-based assessment or `--file` for file-based assessment, but not both. When using `--file`, you must still specify which assessment type to run with `--run-datatype`, `--run-operator`, `--run-index`, or `--run-all`.

## Examples

### Step-by-Step: Complete Assessment Workflow

Follow these steps to collect all necessary data and run the assessment:

#### Step 1: Collect MongoDB Data (Sample Documents, Indexes, Metadata)

Use the `mongodb_collector.sh` script to automatically collect sample documents, index definitions, and instance metadata from your MongoDB instance:

```bash
# Collect data from an authenticated MongoDB instance
./mongodb_collector.sh --uri "mongodb://username:password@host:port/database"

# Or specify a custom output directory
./mongodb_collector.sh --uri "mongodb://username:password@host:port/database" --output-dir my_assessment
```

This automatically creates the following structure:
```
sample_data/
├── data/                         # Sample documents (auto-collected)
│   ├── dbname_collection1_sample.json
│   └── dbname_collection2_sample.json
├── indexes.metadata.json         # Index definitions (auto-collected)
└── mongodb_metadata.json         # Instance metadata (auto-collected)
```

#### Step 2: Collect Application Code or MongoDB Logs (for Operator Checking)

The operator checker needs either your application source code or MongoDB logs to identify unsupported MongoDB operators. Place them in the `app/` subdirectory:

**Option A: Application source code** (if available)
```bash
# Create the app directory and copy your MongoDB application code
mkdir -p sample_data/app
cp -r /path/to/your-mongodb-app/* sample_data/app/
```

**Option B: MongoDB log file** (if application code is not available)

Enable MongoDB profiler to log all queries to the MongoDB log file, then collect the log:

```javascript
// In mongosh: Set profiling level to log ALL queries to MongoDB log
db.setProfilingLevel(0, -1)
```

This sets the slow query threshold to -1ms, causing all operations to be logged to the MongoDB log file. Let your application run for a representative period to capture typical query patterns, then collect the log:

```bash
# Create the app directory and copy the MongoDB log file
mkdir -p sample_data/app
cp /var/log/mongodb/mongod.log sample_data/app/
```

> **Note:** Remember to reset the profiling level after collecting logs to avoid performance impact:
> ```javascript
> db.setProfilingLevel(0, 100)  // Reset to default (log queries slower than 100ms)
> ```

#### Step 3: Run the Assessment

```bash
# Run all assessments
./firestore_migration_assessment.sh --run-all --dir sample_data

# Generate a report with detailed information
./firestore_migration_assessment.sh --run-all --dir sample_data --verbose

# Suppress progress messages
./firestore_migration_assessment.sh --run-all --dir sample_data --quiet
```

The assessment suite automatically routes to the correct subdirectory:
- **Operator checker** → scans `sample_data/app/` (skipped if `app/` doesn't exist)
- **Datatype checker** → scans `sample_data/data/` (skipped if `data/` doesn't exist)
- **Index checker** → scans `sample_data/` for `*.metadata.json` files

### Required MongoDB Privileges

The MongoDB collector script requires certain privileges to collect data, index definitions, and metadata:

| Operation | Required Privileges |
|-----------|---------------------|
| Sample data collection | `read` on target databases |
| Index definitions | `listIndexes` on collections |
| Metadata collection | `listDatabases`, `dbStats`, `serverStatus`, `collStats` |

The recommended MongoDB role is `readAnyDatabase`, which provides all the necessary privileges. If you need to create a custom role with minimal permissions, include:

- `read`: For reading documents
- `dbStats`: For database statistics
- `listDatabases`: For listing all databases
- `listCollections`: For listing collections in databases
- `listIndexes`: For listing indexes on collections
- `serverStatus`: For getting MongoDB server information

Example of creating a custom role with the required privileges:

```javascript
db.createRole({
  role: "firestoreMigrationAssessment",
  privileges: [
    { resource: { cluster: true }, actions: [ "listDatabases", "serverStatus" ] },
    { resource: { db: "", collection: "" }, actions: [ "find", "listCollections", "listIndexes", "dbStats", "collStats" ] }
  ],
  roles: []
})
```

Then assign this role to a user:

```javascript
db.createUser({
  user: "migrationUser",
  pwd: "password",
  roles: [ { role: "firestoreMigrationAssessment", db: "admin" } ]
})
```

### Run Specific Assessment Types

#### Directory-Based Assessment

```bash
# Operator checking only (scans sample_data/app/)
./firestore_migration_assessment.sh --run-operator --dir sample_data

# Datatype checking only (scans sample_data/data/)
./firestore_migration_assessment.sh --run-datatype --dir sample_data

# Index checking only (scans sample_data/ for *.metadata.json files)
./firestore_migration_assessment.sh --run-index --dir sample_data
```

#### File-Based Assessment

When using `--file`, the assessment runs directly on the specified file without subdirectory routing:

```bash
# Check a specific data file for unsupported types
./firestore_migration_assessment.sh --file sample_data/data/sample.json --run-datatype

# Check a MongoDB log or source file for unsupported operators
./firestore_migration_assessment.sh --file sample_data/app/mongod.log --run-operator

# Check an index metadata file for compatibility
./firestore_migration_assessment.sh --file sample_data/indexes.metadata.json --run-index
```

### Generate JSON Report

```bash
./firestore_migration_assessment.sh --dir /path/to/project --run-all --output-format json --output-file report.json

# Generate JSON report without progress messages
./firestore_migration_assessment.sh --dir /path/to/project --run-all --output-format json --quiet
```

### Quick Reference: What Goes Where

| Directory | Content | How to Collect |
|-----------|---------|----------------|
| `sample_data/data/` | Sample JSON documents | Auto-collected by `mongodb_collector.sh` |
| `sample_data/app/` | App source code **or** MongoDB logs | Manually: copy app code or MongoDB log file |
| `sample_data/` (root) | `indexes.metadata.json`, `mongodb_metadata.json` | Auto-collected by `mongodb_collector.sh` |

## Output Formats

### Text Format (Default)

The text format provides a human-readable report with sections for summary and detailed results:

```
==========================================================
           FIRESTORE MIGRATION ASSESSMENT REPORT          
==========================================================

SUMMARY:
--------
Datatype Compatibility:
  Total files scanned: 10
  Files with issues: 3
  Total issues detected: 15

Operator Compatibility:
  Files processed: 5
  Unsupported operators found: 8

Index Compatibility:
  Total indexes: 12
  Compatible indexes: 10
  Incompatible indexes: 2

DATATYPE COMPATIBILITY DETAILS:
-------------------------------
[Detailed output from datatype checker]

OPERATOR COMPATIBILITY DETAILS:
-------------------------------
[Detailed output from operator checker]

INDEX COMPATIBILITY DETAILS:
----------------------------
[Detailed output from index checker]

==========================================================
                      END OF REPORT                       
==========================================================
```

### JSON Format

The JSON format provides structured data that can be processed programmatically. It always includes both summary and detailed information in a properly structured format:

```json
{
  "summary": {
    "datatype_compatibility": {
      "total_files": 10,
      "files_with_issues": 3,
      "total_issues": 15
    },
    "operator_compatibility": {
      "files_processed": 5,
      "unsupported_operators": 8
    },
    "index_compatibility": {
      "total_indexes": 12,
      "compatible_indexes": 10,
      "incompatible_indexes": 2
    }
  },
  "details": {
    "datatype": {
      "files_with_issues": [
        {
          "file": "sample_data/data/orders.json",
          "issues": [
            {
              "line": 1,
              "type": "DBRef",
              "description": "unsupported by Firestore"
            },
            {
              "line": 2,
              "type": "Symbol",
              "description": "unsupported by Firestore"
            }
          ]
        }
      ]
    },
    "operator": {
      "unsupported_operators": [
        {
          "operator": "$text",
          "occurrences": 1,
          "locations": [
            {
              "file": "sample_data/app/sample_mongodb_queries.js",
              "line": 16
            }
          ]
        }
      ]
    },
    "index": {
      "incompatible_indexes": [
        {
          "type": "Hashed",
          "count": 1,
          "indexes": [
            "test.users.userId_hashed"
          ]
        }
      ]
    }
  }
}
```

> **Note:** Unlike the text format which only shows details with the `--verbose` flag, the JSON format always includes the complete details section in a structured format. This makes it ideal for programmatic processing where you need all the data in a machine-readable format.

## How It Works

The assessment suite works by:

1. Parsing command-line arguments to determine which assessments to run
2. Running each selected assessment tool with the appropriate parameters
   - For operator checker: Uses `{dir}/app/` if it exists, otherwise **skips** with a warning
   - For datatype checker: Uses `{dir}/data/` if it exists, otherwise **skips** with a warning
   - For index checker: Uses `{dir}/` directly (scans for `*.metadata.json` files)
3. Capturing and processing the output from each tool
4. Generating a consolidated report in the specified format

This subdirectory routing helps organize different types of files and ensures each checker only scans relevant files. Each individual checker can still be used independently for more focused assessments.

## Limitations

- The suite inherits the limitations of each individual checker
- JSON output format may have issues with complex nested content in the details section
- The suite assumes all checker scripts are in the same directory
- If required subdirectories (`app/` or `data/`) don't exist, the corresponding assessment is skipped with a warning

## License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
