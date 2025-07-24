# MongoDB Data Collector for Firestore Migration Assessment

This tool collects sample data, index definitions, and metadata from a MongoDB instance to support the Firestore Migration Assessment process. It's designed to gather all the necessary information with minimal configuration.

## Overview

The MongoDB Data Collector performs three main tasks:

1. **Sample Data Collection**: Extracts sample documents from each collection in your MongoDB databases
2. **Index Definition Collection**: Captures all index definitions across all collections
3. **Metadata Collection**: Gathers comprehensive metadata about your MongoDB instance, databases, and collections

All collected data is saved to a directory structure that's compatible with the Firestore Migration Assessment Suite.

## Requirements

- Bash shell
- MongoDB Shell (mongosh) installed and in your PATH
- Read access to your MongoDB instance
- Appropriate MongoDB privileges (see below)

## Required MongoDB Privileges

The collector script requires specific MongoDB privileges to function properly:

| Operation | Required Privileges | Description |
|-----------|---------------------|-------------|
| Sample data collection | `read` | Ability to read documents from collections |
| Index definitions | `listIndexes` | Ability to list indexes on collections |
| Metadata collection | `listDatabases`, `dbStats`, `serverStatus`, `collStats` | Ability to list databases and get statistics |

### Recommended Role

The simplest approach is to use the built-in `readAnyDatabase` role, which provides all the necessary privileges:

```javascript
// Create a user with readAnyDatabase role
db.createUser({
  user: "migrationUser",
  pwd: "password",
  roles: [ { role: "readAnyDatabase", db: "admin" } ]
})
```

### Minimal Custom Role

If you need to create a custom role with minimal permissions:

```javascript
// Create a custom role with only the required privileges
db.createRole({
  role: "firestoreMigrationAssessment",
  privileges: [
    { resource: { cluster: true }, actions: [ "listDatabases", "serverStatus" ] },
    { resource: { db: "", collection: "" }, actions: [ "find", "listCollections", "listIndexes", "dbStats", "collStats" ] }
  ],
  roles: []
})

// Assign the custom role to a user
db.createUser({
  user: "migrationUser",
  pwd: "password",
  roles: [ { role: "firestoreMigrationAssessment", db: "admin" } ]
})
```

## Installation

1. Make sure the script is executable:

```bash
chmod +x mongodb_collector.sh
```

2. Ensure mongosh is installed and in your PATH:

```bash
mongosh --version
```

## Usage

```
Usage: ./mongodb_collector.sh [OPTIONS]

Options:
  --uri URI                MongoDB connection URI with authentication
  --output-dir DIR         Directory to store output files (default: sample_data)
  --verbose                Show detailed connection information
  --help                   Display this help message
```

### Basic Usage

```bash
# Collect data from a local MongoDB instance
./mongodb_collector.sh

# Collect data from a remote MongoDB instance with authentication
./mongodb_collector.sh --uri "mongodb://username:password@host:port/database"

# Specify a custom output directory
./mongodb_collector.sh --uri "mongodb://localhost:27017" --output-dir my_mongodb_data

# Show detailed connection information
./mongodb_collector.sh --uri "mongodb://localhost:27017" --verbose
```

## Output Structure

The collector creates the following directory structure:

```
output_dir/
├── data/
│   ├── database1_collection1_sample.json
│   ├── database1_collection2_sample.json
│   ├── database2_collection1_sample.json
│   └── ...
├── indexes.metadata.json
└── mongodb_metadata.json
```

- **data/**: Contains sample documents from each collection in NDJSON format
- **indexes.metadata.json**: Contains all index definitions across all collections
- **mongodb_metadata.json**: Contains comprehensive metadata about your MongoDB instance

## Sample Data Format

Sample data is saved in NDJSON (Newline Delimited JSON) format, with each line containing one document in MongoDB Extended JSON format. This preserves all MongoDB-specific data types.

Example:
```json
{"_id":{"$oid":"5f8d7e9b2b3a4c1d2e3f4a5b"},"name":"John Doe","age":30,"created":{"$date":"2020-10-19T12:34:56.789Z"}}
{"_id":{"$oid":"5f8d7e9b2b3a4c1d2e3f4a5c"},"name":"Jane Smith","age":25,"created":{"$date":"2020-10-19T12:45:00.000Z"}}
```

## Index Definitions Format

Index definitions are saved in a JSON file containing an array of all indexes across all collections, with their complete configuration.

Example:
```json
{
  "metadata": {
    "timestamp": "2023-07-06T12:30:00.000Z",
    "source": "MongoDB"
  },
  "options": {},
  "indexes": [
    {
      "v": 2,
      "key": { "_id": 1 },
      "name": "_id_",
      "ns": "database1.collection1"
    },
    {
      "v": 2,
      "key": { "email": 1 },
      "name": "email_1",
      "unique": true,
      "ns": "database1.users"
    }
  ]
}
```

## Metadata Format

Metadata is saved in a comprehensive JSON file containing detailed information about your MongoDB instance, databases, collections, and indexes.

Example:
```json
{
  "timestamp": "2023-07-06T12:30:00.000Z",
  "mongodb": {
    "version": "6.0.6",
    "buildInfo": { ... },
    "serverStatus": { ... },
    "storageEngine": "wiredTiger"
  },
  "databases": [
    {
      "name": "database1",
      "sizeOnDisk": 1048576,
      "empty": false,
      "collections": [ ... ],
      "stats": { ... },
      "summary": { ... }
    }
  ],
  "summary": {
    "totalDatabases": 1,
    "totalCollections": 5,
    "totalIndexes": 10,
    "totalSize": 5242880,
    "totalDataSize": 3145728,
    "totalStorageSize": 4194304
  }
}
```

## Troubleshooting

### Connection Issues

If you encounter connection issues:

1. Verify that MongoDB is running and accessible
2. Check that the URI is correct
3. Ensure the user has the necessary privileges
4. Try connecting manually with mongosh:
   ```bash
   mongosh "mongodb://username:password@host:port/database"
   ```

### Permission Issues

If you encounter permission issues:

1. Verify that the user has the necessary privileges
2. Try running the script with a user that has the `readAnyDatabase` role
3. Check the MongoDB logs for permission errors

### Empty Output

If the script runs but produces empty output:

1. Verify that your MongoDB instance has databases and collections
2. Check that the user has access to those databases
3. Run with the `--verbose` flag to see more detailed output

## Integration with Firestore Migration Assessment

After collecting the data, you can run the Firestore Migration Assessment Suite on the collected data:

```bash
# Run all assessments on the collected data
./firestore_migration_assessment.sh --run-all --dir sample_data

# Run specific assessments
./firestore_migration_assessment.sh --run-datatype --dir sample_data
./firestore_migration_assessment.sh --run-index --dir sample_data
```

## License

[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
