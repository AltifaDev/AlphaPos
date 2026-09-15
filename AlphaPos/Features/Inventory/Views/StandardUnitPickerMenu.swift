// StandardUnitPickerMenu.swift
// AlphaPos — Standardized Unit of Measure Selection Menu

import SwiftUI

struct StandardUnitPickerMenu: View {
    @Binding var unit: String
    var suggestedUnit: String? = nil
    var isFormFieldStyle: Bool = false

    @EnvironmentObject private var lm: LocalizationManager

    private var isThai: Bool {
        lm.currentLanguage == .thai
    }

    var body: some View {
        Menu {
            // Suggested / Compatible units
            if let suggested = suggestedUnit, !suggested.isEmpty {
                let compatible = UnitOfMeasure.compatibleUnits(for: suggested)
                if !compatible.isEmpty {
                    Section(isThai ? "หน่วยที่แนะนำ" : "Suggested units") {
                        ForEach(compatible, id: \.self) { u in
                            Button {
                                unit = u
                            } label: {
                                HStack {
                                    Text(UnitOfMeasure.displayLabel(for: u, isThai: isThai))
                                    if unit.lowercased() == u.lowercased() {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Mass / Weight
            Section(isThai ? "น้ำหนัก" : "Weight / Mass") {
                ForEach(["g", "kg", "mg"], id: \.self) { u in
                    Button {
                        unit = u
                    } label: {
                        HStack {
                            Text(UnitOfMeasure.displayLabel(for: u, isThai: isThai))
                            if unit.lowercased() == u.lowercased() {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Volume
            Section(isThai ? "ปริมาตร" : "Volume") {
                ForEach(["ml", "liter"], id: \.self) { u in
                    Button {
                        unit = u
                    } label: {
                        HStack {
                            Text(UnitOfMeasure.displayLabel(for: u, isThai: isThai))
                            if unit.lowercased() == u.lowercased() {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Pieces & Packaging
            Section(isThai ? "ชิ้น / บรรจุภัณฑ์" : "Piece & Packaging") {
                ForEach(["piece", "bottle", "can", "cup", "box", "pack", "bag", "dish"], id: \.self) { u in
                    Button {
                        unit = u
                    } label: {
                        HStack {
                            Text(UnitOfMeasure.displayLabel(for: u, isThai: isThai))
                            if unit.lowercased() == u.lowercased() {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            // Kitchen Spoon Measurements
            Section(isThai ? "หน่วยช้อน (ครัว)" : "Kitchen measures") {
                ForEach(["tbsp", "tsp"], id: \.self) { u in
                    Button {
                        unit = u
                    } label: {
                        HStack {
                            Text(UnitOfMeasure.displayLabel(for: u, isThai: isThai))
                            if unit.lowercased() == u.lowercased() {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            if isFormFieldStyle {
                HStack {
                    Text(unit.isEmpty ? (isThai ? "เลือกหน่วยนับ" : "Select unit") : UnitOfMeasure.displayLabel(for: unit, isThai: isThai))
                        .font(.system(size: 14))
                        .foregroundColor(unit.isEmpty ? .textTertiary : .textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
            } else {
                HStack(spacing: 4) {
                    Text(unit.isEmpty ? (suggestedUnit?.isEmpty == false ? UnitOfMeasure.displayLabel(for: suggestedUnit!, isThai: isThai) : (isThai ? "เลือกหน่วย" : "Unit")) : UnitOfMeasure.displayLabel(for: unit, isThai: isThai))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.appSurfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.appBorderSubtle, lineWidth: 1))
            }
        }
    }
}
