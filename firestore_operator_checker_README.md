# Firestore MongoDB Operator Compatibility Checker

This tool examines MongoDB log files or source code from MongoDB applications to determine if there are any queries which use operators that are not supported in Firestore. It produces a detailed report of unsupported operators and file names with line numbers for further investigation, helping you assess compatibility when migrating from MongoDB to Firestore.

## Requirements
- Bash shell
- Basic Unix utilities (grep, cut, tr, etc.)

## Installation
Make the script executable:
```
chmod +x firestore_operator_checker.sh
```

## Usage
This tool supports examining compatibility with MongoDB versions 3.6, 4.0, 5.0, 6.0, 7.0, and 8.0. The script has the following arguments:

```
--mongodb-version=VERSION  MongoDB version to check compatibility for (3.6, 4.0, 5.0, 6.0, 7.0, 8.0, all)
--mode=SCAN|CSV|STATS      Operation mode (default: SCAN)
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

The tool has three operation modes:

1. **SCAN**: Scans files for MongoDB operators and checks their compatibility
2. **CSV**: Generates a CSV report of operator compatibility
3. **STATS**: Shows statistics about operator compatibility

### Examples

#### Example 1: Scan Mode
Check for compatibility with MongoDB version 6.0, files from the folder called test, excluding the ones with extension `.txt`:

```
./firestore_operator_checker.sh --mongodb-version=6.0 --mode=scan --dir=test --excluded-extensions=txt
```

Output:
```
Scanning directory: test
Found 5 files to scan
Processing file: test/sample-python-1.py
Processing file: test/mongodb.log
  Found unsupported operator: $facet (MongoDB 6.0)
    Line numbers:
      Line 80: ...
      Line 82: ...
  Found unsupported operator: $bucket (MongoDB 6.0)
    Line numbers:
      Line 80: ...
  Found unsupported operator: $bucketAuto (MongoDB 6.0)
    Line numbers:
      Line 82: ...
...

MongoDB Compatibility Summary
=============================
Processed 5 files, skipped 0 files
Checked compatibility with MongoDB 6.0
Found 4 unsupported operators:

Operator: $bucket (MongoDB 6.0)
Total occurrences: 1
Locations:
  test/mongodb.log (line 80)
...
```

#### Example 2: CSV Mode
Generate a CSV report of operator compatibility for all MongoDB versions:

```
./firestore_operator_checker.sh --mongodb-version=all --mode=csv
```

This will create a file called `mongodb_firestore_compatibility.csv` with the following format:

```
Operator,MongoDB Version,3.6,4.0,5.0,6.0,7.0,8.0
$addFields,3.6,Yes,Yes,Yes,Yes
$bucket,3.6,No,No,No,No
...
```

#### Example 3: Stats Mode
Show statistics about operator compatibility for MongoDB version 5.0:

```
./firestore_operator_checker.sh --mongodb-version=5.0 --mode=stats
```

Output:
```
MongoDB Compatibility Statistics
================================

MongoDB 5.0 Compatibility:
-----------------------------
Total operators: 21
Supported operators: 14 (66%)
Unsupported operators: 7 (34%)

Unsupported operators in MongoDB 5.0:
  $facet
  $bucket
  $bucketAuto
  $sortByCount
  $graphLookup
  $setWindowFields
  $dateTrunc
```

#### Example 4: Stats Mode for All Versions
Show statistics about operator compatibility for all MongoDB versions:

```
./firestore_operator_checker.sh --mongodb-version=all --mode=stats
```

This will show statistics for each MongoDB version and a comparison across versions.

## Notes
- All files scanned by this utility are opened read-only and scanned in memory.
- For large files, make sure you have enough available RAM or split the files accordingly.
- With the exception of operators used, there is no logging of the file contents.
- Using the `--dir` or `--directory` argument will scan all the files, including subdirectories which will be scanned recursively.
- Temporary files are created in `/tmp` and are automatically cleaned up when the script exits.

## Customizing Operator Compatibility
The operator compatibility data is defined at the beginning of the script. If you need to add or modify operators, edit the `cat > /tmp/mongodb_compat_data.txt << 'EOF'` section of the script.

### MongoDB 7.0 and 8.0 Operators

The tool includes support for newer MongoDB operators introduced in versions 7.0 and 8.0:

#### MongoDB 7.0 Operators:
- $documents
- $densify
- $fill
- $search
- $vectorSearch
- $searchMeta
- $range

#### MongoDB 8.0 Operators:
- $merge (enhanced)
- $unionWith (enhanced)
- $changeStream
- $listSessions
- $currentOp

## Troubleshooting
- If you encounter permission issues, make sure the script is executable (`chmod +x firestore_operator_checker.sh`).
- If the script fails to find operators, check that your files contain MongoDB operators in the expected format (e.g., `$match`, `$group`, etc.).
- For any other issues, check the error messages and ensure your environment meets the requirements.
