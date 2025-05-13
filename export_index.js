/**
 * MongoDB Index Collection Script (JSON-only version)
 * 
 * This script collects index definitions from all databases and collections
 * in a MongoDB instance and outputs them in a flat list format as JSON only.
 * 
 * Usage from command line:
 * mongosh --quiet --file export_index.js > indexes_output.json
 */

// Initialize the result object with an empty indexes array
var result = {
    options: {},
    indexes: []
};

// Get all databases (excluding admin, local, and config)
var dbs = db.adminCommand('listDatabases').databases
    .filter(function(d) {
        return !['admin', 'local', 'config'].includes(d.name);
    })
    .map(function(d) {
        return d.name;
    });

// Process each database
dbs.forEach(function(dbName) {
    // Switch to this database
    var currentDb = db.getSiblingDB(dbName);
    
    // Get all collections (excluding system collections)
    var collections = currentDb.getCollectionNames()
        .filter(function(c) {
            return !c.startsWith("system.");
        });
    
    // Process each collection
    collections.forEach(function(collName) {
        // Get indexes for this collection
        var indexes = currentDb[collName].getIndexes();
        
        if (indexes.length === 0) {
            return;
        }
        
        // Add all indexes to the result array
        indexes.forEach(function(index) {
            // Make sure the namespace is set correctly
            if (!index.ns) {
                index.ns = dbName + "." + collName;
            }
            result.indexes.push(index);
        });
    });
});

// Output only the JSON result
print(JSON.stringify(result, null, 2));
