import SwiftUI

/// A task-focused explanation of the relationship between raw stock, prep
/// recipes, and sale-item recipes. The example is intentionally concrete so
/// warehouse and kitchen staff do not need to understand BOM terminology.
struct RecipeStockGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var lm: LocalizationManager

    private var isThai: Bool { lm.currentLanguage == .thai }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: APSpacing.lg) {
                    intro
                    flowDiagram
                    saleExample
                    stockRules
                }
                .padding(APSpacing.lg)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Color.appBackground)
            .navigationTitle(isThai ? "สูตรอาหารเชื่อมกับสต็อกอย่างไร" : "How recipes use stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isThai ? "เข้าใจแล้ว" : "Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Label(isThai ? "ตัวอย่าง: สปาเกตตีคาโบนารา" : "Example: Spaghetti Carbonara",
                  systemImage: "fork.knife.circle.fill")
                .font(.title2.weight(.bold))
                .foregroundColor(.textPrimary)
            Text(isThai
                 ? "เก็บซอสเป็นสูตรกลาง แล้วแตกลงถึงวัตถุดิบจริงเมื่อขาย จึงตัดสต็อกเพียงครั้งเดียวและตรวจสอบสูตรได้ง่าย"
                 : "Keep sauces as intermediate formulas and expand them to raw ingredients on sale, so stock is deducted once and recipes remain easy to audit.")
                .font(.body)
                .foregroundColor(.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var flowDiagram: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Text(isThai ? "ผังการทำงาน" : "Workflow")
                .font(.headline)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: APSpacing.sm) {
                    flowCard(step: "1", icon: "shippingbox.fill", color: .appTeal,
                             title: isThai ? "วัตถุดิบ" : "Raw stock",
                             detail: isThai ? "ครีม · ไข่ · ชีส\nเบคอน · เส้นแห้ง" : "Cream · eggs · cheese\nbacon · dry pasta")
                    flowArrow(isThai ? "อ้างอิงในสูตร" : "Use in recipe")
                    flowCard(step: "2", icon: "frying.pan.fill", color: .appAmber,
                             title: isThai ? "สูตรกลาง" : "Intermediate formula",
                             detail: isThai ? "ซอสคาโบนารา\nไม่เพิ่มยอดสต็อก" : "Carbonara sauce\nnot added to stock")
                    flowArrow(isThai ? "ขาย 1 จาน" : "Sell one dish")
                    flowCard(step: "3", icon: "takeoutbag.and.cup.and.straw.fill", color: .appAccent,
                             title: isThai ? "สินค้าขาย" : "Sale item",
                             detail: isThai ? "สปาเกตตีคาโบนารา\nแตกถึงวัตถุดิบจริง" : "Spaghetti Carbonara\nexpands to raw ingredients")
                }

                VStack(spacing: APSpacing.sm) {
                    flowCard(step: "1", icon: "shippingbox.fill", color: .appTeal,
                             title: isThai ? "วัตถุดิบ" : "Raw stock",
                             detail: isThai ? "ครีม · ไข่ · ชีส · เบคอน · เส้นแห้ง" : "Cream · eggs · cheese · bacon · dry pasta")
                    verticalArrow(isThai ? "อ้างอิงในสูตร" : "Use in recipe")
                    flowCard(step: "2", icon: "frying.pan.fill", color: .appAmber,
                             title: isThai ? "สูตรกลาง: ซอสคาโบนารา" : "Intermediate: Carbonara sauce",
                             detail: isThai ? "เป็นส่วนผสมของเมนู ไม่บันทึกการผลิต" : "A menu component; no production is recorded")
                    verticalArrow(isThai ? "ขาย 1 จาน" : "Sell one dish")
                    flowCard(step: "3", icon: "takeoutbag.and.cup.and.straw.fill", color: .appAccent,
                             title: isThai ? "สินค้าขาย: สปาเกตตีคาโบนารา" : "Sale item: Spaghetti Carbonara",
                             detail: isThai ? "ขายแล้วตัดถึงวัตถุดิบจริง" : "A sale deducts raw ingredients")
                }
            }
        }
    }

    private func flowCard(step: String, icon: String, color: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            HStack {
                Text(step)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(color)
                    .clipShape(Circle())
                Image(systemName: icon).foregroundColor(color)
                Spacer()
            }
            Text(title).font(.headline).foregroundColor(.textPrimary)
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(APSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: APRadius.lg).stroke(color.opacity(0.45), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    private func flowArrow(_ label: String) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2.weight(.semibold)).foregroundColor(.textSecondary)
            Image(systemName: "arrow.right").foregroundColor(.appAccent)
        }
        .frame(width: 82)
        .accessibilityElement(children: .combine)
    }

    private func verticalArrow(_ label: String) -> some View {
        Label(label, systemImage: "arrow.down")
            .font(.caption.weight(.semibold))
            .foregroundColor(.appAccent)
    }

    private var saleExample: some View {
        VStack(alignment: .leading, spacing: APSpacing.md) {
            Text(isThai ? "ตั้งค่าอย่างไร" : "How to set it up")
                .font(.headline)
            guideRow(number: "1", title: isThai ? "สร้างสูตรกลาง “ซอสคาโบนารา”" : "Create intermediate formula “Carbonara sauce”",
                     detail: isThai ? "กำหนดครีม ไข่ ชีส และเบคอนตามสัดส่วนอ้างอิง โดยไม่บันทึกการผลิตหรือเพิ่มสต็อกซอส" : "Define the reference proportions of cream, eggs, cheese, and bacon. Do not record production or add sauce stock.")
            guideRow(number: "2", title: isThai ? "สร้างสูตรสินค้าขาย “สปาเกตตีคาโบนารา”" : "Create sale recipe “Spaghetti Carbonara”",
                     detail: isThai ? "ต่อ 1 จาน: ซอสคาโบนารา 180 กรัม + เส้นสปาเกตตี 120 กรัม + กล่อง 1 ใบ" : "Per serving: 180 g carbonara sauce + 120 g spaghetti + one box.")
            guideRow(number: "3", title: isThai ? "ขายแล้วระบบแตกสูตรและตัดวัตถุดิบจริง" : "A sale expands formulas to raw ingredients",
                     detail: isThai ? "ระบบตัดครีม ไข่ ชีส เบคอน เส้น และกล่องตามสัดส่วน โดยไม่ตัดยอดซอสกลางซ้ำ" : "The system deducts cream, eggs, cheese, bacon, pasta, and packaging by proportion; it never deducts intermediate sauce stock again.")
        }
        .padding(APSpacing.md)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
    }

    private func guideRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: APSpacing.sm) {
            Text(number)
                .font(.subheadline.weight(.bold))
                .foregroundColor(.appAccent)
                .frame(width: 28, height: 28)
                .background(Color.appAccent.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.textPrimary)
                Text(detail).font(.caption).foregroundColor(.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var stockRules: some View {
        VStack(alignment: .leading, spacing: APSpacing.sm) {
            Label(isThai ? "จำง่าย ๆ" : "Remember", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .foregroundColor(.appTeal)
            Text(isThai
                 ? "สูตรกลาง = เก็บโครงสร้างสูตรเท่านั้น  •  ขาย = แตกสูตรและตัดวัตถุดิบปลายทางเพียงครั้งเดียว  •  วัตถุดิบไม่พอ = ไม่เปลี่ยนยอดใดเลย"
                 : "Intermediate formula = recipe structure only  •  Sale = expand and deduct leaf ingredients once  •  Insufficient stock = no balances change")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(APSpacing.md)
        .background(Color.appTeal.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: APRadius.lg))
        .accessibilityElement(children: .combine)
    }
}
