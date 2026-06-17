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
                    Text("report_brand_header".t)
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
                    Text("generated_at_lbl".t)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                    Text(generatedAt)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("report_scope_lbl".t)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                    Text("completed_transactions_lbl".t)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            
            // Financial KPI Matrix
            VStack(alignment: .leading, spacing: 10) {
                Text("financial_summary_lbl".t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .tracking(1.0)
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow {
                        kpiBlock(title: "kpi_total_revenue".t, value: "฿\(grossSales.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "net_sales_lbl".t, value: "฿\(netSales.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "kpi_tax_collected".t, value: "฿\(tax.formatted(.number.precision(.fractionLength(2))))")
                    }
                    GridRow {
                        kpiBlock(title: "service_charge_lbl".t, value: "฿\(serviceCharge.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "discounts_given_lbl".t, value: "฿\(discount.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "kpi_total_orders".t, value: "\(totalOrders)")
                    }
                    GridRow {
                        kpiBlock(title: "kpi_avg_ticket".t, value: "฿\(averageTicket.formatted(.number.precision(.fractionLength(2))))")
                        kpiBlock(title: "kpi_items_sold".t, value: "\(totalItems)")
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
                Text("payment_methods".t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                
                TableSection {
                    HStack {
                        Text("method_header".t).bold()
                        Spacer()
                        Text("transactions_header".t).bold()
                        Spacer().frame(width: 80)
                        Text("revenue_header".t).bold()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    
                    Divider()
                    
                    if payments.isEmpty {
                        Text("no_transactions_pdf".t)
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(payments) { pt in
                            HStack {
                                Text(pt.method)
                                Spacer()
                                Text(LocalizationManager.shared.t("orders_count_template", pt.count))
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
                Text("top_products_summary_lbl".t)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                
                TableSection {
                    HStack {
                        Text("item_name_header".t).bold()
                        Spacer()
                        Text("category_header".t).bold()
                        Spacer().frame(width: 80)
                        Text("qty_sold_header".t).bold()
                        Spacer().frame(width: 80)
                        Text("total_revenue_header".t).bold()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    
                    Divider()
                    
                    if products.isEmpty {
                        Text("no_items_sold_pdf".t)
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
                    Text("prepared_by".t)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.gray)
                }
                VStack(alignment: .center, spacing: 40) {
                    Color.clear.frame(height: 1)
                    Divider().background(Color.black)
                    Text("approved_by".t)
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
