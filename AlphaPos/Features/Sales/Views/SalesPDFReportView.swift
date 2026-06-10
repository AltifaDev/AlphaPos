import SwiftUI

struct SalesPDFReportView: View {
    let title: String
    let subtitle: String
    let generatedAt: String
    
    // Financial Metrics
    let grossSales: Double
    let netSales: Double
    let tax: Double
    let serviceCharge: Double
    let discount: Double
    let totalOrders: Int
    let averageTicket: Double
    let totalItems: Int
    
    // Breakdowns
    let payments: [PaymentBreakdownPoint]
    let products: [ProductSalesPoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ALPHAPOS RESTAURANT MANAGEMENT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    Text(title)
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.black)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                }
                Spacer()
                // Logo placeholder or system symbol
                Image(systemName: "bolt.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.black)
                    .padding(10)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
            }
            
            Divider()
                .background(Color.gray.opacity(0.5))
            
            // Meta Information
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generated At:")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                    Text(generatedAt)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Report Scope:")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                    Text("Completed Transactions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            
            // Financial KPI Matrix
            VStack(alignment: .leading, spacing: 10) {
                Text("FINANCIAL SUMMARY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .tracking(1.0)
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        kpiBlock(title: "GROSS SALES", value: "฿\(grossSales.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "NET SALES", value: "฿\(netSales.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "TAX COLLECTED", value: "฿\(tax.formatted(.number.precision(.fractionLength(2))))")
                    }
                    GridRow {
                        kpiBlock(title: "SERVICE CHARGE", value: "฿\(serviceCharge.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "DISCOUNTS GIVEN", value: "฿\(discount.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "TOTAL ORDERS", value: "\(totalOrders)")
                    }
                    GridRow {
                        kpiBlock(title: "AVG ORDER VALUE", value: "฿\(averageTicket.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "TOTAL ITEMS SOLD", value: "\(totalItems)")
                        Color.clear
                    }
                }
                .padding(15)
                .background(Color.black.opacity(0.02))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            
            // Payment Breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("PAYMENT METHOD BREAKDOWN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                
                TableSection {
                    HStack {
                        Text("Method").bold()
                        Spacer()
                        Text("Transactions").bold()
                        Spacer().frame(width: 80)
                        Text("Revenue").bold()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    
                    Divider()
                    
                    if payments.isEmpty {
                        Text("No transactions recorded.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(payments) { pt in
                            HStack {
                                Text(pt.method)
                                Spacer()
                                Text("\(pt.count) orders")
                                Spacer().frame(width: 80)
                                Text("฿\(pt.amount.formatted(.number.precision(.fractionLength(2))))")
                            }
                            .font(.system(size: 10, weight: .medium))
                            
                            Divider()
                        }
                    }
                }
            }
            
            // Top Products Summary (Preview of top 6)
            VStack(alignment: .leading, spacing: 8) {
                Text("TOP PRODUCTS SUMMARY")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                
                TableSection {
                    HStack {
                        Text("Item Name").bold()
                        Spacer()
                        Text("Category").bold()
                        Spacer().frame(width: 80)
                        Text("Qty Sold").bold()
                        Spacer().frame(width: 80)
                        Text("Total Revenue").bold()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    
                    Divider()
                    
                    if products.isEmpty {
                        Text("No items sold.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(products.prefix(6)) { prod in
                            HStack {
                                Text(prod.name)
                                Spacer()
                                Text(prod.category)
                                Spacer().frame(width: 80)
                                Text("\(prod.quantity)")
                                Spacer().frame(width: 80)
                                Text("฿\(prod.totalRevenue.formatted(.number.precision(.fractionLength(2))))")
                            }
                            .font(.system(size: 10))
                            
                            Divider()
                        }
                    }
                }
            }
            
            Spacer()
            
            // Signatures block
            HStack(spacing: 60) {
                VStack(alignment: .center, spacing: 40) {
                    Color.clear.frame(height: 1)
                    Divider().background(Color.black)
                    Text("PREPARED BY (CASHIER)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                }
                VStack(alignment: .center, spacing: 40) {
                    Color.clear.frame(height: 1)
                    Divider().background(Color.black)
                    Text("APPROVED BY (STORE MANAGER)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .padding(40)
        .frame(width: 612, height: 792) // Letter page size
        .background(Color.white)
        .foregroundColor(.black)
    }
    
    // MARK: - Subviews
    
    private func kpiBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TableSection<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
        }
        .padding(10)
        .background(Color.black.opacity(0.01))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}
