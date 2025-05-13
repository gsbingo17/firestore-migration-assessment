# Firestore JSON Data Type Compatibility Checker

This tool scans JSON files to identify data types that are unsupported by Firestore. It helps identify potential compatibility issues when migrating data from MongoDB to Firestore.

## Requirements

- Bash shell
- jq (JSON processor for Bash)

## Installation

1. Clone the repository or download the script
2. Make the script executable:

```bash
chmod +x firestore_datatype_checker.sh
```

### Installing jq

The script requires jq for JSON processing. You can install it using your package manager:

#### On Ubuntu/Debian:
```bash
sudo apt-get install jq
```

#### On macOS:
```bash
brew install jq
```

#### On CentOS/RHEL:
```bash
sudo yum install jq
```

#### On Windows (with Chocolatey):
```bash
choco install jq
```

## Usage

```
Usage: ./firestore_datatype_checker.sh [options]

Options:
  --dir DIR              Directory to scan recursively for JSON files
  --file FILE            Single JSON file to check
  --verbose              Show detailed information about each issue found
  --help                 Display this help message
```

### Examples

#### Check a single file:
```bash
./firestore_datatype_checker.sh --file path/to/file.json
```

#### Check all JSON files in a directory (recursively):
```bash
./firestore_datatype_checker.sh --dir path/to/directory
```

#### Show detailed information about each issue:
```bash
./firestore_datatype_checker.sh --dir path/to/directory --verbose
```

## Unsupported Data Types

The script checks for the following data types that are unsupported by Firestore:

1. **DBPointer**: MongoDB database pointer
2. **DBRef**: MongoDB database reference
3. **JavaScript**: JavaScript code
4. **JavaScript with scope**: JavaScript code with scope
5. **Symbol**: Symbol type
6. **Undefined**: Undefined value

## Output Format

The script outputs a list of files with compatibility issues, including the line number and type of issue found:

```
Firestore Compatibility Issues:
------------------------------
File: /path/to/file1.json
  - Line 23: DBRef detected (unsupported by Firestore)
  - Line 45: JavaScript code detected (unsupported by Firestore)

File: /path/to/file2.json
  - Line 12: Symbol type detected (unsupported by Firestore)
  - Line 78: Undefined value detected (unsupported by Firestore)

Summary:
  Scanned 10 files
  Found 4 files with compatibility issues
  Detected 7 unsupported data types
```

With the `--verbose` option, additional information is provided:

```
File: /path/to/file1.json
  - Line 23: DBRef detected (unsupported by Firestore)
    Path: ["unsupportedTypes","dbRef"]
    Value: {"$ref":"collection","$id":{"$oid":"507f1f77bcf86cd799439011"},"$db":"database"}
```

## How It Works

The script uses jq to parse and analyze JSON files, looking for specific patterns that indicate unsupported data types. For each file, it:

1. Checks if the file is valid JSON
2. Searches for patterns that match unsupported data types
3. Reports any issues found, including the approximate line number
4. Provides a summary of the scan results

## Limitations

- Line numbers are approximate and may not be exact in complex JSON files
- The script only detects explicit BSON extended JSON syntax (e.g., `{"$code": "..."}`)
- It does not detect implicit JavaScript code embedded as strings

## License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
