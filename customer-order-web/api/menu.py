"""
AlphaPos — Menu & Modifiers API routes
"""
from fastapi import APIRouter, HTTPException
from contextlib import closing
import json

from .deps import get_db_row_connection, log_event

router = APIRouter(prefix="/v1", tags=["menu"])


@router.get("/menu")
def get_menu():
    """Returns all active menu items from local SQLite cache."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM menu_items")
            rows = cursor.fetchall()

            menu = []
            for row in rows:
                row_keys = row.keys()
                name_trans_raw = row["name_translations"] if "name_translations" in row_keys else "{}"
                desc_trans_raw = row["description_translations"] if "description_translations" in row_keys else "{}"

                try:
                    name_trans = json.loads(name_trans_raw) if name_trans_raw else {}
                except Exception:
                    name_trans = {}
                try:
                    desc_trans = json.loads(desc_trans_raw) if desc_trans_raw else {}
                except Exception:
                    desc_trans = {}

                item = {
                    "id": row["id"],
                    "name": row["name"],
                    "desc": row["description"],
                    "price": row["price"],
                    "category": row["category"],
                    "emoji": row["emoji"],
                    "imgClass": row["img_class"],
                    "image_url": row["image_url"] if "image_url" in row_keys else "",
                    "name_translations": name_trans,
                    "description_translations": desc_trans,
                }
                # Add dietary/allergen fields if available
                for col in ("is_vegetarian", "is_vegan", "is_halal", "is_gluten_free", "spice_level", "calories", "prep_time_minutes"):
                    if col in row_keys:
                        item[col] = row[col]
                menu.append(item)

            return menu
    except Exception as e:
        log_event("error", "get_menu_failed", str(e))
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@router.get("/modifiers-config")
def get_modifiers_config():
    """Returns modifier groups with their options for the ordering UI."""
    try:
        with closing(get_db_row_connection()) as conn:
            cursor = conn.cursor()

            # Get modifier groups
            cursor.execute("SELECT * FROM modifier_groups WHERE is_available = 1 ORDER BY sort_order")
            groups = cursor.fetchall()

            result = []
            for group in groups:
                group_id = group["id"]
                cursor.execute(
                    "SELECT * FROM modifiers WHERE group_id = ? AND is_available = 1 ORDER BY sort_order",
                    (group_id,)
                )
                options = cursor.fetchall()

                result.append({
                    "id": group["id"],
                    "name": group["name"],
                    "selection_type": group["selection_type"] if "selection_type" in group.keys() else "single",
                    "min_selections": group["min_selections"] if "min_selections" in group.keys() else 0,
                    "max_selections": group["max_selections"] if "max_selections" in group.keys() else 1,
                    "menu_item_ids": json.loads(group["menu_item_ids"]) if "menu_item_ids" in group.keys() and group["menu_item_ids"] else [],
                    "options": [
                        {
                            "id": opt["id"],
                            "name": opt["name"],
                            "extra_price": float(opt["extra_price"]) if opt["extra_price"] else 0,
                            "is_default": bool(opt["is_default"]) if "is_default" in opt.keys() else False,
                        }
                        for opt in options
                    ]
                })

            return result
    except Exception as e:
        log_event("error", "get_modifiers_failed", str(e))
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
