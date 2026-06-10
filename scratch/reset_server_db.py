import os
import sqlite3

DB_DIR = "/Users/mac/Documents/AlphaPos/customer-order-web"
DB_FILE = os.path.join(DB_DIR, "alphapos.db")
DB_WAL = os.path.join(DB_DIR, "alphapos.db-wal")
DB_SHM = os.path.join(DB_DIR, "alphapos.db-shm")

def reset_db():
    print("Resetting server SQLite database...")
    
    # Remove database files if they exist
    for f in [DB_FILE, DB_WAL, DB_SHM]:
        if os.path.exists(f):
            try:
                os.remove(f)
                print(f"Removed file: {f}")
            except Exception as e:
                print(f"Error removing {f}: {e}")
                
    print("Database reset completed. The server will re-create it on startup.")

if __name__ == "__main__":
    reset_db()
