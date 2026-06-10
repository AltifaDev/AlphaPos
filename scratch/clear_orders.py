import sqlite3
import os

DB_FILE = "/Users/mac/Documents/AlphaPos/customer-order-web/alphapos.db"

def clear_db():
    if not os.path.exists(DB_FILE):
        print("Database file does not exist.")
        return
    
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    try:
        cursor.execute("DELETE FROM order_items;")
        cursor.execute("DELETE FROM orders;")
        cursor.execute("DELETE FROM table_sessions;")
        cursor.execute("DELETE FROM service_requests;")
        cursor.execute("DELETE FROM timecards;")
        conn.commit()
        print("Successfully deleted all orders, items, sessions, requests, and timecards from database.")
    except Exception as e:
        print("Error clearing database:", e)
    finally:
        conn.close()

if __name__ == "__main__":
    clear_db()
