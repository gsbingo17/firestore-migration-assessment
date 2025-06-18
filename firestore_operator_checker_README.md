# Firestore Operator Compatibility Checker

This tool examines MongoDB code/logs to determine if there are any queries which use operators that are not supported in Firestore. It produces a detailed report of unsupported operators and file names with line numbers for further investigation, helping you assess compatibility when migrating from MongoDB to Firestore.

## Key Features

- **Context-Aware Detection**: Recognizes that some operators behave differently in different contexts:
  - `$sort:stage` (aggregation pipeline) vs `$sort:update` (update operations)
  - `$push:accumulator` (aggregation) vs `$push:update` (update operations)
  - `$slice:projection` vs `$slice:update`
- **Special Operator Handling**: Handles complex operators like positional operators (`$[]`, `$[<identifier>]`)
- **Multiple Output Formats**: Scan mode and CSV reports

## Requirements
- Bash shell
- Basic Unix utilities (grep, cut, tr, etc.)

## Installation
Make the script executable:
```
chmod +x firestore_operator_checker.sh
```

## Usage
```
Usage: firestore_operator_checker.sh [OPTIONS]

Options:
  --mode=SCAN|CSV            Operation mode (default: SCAN)
  --dir=DIR                  Directory to scan (alias for --directory)
  --directory=DIR            Directory to scan
  --file=FILE                Specific file to scan
  --excluded-extensions=EXT  Comma-separated list of extensions to exclude (default: none)
  --included-extensions=EXT  Comma-separated list of extensions to include (default: all)
  --excluded-directories=DIR Comma-separated list of directories to exclude (default: none)
  --show-supported           Show supported operators in report
  --help                     Display this help message
```

### Modes

The tool has two operation modes:

1. **SCAN**: Scans files for MongoDB operators and checks their compatibility
2. **CSV**: Generates a CSV report of operator compatibility

### Examples

#### Example 1: Scan Mode
Check for compatibility with files from the folder called test, excluding the ones with extension `.txt`:

```
./firestore_operator_checker.sh --mode=scan --dir=test --excluded-extensions=txt
```

Output:
```
Scanning directory: test
Found 5 files to scan
Processing file: test/sample-python-1.py
Processing file: test/mongodb.log
  Found unsupported operator: $facet
    Line numbers:
      Line 80: ...
      Line 82: ...
  Found unsupported operator: $bucket
    Line numbers:
      Line 80: ...
  Found unsupported operator: $bucketAuto
    Line numbers:
      Line 82: ...
...

Firestore Operator Compatibility Summary:
----------------------------------------------
Processed 5 files, skipped 0 files
Found 4 unsupported operators:

Operator: $bucket
Total occurrences: 1
Locations:
  test/mongodb.log (line 80)
...
```

#### Example 2: CSV Mode
Generate a CSV report of operator compatibility:

```
./firestore_operator_checker.sh --mode=csv
```

This will create a file called `firestore_operator_compatibility.csv` with the following format:

```
Operator,Firestore Support
$addFields,Yes
$bucket,No
...
```

## How It Works

The script uses a compatibility data file (`mongodb_compat_data.txt`) that contains a list of MongoDB operators and their compatibility status with Firestore. The format is:

```
$operator[:context]: Yes|No
```

For example:
```
$sort:stage: Yes
$sort:update: No
$push:accumulator: Yes
$push:update: Yes
```

The script scans files for MongoDB operators and checks their compatibility status. It also performs context-aware detection to determine if an operator is used in a supported context.

## Notes
- All files scanned by this utility are opened read-only and scanned in memory.
- For large files, make sure you have enough available RAM or split the files accordingly.
- With the exception of operators used, there is no logging of the file contents.
- Using the `--dir` or `--directory` argument will scan all the files, including subdirectories which will be scanned recursively.
- Temporary files are created in `/tmp` and are automatically cleaned up when the script exits.

## License
[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
