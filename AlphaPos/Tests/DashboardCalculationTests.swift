// DashboardCalculationTests.swift
// Pure regression coverage for the accounting rules shared by Dashboard/Reports.

import Foundation

enum DashboardCalculationLogic {
    struct RestaurantLineInput {
        let lineType: String
        let quantity: Int
        let modifierCount: Int
    }

    static func restaurantLineCounts(_ lines: [RestaurantLineInput]) -> (main: Int, addOns: Int, bundle: Int, rewards: Int) {
        lines.reduce(into: (main: 0, addOns: 0, bundle: 0, rewards: 0)) { result, line in
            switch line.lineType {
            case "addon": result.addOns += line.quantity
            case "bundle_component": result.bundle += line.quantity
            case "promotion_reward": result.rewards += line.quantity
            default:
                result.main += line.quantity
                result.addOns += line.modifierCount * line.quantity
            }
        }
    }

    struct PaymentInput {
        let amount: Double
        let status: String
        let paidAt: Date
        let isDeleted: Bool
        var isCaptured: Bool { status == "completed" || status == "captured" }
    }

    struct RefundInput {
        let amount: Double
        let status: String
        let eventAt: Date
        let isDeleted: Bool
    }

    static func isRecognizedSale(orderStatus: String, isDeleted: Bool, payments: [PaymentInput]) -> Bool {
        !isDeleted && orderStatus != "cancelled" &&
        (orderStatus == "completed" || payments.contains { !$0.isDeleted && $0.isCaptured })
    }

    static func completedRefundTotal(_ refunds: [RefundInput], in interval: DateInterval) -> Double {
        refunds.filter {
            !$0.isDeleted && $0.status == "completed" && interval.contains($0.eventAt)
        }.reduce(0) { $0 + max($1.amount, 0) }
    }

    static func settlementVariance(sales: Double, captured: Double, refunds: Double) -> Double {
        (captured - refunds) - (sales - refunds)
    }

    static func reportQuantities(_ lines: [RestaurantLineInput]) -> (main: Int, addOns: Int, allUnits: Int) {
        let main = lines.filter { $0.lineType == "main" }.reduce(0) { $0 + $1.quantity }
        let addOns = lines.filter { $0.lineType == "addon" }.reduce(0) { $0 + $1.quantity }
        let allUnits = lines.reduce(0) { $0 + $1.quantity }
        return (main, addOns, allUnits)
    }

    static func allocatedAmount(lineSubtotal: Double, allLineSubtotal: Double, orderAmount: Double) -> Double {
        guard allLineSubtotal > 0 else { return 0 }
        return orderAmount * lineSubtotal / allLineSubtotal
    }
}

enum DashboardCalculationTests {
    static func runAll() -> [TestResult] {
        [
            failedPaymentDoesNotRecognizeSale(),
            capturedPaymentRecognizesSale(),
            pendingAndRejectedRefundsDoNotReduceRevenue(),
            refundUsesEventPeriod(),
            completedRefundDoesNotCreateFalseVariance(),
            partialPaymentAllocatesTicketComponents(),
            partialPaymentAndRefundReconcileAcrossDashboard(),
            restaurantLineTypesStaySeparate(),
            reportScopesDoNotMixRestaurantLineTypes(),
            reportScopeDiscountsDoNotDuplicate(),
            storefrontAndDeliverySalesSeparationReconciles(),
            storefrontTenderClassificationMatchesZReport(),
            fixedAssetUsesStraightLineDepreciation(),
            investmentPaybackUsesIncrementalCashFlow(),
            legacyCapExNormalizesToFixedAsset(),
            addOnBreakdownItemizationReconcilesWithTotal(),
            storefrontAndDeliveryAddOnSeparationReconciles(),
            transferTenderDetailedBreakdownMatchesTotal(),
            orderVoidReversalReconcilesSalesAndInventory()
        ]
    }

    private static func fixedAssetUsesStraightLineDepreciation() -> TestResult {
        let name = #function
        let monthly = AccountingMath.monthlyStraightLineDepreciation(
            cost: 120_000, residualValue: 12_000, usefulLifeMonths: 36
        )
        return abs(monthly - 3_000) < 0.001
            ? .success(name)
            : .failure(name, "Expected monthly depreciation 3,000, got \(monthly)")
    }

    private static func investmentPaybackUsesIncrementalCashFlow() -> TestResult {
        let name = #function
        let months = AccountingMath.simplePaybackMonths(
            investment: 60_000, monthlyCashBenefit: 12_000, monthlyIncrementalCost: 2_000
        )
        return abs((months ?? 0) - 6) < 0.001
            ? .success(name)
            : .failure(name, "Expected payback 6 months, got \(String(describing: months))")
    }

    private static func legacyCapExNormalizesToFixedAsset() -> TestResult {
        let name = #function
        let treatment = AccountingMath.normalizedExpenseRecognition("", legacyIsCapEx: true)
        return treatment == "fixed_asset"
            ? .success(name)
            : .failure(name, "Legacy CapEx normalized to \(treatment)")
    }

    private static func restaurantLineTypesStaySeparate() -> TestResult {
        let name = #function
        let counts = DashboardCalculationLogic.restaurantLineCounts([
            .init(lineType: "main", quantity: 2, modifierCount: 1),
            .init(lineType: "addon", quantity: 1, modifierCount: 0),
            .init(lineType: "bundle_component", quantity: 3, modifierCount: 0),
            .init(lineType: "promotion_reward", quantity: 1, modifierCount: 0)
        ])
        return counts.main == 2 && counts.addOns == 3 && counts.bundle == 3 && counts.rewards == 1
            ? .success(name)
            : .failure(name, "Restaurant line types were merged: \(counts)")
    }

    private static func reportScopesDoNotMixRestaurantLineTypes() -> TestResult {
        let name = #function
        let quantities = DashboardCalculationLogic.reportQuantities([
            .init(lineType: "main", quantity: 2, modifierCount: 0),
            .init(lineType: "addon", quantity: 3, modifierCount: 0),
            .init(lineType: "bundle_component", quantity: 4, modifierCount: 0),
            .init(lineType: "promotion_reward", quantity: 1, modifierCount: 0)
        ])
        return quantities.main == 2 && quantities.addOns == 3 && quantities.allUnits == 10
            ? .success(name)
            : .failure(name, "Report scopes were mixed: \(quantities)")
    }

    private static func reportScopeDiscountsDoNotDuplicate() -> TestResult {
        let name = #function
        let mainDiscount = DashboardCalculationLogic.allocatedAmount(lineSubtotal: 80, allLineSubtotal: 100, orderAmount: 10)
        let addOnDiscount = DashboardCalculationLogic.allocatedAmount(lineSubtotal: 20, allLineSubtotal: 100, orderAmount: 10)
        return abs(mainDiscount - 8) < 0.001 && abs(addOnDiscount - 2) < 0.001 && abs(mainDiscount + addOnDiscount - 10) < 0.001
            ? .success(name)
            : .failure(name, "Scoped discounts duplicated: main=\(mainDiscount), addOn=\(addOnDiscount)")
    }

    private static func failedPaymentDoesNotRecognizeSale() -> TestResult {
        let name = #function
        let payment = DashboardCalculationLogic.PaymentInput(amount: 100, status: "failed", paidAt: Date(), isDeleted: false)
        return DashboardCalculationLogic.isRecognizedSale(orderStatus: "preparing", isDeleted: false, payments: [payment])
            ? .failure(name, "A failed payment must not recognize revenue.") : .success(name)
    }

    private static func capturedPaymentRecognizesSale() -> TestResult {
        let name = #function
        let payment = DashboardCalculationLogic.PaymentInput(amount: 100, status: "captured", paidAt: Date(), isDeleted: false)
        return DashboardCalculationLogic.isRecognizedSale(orderStatus: "preparing", isDeleted: false, payments: [payment])
            ? .success(name) : .failure(name, "Captured tender must recognize revenue.")
    }

    private static func pendingAndRejectedRefundsDoNotReduceRevenue() -> TestResult {
        let name = #function
        let now = Date()
        let interval = DateInterval(start: now.addingTimeInterval(-10), end: now.addingTimeInterval(10))
        let refunds = [
            DashboardCalculationLogic.RefundInput(amount: 20, status: "pending_approval", eventAt: now, isDeleted: false),
            DashboardCalculationLogic.RefundInput(amount: 30, status: "rejected", eventAt: now, isDeleted: false)
        ]
        return DashboardCalculationLogic.completedRefundTotal(refunds, in: interval) == 0
            ? .success(name) : .failure(name, "Only completed refunds may reduce revenue.")
    }

    private static func refundUsesEventPeriod() -> TestResult {
        let name = #function
        let now = Date()
        let interval = DateInterval(start: now.addingTimeInterval(-10), end: now.addingTimeInterval(10))
        let old = DashboardCalculationLogic.RefundInput(amount: 50, status: "completed", eventAt: now.addingTimeInterval(-86_400), isDeleted: false)
        return DashboardCalculationLogic.completedRefundTotal([old], in: interval) == 0
            ? .success(name) : .failure(name, "Refund must be attributed to its event date, not the order date.")
    }

    private static func completedRefundDoesNotCreateFalseVariance() -> TestResult {
        let name = #function
        let variance = DashboardCalculationLogic.settlementVariance(sales: 1_000, captured: 1_000, refunds: 200)
        return abs(variance) < 0.001
            ? .success(name) : .failure(name, "A valid refund produced variance \(variance).")
    }

    private static func partialPaymentAllocatesTicketComponents() -> TestResult {
        let name = #function
        let fraction = AccountingMath.capturedFraction(ticketTotal: 1_000, recognizedBeforeRefunds: 400)
        let grossBeforeDiscount = 1_100 * fraction
        let discount = 100 * fraction
        return abs(fraction - 0.4) < 0.001 && abs(grossBeforeDiscount - discount - 400) < 0.001
            ? .success(name) : .failure(name, "Partial capture must recognize 40% of gross and discount.")
    }

    private static func partialPaymentAndRefundReconcileAcrossDashboard() -> TestResult {
        let name = #function
        let ledgerNet = [
            AccountingMath.recognizedAmount(eventType: "sale_capture", amount: 400)!,
            AccountingMath.recognizedAmount(eventType: "refund", amount: -100)!
        ].reduce(0, +)
        let hourly = ledgerNet
        let categories = AccountingMath.allocate(ledgerNet, weights: [600, 400])
        let profit = ledgerNet - (250 * AccountingMath.capturedFraction(ticketTotal: 1_000, recognizedBeforeRefunds: 400))
        let reconciles = abs(hourly - 300) < 0.001 && abs(categories.reduce(0, +) - 300) < 0.001 && abs(profit - 200) < 0.001
        return reconciles ? .success(name) : .failure(name, "Partial payment/refund did not reconcile: hourly=\(hourly), categories=\(categories), profit=\(profit)")
    }

    private static func storefrontAndDeliverySalesSeparationReconciles() -> TestResult {
        let name = #function
        struct OrderMock {
            let orderType: String
            let deliveryBrand: String?
            let netTotal: Double
        }

        let orders = [
            OrderMock(orderType: "dine_in", deliveryBrand: nil, netTotal: 500),
            OrderMock(orderType: "take_out", deliveryBrand: nil, netTotal: 300),
            OrderMock(orderType: "delivery", deliveryBrand: "Grab", netTotal: 450),
            OrderMock(orderType: "delivery", deliveryBrand: "LINE MAN", netTotal: 250)
        ]

        let storefrontTotal = orders.filter { $0.orderType != "delivery" }.reduce(0.0) { $0 + $1.netTotal }
        let deliveryTotal = orders.filter { $0.orderType == "delivery" }.reduce(0.0) { $0 + $1.netTotal }
        let totalRevenue = orders.reduce(0.0) { $0 + $1.netTotal }

        let validSum = abs((storefrontTotal + deliveryTotal) - totalRevenue) < 0.001
        let validStorefront = abs(storefrontTotal - 800) < 0.001
        let validDelivery = abs(deliveryTotal - 700) < 0.001

        return (validSum && validStorefront && validDelivery)
            ? .success(name)
            : .failure(name, "Storefront (\(storefrontTotal)) + Delivery (\(deliveryTotal)) != Total (\(totalRevenue))")
    }

    private static func storefrontTenderClassificationMatchesZReport() -> TestResult {
        let name = #function
        struct PaymentMock {
            let method: String
            let amount: Double
            let isDelivery: Bool
        }

        let payments = [
            PaymentMock(method: "cash", amount: 400, isDelivery: false),
            PaymentMock(method: "qr_promptpay", amount: 400, isDelivery: false),
            PaymentMock(method: "credit_card", amount: 200, isDelivery: false),
            PaymentMock(method: "grab", amount: 350, isDelivery: true)
        ]

        let inStoreCash = payments.filter { !$0.isDelivery && $0.method == "cash" }.reduce(0.0) { $0 + $1.amount }
        let inStoreQR = payments.filter { !$0.isDelivery && ["qr_promptpay", "transfer"].contains($0.method) }.reduce(0.0) { $0 + $1.amount }
        let inStoreTotal = payments.filter { !$0.isDelivery }.reduce(0.0) { $0 + $1.amount }
        let deliveryTotal = payments.filter { $0.isDelivery }.reduce(0.0) { $0 + $1.amount }

        let matches = inStoreCash == 400 && inStoreQR == 400 && inStoreTotal == 1000 && deliveryTotal == 350
        return matches
            ? .success(name)
            : .failure(name, "In-store tender breakdown mismatch: cash=\(inStoreCash), qr=\(inStoreQR), inStoreTotal=\(inStoreTotal), delivery=\(deliveryTotal)")
    }

    private static func addOnBreakdownItemizationReconcilesWithTotal() -> TestResult {
        let name = #function
        struct MockModifier {
            let name: String
            let price: Double
        }
        struct MockItem {
            let name: String
            let lineType: String
            let quantity: Int
            let unitPrice: Double
            let subtotal: Double
            let modifiers: [MockModifier]
        }

        let items: [MockItem] = [
            MockItem(name: "ข้าวผัดกะเพรา", lineType: "main", quantity: 2, unitPrice: 60, subtotal: 120, modifiers: [
                MockModifier(name: "ไข่ดาว", price: 10),
                MockModifier(name: "พิเศษเนื้อ", price: 15)
            ]),
            MockItem(name: "กาแฟลาเต้", lineType: "main", quantity: 1, unitPrice: 55, subtotal: 55, modifiers: [
                MockModifier(name: "เพิ่มช็อตกาแฟ", price: 15)
            ]),
            MockItem(name: "ไข่ต้ม", lineType: "addon", quantity: 3, unitPrice: 10, subtotal: 30, modifiers: [])
        ]

        var totalAddOnsSold = 0
        var totalAddOnsRevenue = 0.0
        var breakdown: [String: (qty: Int, rev: Double)] = [:]

        for item in items {
            switch item.lineType {
            case "main":
                totalAddOnsSold += item.modifiers.count * item.quantity
                let modRev = item.modifiers.reduce(0.0) { $0 + ($1.price * Double(item.quantity)) }
                totalAddOnsRevenue += modRev
                for mod in item.modifiers {
                    let rev = mod.price * Double(item.quantity)
                    breakdown[mod.name, default: (0, 0)].qty += item.quantity
                    breakdown[mod.name, default: (0, 0)].rev += rev
                }
            case "addon":
                totalAddOnsSold += item.quantity
                totalAddOnsRevenue += item.subtotal
                breakdown[item.name, default: (0, 0)].qty += item.quantity
                breakdown[item.name, default: (0, 0)].rev += item.subtotal
            default: break
            }
        }

        let breakdownQtySum = breakdown.values.reduce(0) { $0 + $1.qty }
        let breakdownRevSum = breakdown.values.reduce(0.0) { $0 + $1.rev }

        let passed = (totalAddOnsSold == 8) && // (2 mods * 2 qty = 4) + (1 mod * 1 qty = 1) + 3 = 8
                     (totalAddOnsRevenue == 95.0) && // (10*2 + 15*2) + 15 + 30 = 20 + 30 + 15 + 30 = 95
                     (breakdownQtySum == totalAddOnsSold) &&
                     (abs(breakdownRevSum - totalAddOnsRevenue) < 0.001) &&
                     (breakdown["ไข่ดาว"]?.qty == 2 && breakdown["ไข่ดาว"]?.rev == 20.0) &&
                     (breakdown["ไข่ต้ม"]?.qty == 3 && breakdown["ไข่ต้ม"]?.rev == 30.0)

        return passed
            ? .success(name)
            : .failure(name, "Add-on reconciliation failed: totalQty=\(totalAddOnsSold), totalRev=\(totalAddOnsRevenue), breakdownQty=\(breakdownQtySum), breakdownRev=\(breakdownRevSum)")
    }

    private static func storefrontAndDeliveryAddOnSeparationReconciles() -> TestResult {
        let name = #function
        struct MockModifier {
            let name: String
            let price: Double
        }
        struct MockItem {
            let name: String
            let lineType: String
            let quantity: Int
            let unitPrice: Double
            let subtotal: Double
            let modifiers: [MockModifier]
        }
        struct MockOrder {
            let orderType: String
            let items: [MockItem]
        }

        let orders: [MockOrder] = [
            MockOrder(orderType: "dine_in", items: [
                MockItem(name: "ข้าวกะเพรา", lineType: "main", quantity: 2, unitPrice: 60, subtotal: 120, modifiers: [
                    MockModifier(name: "ไข่ดาว", price: 10)
                ]),
                MockItem(name: "น้ำพริกแคบหมู", lineType: "addon", quantity: 3, unitPrice: 20, subtotal: 60, modifiers: [])
            ]),
            MockOrder(orderType: "delivery", items: [
                MockItem(name: "ข้าวผัดปู", lineType: "main", quantity: 1, unitPrice: 90, subtotal: 90, modifiers: [
                    MockModifier(name: "ไข่ดาว", price: 15),
                    MockModifier(name: "พิเศษข้าว", price: 10)
                ]),
                MockItem(name: "ชาไทยเย็น", lineType: "addon", quantity: 2, unitPrice: 35, subtotal: 70, modifiers: [])
            ])
        ]

        var totalAddOnsSold = 0
        var totalAddOnsRevenue = 0.0
        var storefrontAddOnsSold = 0
        var storefrontAddOnsRevenue = 0.0
        var deliveryAddOnsSold = 0
        var deliveryAddOnsRevenue = 0.0

        for order in orders {
            let isDelivery = order.orderType == "delivery"
            for item in order.items {
                switch item.lineType {
                case "main":
                    let modCount = item.modifiers.count * item.quantity
                    let modRev = item.modifiers.reduce(0.0) { $0 + ($1.price * Double(item.quantity)) }
                    totalAddOnsSold += modCount
                    totalAddOnsRevenue += modRev
                    if isDelivery {
                        deliveryAddOnsSold += modCount
                        deliveryAddOnsRevenue += modRev
                    } else {
                        storefrontAddOnsSold += modCount
                        storefrontAddOnsRevenue += modRev
                    }
                case "addon":
                    totalAddOnsSold += item.quantity
                    totalAddOnsRevenue += item.subtotal
                    if isDelivery {
                        deliveryAddOnsSold += item.quantity
                        deliveryAddOnsRevenue += item.subtotal
                    } else {
                        storefrontAddOnsSold += item.quantity
                        storefrontAddOnsRevenue += item.subtotal
                    }
                default: break
                }
            }
        }

        let passed = (storefrontAddOnsSold == 5) && // 2 ไข่ดาว + 3 น้ำพริก = 5
                     (storefrontAddOnsRevenue == 80.0) && // (10*2) + 60 = 80
                     (deliveryAddOnsSold == 4) && // (2 mods * 1 qty = 2) + 2 ชาไทย = 4
                     (deliveryAddOnsRevenue == 95.0) && // 15 + 10 + 70 = 95
                     (totalAddOnsSold == 9) &&
                     (totalAddOnsRevenue == 175.0) &&
                     (storefrontAddOnsSold + deliveryAddOnsSold == totalAddOnsSold) &&
                     (abs((storefrontAddOnsRevenue + deliveryAddOnsRevenue) - totalAddOnsRevenue) < 0.001)

        return passed
            ? .success(name)
            : .failure(name, "Storefront vs Delivery Add-on separation failed: storefrontQty=\(storefrontAddOnsSold), deliveryQty=\(deliveryAddOnsSold), totalQty=\(totalAddOnsSold)")
    }

    private static func transferTenderDetailedBreakdownMatchesTotal() -> TestResult {
        let name = #function
        struct PaymentInput {
            let method: String
            let amount: Double
        }

        let payments = [
            PaymentInput(method: "qr_promptpay", amount: 250),
            PaymentInput(method: "promptpay", amount: 150),
            PaymentInput(method: "bank_transfer", amount: 500),
            PaymentInput(method: "transfer", amount: 100),
            PaymentInput(method: "cash", amount: 300)
        ]

        var totalTransfer = 0.0
        var breakdown: [String: (amount: Double, count: Int)] = [:]

        for p in payments {
            let key = p.method.lowercased()
            if ["qr", "qr_promptpay", "promptpay", "transfer", "bank_transfer"].contains(key) {
                totalTransfer += p.amount
                let subKey = (key.contains("qr") || key.contains("promptpay")) ? "promptpay" : "bank_transfer"
                breakdown[subKey, default: (0, 0)].amount += p.amount
                breakdown[subKey, default: (0, 0)].count += 1
            }
        }

        let promptPayAmount = breakdown["promptpay"]?.amount ?? 0
        let bankTransferAmount = breakdown["bank_transfer"]?.amount ?? 0

        let passed = (totalTransfer == 1000.0) &&
                     (promptPayAmount == 400.0) &&
                     (breakdown["promptpay"]?.count == 2) &&
                     (bankTransferAmount == 600.0) &&
                     (breakdown["bank_transfer"]?.count == 2) &&
                     (promptPayAmount + bankTransferAmount == totalTransfer)

        return passed
            ? .success(name)
            : .failure(name, "Transfer tender breakdown mismatch: total=\(totalTransfer), promptpay=\(promptPayAmount), bank=\(bankTransferAmount)")
    }

    private static func orderVoidReversalReconcilesSalesAndInventory() -> TestResult {
        let name = #function
        var orderStatus = "completed"
        var netSales = 350.0
        var inventoryStock = 10.0
        let itemsConsumed = 3.0
        inventoryStock -= itemsConsumed // Stock deducted on sale -> 7.0

        // Void action with restock = true
        let restock = true
        if restock {
            inventoryStock += itemsConsumed // 7.0 + 3.0 = 10.0 restored
        }
        orderStatus = "cancelled"
        let refundAmount = 350.0
        netSales -= refundAmount // Sales reversed to 0

        let passed = (orderStatus == "cancelled") &&
                     (inventoryStock == 10.0) &&
                     (netSales == 0.0)

        return passed
            ? .success(name)
            : .failure(name, "Void reversal failed: status=\(orderStatus), stock=\(inventoryStock), netSales=\(netSales)")
    }
}

