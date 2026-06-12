def crc16_ccitt(data: str) -> int:
    crc = 0xFFFF
    polynomial = 0x1021
    for char in data.encode('utf-8'):
        for i in range(8):
            bit = ((char >> (7 - i)) & 1) == 1
            c15 = ((crc >> 15) & 1) == 1
            crc = (crc << 1) & 0xFFFF
            if c15 ^ bit:
                crc ^= polynomial
    return crc

# Example PromptPay payload generation (without CRC)
# Target: 0899999999 (Phone number)
# Amount: 150.00
sanitized = "0899999999"
if sanitized.startswith("0"):
    phone = "0066" + sanitized[1:]
else:
    phone = sanitized

account_info = "0016A000000677010111" + f"0113{phone}"
payload = "000201" + "010212" + f"29{len(account_info):02d}{account_info}" + "5303764" + f"5406150.00" + "5802TH" + "6304"
crc = crc16_ccitt(payload)
full_payload = payload + f"{crc:04X}"
print("Generated Payload:", full_payload)

# Let's verify with known promptpay payload format:
# Tag 00: 000201
# Tag 01: 010212
# Tag 29: 29370016A00000067701011101130066899999999
# Tag 53: 5303764
# Tag 54: 5406150.00
# Tag 58: 5802TH
# Tag 63: 6304
# If CRC matches, then full_payload should end with the right 4 hex chars.
