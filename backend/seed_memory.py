import chromadb

# 1. Initialize a local ChromaDB instance (it saves data to a folder on your Mac)
client = chromadb.PersistentClient(path="./chroma_data")

# 2. Create a "collection" (the Chroma equivalent of a SQL table)
collection = client.get_or_create_collection(name="session_memories")

# 3. Inject a memory of a highly successful past session
collection.add(
    documents=[
        "Completed a highly focused 120-minute session on C++ Data Structures. Successfully mastered binary search implementations, specifically ensuring the use of the l + (r - l) / 2 formula for midpoint calculations to strictly prevent integer overflow risks. High discipline maintained."
    ],
    metadatas=[{"status": "completed", "topic": "DSA"}],
    ids=["session_001"]
)

print("Memory successfully seeded into ChromaDB!")