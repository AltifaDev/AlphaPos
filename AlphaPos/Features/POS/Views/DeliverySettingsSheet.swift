import SwiftUI

struct DeliverySettingsSheet: View {
    @Binding var gp: Double
    @Binding var adFee: Double
    @Binding var adFeeIsPct: Bool
    @Binding var otherFee: Double
    let brandName: String
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_language") private var appLanguage = "en"
    
    @State private var gpString = ""
    @State private var adFeeString = ""
    @State private var adFeeIsPctLocal = false
    @State private var otherFeeString = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                VStack(spacing: APSpacing.lg) {
                    VStack(alignment: .leading, spacing: APSpacing.md) {
                        Text("Configure Platform Fees")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        
                        Text("Set the GP commission percentage and other marketing or operational costs incurred for this \(brandName) order.")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        
                        Divider().background(Color.appDivider)
                        
                        // GP Input
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Platform GP Commission (%)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.textSecondary)
                            HStack {
                                TextField("e.g. 30", text: $gpString)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                    .padding(10)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.sm)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                Text("%")
                                    .font(.headline)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                        
                        // Ad Fee Input
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Advertising / Marketing Costs")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.textSecondary)
                                
                                Spacer()
                                
                                Picker("Fee Type", selection: $adFeeIsPctLocal) {
                                    Text("฿").tag(false)
                                    Text("%").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 80)
                            }
                            
                            HStack {
                                TextField(adFeeIsPctLocal ? "e.g. 5.0" : "0.00", text: $adFeeString)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                    .padding(10)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.sm)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                Text(adFeeIsPctLocal ? "%" : "฿")
                                    .font(.headline)
                                    .foregroundColor(.textSecondary)
                                    .frame(width: 20)
                            }
                        }
                        
                        // Other Expenses
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Other Operational Fees / Packaging (฿)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.textSecondary)
                            HStack {
                                TextField("0.00", text: $otherFeeString)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                    .padding(10)
                                    .background(Color.appSurfaceHigh)
                                    .cornerRadius(APRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: APRadius.sm)
                                            .stroke(Color.appBorderSubtle, lineWidth: 1)
                                    )
                                Text("฿")
                                    .font(.headline)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }
                    .padding(APSpacing.lg)
                    .apCard()
                    
                    Spacer()
                    
                    Button(action: {
                        gp = Double(gpString) ?? 0.0
                        adFee = Double(adFeeString) ?? 0.0
                        adFeeIsPct = adFeeIsPctLocal
                        otherFee = Double(otherFeeString) ?? 0.0
                        dismiss()
                    }) {
                        Text("Apply Configurations")
                            .apGradientButton()
                    }
                    .padding(.horizontal, APSpacing.lg)
                    .padding(.bottom, APSpacing.lg)
                }
                .padding()
            }
            .navigationTitle("\(brandName) Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.textSecondary)
                }
            }
            .onAppear {
                gpString = gp > 0 ? String(format: "%.1f", gp) : ""
                adFeeString = adFee > 0 ? (adFeeIsPct ? String(format: "%.1f", adFee) : String(format: "%.2f", adFee)) : ""
                adFeeIsPctLocal = adFeeIsPct
                otherFeeString = otherFee > 0 ? String(format: "%.2f", otherFee) : ""
            }
        }
        .apColorScheme()
    }
}
