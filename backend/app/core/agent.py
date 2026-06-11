import os
import uuid
import chromadb
from dotenv import load_dotenv
from smolagents import tool, CodeAgent, LiteLLMModel

load_dotenv()

# --- TOOL 1: The Math Engine ---
@tool
def calculate_quitting_penalty(duration_minutes: int, minutes_completed: int) -> str:
    """
    Calculates the exact discipline score penalty if a user quits a focus session early.
    
    Args:
        duration_minutes: The total length of the session they committed to.
        minutes_completed: How many minutes they actually worked before giving up.
    """
    completion_percentage = minutes_completed / duration_minutes
    if completion_percentage < 0.10:
        return "Penalty: -25 points. Assessment: CRITICAL"
    elif completion_percentage < 0.50:
        return "Penalty: -15 points. Assessment: HIGH"
    return "Penalty: -5 points. Assessment: MINOR"

# Global vector DB client initialization to prevent SQLite locks and expensive I/O connection overhead under concurrent load.
_chroma_client = None
_chroma_collection = None
_cache_collection = None

def _get_chroma_client():
    global _chroma_client
    if _chroma_client is not None:
        return _chroma_client
    try:
        _chroma_client = chromadb.PersistentClient(path="./chroma_data")
        return _chroma_client
    except Exception as e:
        print(f"⚠️ Warning: Could not initialize Chroma DB connection: {e}")
        return None

def _get_chroma_collection():
    global _chroma_collection
    if _chroma_collection is not None:
        return _chroma_collection
    client = _get_chroma_client()
    if client is None:
        return None
    try:
        _chroma_collection = client.get_or_create_collection(name="session_memories")
        return _chroma_collection
    except Exception as e:
        print(f"⚠️ Warning: Could not get or create session_memories collection: {e}")
        return None

def _get_cache_collection():
    global _cache_collection
    if _cache_collection is not None:
        return _cache_collection
    client = _get_chroma_client()
    if client is None:
        return None
    try:
        # ChromaDB by default uses L2 distance (squared L2 distance).
        _cache_collection = client.get_or_create_collection(name="pushback_cache")
        return _cache_collection
    except Exception as e:
        print(f"⚠️ Warning: Could not get or create pushback_cache collection: {e}")
        return None

# --- TOOL 2: The Memory Engine ---
@tool
def query_past_successes(topic: str) -> str:
    """
    Searches the user's historical memory bank to find past successful focus sessions related to a specific topic.
    Use this to remind the user of their past competence.
    
    Args:
        topic: The subject the user is currently struggling with (e.g., 'DSA', 'Math', 'Writing').
    """
    collection = _get_chroma_collection()
    if collection is None:
        return "No past memories found for this topic (database offline)."

    try:
        # Search the vector database for memories matching the current topic
        results = collection.query(
            query_texts=[topic],
            n_results=1
        )
        if results and results.get('documents') and len(results['documents']) > 0 and len(results['documents'][0]) > 0:
            return f"Past success found: {results['documents'][0][0]}"
    except Exception as e:
        print(f"⚠️ Error querying past successes vector store: {e}")
        
    return "No past memories found for this topic."

# --- THE BRAIN ---
def generate_pushback_message(goal: str, duration: int) -> str:
    # 1. Query Semantic Cache to avoid expensive Gemini API billing
    cache = _get_cache_collection()
    if cache is not None:
        try:
            results = cache.query(
                query_texts=[goal],
                n_results=1
            )
            # Check if distance is within the semantic similarity threshold
            if results and results.get('distances') and len(results['distances'][0]) > 0:
                distance = results['distances'][0][0]
                # Default Chroma L2 distance: <= 0.6 represents highly similar semantic prompts.
                if distance <= 0.6:  
                    cached_response = results['metadatas'][0][0]['response']
                    print(f"🎯 Cache Hit! Reusing response for goal: '{goal}' (Distance: {distance:.3f})")
                    return cached_response
        except Exception as e:
            print(f"⚠️ Error querying semantic cache: {e}")

    # 2. Cache Miss: Query Gemini AI Agent
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        return "SYSTEM OVERRIDE: API Key missing."

    model = LiteLLMModel(model_id="gemini/gemini-2.5-flash-lite", api_key=api_key)
    
    # Notice we now pass BOTH tools to the agent
    agent = CodeAgent(
        tools=[calculate_quitting_penalty, query_past_successes], 
        model=model
    )
    
    minutes_worked = 12 
    
    # The upgraded prompt forcing the agent to use both tools
    prompt = f"""
    The user is trying to abandon their focus session early.
    Current Goal: {goal}
    Committed Duration: {duration} minutes.
    Time worked: {minutes_worked} minutes.
    
    Step 1: Use your memory tool to search for past successes related to their goal.
    Step 2: Use your penalty tool to calculate the score hit for quitting.
    Step 3: Write a 3-sentence, hyper-aggressive motivational response. 
    You MUST cite their specific past achievements from the memory tool to guilt them into staying, and explicitly state the penalty points.
    """
    
    print(f"\n--- WAKING AGENT FOR GOAL: {goal} ---")
    response = str(agent.run(prompt))
    
    # 3. Save to Semantic Cache for future reuse
    if cache is not None:
        try:
            # We store the 'goal' as the queryable document, and store the generated 'response' in metadata
            cache.add(
                documents=[goal],
                metadatas=[{"goal": goal, "duration": duration, "response": response}],
                ids=[str(uuid.uuid4())]
            )
            print(f"💾 Cached new response for goal: '{goal}'")
        except Exception as e:
            print(f"⚠️ Error saving to semantic cache: {e}")
            
    return response