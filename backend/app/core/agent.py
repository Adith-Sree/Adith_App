import os
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

def _get_chroma_collection():
    global _chroma_client, _chroma_collection
    if _chroma_collection is not None:
        return _chroma_collection
    try:
        _chroma_client = chromadb.PersistentClient(path="./chroma_data")
        # Gracefully get or create to avoid crashing if empty
        _chroma_collection = _chroma_client.get_or_create_collection(name="session_memories")
        return _chroma_collection
    except Exception as e:
        print(f"⚠️ Warning: Could not initialize Chroma DB connection: {e}")
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
    response = agent.run(prompt)
    return str(response)