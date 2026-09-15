#!/usr/bin/env python3
"""Exercise the actual computeDailySales body with lightweight model doubles.
Requires Swift CLI; no UIKit/SwiftData runtime. This does not verify iOS rendering.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'AlphaPos/Features/Reports/ViewModels/ReportsViewModel.swift').read_text()

def block(marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

types = '\n'.join(block('struct ' + name) for name in [
    'ReportsHourlySalesPoint', 'PaymentMethodPoint',
    'DailySalesDeliveryOrderItem', 'DailySalesDeliveryPlatformItem'])
properties = source[source.index('    var grossRevenue:'):source.index('    // ── Z-Report')]
stubs = '''
import Foundation
struct Order {
    var id = UUID()
    var isDeleted = false
    var total = 107.0
    var subtotal = 100.0
    var tax = 7.0
    var serviceCharge = 0.0
    var discount = 0.0
    var orderType = "delivery"
    var orderNumber = "POS-1"
    var platformOrderNumber: String? = "GP-777"
    var deliveryBrand: String? = "GrabFood"
    var deliveryGPFeeAmount = 10.0
    var deliveryAdFeeAmount = 0.0
    var deliveryOtherFee = 0.0
    var status = "completed"
    var createdAt = Date(timeIntervalSince1970: 100)
}
struct Payment {
    var isDeleted = false
    var isCaptured = true
    var order: Order?
    var registerSessionId: UUID?
    var paidAt = Date(timeIntervalSince1970: 100)
    var tipAmount = 0.0
    var amount = 0.0
}
struct FinancialEvent {
    var isDeleted = false
    var status = "posted"
    var eventType: String
    var amount: Double
    var paymentMethod: String? = "cash"
    var orderId: UUID?
    var isLateAdjustment = false
    var registerSessionId: UUID?
    var occurredAt = Date(timeIntervalSince1970: 100)
    var businessDateKey = "1970-01-01"
}
enum ReportDateBasis { case registerShift, businessDay, calendarDay }
enum BusinessDayContext {
    static func key(for date: Date, cutoffHour: Int = 4, timeZoneID: String = "Asia/Bangkok") -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let shifted = calendar.date(byAdding: .hour, value: -cutoffHour, to: date) ?? date
        let components = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
    static func contains(businessDateKey: String, from start: Date, to end: Date, cutoffHour: Int = 4, timeZoneID: String = "Asia/Bangkok") -> Bool {
        guard !businessDateKey.isEmpty else { return false }
        let startKey = key(for: start, cutoffHour: cutoffHour, timeZoneID: timeZoneID)
        let lastMoment = end.addingTimeInterval(-0.001)
        let endKey = key(for: lastMoment >= start ? lastMoment : start, cutoffHour: cutoffHour, timeZoneID: timeZoneID)
        return businessDateKey >= startKey && businessDateKey <= endKey
    }
}
'''
selection = '''
    var effectiveStartDate = Date(timeIntervalSince1970: 0)
    var effectiveEndDate = Date(timeIntervalSince1970: 1000)
    var selectedRegisterSessionId: UUID?
    var dateBasis = ReportDateBasis.calendarDay
    var businessDayCutoffHour = 4
    var businessTimeZoneID = "Asia/Bangkok"
'''
tests = '''
func near(_ actual: Double, _ expected: Double) {
    precondition(abs(actual - expected) < 0.0001, "expected \\(expected), got \\(actual)")
}
let vm = ReportHarness()
let order = Order()
let sale = FinancialEvent(eventType: "sale_capture", amount: 107, orderId: order.id)
let refund = FinancialEvent(eventType: "refund", amount: 53.5, orderId: order.id)
vm.computeDailySales(orders: [order], payments: [], financialEvents: [sale, refund])
near(vm.deliveryRefunds, 53.5)
near(vm.deliveryNetReceivables, 43.5)
near(vm.deliveryPlatformBreakdown[0].netReceivables, 43.5)
near(vm.accountingRevenueExVAT, 50)
precondition(vm.deliveryOrderDetails[0].platformOrderNumber == "GP-777")
precondition(vm.deliveryOrderDetails[0].orderNumber == "POS-1")
// Historical order with only a refund in this reporting period.
vm.computeDailySales(orders: [order], payments: [], financialEvents: [refund])
near(vm.deliveryNetReceivables, -53.5)
near(vm.deliveryPlatformBreakdown[0].netReceivables, -53.5)
near(vm.deliveryOrderDetails[0].netSales, 0)
near(vm.deliveryOrderDetails[0].refunds, 53.5)
near(vm.accountingRevenueExVAT, -50)
precondition(vm.deliveryOrdersCount == 0)
// Storefront refund-only periods must also retain their negative balance.
var store = order
store.orderType = "dine_in"
vm.computeDailySales(orders: [store], payments: [], financialEvents: [refund])
near(vm.storefrontNetRevenue, -53.5)
precondition(vm.deliveryOrderDetails.isEmpty)
// Trim brand keys consistently and expose missing external IDs, never POS IDs.
var missing = order
missing.deliveryBrand = " GrabFood "
missing.platformOrderNumber = "  "
vm.computeDailySales(orders: [missing], payments: [], financialEvents: [sale, refund])
precondition(vm.deliveryPlatformBreakdown.count == 1)
precondition(vm.deliveryOrderDetails[0].platformOrderNumber == nil)
// Refresh clears prior results; excluded events do not leak into delivery totals.
var excluded = refund
excluded.status = "pending"
vm.computeDailySales(orders: [order], payments: [], financialEvents: [excluded])
near(vm.deliveryRefunds, 0)
precondition(vm.deliveryOrderDetails.isEmpty && vm.deliveryPlatformBreakdown.isEmpty)

// Multi-day businessDay range test: Ensure all days in multi-day range are captured.
var multiDayVM = ReportHarness()
multiDayVM.dateBasis = .businessDay
// Set 3-day range: 2026-09-01 04:00:00 to 2026-09-04 04:00:00 ICT
let df = DateFormatter()
df.calendar = Calendar(identifier: .gregorian)
df.dateFormat = "yyyy-MM-dd HH:mm:ss"
df.timeZone = TimeZone(identifier: "Asia/Bangkok")
multiDayVM.effectiveStartDate = df.date(from: "2026-09-01 04:00:00")!
multiDayVM.effectiveEndDate = df.date(from: "2026-09-04 04:00:00")!

let ord1 = Order(id: UUID(), isDeleted: false, total: 100, subtotal: 100, tax: 0, serviceCharge: 0, discount: 0, orderType: "dine_in", orderNumber: "POS-101")
let ord2 = Order(id: UUID(), isDeleted: false, total: 200, subtotal: 200, tax: 0, serviceCharge: 0, discount: 0, orderType: "dine_in", orderNumber: "POS-102")
let ord3 = Order(id: UUID(), isDeleted: false, total: 300, subtotal: 300, tax: 0, serviceCharge: 0, discount: 0, orderType: "dine_in", orderNumber: "POS-103")

let eventDay1 = FinancialEvent(eventType: "sale_capture", amount: 100, paymentMethod: "cash", orderId: ord1.id, businessDateKey: "2026-09-01")
let eventDay2 = FinancialEvent(eventType: "sale_capture", amount: 200, paymentMethod: "cash", orderId: ord2.id, businessDateKey: "2026-09-02")
let eventDay3 = FinancialEvent(eventType: "sale_capture", amount: 300, paymentMethod: "cash", orderId: ord3.id, businessDateKey: "2026-09-03")

multiDayVM.computeDailySales(orders: [ord1, ord2, ord3], payments: [], financialEvents: [eventDay1, eventDay2, eventDay3])
near(multiDayVM.grossRevenue, 600)
near(multiDayVM.storefrontGross, 600)
near(multiDayVM.storefrontCash, 600)
precondition(multiDayVM.storefrontOrdersCount == 3)

// Tender variance test: Real payments mismatch detected
var varianceVM = ReportHarness()
let vOrder = Order(id: UUID(), isDeleted: false, total: 100, subtotal: 100, tax: 0, serviceCharge: 0, discount: 0, orderType: "dine_in")
let vSale = FinancialEvent(eventType: "sale_capture", amount: 100, paymentMethod: "cash", orderId: vOrder.id)
// Cashier collected only 90 baht (short by 10)
let vPayment = Payment(isDeleted: false, isCaptured: true, order: vOrder, registerSessionId: nil, paidAt: Date(timeIntervalSince1970: 100), tipAmount: 0, amount: 90)
varianceVM.computeDailySales(orders: [vOrder], payments: [vPayment], financialEvents: [vSale])
near(varianceVM.paymentsCollected, 90)
near(varianceVM.salesTenderVariance, -10)

// Void/reversal storefront adjustment test:
let voidEvent = FinancialEvent(eventType: "payment_void", amount: -30, paymentMethod: "cash", orderId: ord1.id, businessDateKey: "2026-09-01")
multiDayVM.computeDailySales(orders: [ord1, ord2, ord3], payments: [], financialEvents: [eventDay1, eventDay2, eventDay3, voidEvent])
near(multiDayVM.storefrontCash, 570)

print("PASS: production Daily Sales calculation — delivery refunds, refund-only periods, VAT, identifiers, brand normalization, multi-day ranges, void adjustments, refresh and event status")
'''
tmp_dir = root / 'tmp'
tmp_dir.mkdir(exist_ok=True)
module_cache = root / '.build/tests/module-cache'
module_cache.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix='alphapos-dbd-', dir=str(tmp_dir)) as temp:
    main = Path(temp) / 'main.swift'
    main.write_text(stubs + types + '\nfinal class ReportHarness {\n' + selection + properties
                    + block('    func computeDailySales(') + '\n}\n' + tests)
    binary = str(Path(temp) / 'test')
    (root / 'tmp/debug_main.swift').write_text(stubs + types + '\nfinal class ReportHarness {\n' + selection + properties
                    + block('    func computeDailySales(') + '\n}\n' + tests)
    subprocess.run([
        'swiftc',
        '-module-cache-path', str(module_cache),
        str(root / 'AlphaPos/Core/Financial/AccountingMath.swift'),
        str(main), '-o', binary
    ], check=True)
    subprocess.run([binary], check=True)
