import urllib.request
import json

url = "https://your-supabase-project.supabase.co/rest/v1/"
anon_key = "your-anon-key"

headers = {
    "apikey": anon_key,
    "Authorization": f"Bearer {anon_key}",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates"
}

default_menu = [
    {"id": "app1", "name": "Crispy Golden Spring Rolls", "description": "Crispy fried rolls filled with fresh vegetables, glass noodles, and sweet dipping sauce.", "price": 120.00, "category": "appetizers", "emoji": "🌯", "img_class": "img-app"},
    {"id": "app2", "name": "Spicy Herbal Fish Cakes", "description": "Traditional red-curry seasoned fish cakes blended with green beans.", "price": 150.00, "category": "appetizers", "emoji": "🍥", "img_class": "img-app"},
    {"id": "app3", "name": "Tom Yum Goong", "description": "A hot, sour, and aromatic soup infused with lemongrass and fresh river prawns.", "price": 280.00, "category": "appetizers", "emoji": "🍲", "img_class": "img-app"},
    {"id": "main1", "name": "Signature River Prawn Pad Thai", "description": "Wok-fried rice noodles in sweet tamarind sauce, with two grilled giant river prawns.", "price": 290.00, "category": "mains", "emoji": "🍝", "img_class": "img-main"},
    {"id": "main2", "name": "Royal Emerald Green Curry", "description": "Authentic Thai green curry with tender chicken breast and eggplants.", "price": 190.00, "category": "mains", "emoji": "🍛", "img_class": "img-main"},
    {"id": "main3", "name": "Slow-Braised Northern Khao Soi Beef", "description": "Tender beef shank braised in a rich curry noodle broth, with egg noodles.", "price": 240.00, "category": "mains", "emoji": "🍜", "img_class": "img-main"},
    {"id": "drink1", "name": "Traditional Thai Iced Tea", "description": "Premium black tea brewed with spices, sweetened, and topped with rich milk.", "price": 85.00, "category": "drinks", "emoji": "🥤", "img_class": "img-drink"},
    {"id": "drink2", "name": "Fresh Whole Coconut Juice", "description": "Chilled young coconut cut fresh, providing refreshing natural coconut water.", "price": 95.00, "category": "drinks", "emoji": "🥥", "img_class": "img-drink"},
    {"id": "drink3", "name": "Sparkling Lemon Lemongrass Soda", "description": "Refreshing carbonated soda infused with lemongrass extract and fresh lemon.", "price": 75.00, "category": "drinks", "emoji": "🍹", "img_class": "img-drink"},
    {"id": "dessert1", "name": "Mango Sticky Rice", "description": "Sweet glutinous rice served with ripe golden honey mangoes and coconut cream.", "price": 160.00, "category": "desserts", "emoji": "🥭", "img_class": "img-dessert"},
    {"id": "dessert2", "name": "Artisanal Young Coconut Ice Cream", "description": "House-made coconut ice cream served inside a half coconut shell.", "price": 120.00, "category": "desserts", "emoji": "🍨", "img_class": "img-dessert"}
]

default_employees = [
    {
        "id": "11111111-1111-1111-1111-111111111111",
        "first_name": "Somchai",
        "last_name": "Suksabai",
        "phone": "081-234-5678",
        "national_id": "1234567890123",
        "employment_type": "monthly",
        "pay_rate": 25000.0,
        "username": "somchai",
        "pin_code": "1234",
        "role": "Manager"
    },
    {
        "id": "22222222-2222-2222-2222-222222222222",
        "first_name": "Somsri",
        "last_name": "Jaidee",
        "phone": "089-876-5432",
        "national_id": "9876543210987",
        "employment_type": "hourly",
        "pay_rate": 75.0,
        "username": "somsri",
        "pin_code": "5678",
        "role": "Barista"
    }
]

def seed_table(table_name, data):
    print(f"Seeding {table_name}...")
    req = urllib.request.Request(
        f"{url}{table_name}",
        data=json.dumps(data).encode("utf-8"),
        headers=headers,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as response:
            print(f"Successfully seeded {table_name}. Status: {response.status}")
    except urllib.error.HTTPError as e:
        error_content = e.read().decode("utf-8")
        print(f"Error seeding {table_name}. Status: {e.code}, Response: {error_content}")
    except Exception as e:
        print(f"Failed to seed {table_name}: {e}")

if __name__ == "__main__":
    seed_table("menu_items", default_menu)
    seed_table("employees", default_employees)
