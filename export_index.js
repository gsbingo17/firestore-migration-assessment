/**
 * MongoDB Index Collection Script (JSON-only version)
 * 
 * This script collects index definitions from all databases and collections
 * in a MongoDB instance and outputs them in a flat list format as JSON only.
 * 
 * Usage from command line:
 * mongosh --quiet --file export_index.js > indexes.metadata.json
 * 
 * With authentication:
 * mongosh --quiet --eval "const URI='mongodb://username:password@host:port/database'" --file export_index.js > indexes.metadata.json
 */

// Initialize the result object with metadata and an empty indexes array
var result = {
    metadata: {
        timestamp: new Date().toISOString(),
        source: "MongoDB"
    },
    options: {},
    indexes: []
};

// Check if a URI was provided via command line
// The URI can be passed using --eval "const URI='mongodb://username:password@host:port/database'"
var mongoClient;
var mongoDb;

try {
    if (typeof URI !== 'undefined' && URI) {
        // Use the Mongo constructor to create a new client with the URI
        mongoClient = new Mongo(URI);
        
        // Extract database name from URI or use "admin" as default
        let dbName = "admin";
        if (URI.includes("/")) {
            const uriParts = URI.split("/");
            if (uriParts.length > 3) {
                // Extract database name, removing any query parameters
                const dbPart = uriParts[3].split("?")[0];
                if (dbPart !== "") {
                    dbName = dbPart;
                }
            }
        }
        
        // Get the database from the client
        mongoDb = mongoClient.getDB(dbName);
        print(`Connected to database: ${dbName}`);
    } else {
        // Use the default connection
        mongoDb = db;
    }
} catch (err) {
    print(`Error connecting to MongoDB: ${err.message}`);
    // Exit with error
    quit(1);
}

// Get all databases (excluding admin, local, and config)
var dbs = mongoDb.adminCommand('listDatabases').databases
    .filter(function(d) {
        return !['admin', 'local', 'config'].includes(d.name);
    })
    .map(function(d) {
        return d.name;
    });

// Process each database
dbs.forEach(function(dbName) {
    // Switch to this database
    var currentDb = mongoDb.getSiblingDB(dbName);
    
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

// Close the client connection if we created one
if (mongoClient && typeof URI !== 'undefined' && URI) {
    mongoClient.close();
}
