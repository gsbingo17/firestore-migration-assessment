# Firestore Index Compatibility Checker

This tool checks MongoDB index metadata for compatibility with Firestore. It helps identify potential compatibility issues when migrating from MongoDB to Firestore by analyzing index structures and configurations.

## Requirements
- Bash shell
- jq (JSON processor for Bash)

## Installation
Make the script executable:

```bash
chmod +x index_compat_checker.sh
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

## Obtaining Index Schema for Assessment

Before using this tool, you need to obtain the index metadata from your MongoDB or DocumentDB instance. Here are several methods to get the index schema:

### Method 1: Using mongodump

The simplest way to get index metadata is to use the `mongodump` utility:

```bash
# For MongoDB
mongodump --uri 'mongodb://username:password@hostname:port/database' --out dump_dir
```

This will create a directory structure with metadata files for each collection:

```
dump_dir/
  ├── database1/
  │   ├── collection1.bson         # Collection data
  │   ├── collection1.metadata.json # Index metadata
  │   └── collection2.metadata.json
  └── database2/
      └── collection3.metadata.json
```

### Method 2: Using the Export Index Script

You can use the provided `export_index.js` script to export all indexes from your MongoDB instance in a format compatible with the index compatibility checker:

```bash
# Run the script with mongosh
mongosh --quiet --file export_index.js > indexes_output.json
```

This will create a single JSON file containing all indexes from all databases and collections in the following format:

```json
{
  "options": {},
  "indexes": [
    {
      "v": 2,
      "key": {"_id": 1},
      "name": "_id_",
      "ns": "database.collection"
    },
    {
      "v": 2,
      "key": {"email": 1},
      "name": "email_1",
      "unique": true,
      "ns": "database.users"
    },
    {
      "v": 2,
      "key": {"_fts": "text", "_ftsx": 1},
      "name": "product_text_search_index",
      "ns": "database.products"
    }
    // ... all indexes from all collections and databases
  ]
}
```

The script automatically:
- Connects to your MongoDB instance
- Iterates through all databases (excluding admin, local, and config)
- Collects indexes from all collections (excluding system collections)
- Ensures each index has the correct namespace information
- Outputs a single JSON file that can be directly used with the compatibility checker

To use this script with authentication:

```bash
# With username/password authentication
mongosh --quiet --host hostname --port port -u username -p password --authenticationDatabase admin --file export_index.js > indexes_output.meta.data.json

# With connection string
mongosh --quiet "mongodb://username:password@hostname:port/?authSource=admin" --file export_index.js > indexes_output.metadata.json
```

Then analyze the exported indexes with the compatibility checker:

```bash
./index_compat_checker.sh --file indexes_output.json --summary
```

### Method 3: Manual Export

You can also manually export index information using the MongoDB shell:

```javascript
// Connect to your MongoDB instance
mongo --host hostname --port port -u username -p password --authenticationDatabase admin

// Switch to your database
use your_database

// Get all collections
db.getCollectionNames().forEach(function(collection) {
  // Get indexes for each collection
  var indexes = db[collection].getIndexes();
  
  // Print or save the indexes
  print("Collection: " + collection);
  printjson(indexes);
});
```

Then save the output to a file with the proper JSON format:

```json
{
  "options": {},
  "indexes": [
    {
      "v": 2,
      "key": {"_id": 1},
      "name": "_id_",
      "ns": "database.collection"
    },
    ...
  ]
}
```

### Method 4: Using MongoDB Compass

1. Connect to your MongoDB instance using MongoDB Compass
2. Navigate to your database and collection
3. Go to the "Indexes" tab
4. Export the indexes to a JSON file

### Index Metadata Format

The metadata files should follow this JSON structure:

```json
{
  "options": {},  // Collection options
  "indexes": [    // Array of index definitions
    {
      "v": 2,                     // Index version
      "key": {"_id": 1},          // Index key specification
      "name": "_id_",             // Index name
      "ns": "database.collection" // Namespace (database.collection)
    },
    {
      "v": 2,
      "key": {"field1": 1, "field2": -1},  // Compound index
      "name": "field1_1_field2_-1",
      "ns": "database.collection"
    }
  ]
}
```

## Usage
The compatibility checker accepts the following arguments:

```
--debug                Output debugging information
--dir DIR              Directory containing metadata files to check
--file FILE            Single metadata file to check
--show-issues          Show detailed compatibility issues
--show-compatible      Show compatible indexes only
--summary              Show a summary of compatibility statistics
--quiet                Suppress progress messages
```

### Examples

#### Check compatibility and show a summary:
```bash
./index_compat_checker.sh --dir /path/to/metadata --summary

# Or with a single file
./index_compat_checker.sh --file indexes_output.json --summary
```

Output:
```
Index Compatibility Summary:
---------------------------
Total indexes: 19
Compatible indexes: 13 (68.4%)
Incompatible indexes: 6 (31.6%)

Unique indexes found: 2
  Affected indexes:
    * test.users.email_1
    * test.users.lastName_1

Text indexes found: 1
  Affected indexes:
    * test.products.product_text_search_index

TTL indexes found: 1
  Affected indexes:
    * test.log_entries.log_entry_ttl_index

Partial indexes found: 1
  Affected indexes:
    * test.users.active_users_email_index

Unsupported index types found:
  - hashed
    Affected indexes:
      * test.users.userId_hashed
```

#### Show detailed compatibility issues:
```bash
./index_compat_checker.sh --dir /path/to/metadata --show-issues
```

Output:
```json
{
    "database_name": {
        "collection_name": {
            "index_name": {
                "unsupported_index_types": "2d"
            },
            "another_index_name": {
                "unsupported_index_options": [
                    "collation"
                ]
            }
        }
    }
}
```

#### Show only compatible indexes:
```bash
./index_compat_checker.sh --dir /path/to/metadata --show-compatible
```

Output:
```json
{
    "database_name": {
        "collection_name": {
            "filepath": "/path/to/metadata/collection.metadata.json",
            "indexes": {
                "_id_": {
                    "key": {
                        "_id": 1
                    },
                    "ns": "database_name.collection_name",
                    "v": 2
                },
                "field1_1": {
                    "key": {
                        "field1": 1
                    },
                    "ns": "database_name.collection_name",
                    "v": 2
                }
            },
            "options": {}
        }
    }
}
```

## Compatibility Checks

The tool checks for the following compatibility issues when migrating from MongoDB to Firestore:

1. **Unsupported Index Types**:
   - 2d (geospatial)
   - 2dsphere
   - hashed

2. **Unsupported Index Features**:
   - Unique indexes
   - Text indexes
   - TTL indexes (expireAfterSeconds)
   - Partial indexes (partialFilterExpression)

3. **Unsupported Index Options**:
   - storageEngine
   - collation
   - dropDuplicates

4. **Unsupported Collection Options**:
   - capped collections

## Features

The index compatibility checker includes the following features:

1. **Comprehensive Index Analysis**:
   - Detects unsupported index types (2d, 2dsphere, hashed)
   - Identifies unique indexes (indexes with the `unique: true` property)
   - Finds text indexes (indexes with `"_fts": "text"` in the key field)
   - Detects TTL indexes (indexes with the `expireAfterSeconds` field)
   - Identifies partial indexes (indexes with the `partialFilterExpression` field)

2. **Flexible Input Options**:
   - Can process a directory of metadata files with the `--dir` option
   - Can process a single metadata file with the `--file` option
   - Useful for analyzing the output from `export_index.js`

3. **Improved Namespace Handling**:
   - Correctly extracts the namespace from each index
   - Ensures accurate reporting of affected indexes

4. **Detailed Reporting**:
   - Separate sections for each type of unsupported index
   - Lists affected indexes by category
   - Provides summary statistics on compatibility

## Directory Structure

The tool expects a directory structure containing metadata files. The structure can be either:

### Hierarchical Structure (from mongodump)

```
metadata_dir/
  ├── database1/
  │   ├── collection1.metadata.json
  │   └── collection2.metadata.json
  └── database2/
      └── collection3.metadata.json
```

### Flat Structure

```
metadata_dir/
  ├── collection1.metadata.json
  ├── collection2.metadata.json
  └── collection3.metadata.json
```

### Single File

```
indexes_output.json
```

As long as the metadata files contain the correct namespace information (`ns` field), the tool will correctly identify the database and collection names.

## License
[Apache 2.0](http://www.apache.org/licenses/LICENSE-2.0)
