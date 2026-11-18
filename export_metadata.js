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

// Use the default connection (mongosh handles the URI connection automatically)
print(`Using MongoDB connection provided by mongosh...`);
var mongoDb = db;

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
    
    // Helper to safely convert MongoDB BSON Long / NumberLong / numeric values to JS numbers
    function toNum(val) {
        if (val === null || val === undefined) return 0;
        if (typeof val === "number") return val;
        if (typeof val === "bigint") return Number(val);
        if (typeof val.toNumber === "function") return val.toNumber();
        if (typeof val === "object" && typeof val.low === "number" && typeof val.high === "number") {
            var unsigned = Boolean(val.unsigned);
            var low = val.low >>> 0;
            var high = unsigned ? (val.high >>> 0) : val.high;
            return high * 4294967296 + low;
        }
        var parsed = Number(val);
        return isNaN(parsed) ? 0 : parsed;
    }

    // Get server status for storage engine, workload, and WiredTiger cache metrics
    var serverStatus = mongoDb.adminCommand("serverStatus");
    var uptimeSeconds = Math.max(1, toNum(serverStatus.uptime));
    var uptimeDays = uptimeSeconds / 86400;

    result.mongodb.serverStatus = {
        host: serverStatus.host,
        version: serverStatus.version,
        process: serverStatus.process,
        pid: serverStatus.pid,
        uptime: uptimeSeconds,
        uptimeMillis: serverStatus.uptimeMillis,
        uptimeEstimate: serverStatus.uptimeEstimate,
        localTime: serverStatus.localTime
    };
    
    // Get storage engine information
    if (serverStatus.storageEngine) {
        result.mongodb.storageEngine = serverStatus.storageEngine.name;
    }

    // Extract cumulative & daily-prorated document/query execution metrics
    var docMetrics = (serverStatus.metrics && serverStatus.metrics.document) ? serverStatus.metrics.document : {};
    var qeMetrics = (serverStatus.metrics && serverStatus.metrics.queryExecutor) ? serverStatus.metrics.queryExecutor : {};
    var opMetrics = (serverStatus.metrics && serverStatus.metrics.operation) ? serverStatus.metrics.operation : {};

    var docsReturnedTotal = toNum(docMetrics.returned);
    var docsExaminedTotal = toNum(qeMetrics.scannedObjects);
    var keysExaminedTotal = toNum(qeMetrics.scanned);
    var insertsTotal = toNum(docMetrics.inserted);
    var updatesTotal = toNum(docMetrics.updated);
    var deletesTotal = toNum(docMetrics.deleted);
    var writesTotal = insertsTotal + updatesTotal + deletesTotal;
    var scanAndOrderTotal = toNum(opMetrics.scanAndOrder);

    result.mongodb.workloadMetrics = {
        uptimeSeconds: uptimeSeconds,
        uptimeDays: Number(uptimeDays.toFixed(4)),
        totals: {
            docsExamined: docsExaminedTotal,
            docsReturned: docsReturnedTotal,
            keysExamined: keysExaminedTotal,
            inserts: insertsTotal,
            updates: updatesTotal,
            deletes: deletesTotal,
            writes: writesTotal,
            scanAndOrder: scanAndOrderTotal
        },
        dailyAverage: {
            docsExaminedPerDay: Number((docsExaminedTotal / uptimeDays).toFixed(2)),
            docsReturnedPerDay: Number((docsReturnedTotal / uptimeDays).toFixed(2)),
            keysExaminedPerDay: Number((keysExaminedTotal / uptimeDays).toFixed(2)),
            insertsPerDay: Number((insertsTotal / uptimeDays).toFixed(2)),
            updatesPerDay: Number((updatesTotal / uptimeDays).toFixed(2)),
            deletesPerDay: Number((deletesTotal / uptimeDays).toFixed(2)),
            writesPerDay: Number((writesTotal / uptimeDays).toFixed(2)),
            scanAndOrderPerDay: Number((scanAndOrderTotal / uptimeDays).toFixed(2))
        }
    };

    // Extract WiredTiger cache statistics (in-memory hits vs. physical disk reads)
    var wtCache = (serverStatus.wiredTiger && serverStatus.wiredTiger.cache) ? serverStatus.wiredTiger.cache : null;
    var cacheRequests = wtCache ? toNum(wtCache["pages requested from the cache"]) : 0;
    var cacheMisses = wtCache ? toNum(wtCache["pages read into cache"]) : 0;
    var cacheHits = Math.max(0, cacheRequests - cacheMisses);
    var cacheHitRatePct = cacheRequests > 0 ? (cacheHits / cacheRequests) * 100 : 0;
    var diskMissRatePct = cacheRequests > 0 ? (cacheMisses / cacheRequests) * 100 : 0;

    result.mongodb.wiredTigerCache = {
        available: Boolean(wtCache),
        cacheRequests: cacheRequests,
        cacheHits: cacheHits,
        cacheMisses: cacheMisses,
        cacheHitRatePct: Number(cacheHitRatePct.toFixed(2)),
        diskMissRatePct: Number(diskMissRatePct.toFixed(2)),
        bytesCurrentlyInCache: wtCache ? toNum(wtCache["bytes currently in the cache"]) : 0,
        maxBytesConfigured: wtCache ? toNum(wtCache["maximum bytes configured"]) : 0,
        trackedDirtyBytes: wtCache ? toNum(wtCache["tracked dirty bytes in the cache"]) : 0
    };

    // Compute TCO Scan-Bloat & In-Memory Cache Diagnostics
    var scanToReturnRatio = docsReturnedTotal > 0 ? (docsExaminedTotal / docsReturnedTotal) : 0;
    var unreturnedDocsPerDay = Math.max(0, (docsExaminedTotal - docsReturnedTotal) / uptimeDays);
    var discardedScanPct = docsExaminedTotal > 0 ? ((docsExaminedTotal - docsReturnedTotal) / docsExaminedTotal) * 100 : 0;
    var isRamMaskedScanBloat = (cacheHitRatePct >= 80.0) && (scanToReturnRatio > 10.0);

    result.tcoDiagnostics = {
        scanToReturnRatio: Number(scanToReturnRatio.toFixed(2)),
        discardedScanPct: Number(discardedScanPct.toFixed(2)),
        unreturnedDocsPerDay: Number(unreturnedDocsPerDay.toFixed(2)),
        cacheHitRatePct: Number(cacheHitRatePct.toFixed(2)),
        diskMissRatePct: Number(diskMissRatePct.toFixed(2)),
        estimatedInMemoryDocsExaminedPerDay: Number(((docsExaminedTotal / uptimeDays) * (cacheHitRatePct / 100)).toFixed(2)),
        estimatedDiskDocsExaminedPerDay: Number(((docsExaminedTotal / uptimeDays) * (diskMissRatePct / 100)).toFixed(2)),
        isRamMaskedScanBloat: isRamMaskedScanBloat,
        status: isRamMaskedScanBloat
            ? "IN_MEMORY_SCAN_BLOAT_WARNING"
            : (scanToReturnRatio > 10.0 ? "HIGH_SCAN_RATIO_WARNING" : "HEALTHY"),
        message: isRamMaskedScanBloat
            ? "WARNING: " + cacheHitRatePct.toFixed(1) + "% of reads are served from WiredTiger RAM while DocsExamined is " +
              scanToReturnRatio.toFixed(1) + "x DocsReturned (" + discardedScanPct.toFixed(1) + "% discarded scans). " +
              "Because scannedObjects sits above the RAM cache, plugging raw DocsExamined into an operation-metered Firestore TCO calculator " +
              "will artificially bloat read TCO multiple times. Normalize scan ratio via composite index tuning before sizing."
            : "Read cache profile and DocsExamined-to-DocsReturned ratio are within normal sizing bounds."
    };
    
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

// Connection is managed by mongosh automatically
