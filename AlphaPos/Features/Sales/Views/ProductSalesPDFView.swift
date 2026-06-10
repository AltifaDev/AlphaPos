import SwiftUI

struct ProductSalesPDFView: View {
    let title: String
    let subtitle: String
    let generatedAt: String
    
    // Detailed list of all product metrics
    let products: [ProductSalesPoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ALPHAPOS RETAIL AND INVENTORY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    Text("Product Sales Detailed Report")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.black)
                    Text("\(title) • \(subtitle)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.black)
                    .padding(10)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
            }
            
            Divider()
                .background(Color.gray.opacity(0.5))
            
            // Meta info
            HStack {
                Text("Report Generated: \(generatedAt)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
                Spacer()
                Text("Total Unique Products: \(products.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.black)
            }
            
            // Detailed Spreadsheet Grid
            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 0) {
                    Text("Item Name")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Category")
                        .frame(width: 120, alignment: .leading)
                    Text("Qty Sold")
                        .frame(width: 80, alignment: .trailing)
                    Text("Unit Price")
                        .frame(width: 100, alignment: .trailing)
                    Text("Total Revenue")
                        .frame(width: 120, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.black)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.black.opacity(0.05))
                
                Divider()
                
                if products.isEmpty {
                    Text("No products sold in the selected time range.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // Item Rows (renders up to 18 rows to fit clean in a single Letter page)
                    ForEach(Array(products.enumerated()), id: \.offset) { index, prod in
                        HStack(spacing: 0) {
                            Text(prod.name)
                                .font(.system(size: 10, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                            Text(prod.category)
                                .font(.system(size: 9))
                                .frame(width: 120, alignment: .leading)
                            Text("\(prod.quantity)")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 80, alignment: .trailing)
                            Text("฿\(prod.unitPrice.formatted(.number.precision(.fractionLength(2))))")
                                .font(.system(size: 9))
                                .frame(width: 100, alignment: .trailing)
                            Text("฿\(prod.totalRevenue.formatted(.number.precision(.fractionLength(2))))")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 120, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(index % 2 == 0 ? Color.clear : Color.black.opacity(0.01))
                        
                        Divider()
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            Spacer()
            
            // Footer audit disclaimer
            HStack {
                Text("This report lists all inventory items ordered and served through the AlphaPos system. All values are subject to internal stock audit validations.")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text("Page 1 of 1")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
            }
            .padding(.top, 10)
        }
        .padding(40)
        .frame(width: 612, height: 792) // Letter page size
        .background(Color.white)
        .foregroundColor(.black)
    }
}
