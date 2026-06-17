import sqlite3
import datetime

db_path = "/Users/mac/Documents/AlphaPos/customer-order-web/alphapos.db"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Make sure promotions table exists and has media_type
cursor.execute("""
CREATE TABLE IF NOT EXISTS promotions (
    id TEXT PRIMARY KEY,
    title TEXT,
    promo_description TEXT,
    image_data TEXT,
    media_type TEXT DEFAULT 'image',
    is_active INTEGER DEFAULT 1,
    is_deleted INTEGER DEFAULT 0,
    updated_at TEXT
)
""")

# Tiny 1-second blank MP4 base64 string
dummy_mp4_base64 = "AAAAHGZ0eXBtcDQyAAAAAG1wNDJpc29tYXZjMQAAAz5tb292AAAAbG12aGQAAAAA0kC3OtJAtzoAAAPoAAAAKAABAAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAACNnRyYWsAAABcdGtoZAAAAAPSQLc60kC3OgAAAAEAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAcBtZGlhAAAAWG1kaGQsAAAAANJAtzrSQLc6AABkAAAAZAAAAQAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgaGRscgAAAAAAAAAadmlkZQAAAAAAAAAAAAAAAAAAAAAAAAB2aWRlbwAAAAFYbWluZgAAABR2bWhkAAAAAQAAAAAAAAAAAAAAJGRpbmYAAAAcYmRydgAAABBtZXByAAAAAAAAAAAAAAAAYnN0YwAAABRmaWxtAAAAAAAAAAAAAAAAY29hbAAAABxzdGJsAAAAd3N0c2QAAAAAAAAAAQAAAGdhdmMxAAAAAAABAAEASAAAAEgAAAAAAB5hdmNDgQCAA//+"

now_str = datetime.datetime.now().isoformat()

# Insert or replace the mock promotion
cursor.execute("""
INSERT OR REPLACE INTO promotions (id, title, promo_description, image_data, media_type, is_active, is_deleted, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
""", ("mock_video_promo", "วิดีโอโปรโมชั่นลด 50%", "สั่งซื้อผ่านเว็บบอร์ดวันนี้ รับส่วนลดทันที 50% ทุกเมนู!", dummy_mp4_base64, "video", 1, 0, now_str))

conn.commit()
conn.close()
print("Successfully seeded video promotion into local SQLite db.")
