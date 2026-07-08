import SwiftUI

struct PromotionPerformanceReportView: View {
    @Bindable var viewModel: ReportsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: APSpacing.md) {
                // Header overview cards
                HStack(spacing: APSpacing.md) {
                    let totalRedemptions = viewModel.promotionPerformanceItems.reduce(0) { $0 + $1.redemptionCount }
                    let totalDiscount = viewModel.promotionPerformanceItems.reduce(0.0) { $0 + $1.totalDiscountGiven }
                    let totalRevenue = viewModel.promotionPerformanceItems.reduce(0.0) { $0 + $1.triggeredRevenue }

                    kpiCard(
                        title: "ยอดการใช้งานรวม",
                        value: "\(totalRedemptions) ครั้ง",
                        icon: "tag.fill",
                        color: .appTeal
                    )
                    kpiCard(
                        title: "ส่วนลดที่ให้ไปทั้งหมด",
                        value: "฿\(String(format: "%.2f", totalDiscount))",
                        icon: "gift.fill",
                        color: .appRose
                    )
                    kpiCard(
                        title: "ยอดขายที่เกิดขึ้นร่วม",
                        value: "฿\(String(format: "%.2f", totalRevenue))",
                        icon: "dollarsign.circle.fill",
                        color: .appAccent
                    )
                }

                // Table ledger
                VStack(alignment: .leading, spacing: 0) {
                    Text("ตารางแสดงประสิทธิภาพโปรโมชั่น")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textPrimary)
                        .padding(.bottom, APSpacing.sm)

                    // Header Row
                    HStack {
                        Text("ชื่อโปรโมชั่น").frame(maxWidth: .infinity, alignment: .leading)
                        Text("ประเภทส่วนลด").frame(width: 120, alignment: .leading)
                        Text("จำนวนครั้งที่ใช้").frame(width: 100, alignment: .trailing)
                        Text("ส่วนลดทั้งหมด").frame(width: 120, alignment: .trailing)
                        Text("ยอดขายร่วม").frame(width: 120, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, APSpacing.sm)
                    .background(Color.appSurfaceHigh)

                    Divider().background(Color.appDivider)

                    // Data Rows
                    if viewModel.promotionPerformanceItems.isEmpty {
                        Text("ไม่มีข้อมูลโปรโมชั่นในรอบนี้")
                            .font(.system(size: 9))
                            .foregroundColor(.textSecondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(viewModel.promotionPerformanceItems) { item in
                            HStack {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(displayDiscountType(item.discountType))
                                    .font(.system(size: 9))
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 120, alignment: .leading)

                                Text("\(item.redemptionCount) ครั้ง")
                                    .font(.system(size: 9))
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 100, alignment: .trailing)

                                Text("฿\(String(format: "%.2f", item.totalDiscountGiven))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.appRose)
                                    .frame(width: 120, alignment: .trailing)

                                Text("฿\(String(format: "%.2f", item.triggeredRevenue))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.appTeal)
                                    .frame(width: 120, alignment: .trailing)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, APSpacing.sm)
                            .background(Color.appSurface)

                            Divider().background(Color.appDivider)
                        }
                    }
                }
                .padding(APSpacing.md)
                .background(Color.appSurface)
                .cornerRadius(APRadius.md)
            }
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: APSpacing.md) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            Spacer()
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .cornerRadius(APRadius.md)
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
    }

    private func displayDiscountType(_ type: String) -> String {
        switch type {
        case "percentage":   return "เปอร์เซ็นต์ (%)"
        case "fixed":        return "บาท (Fixed)"
        case "bundle_price":  return "ราคาชุดเซ็ต (Bundle)"
        case "buy_x_get_y":   return "ซื้อ X แถม Y"
        case "buy_x_pay_y":   return "ซื้อ X จ่าย Y"
        default:             return "ส่วนลดตรง"
        }
    }
}
