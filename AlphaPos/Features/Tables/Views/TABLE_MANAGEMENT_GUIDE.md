# Table Management UI/UX Redesign - Implementation Guide

## Overview

The Table Management system has been completely redesigned with new UX/UI features including:

1. **Interactive Floor Plan Canvas** - Visual drag-and-drop interface for managing table layouts
2. **Add New Tables** - Create tables with custom numbers and seat counts
3. **Adjust Seat Capacity** - Easily modify the number of seats per table
4. **Drag-and-Drop Positioning** - Rearrange table positions like moving apps on a mobile device
5. **Visual Status Indicators** - Color-coded status system (Vacant, Occupied, Reserved, Cleaning)
6. **Edit Mode Toggle** - Switch between view and edit modes

---

## Key Features

### 1. Floor Plan Canvas
- Interactive visual representation of the restaurant layout
- Grid background for positioning reference
- Tables displayed with visual indicators for capacity and status
- Smooth drag-and-drop gestures for repositioning

**How to Use:**
- Toggle "Edit Layout" mode to enable dragging
- Tap and drag any table to reposition it
- Tables snap to grid for better alignment
- Position data is automatically saved

### 2. Add New Tables
- Dedicated modal sheet for creating new tables
- Input fields for:
  - **Table Number/Name**: Unique identifier (e.g., "1", "A", "VIP-1")
  - **Number of Seats**: 1-20 seats with +/- buttons
  - **Initial Status**: vacant, reserved, or cleaning
- Live preview of table appearance
- Visual chair layout representation

**How to Use:**
1. Tap "Add Table" button
2. Enter table number/name
3. Adjust seat count using +/- buttons
4. Select initial status
5. Tap "Create Table" to add

### 3. Edit Table Capacity
- Quick capacity adjustment from table detail view
- +/- buttons for easy modification
- Changes saved immediately
- Visual feedback during editing

**How to Use:**
1. Tap any table to open details
2. Tap pencil icon next to capacity
3. Use +/- buttons to adjust seats
4. Tap "Done" to confirm

### 4. Color-Coded Status System
- **Vacant (Teal)**: Table available for customers
- **Occupied (Rose)**: Currently in use with active session
- **Reserved (Amber)**: Pre-booked table
- **Cleaning (Accent)**: Being prepared for next use

---

## Model Updates

### RestaurantTable Model Changes

Added positioning properties:
```swift
var positionX: Double = 0
var positionY: Double = 0
```

These properties store the exact coordinates of each table on the floor plan canvas, allowing for persistent storage of layout arrangements.

---

## Component Structure

### Main Components

#### `TableView`
- Main container for the floor plan
- Manages tables array via SwiftData @Query
- Handles layout edit mode toggle
- Displays floor plan canvas with draggable tables
- Integrates add table functionality

#### `AddTableSheet`
- Modal form for creating new tables
- Input validation
- Live preview
- Error handling

#### `TableDetailView`
- Shows table details and active session info
- Allows capacity editing
- Manages session operations (open, close, checkout)
- Displays QR code for customer ordering

---

## Usage Scenarios

### Scenario 1: Setting Up Restaurant Layout
1. Open Table Management
2. Tap "Add Table" multiple times to create all tables
3. Fill in table numbers and seat counts
4. Toggle "Edit Layout" to ON
5. Drag tables to desired positions matching restaurant floor plan
6. Toggle "Edit Layout" to OFF when done

### Scenario 2: Seating Customers
1. Tap desired table
2. Tap "Open Table Session & Generate QR"
3. Table becomes occupied (red) and QR code is generated
4. Customers can scan QR to order from mobile web

### Scenario 3: Reorganizing Layout
1. Toggle "Edit Layout" to ON
2. Drag tables to new positions
3. Tables automatically save position when dragging ends
4. Toggle "Edit Layout" to OFF

---

## Data Persistence

- All table information is stored in SwiftData
- Position coordinates are persisted for layout continuity
- Changes sync via the offline-first sync engine
- Timestamped with `updatedAt` for conflict resolution

---

## Visual Design System

- **Design Language**: AlphaPos Design System
- **Color Palette**: 
  - Accent/Primary: Cyan/Teal
  - Success/Positive: Green
  - Danger/Destructive: Rose/Red
  - Warning: Amber/Orange
  
- **Spacing**: Consistent gap and padding sizing
- **Corner Radius**: 
  - Small (sm): 6pt
  - Medium (md): 8pt
  - Large (lg): 12pt

---

## Technical Details

### State Management
- Uses SwiftUI @State for UI state
- @Bindable for model binding
- @Query for data fetching from SwiftData
- ModelContext for database operations

### Gestures
- **Drag Gesture**: Used for repositioning tables in edit mode
- Only active when "Edit Layout" is toggled ON
- Smooth animation and shadow feedback during drag

### Validation
- Table number cannot be empty
- Capacity range: 1-20 seats
- Error alerts for invalid inputs

---

## Future Enhancement Opportunities

1. **Multi-floor Support**: Add floor selection dropdown
2. **Custom Shapes**: Support different table shapes (round, rectangular)
3. **Zone Management**: Group tables into service zones
4. **Capacity Warnings**: Alert when overshooting restaurant max capacity
5. **Import/Export**: Save and load layout configurations
6. **Undo/Redo**: History of layout changes
7. **Snapping Grid**: Optional magnetic grid for alignment
8. **Table Rotation**: Rotate table orientation

---

## Testing

The view includes preview data with:
- Mock tables in various states
- Sample positions for layout reference
- In-memory SwiftData for preview mode

Run tests with:
```bash
./run_tests.sh
```

---

## Support

For issues or feature requests, refer to:
- Code structure: `/Users/mac/Documents/AlphaPos/AlphaPos/Features/Tables/Views/`
- Models: `/Users/mac/Documents/AlphaPos/AlphaPos/Models/RestaurantTable.swift`
