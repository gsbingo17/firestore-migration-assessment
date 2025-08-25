# Firestore Operator Compatibility Checker

This tool examines MongoDB code/logs to determine if there are any queries which use operators that are not supported in Firestore. It produces a detailed report of unsupported operators and file names with line numbers for further investigation, helping you assess compatibility when migrating from MongoDB to Firestore.

## Key Features

- **Robust Operator Detection**: Uses improved pattern matching with literal string search for MongoDB operators and regex for commands
- **False Positive Prevention**: Enhanced validation to avoid matching operators within variable names or comments
- **Flexible File Filtering**: Support for including/excluding file extensions and directories
- **Multiple Output Formats**: Scan mode for detailed analysis and CSV reports for compatibility overview
- **Comprehensive Reporting**: Detailed line-by-line analysis with exact file locations and line numbers
- **Enhanced Argument Support**: Supports both `--option=value` and `--option value` syntax formats

## Requirements
- Bash shell
- Basic Unix utilities (grep, cut, tr, etc.)

## Installation
Make the script executable:
```bash
chmod +x firestore_operator_checker.sh
```

## Usage
```
Usage: firestore_operator_checker.sh [OPTIONS]

Options:
  --mode SCAN|CSV            Operation mode (default: SCAN)
  --dir DIR                  Directory to scan
  --file FILE                Specific file to scan
  --excluded-extensions EXT  Comma-separated list of extensions to exclude (default: none)
  --included-extensions EXT  Comma-separated list of extensions to include (default: all)
  --excluded-directories DIR Comma-separated list of directories to exclude (default: none)
  --show-supported           Show supported operators in report
  --help                     Display this help message
```

### Modes

The tool has two operation modes:

1. **SCAN**: Scans files for MongoDB operators and checks their compatibility
2. **CSV**: Generates a CSV report of operator compatibility

### Examples

#### Example 1: Scan Mode - Directory with Filtering
Check for compatibility with files from the folder called test, excluding files with `.txt` extension:

```bash
./firestore_operator_checker.sh --mode=scan --dir=test --excluded-extensions=txt
```

Alternative syntax:
```bash
./firestore_operator_checker.sh --mode scan --dir test --excluded-extensions txt
```

Output:
```
Scanning directory: test
Found 5 files to scan
Processing file: test/sample-python-1.py
Processing file: test/mongodb.log
  Found unsupported operator: $facet
    Line 80: db.orders.aggregate([{$facet: {byStatus: [{$group: {_id: "$status"}}]}}])
  Found unsupported operator: $bucket
    Line 82: db.products.aggregate([{$bucket: {groupBy: "$price", boundaries: [0, 100, 200]}}])
...

Firestore Operator Compatibility Summary:
----------------------------------------------
Processed 5 files, skipped 0 files
Found 3 unsupported operators:

Operator: $facet
Total occurrences: 1
Locations:
  test/mongodb.log (line 80)

Operator: $bucket
Total occurrences: 1
Locations:
  test/mongodb.log (line 82)

Operator: $bucketAuto
Total occurrences: 1
Locations:
  test/mongodb.log (line 85)
```

#### Example 2: Scan Mode - Single File
Scan a specific file:

```bash
./firestore_operator_checker.sh --mode=scan --file=app/queries.js
```

#### Example 3: Scan Mode - Include Specific Extensions
Scan only JavaScript and Python files:

```bash
./firestore_operator_checker.sh --mode=scan --dir=./src --included-extensions=js,py
```

#### Example 4: Scan Mode - Exclude Directories
Scan excluding test and node_modules directories:

```bash
./firestore_operator_checker.sh --mode=scan --dir=./project --excluded-directories=test,node_modules
```

#### Example 5: Show Supported Operators
Include supported operators in the report:

```bash
./firestore_operator_checker.sh --mode=scan --dir=./src --show-supported
```

#### Example 6: CSV Mode
Generate a CSV report of operator compatibility:

```bash
./firestore_operator_checker.sh --mode=csv
```

This will create a file called `firestore_operator_compatibility.csv` with the following format:

```csv
Operator,Firestore Support
$addFields,Yes
$bucket,No
$count,Yes
$facet,No
$group,Yes
```

## How It Works

The script uses a compatibility data file (`mongodb_compat_data.txt`) that contains a list of MongoDB operators and their compatibility status with Firestore. The format is:

```
$operator: Yes|No
command: Yes|No
```

For example:
```
$addFields: Yes
$bucket: No
$count: Yes
$facet: No
$group: Yes
$limit: Yes
$match: Yes
$project: Yes
$sort: Yes
$unwind: Yes
aggregate: Yes
find: Yes
insertOne: Yes
updateMany: Yes
```

### Detection Process

1. **Pattern Matching**: The script uses different search strategies:
   - **MongoDB Operators** (starting with `$`): Uses literal string search for exact matches
   - **MongoDB Commands**: Uses regex with word boundaries to avoid false positives

2. **Validation**: Each match is validated to avoid false positives:
   - Skips commented lines (lines starting with `//`)
   - For operators starting with `$`, ensures they're not part of variable names
   - Verifies the operator context matches the expected pattern

3. **Reporting**: Provides detailed information including:
   - File path and line number for each occurrence
   - Total count of occurrences per operator
   - Summary of all unsupported operators found

## Collecting MongoDB Operation Logs

To effectively analyze MongoDB query patterns, you'll need to capture operation logs that contain the queries executed against your database.

### Configuring Query Logging in MongoDB

#### For Self-Hosted and Local MongoDB Installations:

MongoDB's default configuration only logs queries that exceed a 100ms execution time threshold. To view your current profiling configuration, execute this command in the MongoDB shell:

```javascript
> db.getProfilingStatus()
{
  "was": 0,
  "slowms": 100,
  "sampleRate": 1
}
```

To capture all queries regardless of execution time, modify the slow query threshold to `-1`:

```javascript
> db.setProfilingLevel(0, -1)
```

When you've finished collecting query data, restore the original threshold:

```javascript
> db.setProfilingLevel(0, 100)
```

#### For MongoDB Atlas Deployments:

For cloud-hosted MongoDB instances on Atlas:
- Review the Atlas documentation on [configuring query profiling](https://www.mongodb.com/docs/atlas/tutorial/profile-database/#access-the-query-profiler)
- Follow the instructions for [retrieving log files](https://www.mongodb.com/docs/atlas/mongodb-logs/) from your Atlas cluster

#### Important Considerations:

Query profiling introduces additional system overhead that may impact performance. It's strongly recommended to:
- Perform query logging in development or testing environments rather than production
- Limit the duration of comprehensive logging to minimize performance impact
- Consult the [official MongoDB documentation](https://www.mongodb.com/docs/manual/reference/method/db.setProfilingLevel/) for detailed information about profiling configuration options

## Analyzing Application Source Code

Beyond examining MongoDB logs, this tool can scan application source code to identify MongoDB operators used directly in your codebase. Many applications embed MongoDB queries directly in their source files, using operators for CRUD operations.

### Common MongoDB Operator Patterns in Code

#### JavaScript/Node.js (with MongoDB Driver or Mongoose)
```javascript
// Find with query operators
db.collection('users').find({ 
  age: { $gt: 21, $lt: 65 },
  status: { $in: ['active', 'pending'] },
  $or: [
    { email: { $exists: true } },
    { phone: { $exists: true } }
  ]
});

// Update with update operators
db.collection('products').updateMany(
  { category: "electronics" },
  { 
    $set: { onSale: true },
    $inc: { inventory: -5 },
    $push: { tags: "clearance" }
  }
);

// Aggregation pipeline operators
db.collection('orders').aggregate([
  { $match: { status: "completed" } },
  { $group: { _id: "$customer", total: { $sum: "$amount" } } },
  { $sort: { total: -1 } }
]);
```

#### Python (with PyMongo)
```python
# Find with query operators
users = db.users.find({
    "age": {"$gt": 21, "$lt": 65},
    "status": {"$in": ["active", "pending"]},
    "$or": [
        {"email": {"$exists": True}},
        {"phone": {"$exists": True}}
    ]
})

# Update with update operators
db.products.update_many(
    {"category": "electronics"},
    {
        "$set": {"on_sale": True},
        "$inc": {"inventory": -5},
        "$push": {"tags": "clearance"}
    }
)
```

### Recommended File Types to Scan

When analyzing application code, consider scanning these file types:

- **JavaScript/TypeScript**: `.js`, `.ts`, `.jsx`, `.tsx` (Node.js applications)
- **Python**: `.py` (PyMongo applications)
- **Java**: `.java` (MongoDB Java driver applications)
- **C#**: `.cs` (MongoDB .NET driver applications)
- **Ruby**: `.rb` (MongoDB Ruby driver applications)
- **PHP**: `.php` (MongoDB PHP driver applications)
- **Golang**: `.go` (MongoDB Go driver applications)

### Scanning Tips

- Use the `--included-extensions` option to focus on specific file types
- Use the `--excluded-directories` option to skip test directories or third-party code
- Look for files that import or require MongoDB client libraries
- Pay special attention to data access layers, repositories, or service files

Example command to scan a Node.js application:
```bash
./firestore_operator_checker.sh --mode=scan --dir=./src --included-extensions=js,ts --excluded-directories=node_modules,test
```

## Notes
- All files scanned by this utility are opened read-only and scanned in memory.
- For large files, make sure you have enough available RAM or split the files accordingly.
- With the exception of operators used, there is no logging of the file contents.
- Temporary files are created in `/tmp` and are automatically cleaned up when the script exits.
- The script handles both `--option=value` and `--option value` argument formats for flexibility.

## License
[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
