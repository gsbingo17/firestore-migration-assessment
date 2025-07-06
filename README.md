# Firestore Migration Assessment Suite

This tool combines the three Firestore compatibility checkers (datatype, operator, and index) into a unified assessment suite for evaluating MongoDB to Firestore migration compatibility.

## Overview

The Firestore Migration Assessment Suite provides a comprehensive analysis of potential compatibility issues when migrating from MongoDB to Firestore. It evaluates:

1. **Data Type Compatibility**: Identifies MongoDB data types that are not supported by Firestore
2. **Operator Compatibility**: Identifies MongoDB query operators that are not supported in Firestore
3. **Index Compatibility**: Checks MongoDB index structures for compatibility with Firestore

## Directory Structure and Default Behavior

The assessment suite uses a smart subdirectory routing system to organize different types of files:

```
your_project/
├── app/                    # Application code for operator checking
├── data/                   # JSON files for datatype checking
├── indexes.metadata.json   # Index definitions for index checking
└── mongodb_metadata.json   # Comprehensive metadata for MongoDB instance
```

When you specify a directory with the `--dir` parameter, the assessment suite automatically:

- Uses the `app` subdirectory for operator checking (if it exists)
- Uses the `data` subdirectory for datatype checking (if it exists)
- Uses the main directory for index checking

This organization helps each checker focus on relevant files and reduces scanning overlap. If a subdirectory doesn't exist, the checker falls back to using the main directory.

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

### Run All Assessments on a Directory

```bash
# Recommended approach: Use subdirectory structure with single --dir parameter
./firestore_migration_assessment.sh --run-all --dir sample_data
# - Operator checker scans: sample_data/app (if exists) or sample_data
# - Datatype checker scans: sample_data/data (if exists) or sample_data
# - Index checker scans: sample_data

# Generate a report with detailed information
./firestore_migration_assessment.sh --run-all --dir sample_data --verbose

# Suppress progress messages
./firestore_migration_assessment.sh --run-all --dir sample_data --quiet
```

### Collect Sample Data with Authentication

```bash
# Collect sample data from an authenticated MongoDB instance
./mongodb_collector.sh --uri "mongodb://username:password@host:port/database"

# Then run assessment on the collected data
./firestore_migration_assessment.sh --run-all --dir sample_data
```

### Run Specific Assessment Types

#### Directory-Based Assessment

```bash
# Use subdirectory structure with single --dir parameter
./firestore_migration_assessment.sh --run-operator --dir sample_data
# (This will scan sample_data/app if it exists)

./firestore_migration_assessment.sh --run-datatype --dir sample_data
# (This will scan sample_data/data if it exists)

./firestore_migration_assessment.sh --run-index --dir sample_data
# (This will scan sample_data for metadata files)
```

#### File-Based Assessment

```bash
# Check specific files with the unified --file parameter
./firestore_migration_assessment.sh --file sample_data/data/sample.json --run-datatype
./firestore_migration_assessment.sh --file logs/mongodb.log --run-operator
./firestore_migration_assessment.sh --file sample_data/indexes.metadata.json --run-index

# Run multiple assessment types on a single file
./firestore_migration_assessment.sh --file sample_data/data/sample.json --run-all
```

### Generate JSON Report

```bash
./firestore_migration_assessment.sh --dir /path/to/project --run-all --output-format json --output-file report.json

# Generate JSON report without progress messages
./firestore_migration_assessment.sh --dir /path/to/project --run-all --output-format json --quiet
```

### Organizing Files for Optimal Scanning

For best results, organize your files according to the expected directory structure:

```bash
# Create the recommended directory structure
mkdir -p sample_data/app sample_data/data

# Place application code in the app directory
cp -r your-mongodb-app/* sample_data/app/

# Place JSON data files in the data directory
cp *.json sample_data/data/

# Place index definitions and MongoDB metadata in the main directory
cp indexes.metadata.json mongodb_metadata.json sample_data/

# Run the assessment
./firestore_migration_assessment.sh --run-all --dir sample_data
```

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
          "type": "2dsphere",
          "count": 1,
          "indexes": [
            "test.collection.location_2dsphere"
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
   - For operator checker: Uses `{dir}/app` if it exists, otherwise uses `{dir}`
   - For datatype checker: Uses `{dir}/data` if it exists, otherwise uses `{dir}`
   - For index checker: Uses `{dir}` directly
3. Capturing and processing the output from each tool
4. Generating a consolidated report in the specified format

This subdirectory routing helps organize different types of files and ensures each checker only scans relevant files. Each individual checker can still be used independently for more focused assessments.

## Limitations

- The suite inherits the limitations of each individual checker
- JSON output format may have issues with complex nested content in the details section
- The suite assumes all checker scripts are in the same directory
- If subdirectories don't exist, checkers fall back to scanning the main directory, which may include irrelevant files

## License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
