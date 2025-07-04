// Sample MongoDB queries for operator compatibility testing

// Connect to MongoDB
const { MongoClient } = require('mongodb');
const uri = "mongodb://localhost:27017";
const client = new MongoClient(uri);

async function runQueries() {
  try {
    await client.connect();
    const database = client.db("sample_database");
    const collection = database.collection("users");
    
    // Example 1: Using $text operator (unsupported in Firestore)
    const textSearchResults = await collection.find({
      $text: { $search: "John" }
    }).toArray();
    console.log("Text search results:", textSearchResults);
    
    // Example 2: Using $where operator (unsupported in Firestore)
    const whereResults = await collection.find({
      $where: "this.age > 30 && this.name.startsWith('J')"
    }).toArray();
    console.log("Where results:", whereResults);
    
    // Example 3: Using $geoWithin with $center (unsupported in Firestore)
    const geoResults = await collection.find({
      location: {
        $geoWithin: {
          $center: [[0, 0], 10]
        }
      }
    }).toArray();
    console.log("Geo results:", geoResults);
    
    // Example 4: Using array positional operator $[] (unsupported in Firestore)
    await collection.updateMany(
      { tags: "important" },
      { $set: { "tags.$[]": "critical" } }
    );
    
    // Example 5: Using $slice in projection (supported in Firestore)
    const sliceResults = await collection.find(
      { tags: { $exists: true } },
      { tags: { $slice: 2 } }
    ).toArray();
    console.log("Slice results:", sliceResults);
    
  } finally {
    await client.close();
  }
}

runQueries().catch(console.error);
