# Firestore Migration Assessment Suite

This tool combines the three Firestore compatibility checkers (datatype, operator, and index) into a unified assessment suite for evaluating MongoDB to Firestore migration compatibility.

## Overview

The Firestore Migration Assessment Suite provides a comprehensive analysis of potential compatibility issues when migrating from MongoDB to Firestore. It evaluates:

1. **Data Type Compatibility**: Identifies MongoDB data types that are not supported by Firestore
2. **Operator Compatibility**: Identifies MongoDB query operators that are not supported in Firestore
3. **Index Compatibility**: Checks MongoDB index structures for compatibility with Firestore

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
  --log-file FILE           MongoDB log file to analyze for operator compatibility
  --data-file FILE          JSON data file to check for data type compatibility
  --metadata-dir DIR        Directory containing index metadata files
  --mongodb-version VER     MongoDB version to check against (3.6, 4.0, 5.0, 6.0, 7.0, 8.0, all)
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

## Examples

### Run All Assessments on a Directory

```bash
./firestore_migration_assessment.sh --data-file sample_data/data.json --run-datatype --verbose

# Suppress progress messages
./firestore_migration_assessment.sh --run-all --dir /path/to/project --quiet
```

### Run Specific Assessment Types

```bash
# Check operator compatibility with MongoDB 6.0
./firestore_migration_assessment.sh --log-file logs/mongodb.log --run-operator --mongodb-version=6.0

# Check data type compatibility
./firestore_migration_assessment.sh --data-file sample_data/data.json --run-datatype

# Check index compatibility
./firestore_migration_assessment.sh --metadata-dir /path/to/metadata --run-index
```

### Generate JSON Report

```bash
./firestore_migration_assessment.sh --dir /path/to/project --run-all --output-format json --output-file report.json

# Generate JSON report without progress messages
./firestore_migration_assessment.sh --dir /path/to/project --run-all --output-format json --quiet
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

Operator Compatibility (MongoDB 7.0):
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

The JSON format provides structured data that can be processed programmatically:

```json
{
  "summary": {
    "datatype_compatibility": {
      "total_files": 10,
      "files_with_issues": 3,
      "total_issues": 15
    },
    "operator_compatibility": {
      "mongodb_version": "7.0",
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
    "datatype": "[Detailed output from datatype checker]",
    "operator": "[Detailed output from operator checker]",
    "index": "[Detailed output from index checker]"
  }
}
```

## How It Works

The assessment suite works by:

1. Parsing command-line arguments to determine which assessments to run
2. Running each selected assessment tool with the appropriate parameters
3. Capturing and processing the output from each tool
4. Generating a consolidated report in the specified format

Each individual checker can still be used independently for more focused assessments.

## Limitations

- The suite inherits the limitations of each individual checker
- JSON output format may have issues with complex nested content in the details section
- The suite assumes all checker scripts are in the same directory

## License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
