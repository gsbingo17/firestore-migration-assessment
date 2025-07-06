/**
 * MongoDB Sample Data Collection Script
 * 
 * This script collects sample documents from all databases and collections
 * in a MongoDB instance and outputs them as separate JSON files per collection.
 * It's designed to provide sample data for the Firestore data type compatibility checker.
 * 
 * The output format exactly matches mongoexport's NDJSON format:
 * - One document per line (newline-delimited JSON)
 * - BSON types properly represented in extended JSON format
 * - No metadata wrapper (pure document data)
 * 
 * Usage from command line:
 * mkdir -p sample_data
 * mongosh --quiet --file export_sample_data.js
 * 
 * With authentication:
 * mongosh --quiet --eval "const URI='mongodb://username:password@host:port/database'" --file export_sample_data.js
 * 
 * This will create multiple files in the sample_data directory named:
 * {database}_{collection}_sample.json
 */

// Configuration
const SAMPLE_SIZE = 10;           // Number of documents to sample per collection
// Use OUTPUT_DIR from command line if provided, otherwise default to "sample_data"
const OUTPUT_DIR = (typeof OUTPUT_DIR !== 'undefined' && OUTPUT_DIR) ? OUTPUT_DIR : "sample_data"; 

// Initialize counters for summary
let totalDatabases = 0;
let totalCollections = 0;
let totalDocuments = 0;
let skippedCollections = 0;

// Check if a URI was provided via command line
// The URI can be passed using --eval "const URI='mongodb://username:password@host:port/database'"
let mongoClient;
let mongoDb;

try {
    if (typeof URI !== 'undefined' && URI) {
        print(`Connecting to MongoDB using provided URI...`);
        // Use the Mongo constructor to create a new client with the URI
        mongoClient = new Mongo(URI);
        
        // Extract database name from URI or use "admin" as default
        let dbName = "admin";
        if (URI.includes("/")) {
            const uriParts = URI.split("/");
            if (uriParts.length > 3 && uriParts[3] !== "") {
                // Extract database name, removing any query parameters
                dbName = uriParts[3].split("?")[0];
            }
        }
        
        // Get the database from the client
        mongoDb = mongoClient.getDB(dbName);
        print(`Connected successfully to database: ${dbName}`);
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

// Get all databases (excluding admin, local, and config)
const dbs = mongoDb.adminCommand('listDatabases').databases
    .filter(function(d) {
        return !['admin', 'local', 'config'].includes(d.name);
    })
    .map(function(d) {
        return d.name;
    });

totalDatabases = dbs.length;

// Process each database
dbs.forEach(function(dbName) {
    // Switch to this database
    const currentDb = mongoDb.getSiblingDB(dbName);
    
    // Get all collections (excluding system collections)
    const collections = currentDb.getCollectionNames()
        .filter(function(c) {
            return !c.startsWith("system.");
        });
    
    // Process each collection
    collections.forEach(function(collName) {
        totalCollections++;
        
        try {
            // Sample documents using aggregation pipeline
            const samplePipeline = [{ $sample: { size: SAMPLE_SIZE } }];
            
            // Use the aggregation cursor directly
            const cursor = currentDb[collName].aggregate(samplePipeline);
            const sampledDocs = [];
            
            // Process each document to ensure it's in extended JSON format
            while (cursor.hasNext()) {
                // Get the next document
                const doc = cursor.next();
                // Convert to extended JSON format using MongoDB's EJSON
                sampledDocs.push(doc);
            }
            
            // If no documents were found, skip this collection
            if (sampledDocs.length === 0) {
                print(`No documents found in ${dbName}.${collName}, skipping...`);
                skippedCollections++;
                return;
            }
            
            // Track metadata for summary
            const actualSampleSize = sampledDocs.length;
            totalDocuments += actualSampleSize;
            
            // Create filename for this collection
            const filename = `${OUTPUT_DIR}/${dbName}_${collName}_sample.json`;
            
            // Write the documents to a file in NDJSON format (one document per line)
            try {
                // Print file start marker
                print(`__FILE_START__:${filename}`);
                
                // Print each document as a separate line (NDJSON format) in extended JSON format
                for (const doc of sampledDocs) {
                    // Use MongoDB's native EJSON library with relaxed=false
                    // This ensures all BSON types are properly represented in extended JSON format
                    const jsonStr = EJSON.stringify(doc, { relaxed: false });
                    
                    print(jsonStr);
                }
                
                // Print file end marker
                print("__FILE_END__");
                
                // Print metadata as a comment for tracking purposes
                print(`# Metadata: database=${dbName}, collection=${collName}, sample_size=${actualSampleSize}`);
                
                print(`Sampled ${sampledDocs.length} documents from ${dbName}.${collName}`);
            } catch (writeErr) {
                print(`Error writing sample data for ${dbName}.${collName}: ${writeErr.message}`);
                skippedCollections++;
            }
        } catch (err) {
            print(`Error sampling from ${dbName}.${collName}: ${err.message}`);
            skippedCollections++;
        }
    });
});

// Print summary
print("\nSample Data Collection Summary:");
print(`Processed ${totalDatabases} databases`);
print(`Processed ${totalCollections} collections (${skippedCollections} skipped)`);
print(`Collected ${totalDocuments} total sample documents`);
// print(`\nOutput format: MongoDB Extended JSON NDJSON format (identical to mongoexport)`);

// Note: This script outputs special markers (__FILE_START__ and __FILE_END__)
// that need to be processed by a shell script to create the actual files.
// Here's a sample shell script to process the output:

print(`
# Sample shell script to process the output:
# ==========================================
# #!/bin/bash
# mkdir -p ${OUTPUT_DIR}
# mongosh --quiet --file export_sample_data.js | awk '
#   /^__FILE_START__:/ {
#     file=substr($0, 16)
#     in_file=1
#     next
#   }
#   /^__FILE_END__/ {
#     in_file=0
#     next
#   }
#   in_file {
#     print > file
#   }
# '
`);

// Close the client connection if we created one
if (mongoClient && typeof URI !== 'undefined' && URI) {
    mongoClient.close();
    print("MongoDB connection closed");
}
