import sqlite3

def inspect():
    conn = sqlite3.connect('/Users/mac/Documents/AlphaPos/customer-order-web/alphapos.db')
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    print("=== Table Sessions ===")
    cursor.execute("SELECT * FROM table_sessions")
    for row in cursor.fetchall():
        print(dict(row))

    print("\n=== Active Table Sessions ===")
    cursor.execute("SELECT * FROM table_sessions WHERE is_active = 1")
    for row in cursor.fetchall():
        print(dict(row))

    print("\n=== Recent Orders ===")
    cursor.execute("SELECT * FROM orders ORDER BY created_at DESC LIMIT 10")
    for row in cursor.fetchall():
        print(dict(row))

    conn.close()

if __name__ == "__main__":
    inspect()
