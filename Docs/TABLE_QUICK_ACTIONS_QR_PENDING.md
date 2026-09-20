# สรุปงานค้าง: เมนูกดค้างโต๊ะ, QR ชำระเงิน และใบตรวจรายการ

วันที่สรุป: 18 กันยายน 2026

## ขอบเขตคำขอ

เพิ่มเมนูเมื่อกดค้างที่โต๊ะให้ทำงานได้โดยไม่ต้องเข้า POS ได้แก่

1. พิมพ์ใบเสร็จตรวจรายการ (pre-bill) พร้อม QR ชำระเงิน
2. เปิด QR Code ชำระเงินบนหน้าจอ
3. ใช้กติกายอดเงิน การตรวจรายการ งานครัว การบันทึก Payment การปิด session และการพิมพ์ใบเสร็จให้เหมือนหน้าออเดอร์หลัก

## สิ่งที่ทำไปแล้ว

- เพิ่มรายการใน context menu ของโต๊ะใน `AlphaPos/Features/Tables/Views/TableView.swift`
- เพิ่มการค้นหา active `TableSession` ของโต๊ะและโต๊ะที่ join กัน
- เพิ่ม `printQuickPreBill(_:)` ซึ่งเรียก `PrintService.shared.dispatchPreBill(orders:)` เช่นเดียวกับ POS หลัก
- เพิ่ม `presentQuickQR(_:)` และเปิด `QRPaymentModalView` ที่ใช้ร่วมกับหน้า POS หลัก
- ตรวจสอบ `kitchen_workflow_required` ก่อนให้ชำระผ่าน QR
- เพิ่ม `completeQuickQRPayment(_:)` สำหรับสร้าง Payment แบบ `QR PromptPay`, เปลี่ยนสถานะ order, ปิด table session, เปลี่ยนสถานะโต๊ะ และสั่งพิมพ์ใบเสร็จ
- เพิ่มการป้องกันปัญหาแตะโต๊ะยาก: เพิ่ม minimum distance ของ canvas drag และให้ tap ของการ์ดโต๊ะมี priority สูงกว่า canvas gesture

## ปัญหาที่พบจากการวิเคราะห์ QR

### 1. ยอด QR ต้องใช้ยอดที่ชำระได้จริง

`QRPaymentModalView` รับ `totalAmount` และใช้ค่านี้สร้าง PromptPay payload โดยตรง

จุดที่ต้องแก้/ตรวจให้เสร็จ:

- sheet ต้องส่งยอดค้างชำระจริง ไม่ใช่ `session.totalAmount` ซึ่งอาจรวมออเดอร์ที่ชำระแล้วหรือยอดที่มีการจ่ายบางส่วน
- ควรใช้ `calculatePayableAmount(for:)` หรือค่าที่คำนวณเทียบเท่ากับ `outstandingAmount` ของออเดอร์ทั้งหมด
- ยอดที่แสดงในหัวข้อ QR, จำนวนเงินใน PromptPay payload และยอดที่สร้าง Payment ต้องเป็นค่าเดียวกัน
- ต้องตรวจกรณีส่วนลด, service charge, tax, government support และ partial payment

ปัจจุบันมี computed property `quickPaymentAmount` แล้ว แต่จุดแสดง QR ต้องตรวจให้ส่งค่านี้เข้า `QRPaymentModalView` แทน `session.totalAmount`

### 2. การยืนยัน QR ต้องใช้กติกาเดียวกับ `completeCheckout`

ก่อนปล่อยใช้งานจริงควรเทียบ `completeQuickQRPayment(_:)` กับ `POSView.completeCheckout(...)` แบบ field-by-field โดยเฉพาะ:

- การ terminalize order และสถานะรายการครัว
- การคำนวณยอดค้างชำระราย order
- การ stamp `BusinessDayContext`
- การบันทึก accounting ledger
- การปิด remote session ทุกโต๊ะใน joined group
- การ sync และการจัดการกรณี network ล้มเหลว
- การป้องกันการกดยืนยันซ้ำระหว่างกำลังบันทึก

## การตรวจสอบใบพิมพ์รายการ

เส้นทางพิมพ์ที่นำมาใช้คือ `PrintService.dispatchPreBill(orders:)` ซึ่งเรียก renderer `ESCPOSBuilder.buildPreBill` และส่งไปยัง printer role `receipt`

สิ่งที่ควรทดสอบให้ครบ:

- รายการสินค้าทุกบรรทัดที่ยังไม่ชำระ
- จำนวน, ราคาต่อหน่วย, modifiers/toppings และหมายเหตุ
- subtotal, discount, tax, service charge และยอดรวม
- เลขโต๊ะ/เลข session/เลขออเดอร์
- QR PromptPay และยอดที่ encode อยู่ใน QR
- กรณีหลายออเดอร์ใน session เดียว
- กรณีออเดอร์ชำระบางส่วน
- กรณีไม่มี printer หรือ printer ส่งไม่สำเร็จ

โค้ดปัจจุบันกรองออเดอร์ที่ถูกลบ, cancelled และ settled ออกแล้ว แต่ต้องตรวจผลพิมพ์จริงจากเครื่อง 58mm/80mm เพราะ build ของใบพิมพ์อยู่ใน `PrinterRenderer.swift` และอาจมีข้อจำกัดความกว้าง/การตัดบรรทัด

## สถานะ build ล่าสุด

- `git diff --check` ผ่าน
- เคยพบ compile error จาก expression ใน context view และแก้โดยแยก expression เป็นตัวแปรย่อย
- เพิ่มการคำนวณ `quickPaymentAmount` จากยอดค้างชำระจริง และ guard ป้องกันการยืนยัน QR ซ้ำ
- build รอบล่าสุดผ่านแล้ว: `BUILD SUCCEEDED`
- ห้ามส่งขึ้น production ก่อนยืนยัน build สำเร็จและทดสอบ flow บน iPad จริงหรือ simulator

## งานที่ต้องทำต่อเรียงลำดับ

1. แก้ QR sheet ให้ใช้ยอดค้างชำระจริง (`quickPaymentAmount`) และแสดงยอดเดียวกันทุกจุด
2. ตรวจและลดความซ้ำของ logic `completeQuickQRPayment` โดยดึง helper ร่วมกับ POS หลักถ้าเหมาะสม
3. เพิ่ม guard กันกดยืนยัน QR ซ้ำ และแสดง progress ระหว่างบันทึก
4. รัน build ใหม่จน `BUILD SUCCEEDED`
5. ทดสอบ context menu บนโต๊ะที่มีออเดอร์หลายรายการ
6. ทดสอบพิมพ์ใบตรวจรายการด้วย printer 58mm และ 80mm
7. ตรวจภาพ/ข้อมูล QR ว่ายอดตรงกับยอดที่แสดงบนหน้าจอ
8. ทดสอบยืนยันชำระด้วย QR แล้วตรวจ Payment, order status, table status, table session และใบเสร็จ
9. ทดสอบ network offline/timeout และยืนยันว่าไม่สร้าง Payment ซ้ำ

## ไฟล์หลักที่เกี่ยวข้อง

- `AlphaPos/Features/Tables/Views/TableView.swift`
- `AlphaPos/Features/POS/Views/POSView.swift`
- `AlphaPos/Core/Print/PrintService.swift`
- `AlphaPos/Core/Print/PrinterRenderer.swift`
- `AlphaPos/Models/TableSession.swift`
- `AlphaPos/Models/Order.swift`
