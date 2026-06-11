DEFAULT_EMPLOYEES = [
    ("11111111-1111-1111-1111-111111111111", "Somchai", "Suksabai", "081-234-5678", "1234567890123", "monthly", 25000.0, "somchai", "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4", "Manager"),
    ("22222222-2222-2222-2222-222222222222", "Somsri", "Jaidee", "089-876-5432", "9876543210987", "hourly", 75.0, "somsri", "3f786850e387550fdab836ed7e6dc881de23001bdec45830613a48e7347793d4", "Barista")
]

DEFAULT_MENU = [
    # Mains (25)
    ("isan1", "Classic Som Tum Thai", "Green papaya salad with peanuts, dried shrimp, lime, palm sugar, and fish sauce.", 85.00, "mains", "🥗", "img-main", "https://images.unsplash.com/photo-1626132647523-66f5bf380027?w=400&q=80"),
    ("isan2", "Som Tum Boo Plarah", "Papaya salad with fermented fish sauce, salted crab, and fresh Thai herbs.", 90.00, "mains", "🥗", "img-main", "https://images.unsplash.com/photo-1625813506062-0aeb1d7a094b?w=400&q=80"),
    ("isan3", "Som Tum Korat", "Papaya salad combining Som Tum Thai and Boo Plarah styles with rice noodles.", 95.00, "mains", "🥗", "img-main", "https://images.unsplash.com/photo-1617470703128-26a0fc9af10f?w=400&q=80"),
    ("isan4", "Som Tum Suan Pak", "Herbal papaya salad with seasonal Isan wild vegetables and bitter herbs.", 100.00, "mains", "🥗", "img-main", "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=400&q=80"),
    ("isan5", "Som Tum Tard Platter", "Platter-sized papaya salad served with boiled eggs, pork cracklings, and noodles.", 220.00, "mains", "🍱", "img-main", "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80"),
    ("isan6", "Tum Corn with Salted Egg", "Sweet yellow corn salad tossed with rich salted egg yolk and lime juice.", 110.00, "mains", "🌽", "img-main", "https://images.unsplash.com/photo-1551248429-40975aa4de74?w=400&q=80"),
    ("isan7", "Tum Cucumber (Tum Tang)", "Spicy cucumber salad with fermented fish sauce, chilies, and garlic.", 80.00, "mains", "🥒", "img-main", "https://images.unsplash.com/photo-1603052875302-d376b7c0638a?w=400&q=80"),
    ("isan8", "Tum Tray Seafood", "Papaya salad platter served with giant river prawns, green mussels, and squid.", 250.00, "mains", "🍛", "img-main", "https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?w=400&q=80"),
    ("isan9", "Spicy Minced Pork Larb", "Minced pork salad with roasted ground rice, mint, lime, and dried chili.", 120.00, "mains", "🥩", "img-main", "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&q=80"),
    ("isan10", "Spicy Minced Chicken Larb", "Minced chicken breast salad seasoned with Isan herbs and fresh lime juice.", 120.00, "mains", "🍗", "img-main", "https://images.unsplash.com/photo-1606787366850-de6330128bfc?w=400&q=80"),
    ("isan11", "Spicy Minced Duck Larb", "Authentic minced duck salad seasoned with roasted ground rice, mint, and galangal.", 140.00, "mains", "🦆", "img-main", "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=400&q=80"),
    ("isan12", "Larb Woon Sen (Glass Noodle)", "Spicy glass noodle salad with minced pork, red onions, lime, and chilies.", 115.00, "mains", "🍜", "img-main", "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=400&q=80"),
    ("isan13", "Larb Mushroom (Vegetarian)", "Vegetarian Larb with mixed forest mushrooms, mint, and roasted rice powder.", 105.00, "mains", "🍄", "img-main", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan14", "Nam Tok Moo (Pork Salad)", "Grilled sliced pork collar salad with roasted ground rice, chili, and fresh mint.", 130.00, "mains", "🐷", "img-main", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan15", "Nam Tok Neua (Beef Salad)", "Grilled sliced beef ribeye salad with authentic Isan herbs and lime dressing.", 160.00, "mains", "🐮", "img-main", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan16", "Sup Nor Mai (Bamboo Salad)", "Spicy warm shredded bamboo shoot salad infused with aromatic yanang leaf juice.", 95.00, "mains", "🎋", "img-main", "https://images.unsplash.com/photo-1540420773420-3366772f4999?w=400&q=80"),
    ("isan17", "Tom Zap Pork Ribs", "Hot, sour, and aromatic soup with tender pork ribs and fresh lemongrass.", 150.00, "mains", "🍲", "img-main", "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80"),
    ("isan18", "Tom Zap Beef Shank", "Spicy herbal soup with slow-braised beef shank, toasted rice, and fresh lime.", 180.00, "mains", "🍲", "img-main", "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80"),
    ("isan19", "Kaeng Om Pork (Isan Curry)", "Isan herbal soup with pork, dill, cabbage, pumpkin, and yanang juice.", 140.00, "mains", "🍲", "img-main", "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80"),
    ("isan20", "Kaeng Om Chicken", "Spicy herbal soup with chicken, dill, local vegetables, and roasted rice.", 135.00, "mains", "🍲", "img-main", "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80"),
    ("isan21", "Kaeng Pak Wahn with Ant Eggs", "Clear seasonal soup with wild star gooseberry leaves and premium ant eggs.", 150.00, "mains", "🥣", "img-main", "https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80"),
    ("isan22", "Koi Neua (Beef Tartare)", "Isan-style raw minced beef salad with fresh chili, herbs, and bitter bile.", 175.00, "mains", "🥩", "img-main", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan23", "Sizzling Moo Nam Tok", "Sizzling hot plate of grilled pork neck tossed with lime, herbs, and roasted rice.", 165.00, "mains", "🍳", "img-main", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan24", "Yum Moo Yor (Pork Sausage)", "Spicy Vietnamese pork sausage salad with onions, tomatoes, and lime juice.", 110.00, "mains", "🍥", "img-main", "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80"),
    ("isan25", "Yum Glass Noodle Seafood", "Spicy salad with glass noodles, fresh river prawns, squid, and celery.", 160.00, "mains", "🥗", "img-main", "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=400&q=80"),
    # Appetizers (15)
    ("isan26", "Classic Gai Yang (Half)", "Charcoal-grilled marinated chicken served with sweet chili and spicy Jaew sauces.", 180.00, "appetizers", "🍗", "img-app", "https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?w=400&q=80"),
    ("isan27", "Classic Gai Yang (Whole)", "Full-sized charcoal-grilled marinated chicken with authentic Isan spices.", 340.00, "appetizers", "🐔", "img-app", "https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?w=400&q=80"),
    ("isan28", "Moo Ping with Sticky Rice", "Three skewers of grilled sweet pork served with warm steamed sticky rice.", 95.00, "appetizers", "🍢", "img-app", "https://images.unsplash.com/photo-1582576163090-09d3b6f8a969?w=400&q=80"),
    ("isan29", "Kor Moo Yang (Pork Neck)", "Sliced charcoal-grilled pork neck served with spicy tamarind Jaew dipping sauce.", 150.00, "appetizers", "🥩", "img-app", "https://images.unsplash.com/photo-1603048588665-791ca8aea617?w=400&q=80"),
    ("isan30", "Suea Rong Hai (Crying Tiger)", "Charcoal-grilled marinated beef brisket served with dynamic chili Jaew sauce.", 220.00, "appetizers", "🥩", "img-app", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan31", "Isan Sausage Skewers", "Grilled fermented pork and rice sausage served with ginger and cabbage leaves.", 110.00, "appetizers", "🍥", "img-app", "https://images.unsplash.com/photo-1582576163090-09d3b6f8a969?w=400&q=80"),
    ("isan32", "Sai Krok E-San Moo (Balls)", "Grilled round fermented pork and garlic sausage balls served with fresh chilies.", 110.00, "appetizers", "🍡", "img-app", "https://images.unsplash.com/photo-1582576163090-09d3b6f8a969?w=400&q=80"),
    ("isan33", "Fried Larb Balls (Larb Tod)", "Deep-fried spicy minced pork balls with roasted ground rice and lime leaves.", 115.00, "appetizers", "🧆", "img-app", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan34", "Crispy Isan Chicken Wings", "Deep-fried marinated chicken wings tossed in garlic and light soy sauce.", 120.00, "appetizers", "🍗", "img-app", "https://images.unsplash.com/photo-1569058242253-92a9c755a0ec?w=400&q=80"),
    ("isan35", "Deep Fried Pork Ribs", "Crispy deep-fried marinated pork ribs topped with crispy golden garlic.", 140.00, "appetizers", "🥩", "img-app", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan36", "Crispy Pork Crackling", "Crunchy deep-fried pork rinds, the perfect accompaniment for papaya salad.", 40.00, "appetizers", "🥓", "img-app", "https://images.unsplash.com/photo-1608039829572-78524f79c4c7?w=400&q=80"),
    ("isan37", "Fried Sun-Dried Pork (Moo Dad Deaw)", "Deep-fried sweet and salty marinated sun-dried pork strips.", 130.00, "appetizers", "🥩", "img-app", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan38", "Fried Sun-Dried Beef (Neua Dad Deaw)", "Deep-fried marinated sun-dried beef strips served with chili sauce.", 160.00, "appetizers", "🥩", "img-app", "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&q=80"),
    ("isan39", "Grilled River Prawn (Single)", "Charcoal grilled giant river prawn served with spicy garlic seafood sauce.", 145.00, "appetizers", "🦐", "img-app", "https://images.unsplash.com/photo-1559314809-0d155014e29e?w=400&q=80"),
    ("isan40", "Steamed Sticky Rice (Khao Niew)", "Warm steamed Thai glutinous rice served in a traditional bamboo basket.", 20.00, "appetizers", "🍚", "img-app", "https://images.unsplash.com/photo-1536304997881-a372c179924b?w=400&q=80"),
    # Drinks (10)
    ("isan41", "Cold Chrysanthemum Tea", "Sweet and cooling herbal chrysanthemum infusion served over ice.", 45.00, "drinks", "🥤", "img-drink", "https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=400&q=80"),
    ("isan42", "Cold Roselle Juice", "Sweet and tart herbal roselle flower tea served with ice cubes.", 45.00, "drinks", "🥤", "img-drink", "https://images.unsplash.com/photo-1497534446932-c925b458314e?w=400&q=80"),
    ("isan43", "Lemongrass Pandan Iced Tea", "Fragrant iced tea brewed with fresh lemongrass stalk and sweet pandan leaves.", 50.00, "drinks", "🥤", "img-drink", "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=400&q=80"),
    ("isan44", "Traditional Thai Iced Milk Tea", "Sweet brewed orange Thai tea topped with evaporated milk over shaved ice.", 65.00, "drinks", "🥤", "img-drink", "https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=400&q=80"),
    ("isan45", "Thai Black Tea (Cha Dum Yen)", "Sweetened dark brewed Thai tea served chilled over crushed ice.", 55.00, "drinks", "🥤", "img-drink", "https://images.unsplash.com/photo-1576092768241-dec231879fc3?w=400&q=80"),
    ("isan46", "Fresh Whole Young Coconut", "Freshly opened sweet young coconut juice with tender coconut flesh.", 80.00, "drinks", "🥥", "img-drink", "https://images.unsplash.com/photo-1526318896980-cf78c088247c?w=400&q=80"),
    ("isan47", "Singha Lager Beer (Small)", "Premium clean Thai lager beer bottle, served chilled.", 95.00, "drinks", "🍺", "img-drink", "https://images.unsplash.com/photo-1608270586620-248524c67de9?w=400&q=80"),
    ("isan48", "Chang Lager Beer (Small)", "Famous crisp and strong Thai lager beer, served ice-cold.", 90.00, "drinks", "🍺", "img-drink", "https://images.unsplash.com/photo-1608270586620-248524c67de9?w=400&q=80"),
    ("isan49", "Sparkling Lime Pandan Soda", "Refreshing carbonated soda infused with fresh lime juice and pandan syrup.", 55.00, "drinks", "🍹", "img-drink", "https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?w=400&q=80"),
    ("isan50", "Mineral Drinking Water", "Chilled bottled mineral drinking water served with a glass of ice.", 20.00, "drinks", "🥛", "img-drink", "https://images.unsplash.com/photo-1548865140-64a23cf87aee?w=400&q=80"),
]

def get_default_tables(merchant_id):
    return [
        ("436490cb-2f10-4d16-938d-332b61b5181f", merchant_id, "4", 6, "vacant", "t4_static_hash", 40.0, 200.0, 1, 0, 0, "Indoor"),
        ("8715ff6f-2918-480e-8d98-2aeceaf2ad7e", merchant_id, "VIP 1", 10, "vacant", "tvip1_static_hash", 140.0, 360.0, 1, 0, 0, "Outdoor"),
        ("612077f4-8ea1-4953-b449-21ac188dbff8", merchant_id, "2", 4, "vacant", "t2_static_hash", 200.0, 40.0, 1, 0, 0, "Indoor"),
        ("d2c655ee-7bd0-48bc-83d1-d5ce34b3c9c4", merchant_id, "1", 2, "vacant", "t1_static_hash", 40.0, 40.0, 1, 0, 0, "Indoor"),
        ("7ba6b519-fd1b-4d52-99f1-0d62bf3f0157", merchant_id, "3", 2, "vacant", "t3_static_hash", 327.5, 36.5, 1, 0, 0, "Outdoor"),
        ("d1921924-9a88-4fc1-bdac-4c69b18ca3b4", merchant_id, "5", 8, "vacant", "t5_static_hash", 202.5, 190.5, 1, 0, 0, "Outdoor"),
        ("2f2c9f86-6e59-4030-995d-544bd482a1a3", merchant_id, "201", 4, "vacant", "t201_static_hash", 60.0, 60.0, 2, 0, 0, "Indoor"),
        ("51573667-fe9d-466b-8a52-d9b5e127a54a", merchant_id, "202", 4, "vacant", "t202_static_hash", 240.0, 60.0, 2, 0, 0, "Indoor"),
        ("b272e586-ab81-4478-99a5-77818b3257b7", merchant_id, "203", 6, "vacant", "t203_static_hash", 420.0, 60.0, 2, 0, 0, "Indoor"),
        ("d57c7c5c-4fa7-4b9f-b104-a270aeb965ac", merchant_id, "301 (ROOF)", 8, "vacant", "t301_static_hash", 120.0, 120.0, 3, 0, 0, "Rooftop")
    ]
