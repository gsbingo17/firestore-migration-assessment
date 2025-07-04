from pymongo import MongoClient
from bson.objectid import ObjectId
from datetime import datetime

# MongoDB Connection URI
uri = "mongodb://localhost:27017/" # Modify if your MongoDB is elsewhere
db_name = "myPythonDb" # Your database name
collection_name = "users" # Your collection name

def main():
    client = None # Initialize client to None
    try:
        # Connect to MongoDB server
        client = MongoClient(uri)
        db = client[db_name]
        collection = db[collection_name]

        print("Successfully connected to MongoDB server.")

        # --- 1. Insert Operations ---

        print("\n--- Insert Operations ---")

        # 1.1 Insert a single document
        user1 = {"name": "Alice", "age": 30, "city": "New York", "interests": ["reading", "hiking"]}
        insert_one_result = collection.insert_one(user1)
        print(f"Inserted single document, _id: {insert_one_result.inserted_id}")

        # 1.2 Insert multiple documents
        users_to_insert = [
            {"name": "Bob", "age": 25, "city": "London", "interests": ["gaming", "coding"]},
            {"name": "Charlie", "age": 35, "city": "Paris", "interests": ["traveling", "cooking", "gaming"]},
            {"name": "David", "age": 28, "city": "New York", "interests": ["sports"]}
        ]
        insert_many_result = collection.insert_many(users_to_insert)
        print(f"Inserted {len(insert_many_result.inserted_ids)} documents.")

        # --- 2. Read Operations ---

        print("\n--- Read Operations ---")

        # 2.1 Find all documents
        print("\nAll users:")
        all_users = list(collection.find({}))
        for user in all_users:
            print(user)

        # 2.2 Find documents matching a condition (using query operators)
        print("\nUsers older than 30:")
        users_older_than_30 = list(collection.find({"age": {"$gt": 30}}))
        for user in users_older_than_30:
            print(user)

        # 2.3 Find a single document (using find_one)
        print("\nFind user named 'Bob':")
        bob = collection.find_one({"name": "Bob"})
        print(bob)

        # 2.4 Find documents where array contains specific elements ($in, $all)
        print("\nUsers interested in 'gaming':")
        gaming_users = list(collection.find({"interests": "gaming"})) # Direct match in array
        for user in gaming_users:
            print(user)

        print("\nUsers interested in both 'reading' and 'hiking' ($all):")
        reading_hiking_users = list(collection.find({"interests": {"$all": ["reading", "hiking"]}}))
        for user in reading_hiking_users:
            print(user)

        # 2.5 Use projection to return only specific fields
        print("\nAll users, only name and city:")
        names_and_cities = list(collection.find({}, {"name": 1, "city": 1, "_id": 0}))
        for user in names_and_cities:
            print(user)

        # --- 3. Update Operations ---

        print("\n--- Update Operations ---")

        # 3.1 Update a single document ($set)
        print("\nUpdate 'Alice's city to 'San Francisco':")
        update_one_result = collection.update_one(
            {"name": "Alice"},
            {"$set": {"city": "San Francisco"}}
        )
        print(f"Matched {update_one_result.matched_count} documents, modified {update_one_result.modified_count} documents.")
        print(collection.find_one({"name": "Alice"}))

        # 3.2 Update multiple documents ($inc, $set)
        print("\nIncrease age by 1 for all users in 'New York':")
        update_many_result = collection.update_many(
            {"city": "New York"},
            {"$inc": {"age": 1}} # $inc to increment numerical fields
        )
        print(f"Matched {update_many_result.matched_count} documents, modified {update_many_result.modified_count} documents.")
        print("Updated New York users:", list(collection.find({"city": "New York"})))

        # 3.3 Array operations ($addToSet, $pull)
        print("\nAdd unique interest 'traveling' to 'Bob' ($addToSet):")
        collection.update_one(
            {"name": "Bob"},
            {"$addToSet": {"interests": "traveling"}}
        )
        print(collection.find_one({"name": "Bob"}))

        print("\nRemove 'gaming' from 'Charlie's interests ($pull):")
        collection.update_one(
            {"name": "Charlie"},
            {"$pull": {"interests": "gaming"}}
        )
        print(collection.find_one({"name": "Charlie"}))

        # --- 4. Delete Operations ---

        print("\n--- Delete Operations ---")

        # 4.1 Delete a single document
        print("\nDelete user named 'David':")
        delete_one_result = collection.delete_one({"name": "David"})
        print(f"Deleted {delete_one_result.deleted_count} documents.")
        print("Remaining documents count:", collection.count_documents({}))

        # 4.2 Delete multiple documents
        print("\nDelete all users younger than 30:")
        delete_many_result = collection.delete_many({"age": {"$lt": 30}})
        print(f"Deleted {delete_many_result.deleted_count} documents.")
        print("Remaining documents count:", collection.count_documents({}))

        # --- 5. Aggregation Pipeline Operations ---

        print("\n--- Aggregation Pipeline Operations ---")

        # Clear collection and re-insert data for aggregation demo
        collection.delete_many({})
        collection.insert_many([
            {"name": "Alice", "age": 30, "city": "New York", "status": "active",
             "orders": [{"item": "Laptop", "qty": 1, "price": 1200}, {"item": "Mouse", "qty": 2, "price": 25}]},
            {"name": "Bob", "age": 25, "city": "London", "status": "inactive",
             "orders": [{"item": "Keyboard", "qty": 1, "price": 75}]},
            {"name": "Charlie", "age": 35, "city": "Paris", "status": "active",
             "orders": [{"item": "Monitor", "qty": 1, "price": 300}]},
            {"name": "Diana", "age": 30, "city": "New York", "status": "active",
             "orders": [{"item": "Laptop", "qty": 1, "price": 1200}, {"item": "Headphones", "qty": 1, "price": 150}]}
        ])
        print("Re-populating data for aggregation pipeline...")

        # 5.1 Group by city and count users and calculate average age
        print("\nUser statistics grouped by city:")
        city_stats = list(collection.aggregate([
            {
                "$group": {
                    "_id": "$city",           # Group by city field
                    "userCount": {"$sum": 1}, # Count documents in each group
                    "averageAge": {"$avg": "$age"} # Calculate average age
                }
            },
            {
                "$sort": {"userCount": -1} # Sort by user count in descending order
            }
        ]))
        for stat in city_stats:
            print(stat)

        # 5.2 Use $unwind and $group to calculate total order amount
        print("\nTotal order amount for each user:")
        user_order_totals = list(collection.aggregate([
            {"$unwind": "$orders"}, # Deconstruct the orders array
            {
                "$group": {
                    "_id": "$name", # Group by user name
                    "totalAmount": {"$sum": {"$multiply": ["$orders.qty", "$orders.price"]}} # Calculate total amount
                }
            },
            {
                "$sort": {"totalAmount": -1} # Sort by total amount in descending order
            }
        ]))
        for total in user_order_totals:
            print(total)

        # 5.3 Using $filter to process array elements
        print("\nUsers with orders containing items with quantity greater than 1:")
        users_with_large_orders = list(collection.aggregate([
            {
                "$project": {
                    "name": 1,
                    "largeQuantityOrders": {
                        "$filter": {
                            "input": "$orders",
                            "as": "order",
                            "cond": {"$gt": ["$$order.qty", 1]}
                        }
                    }
                }
            },
            {
                # Filter out documents where largeQuantityOrders array is empty
                "$match": {"largeQuantityOrders": {"$ne": []}}
            }
        ]))
        for user in users_with_large_orders:
            print(user)

        # 5.4 Using $lookup (assuming a 'products' collection exists for a real example)
        # Note: This part is for demonstration of structure and won't run without a 'products' collection.
        """
        print("\nUsing $lookup to join orders with product information (assuming a 'products' collection exists):")
        # Example products collection:
        # db.products.insert_many([
        #   {"_id": "item_laptop", "productName": "Laptop", "category": "Electronics"},
        #   {"_id": "item_mouse", "productName": "Mouse", "category": "Peripherals"}
        # ])

        # Assuming 'users' collection documents now have 'order_ids' referencing an 'orders_collection'
        # Example for $lookup:
        # from_collection = db['orders_collection']
        # lookup_result = list(from_collection.aggregate([
        #     {
        #         "$lookup": {
        #             "from": "products",           # Collection to join with
        #             "localField": "product_id",   # Field from current collection
        #             "foreignField": "_id",        # Field from 'products' collection
        #             "as": "product_details"       # Output array field name
        #         }
        #     },
        #     {"$unwind": {"path": "$product_details", "preserveNullAndEmptyArrays": True}}
        # ]))
        # for doc in lookup_result:
        #     print(doc)
        """

    except Exception as e:
        print(f"Operation failed: {e}")
    finally:
        # Close database connection
        if client:
            client.close()
            print("\nMongoDB connection closed.")

if __name__ == "__main__":
    main()
