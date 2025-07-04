/**
 * MongoDB Metadata Collection Script
 * 
 * This script collects comprehensive metadata from a MongoDB instance including:
 * - MongoDB version and server information
 * - Database information (name, storage size, collection count)
 * - Collection information (name, size, document count, indexes)
 * - Index information with detailed properties
 * 
 * Usage from command line:
 * mongosh --quiet --file export_metadata.js > mongodb_metadata.json
 * 
 * With authentication:
 * mongosh --quiet --eval "const URI='mongodb://username:password@host:port/database'" --file export_metadata.js > mongodb_metadata.json
 */

// Initialize the result object
var result = {
    timestamp: new Date().toISOString(),
    mongodb: {
        version: null,
        buildInfo: {},
        serverStatus: {},
        storageEngine: null
    },
    databases: [],
    summary: {
        totalDatabases: 0,
        totalCollections: 0,
        totalIndexes: 0,
        totalSize: 0,
        totalDataSize: 0,
        totalStorageSize: 0
    }
};

// Initialize counters
var totalDatabases = 0;
var totalCollections = 0;
var totalIndexes = 0;
var totalSize = 0;
var totalDataSize = 0;
var totalStorageSize = 0;

// Check if a URI was provided via command line
// The URI can be passed using --eval "const URI='mongodb://username:password@host:port/database'"
var mongoClient;
var mongoDb;

try {
    if (typeof URI !== 'undefined' && URI) {
        print(`Connecting to MongoDB using provided URI...`);
        // Use the Mongo constructor to create a new client with the URI
        mongoClient = new Mongo(URI);
        // Get the database from the client
        mongoDb = mongoClient.getDB("");
        print(`Connected successfully using URI`);
    } else {
        // Use the default connection
        print(`Using default MongoDB connection...`);
        mongoDb = db;
    }
} catch (err) {
    print(`Error connecting to MongoDB: ${err.message}`);
    // Exit with error
    quit(1);
}

// Get MongoDB version and build information
try {
    result.mongodb.version = mongoDb.version();
    
    // Get build info
    var buildInfo = mongoDb.adminCommand("buildInfo");
    result.mongodb.buildInfo = {
        version: buildInfo.version,
        gitVersion: buildInfo.gitVersion,
        allocator: buildInfo.allocator,
        javascriptEngine: buildInfo.javascriptEngine,
        sysInfo: buildInfo.sysInfo,
        bits: buildInfo.bits,
        maxBsonObjectSize: buildInfo.maxBsonObjectSize
    };
    
    // Get server status for storage engine info
    var serverStatus = mongoDb.adminCommand("serverStatus");
    result.mongodb.serverStatus = {
        host: serverStatus.host,
        version: serverStatus.version,
        process: serverStatus.process,
        pid: serverStatus.pid,
        uptime: serverStatus.uptime,
        uptimeMillis: serverStatus.uptimeMillis,
        uptimeEstimate: serverStatus.uptimeEstimate,
        localTime: serverStatus.localTime
    };
    
    // Get storage engine information
    if (serverStatus.storageEngine) {
        result.mongodb.storageEngine = serverStatus.storageEngine.name;
    }
    
    print(`MongoDB version: ${result.mongodb.version}`);
    print(`Storage engine: ${result.mongodb.storageEngine}`);
} catch (err) {
    print(`Warning: Could not retrieve MongoDB version/build info: ${err.message}`);
}

// Get all databases (excluding admin, local, and config)
var dbs = mongoDb.adminCommand('listDatabases').databases
    .filter(function(d) {
        return !['admin', 'local', 'config'].includes(d.name);
    });

totalDatabases = dbs.length;
print(`Found ${totalDatabases} user databases`);

// Process each database
dbs.forEach(function(dbInfo) {
    var dbName = dbInfo.name;
    print(`Processing database: ${dbName}`);
    
    // Switch to this database
    var currentDb = mongoDb.getSiblingDB(dbName);
    
    // Initialize database object
    var dbResult = {
        name: dbName,
        sizeOnDisk: dbInfo.sizeOnDisk || 0,
        empty: dbInfo.empty || false,
        collections: [],
        stats: {},
        summary: {
            totalCollections: 0,
            totalIndexes: 0,
            totalSize: 0,
            totalDataSize: 0,
            totalStorageSize: 0,
            totalDocuments: 0
        }
    };
    
    // Get database stats
    try {
        var dbStats = currentDb.stats();
        dbResult.stats = {
            collections: dbStats.collections,
            views: dbStats.views,
            objects: dbStats.objects,
            avgObjSize: dbStats.avgObjSize,
            dataSize: dbStats.dataSize,
            storageSize: dbStats.storageSize,
            indexes: dbStats.indexes,
            indexSize: dbStats.indexSize,
            totalSize: dbStats.totalSize,
            scaleFactor: dbStats.scaleFactor
        };
        
        // Add to global totals
        totalSize += dbStats.totalSize || 0;
        totalDataSize += dbStats.dataSize || 0;
        totalStorageSize += dbStats.storageSize || 0;
        
    } catch (err) {
        print(`Warning: Could not get stats for database ${dbName}: ${err.message}`);
    }
    
    // Get all collections (excluding system collections)
    var collections = currentDb.getCollectionNames()
        .filter(function(c) {
            return !c.startsWith("system.");
        });
    
    dbResult.summary.totalCollections = collections.length;
    totalCollections += collections.length;
    
    // Process each collection
    collections.forEach(function(collName) {
        print(`  Processing collection: ${dbName}.${collName}`);
        
        // Initialize collection object
        var collResult = {
            name: collName,
            namespace: dbName + "." + collName,
            stats: {},
            indexes: [],
            summary: {
                totalIndexes: 0,
                totalDocuments: 0,
                avgObjSize: 0,
                totalSize: 0,
                storageSize: 0,
                indexSize: 0
            }
        };
        
        // Get collection stats
        try {
            var collStats = currentDb[collName].stats();
            collResult.stats = {
                size: collStats.size,
                count: collStats.count,
                avgObjSize: collStats.avgObjSize,
                storageSize: collStats.storageSize,
                capped: collStats.capped,
                nindexes: collStats.nindexes,
                totalIndexSize: collStats.totalIndexSize,
                indexSizes: collStats.indexSizes
            };
            
            // Update collection summary
            collResult.summary.totalDocuments = collStats.count || 0;
            collResult.summary.avgObjSize = collStats.avgObjSize || 0;
            collResult.summary.totalSize = collStats.size || 0;
            collResult.summary.storageSize = collStats.storageSize || 0;
            collResult.summary.indexSize = collStats.totalIndexSize || 0;
            
            // Update database summary
            dbResult.summary.totalDocuments += collStats.count || 0;
            dbResult.summary.totalSize += collStats.size || 0;
            dbResult.summary.totalStorageSize += collStats.storageSize || 0;
            
        } catch (err) {
            print(`    Warning: Could not get stats for collection ${dbName}.${collName}: ${err.message}`);
        }
        
        // Get indexes for this collection
        try {
            var indexes = currentDb[collName].getIndexes();
            collResult.summary.totalIndexes = indexes.length;
            totalIndexes += indexes.length;
            dbResult.summary.totalIndexes += indexes.length;
            
            // Process each index
            indexes.forEach(function(index) {
                var indexResult = {
                    name: index.name,
                    key: index.key,
                    unique: index.unique || false,
                    sparse: index.sparse || false,
                    background: index.background || false,
                    partialFilterExpression: index.partialFilterExpression || null,
                    expireAfterSeconds: index.expireAfterSeconds || null,
                    textIndexVersion: index.textIndexVersion || null,
                    weights: index.weights || null,
                    default_language: index.default_language || null,
                    language_override: index.language_override || null,
                    v: index.v
                };
                
                // Add namespace if not present
                if (!index.ns) {
                    indexResult.ns = dbName + "." + collName;
                } else {
                    indexResult.ns = index.ns;
                }
                
                collResult.indexes.push(indexResult);
            });
            
            print(`    Found ${indexes.length} indexes`);
        } catch (err) {
            print(`    Warning: Could not get indexes for collection ${dbName}.${collName}: ${err.message}`);
        }
        
        dbResult.collections.push(collResult);
    });
    
    result.databases.push(dbResult);
    print(`Completed database ${dbName}: ${collections.length} collections, ${dbResult.summary.totalIndexes} indexes`);
});

// Update summary
result.summary.totalDatabases = totalDatabases;
result.summary.totalCollections = totalCollections;
result.summary.totalIndexes = totalIndexes;
result.summary.totalSize = totalSize;
result.summary.totalDataSize = totalDataSize;
result.summary.totalStorageSize = totalStorageSize;

// Output the result as JSON
print(JSON.stringify(result, null, 2));

// Print summary to stderr so it doesn't interfere with JSON output
print(`\nMetadata Collection Summary:`);
print(`MongoDB version: ${result.mongodb.version}`);
print(`Storage engine: ${result.mongodb.storageEngine}`);
print(`Processed ${totalDatabases} databases`);
print(`Processed ${totalCollections} collections`);
print(`Found ${totalIndexes} total indexes`);
print(`Total size: ${(totalSize / (1024 * 1024)).toFixed(2)} MB`);
print(`Total data size: ${(totalDataSize / (1024 * 1024)).toFixed(2)} MB`);
print(`Total storage size: ${(totalStorageSize / (1024 * 1024)).toFixed(2)} MB`);

// Print per-database summary
print(`\nDatabase Summary:`);
result.databases.forEach(function(db) {
    var dbSizeMB = (db.stats.totalSize || 0) / (1024 * 1024);
    print(`- ${db.name}: ${db.summary.totalCollections} collections, ${db.summary.totalIndexes} indexes, ${dbSizeMB.toFixed(2)} MB`);
});

// Close the client connection if we created one
if (mongoClient && typeof URI !== 'undefined' && URI) {
    mongoClient.close();
    print("MongoDB connection closed");
}
