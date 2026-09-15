// ThaiBahtTextFormatter.swift
// AlphaPos — Core Financial Module
//
// Converts monetary amounts into Thai Baht text format according to
// Thai Revenue Department and Royal Society of Thailand standards.
// E.g. 1,250.75 -> "หนึ่งพันสองร้อยห้าสิบบาทเจ็ดสิบห้าสตางค์"
// E.g. 500.00   -> "ห้าร้อยบาทถ้วน"

import Foundation

public enum ThaiBahtTextFormatter {
    private static let numbers = ["ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า"]
    private static let digits = ["", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน", "ล้าน"]

    public static func format(_ amount: Double) -> String {
        guard !amount.isNaN && !amount.isInfinite else { return "ศูนย์บาทถ้วน" }
        
        let rounded = (amount * 100).rounded() / 100
        if abs(rounded) < 0.005 {
            return "ศูนย์บาทถ้วน"
        }

        let isNegative = rounded < 0
        let absAmount = abs(rounded)

        let integerPart = Int(absAmount)
        let fractionalPart = Int(((absAmount - Double(integerPart)) * 100).rounded())

        var result = isNegative ? "ลบ" : ""

        if integerPart > 0 {
            result += convertIntegerToThaiText(integerPart) + "บาท"
        }

        if fractionalPart > 0 {
            if integerPart == 0 {
                result += "ศูนย์บาท"
            }
            result += convertFractionalToThaiText(fractionalPart) + "สตางค์"
        } else {
            result += "ถ้วน"
        }

        return result
    }

    private static func convertIntegerToThaiText(_ number: Int) -> String {
        if number == 0 { return numbers[0] }

        var result = ""
        var num = number

        if num >= 1_000_000 {
            let millions = num / 1_000_000
            result += convertIntegerToThaiText(millions) + "ล้าน"
            num %= 1_000_000
        }

        let str = String(num)
        let length = str.count

        for (index, char) in str.enumerated() {
            guard let digit = Int(String(char)) else { continue }
            let pos = length - index - 1

            if digit != 0 {
                if pos == 1 && digit == 1 {
                    result += digits[1]
                } else if pos == 1 && digit == 2 {
                    result += "ยี่" + digits[1]
                } else if pos == 0 && digit == 1 && length > 1 && num % 10 == 1 && str[str.index(str.startIndex, offsetBy: length - 2)] != "0" {
                    result += "เอ็ด"
                } else {
                    result += numbers[digit] + digits[pos]
                }
            }
        }

        return result
    }

    private static func convertFractionalToThaiText(_ fraction: Int) -> String {
        var result = ""
        let str = String(format: "%02d", fraction)

        let tens = Int(String(str.prefix(1))) ?? 0
        let ones = Int(String(str.suffix(1))) ?? 0

        if tens > 0 {
            if tens == 1 {
                result += "สิบ"
            } else if tens == 2 {
                result += "ยี่สิบ"
            } else {
                result += numbers[tens] + "สิบ"
            }
        }

        if ones > 0 {
            if ones == 1 && tens > 0 {
                result += "เอ็ด"
            } else {
                result += numbers[ones]
            }
        }

        return result
    }
}
