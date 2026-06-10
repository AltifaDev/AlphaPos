import Foundation
import SwiftData
import SwiftUI

@Observable
final class SalesViewModel {
    enum SummaryMode {
        case daily
        case monthly
    }
    
    // UI state variables
    var summaryMode: SummaryMode = .daily
    var selectedDate: Date = Date()
    var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    
    // Aggregated Metrics (KPIs)
    var grossRevenue: Double = 0.0
    var netRevenue: Double = 0.0
    var taxCollected: Double = 0.0
    var serviceChargeCollected: Double = 0.0
    var discountGiven: Double = 0.0
    var totalOrders: Int = 0
    var averageTicketValue: Double = 0.0
    var totalItemsSold: Int = 0
    
    // Trend & Breakdown structures
    var hourlyTrend: [HourlySalesPoint] = []
    var dailyTrend: [DailySalesPoint] = []
    var paymentBreakdown: [PaymentBreakdownPoint] = []
    var productSales: [ProductSalesPoint] = []
    var historicalOrders: [Order] = []
    
    // Available years for filter picker (Current Year - 2 to Current Year + 1)
    let availableYears: [Int] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((currentYear - 2)...(currentYear + 1))
    }()
    
    let monthsList = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    
    init() {}
    
    /// Queries the model context and calculates all metrics for the selected period
    func updateAnalytics(orders: [Order]) {
        let calendar = Calendar.current
        
        // 1. Filter orders matching the date criteria AND that are completed (have payments)
        let filtered = orders.filter { order in
            // Must have associated payments and not be deleted
            guard !order.isDeleted, !order.payments.isEmpty else { return false }
            
            switch summaryMode {
            case .daily:
                return calendar.isDate(order.createdAt, inSameDayAs: selectedDate)
            case .monthly:
                let orderMonth = calendar.component(.month, from: order.createdAt)
                let orderYear = calendar.component(.year, from: order.createdAt)
                return orderMonth == selectedMonth && orderYear == selectedYear
            }
        }
        
        // Sort matching orders newest first
        self.historicalOrders = filtered.sorted(by: { $0.createdAt > $1.createdAt })
        
        // 2. Reset Aggregates
        var tempGross: Double = 0.0
        var tempNet: Double = 0.0
        var tempTax: Double = 0.0
        var tempService: Double = 0.0
        var tempDiscount: Double = 0.0
        var tempItemsCount: Int = 0
        
        // Hourly / Daily temporary maps
        var hourlyMap: [Int: Double] = [:]
        var dailyMap: [Int: Double] = [:]
        
        // Payment breakdowns temporary map
        var paymentMap: [String: (amount: Double, count: Int)] = [:]
        
        // Product sales temporary map (Keyed by Product Name)
        var productMap: [String: ProductSalesPoint] = [:]
        
        // 3. Process each completed order
        for order in filtered {
            tempGross += order.total
            tempTax += order.tax
            tempService += order.serviceCharge
            tempDiscount += order.discount
            tempNet += (order.total - order.tax - order.serviceCharge)
            
            // Time breakdowns
            if summaryMode == .daily {
                let hour = calendar.component(.hour, from: order.createdAt)
                hourlyMap[hour, default: 0.0] += order.total
            } else {
                let day = calendar.component(.day, from: order.createdAt)
                dailyMap[day, default: 0.0] += order.total
            }
            
            // Payment methods aggregation
            for payment in order.payments {
                let method = payment.paymentMethod.lowercased()
                let current = paymentMap[method] ?? (amount: 0.0, count: 0)
                paymentMap[method] = (amount: current.amount + payment.amount, count: current.count + 1)
            }
            
            // Product metrics aggregation — keyed by menuItem.id for uniqueness
            for item in order.items {
                // Ignore cancelled items
                guard item.status != "cancelled" else { continue }
                
                tempItemsCount += item.quantity
                let itemId = item.menuItem?.id ?? item.id.uuidString
                let itemName = item.menuItem?.name ?? "Unknown Dish"
                let category = item.menuItem?.category?.name ?? "Other"
                
                if let existing = productMap[itemId] {
                    productMap[itemId] = ProductSalesPoint(
                        name: itemName,
                        category: category,
                        quantity: existing.quantity + item.quantity,
                        unitPrice: item.unitPrice,
                        totalRevenue: existing.totalRevenue + item.subtotal
                    )
                } else {
                    productMap[itemId] = ProductSalesPoint(
                        name: itemName,
                        category: category,
                        quantity: item.quantity,
                        unitPrice: item.unitPrice,
                        totalRevenue: item.subtotal
                    )
                }
            }
        }
        
        // 4. Assign Primary KPIs
        self.grossRevenue = tempGross
        self.taxCollected = tempTax
        self.serviceChargeCollected = tempService
        self.discountGiven = tempDiscount
        self.netRevenue = tempNet
        self.totalOrders = filtered.count
        self.averageTicketValue = filtered.isEmpty ? 0.0 : (tempGross / Double(filtered.count))
        self.totalItemsSold = tempItemsCount
        
        // 5. Structure Time series Chart points
        if summaryMode == .daily {
            // Fill standard operating hours (e.g. 9:00 AM to 10:00 PM)
            var points: [HourlySalesPoint] = []
            for hour in 9...22 {
                points.append(HourlySalesPoint(hour: hour, revenue: hourlyMap[hour] ?? 0.0))
            }
            // Add any other hours that had sales
            for (hour, rev) in hourlyMap where hour < 9 || hour > 22 {
                points.append(HourlySalesPoint(hour: hour, revenue: rev))
            }
            self.hourlyTrend = points.sorted(by: { $0.hour < $1.hour })
        } else {
            // Fill all days in the selected month
            var points: [DailySalesPoint] = []
            let range = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth)) ?? Date())
            let daysLimit = range?.count ?? 30
            for day in 1...daysLimit {
                points.append(DailySalesPoint(day: day, revenue: dailyMap[day] ?? 0.0))
            }
            self.dailyTrend = points.sorted(by: { $0.day < $1.day })
        }
        
        // 6. Structure Payment breakdown points
        self.paymentBreakdown = paymentMap.map { (key, value) in
            // Map keys into clean display names
            let displayName: String
            switch key {
            case "cash": displayName = "Cash"
            case "credit_card": displayName = "Credit Card"
            case "qr_promptpay": displayName = "PromptPay QR"
            case "true_money": displayName = "TrueMoney Wallet"
            default: displayName = key.capitalized
            }
            return PaymentBreakdownPoint(method: displayName, amount: value.amount, count: value.count)
        }.sorted(by: { $0.amount > $1.amount })
        
        // 7. Structure Product Sales points (Sorted by quantity sold descending)
        self.productSales = productMap.values.sorted(by: { $0.quantity > $1.quantity })
    }
}

// MARK: - Supporting Data Structures

struct HourlySalesPoint: Identifiable, Equatable {
    var id: Int { hour }
    let hour: Int
    let revenue: Double
    
    var hourLabel: String {
        let ampm = hour >= 12 ? "PM" : "AM"
        let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return "\(displayHour) \(ampm)"
    }
}

struct DailySalesPoint: Identifiable, Equatable {
    var id: Int { day }
    let day: Int
    let revenue: Double
    
    var dayLabel: String {
        return "\(day)"
    }
}

struct PaymentBreakdownPoint: Identifiable, Equatable {
    var id: String { method }
    let method: String
    let amount: Double
    let count: Int
}

struct ProductSalesPoint: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let category: String
    let quantity: Int
    let unitPrice: Double
    let totalRevenue: Double
}
