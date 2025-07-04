package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// Define structs for data models
type User struct {
	ID        primitive.ObjectID `bson:"_id,omitempty"`
	Name      string             `bson:"name"`
	Age       int                `bson:"age"`
	City      string             `bson:"city"`
	Interests []string           `bson:"interests"`
	Status    string             `bson:"status,omitempty"`
	Orders    []Order            `bson:"orders,omitempty"`
}

type Order struct {
	Item  string  `bson:"item"`
	Qty   int     `bson:"qty"`
	Price float64 `bson:"price"`
}

type CityStats struct {
	ID         string  `bson:"_id"`
	UserCount  int     `bson:"userCount"`
	AverageAge float64 `bson:"averageAge"`
}

type UserOrderTotal struct {
	ID          string  `bson:"_id"`
	TotalAmount float64 `bson:"totalAmount"`
}

const (
	uri               = "mongodb://localhost:27017" // Your MongoDB URI
	dbName            = "goMongoDb"                 // Your database name
	usersCollection   = "users_data"                // Collection for users data
	productCollection = "products_inventory"        // Collection for product data (for $lookup demo)
)

func main() {
	// Set up MongoDB client
	client, err := mongo.Connect(context.TODO(), options.Client().ApplyURI(uri))
	if err != nil {
		log.Fatal(err)
	}
	defer func() {
		if err = client.Disconnect(context.TODO()); err != nil {
			log.Fatal(err)
		}
		fmt.Println("\nMongoDB connection closed.")
	}()

	// Ping the primary to verify connection
	if err := client.Ping(context.TODO(), nil); err != nil {
		log.Fatal(err)
	}
	fmt.Println("Successfully connected to MongoDB server.")

	db := client.Database(dbName)

	// --- 1. Insertion Operations (users_data collection) ---
	fmt.Println("\n--- Insertion Operations ---")
	usersColl := db.Collection(usersCollection)

	// Clear the collection before starting
	usersColl.DeleteMany(context.TODO(), bson.M{})
	fmt.Printf("Cleared '%s' collection.\n", usersCollection)

	// 1.1 Insert a single document
	user1 := User{Name: "Alice", Age: 30, City: "New York", Interests: []string{"reading", "hiking"}}
	res1, err := usersColl.InsertOne(context.TODO(), user1)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Inserted single user, ID: %s\n", res1.InsertedID.(primitive.ObjectID).Hex())

	// 1.2 Insert multiple documents
	usersToInsert := []interface{}{
		User{Name: "Bob", Age: 25, City: "London", Interests: []string{"gaming", "coding"}},
		User{Name: "Charlie", Age: 35, City: "Paris", Interests: []string{"traveling", "cooking", "gaming"}},
		User{Name: "Diana", Age: 28, City: "New York", Interests: []string{"sports"}},
	}
	resMany, err := usersColl.InsertMany(context.TODO(), usersToInsert)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Inserted %d users.\n", len(resMany.InsertedIDs))

	// --- 2. Read Operations (users_data collection) ---
	fmt.Println("\n--- Read Operations ---")

	// 2.1 Find all documents
	fmt.Println("\nAll users:")
	cursor, err := usersColl.Find(context.TODO(), bson.M{})
	if err != nil {
		log.Fatal(err)
	}
	defer cursor.Close(context.TODO())
	var allUsers []User
	if err = cursor.All(context.TODO(), &allUsers); err != nil {
		log.Fatal(err)
	}
	for _, user := range allUsers {
		fmt.Printf("  %+v\n", user)
	}

	// 2.2 Find documents matching a condition ($gt)
	fmt.Println("\nUsers older than 30:")
	filterAgeGt := bson.M{"age": bson.M{"$gt": 30}}
	cursor, err = usersColl.Find(context.TODO(), filterAgeGt)
	if err != nil {
		log.Fatal(err)
	}
	var usersOlderThan30 []User
	if err = cursor.All(context.TODO(), &usersOlderThan30); err != nil {
		log.Fatal(err)
	}
	for _, user := range usersOlderThan30 {
		fmt.Printf("  %+v\n", user)
	}

	// 2.3 Find a single document (FindOne)
	fmt.Println("\nFind user named 'Bob':")
	var bob User
	err = usersColl.FindOne(context.TODO(), bson.M{"name": "Bob"}).Decode(&bob)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("  %+v\n", bob)

	// 2.4 Find documents where array contains specific elements ($all)
	fmt.Println("\nUsers interested in both 'reading' and 'hiking' ($all):")
	filterInterests := bson.M{"interests": bson.M{"$all": []string{"reading", "hiking"}}}
	cursor, err = usersColl.Find(context.TODO(), filterInterests)
	if err != nil {
		log.Fatal(err)
	}
	var readingHikingUsers []User
	if err = cursor.All(context.TODO(), &readingHikingUsers); err != nil {
		log.Fatal(err)
	}
	for _, user := range readingHikingUsers {
		fmt.Printf("  %+v\n", user)
	}

	// 2.5 Use projection to return only specific fields
	fmt.Println("\nAll users, only name and city:")
	projectionOpts := options.Find().SetProjection(bson.D{{"name", 1}, {"city", 1}, {"_id", 0}})
	cursor, err = usersColl.Find(context.TODO(), bson.M{}, projectionOpts)
	if err != nil {
		log.Fatal(err)
	}
	var namesAndCities []bson.M // Use bson.M to hold dynamic fields
	if err = cursor.All(context.TODO(), &namesAndCities); err != nil {
		log.Fatal(err)
	}
	for _, doc := range namesAndCities {
		fmt.Printf("  %v\n", doc)
	}

	// --- 3. Update Operations (users_data collection) ---
	fmt.Println("\n--- Update Operations ---")

	// 3.1 Update a single document ($set)
	fmt.Println("\nUpdate 'Alice's city to 'San Francisco':")
	updateResult, err := usersColl.UpdateOne(
		context.TODO(),
		bson.M{"name": "Alice"},
		bson.M{"$set": bson.M{"city": "San Francisco"}},
	)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Matched %d docs, modified %d docs.\n", updateResult.MatchedCount, updateResult.ModifiedCount)
	var updatedAlice User
	usersColl.FindOne(context.TODO(), bson.M{"name": "Alice"}).Decode(&updatedAlice)
	fmt.Printf("  %+v\n", updatedAlice)

	// 3.2 Update multiple documents ($inc)
	fmt.Println("\nIncrease age by 1 for all users in 'New York':")
	updateResult, err = usersColl.UpdateMany(
		context.TODO(),
		bson.M{"city": "New York"},
		bson.M{"$inc": bson.M{"age": 1}},
	)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Matched %d docs, modified %d docs.\n", updateResult.MatchedCount, updateResult.ModifiedCount)
	cursor, err = usersColl.Find(context.TODO(), bson.M{"city": "New York"})
	if err != nil {
		log.Fatal(err)
	}
	var newYorkUsers []User
	cursor.All(context.TODO(), &newYorkUsers)
	fmt.Printf("Updated New York users: %+v\n", newYorkUsers)

	// 3.3 Array operations ($addToSet, $pull)
	fmt.Println("\nAdd unique interest 'traveling' to 'Bob' ($addToSet):")
	_, err = usersColl.UpdateOne(
		context.TODO(),
		bson.M{"name": "Bob"},
		bson.M{"$addToSet": bson.M{"interests": "traveling"}},
	)
	if err != nil {
		log.Fatal(err)
	}
	var bobWithNewInterest User
	usersColl.FindOne(context.TODO(), bson.M{"name": "Bob"}).Decode(&bobWithNewInterest)
	fmt.Printf("  %+v\n", bobWithNewInterest)

	fmt.Println("\nRemove 'gaming' from 'Charlie's interests ($pull):")
	_, err = usersColl.UpdateOne(
		context.TODO(),
		bson.M{"name": "Charlie"},
		bson.M{"$pull": bson.M{"interests": "gaming"}},
	)
	if err != nil {
		log.Fatal(err)
	}
	var charlieUpdatedInterest User
	usersColl.FindOne(context.TODO(), bson.M{"name": "Charlie"}).Decode(&charlieUpdatedInterest)
	fmt.Printf("  %+v\n", charlieUpdatedInterest)

	// --- 4. Delete Operations (users_data collection) ---
	fmt.Println("\n--- Delete Operations ---")

	// 4.1 Delete a single document
	fmt.Println("\nDelete user named 'Diana':")
	deleteResult, err := usersColl.DeleteOne(context.TODO(), bson.M{"name": "Diana"})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Deleted %d document(s).\n", deleteResult.DeletedCount)
	count, _ := usersColl.CountDocuments(context.TODO(), bson.M{})
	fmt.Printf("Remaining documents count: %d\n", count)

	// 4.2 Delete multiple documents
	fmt.Println("\nDelete all users younger than 30:")
	deleteResult, err = usersColl.DeleteMany(context.TODO(), bson.M{"age": bson.M{"$lt": 30}})
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Deleted %d document(s).\n", deleteResult.DeletedCount)
	count, _ = usersColl.CountDocuments(context.TODO(), bson.M{})
	fmt.Printf("Remaining documents count: %d\n", count)

	// --- 5. Aggregation Pipeline Operations (users_data collection) ---
	fmt.Println("\n--- Aggregation Pipeline Operations ---")

	// Re-insert data for aggregation demo
	usersColl.DeleteMany(context.TODO(), bson.M{}) // Clear collection
	usersColl.InsertMany(context.TODO(), []interface{}{
		User{Name: "Alice", Age: 30, City: "New York", Status: "active", Orders: []Order{{Item: "Laptop", Qty: 1, Price: 1200}, {Item: "Mouse", Qty: 2, Price: 25}}},
		User{Name: "Bob", Age: 25, City: "London", Status: "inactive", Orders: []Order{{Item: "Keyboard", Qty: 1, Price: 75}}},
		User{Name: "Charlie", Age: 35, City: "Paris", Status: "active", Orders: []Order{{Item: "Monitor", Qty: 1, Price: 300}}},
		User{Name: "Diana", Age: 30, City: "New York", Status: "active", Orders: []Order{{Item: "Laptop", Qty: 1, Price: 1200}, {Item: "Headphones", Qty: 1, Price: 150}}},
	})
	fmt.Println("Re-populated data for aggregation pipeline demo.")

	// 5.1 Group by city, count users, and calculate average age
	fmt.Println("\nUser statistics grouped by city:")
	pipelineCityStats := mongo.Pipeline{
		bson.D{{"$group", bson.D{
			{"_id", "$city"},
			{"userCount", bson.D{{"$sum", 1}}},
			{"averageAge", bson.D{{"$avg", "$age"}}},
		}}},
		bson.D{{"$sort", bson.D{{"userCount", -1}}}},
	}
	cursor, err = usersColl.Aggregate(context.TODO(), pipelineCityStats)
	if err != nil {
		log.Fatal(err)
	}
	var cityStats []CityStats
	if err = cursor.All(context.TODO(), &cityStats); err != nil {
		log.Fatal(err)
	}
	for _, stat := range cityStats {
		fmt.Printf("  %+v\n", stat)
	}

	// 5.2 Use $unwind and $group to calculate total order amount
	fmt.Println("\nTotal order amount for each user:")
	pipelineUserOrderTotals := mongo.Pipeline{
		bson.D{{"$unwind", "$orders"}},
		bson.D{{"$group", bson.D{
			{"_id", "$name"},
			{"totalAmount", bson.D{{"$sum", bson.D{{"$multiply", bson.A{"$orders.qty", "$orders.price"}}}}},
		}}},
		bson.D{{"$sort", bson.D{{"totalAmount", -1}}}},
	}
	cursor, err = usersColl.Aggregate(context.TODO(), pipelineUserOrderTotals)
	if err != nil {
		log.Fatal(err)
	}
	var userOrderTotals []UserOrderTotal
	if err = cursor.All(context.TODO(), &userOrderTotals); err != nil {
		log.Fatal(err)
	}
	for _, total := range userOrderTotals {
		fmt.Printf("  %+v\n", total)
	}

	// 5.3 Using $filter to process array elements
	fmt.Println("\nUsers with orders containing items with quantity greater than 1:")
	pipelineFilterOrders := mongo.Pipeline{
		bson.D{{"$project", bson.D{
			"name": 1,
			"largeQuantityOrders": bson.D{
				{"$filter", bson.D{
					{"input", "$orders"},
					{"as", "order"},
					{"cond", bson.D{{"$gt", bson.A{"$$order.qty", 1}}}},
				}},
			},
		}}},
		bson.D{{"$match", bson.D{"largeQuantityOrders": bson.D{"$ne": bson.A{}}}}}, // Match where the filtered array is not empty
	}
	cursor, err = usersColl.Aggregate(context.TODO(), pipelineFilterOrders)
	if err != nil {
		log.Fatal(err)
	}
	var usersWithLargeOrders []bson.M
	if err = cursor.All(context.TODO(), &usersWithLargeOrders); err != nil {
		log.Fatal(err)
	}
	for _, user := range usersWithLargeOrders {
		fmt.Printf("  %v\n", user)
	}

	// --- 6. $lookup Operation (Demonstrating with a separate 'products_inventory' collection) ---
	fmt.Println("\n--- $lookup Operation ---")
	productsColl := db.Collection(productCollection)

	// Clear and re-insert products for lookup demo
	productsColl.DeleteMany(context.TODO(), bson.M{})
	fmt.Printf("Cleared '%s' collection.\n", productCollection)
	productsToInsert := []interface{}{
		bson.M{"_id": "P001", "productName": "Laptop Pro", "category": "Electronics", "price": 1200.00},
		bson.M{"_id": "P002", "productName": "Wireless Mouse", "category": "Accessories", "price": 25.00},
		bson.M{"_id": "P003", "productName": "Mechanical Keyboard", "category": "Accessories", "price": 75.00},
	}
	_, err = productsColl.InsertMany(context.TODO(), productsToInsert)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Populated '%s' collection with sample data.\n", productCollection)

	// Re-insert some users with product IDs for lookup
	usersColl.DeleteMany(context.TODO(), bson.M{})
	usersColl.InsertMany(context.TODO(), []interface{}{
		bson.M{"name": "Evelyn", "purchasedProducts": []string{"P001", "P002"}},
		bson.M{"name": "Frank", "purchasedProducts": []string{"P003"}},
		bson.M{"name": "Grace", "purchasedProducts": []string{"P999"}}, // Non-existent product for lookup demo
	})
	fmt.Printf("Re-populated '%s' collection for $lookup demo.\n", usersCollection)


	fmt.Println("\nUsers with their purchased product details ($lookup):")
	pipelineLookup := mongo.Pipeline{
		bson.D{{"$unwind", "$purchasedProducts"}}, // Unwind the product IDs
		bson.D{{"$lookup", bson.D{
			"from": productCollection,
			"localField": "purchasedProducts",
			"foreignField": "_id",
			"as": "productDetails",
		}}},
		bson.D{{"$unwind", bson.D{"path": "$productDetails", "preserveNullAndEmptyArrays": true}}}, // Unwind product details, keep users without matches
		bson.D{{"$group", bson.D{ // Group back to get user with array of product details
			"_id": "$_id",
			"name": bson.D{{"$first", "$name"}},
			"allProductDetails": bson.D{{"$push", "$productDetails"}},
		}}},
	}

	cursor, err = usersColl.Aggregate(context.TODO(), pipelineLookup)
	if err != nil {
		log.Fatal(err)
	}
	var usersWithProductDetails []bson.M
	if err = cursor.All(context.TODO(), &usersWithProductDetails); err != nil {
		log.Fatal(err)
	}
	for _, doc := range usersWithProductDetails {
		fmt.Printf("  %v\n", doc)
	}
}
