# วิเคราะห์ความเร็วหน้าจัดการออเดอร์และรับเงินสด — iPadOS 27

วันที่ตรวจ: 14 กันยายน 2026 · ขอบเขต: โค้ดปัจจุบันใน working tree · งานครั้งนี้: เอกสารเท่านั้น

## 1. ข้อสรุปที่ควรดำเนินการก่อน

สาเหตุที่ควรแก้ก่อนคือ **การรอเครือข่ายก่อนบันทึก การทำธุรกรรมจำนวนมากบน main actor และการแสดงผลสำเร็จที่ไม่ได้ผูกกับผลบันทึกจริง** การเปลี่ยนแอนิเมชั่นอย่างเดียวไม่แก้ปัญหาเหล่านี้

เป้าหมายคือกดออเดอร์ เปิดรับเงินสด และกดตัวเลขแล้วตอบสนองทันที ส่วนยืนยันชำระให้รอเฉพาะธุรกรรมที่จำเป็นในเครื่อง จากนั้นพร้อมรับลูกค้าถัดไป โดยซิงก์และพิมพ์ดำเนินต่อแยกกัน ไม่สามารถรับประกันการบันทึกใช้เวลาเป็นศูนย์ และต้องไม่แสดง “ชำระสำเร็จ” ก่อนข้อมูลสำคัญถูกบันทึกสำเร็จ

เอกสารนี้เป็น static analysis ยังไม่ได้จับอาการจริงหรือวัดเวลา จึงระบุได้ว่ามีงานใดอยู่ในเส้นทาง แต่ยังฟันธงไม่ได้ว่าแต่ละงานกินเวลากี่มิลลิวินาที ไม่ได้ build/run แอป; `xcodebuild -version` พบว่า developer directory ปัจจุบันชี้ CommandLineTools จึงยังตรวจเวอร์ชัน Xcode/SDK ที่ใช้งานจริงไม่ได้

## 2. เส้นทางทำงานที่พบ

| การกระทำ | เส้นทางปัจจุบัน | ผลต่อประสบการณ์ |
|---|---|---|
| เปิดเงินสด | ปุ่ม Cash → `verifyShiftAndExecute` → `activePayment = .cash` → `fullScreenCover` → `CashPaymentModalView` | ตรวจสถานะกะจากข้อมูลในเครื่อง; เส้นทางนี้ไม่พบการเรียก network โดยตรง แต่มีงานสร้าง UI และเตรียมเสียง |
| กดตัวเลข | `handleKeypadInput` → feedback/เสียง → แก้ local state → แปลงข้อความเป็นตัวเลขหนึ่งครั้ง | ไม่พบ fetch/save/network ใน handler; หากหน่วงต้องตรวจ render, เสียง และงาน main actor ที่ทำร่วมอยู่ |
| ยืนยันขายหน้าร้าน/Quick Service | `completeDirectCheckout` → รอเลขคิว → รอเลขใบเสร็จ → `processCheckout` → save → เรียก sync/print | มี network สองขั้นต่อเนื่องเมื่อเลขยังว่าง ก่อนเริ่มบันทึก |
| ยืนยันบิลโต๊ะ | `completeCheckout` → สร้าง payment/ledger → ปิด session ในเครื่อง → save → เรียกปิดโต๊ะ remote/sync และ print | ส่วนสร้างข้อมูลและ save ทำแบบ synchronous ก่อนคืนการควบคุมให้ UI |
| หน้าเงินทอน | `confirmPayment` → callback แบบ `Void` → success overlay → ปิดเองหลัง 2 หรือ 3 วินาที | ไม่มีผลลัพธ์จากธุรกรรมย้อนกลับมายืนยันความสำเร็จ; ระยะค้างหน้าคือเวลาการแสดงผล ไม่ใช่เวลาบันทึก |

ตำแหน่งหลัก: `POSView.swift` บรรทัด 320, 386, 406, 1164, 2685, 2936, 4906, 4953 และ `POSViewModel.swift` บรรทัด 344, 1003 (ดูแผนที่ไฟล์ท้ายเอกสาร)

## 3. จุดที่ต้องแก้ตามลำดับความสำคัญ

### P0 — ผลสำเร็จต้องตรงกับการบันทึกจริง

- `CashPaymentModalView.onConfirm` เป็น `(Double) -> Void` และ `confirmPayment` เปิด success overlay โดยไม่รับผลบันทึกกลับมา ในเส้นทางขายหน้าร้าน callback เพียงเริ่ม `Task` ซึ่งยังรอ network อยู่ หน้าเงินสดจึงมีโอกาสแสดงสำเร็จก่อนบันทึก และปิดตัวเองแม้งานยังไม่เสร็จ
- บิลโต๊ะเรียก `modelContext.saveWithLogging(...)` ที่ `POSView.swift:501` แต่ไม่ตรวจค่า `Bool`; helper ที่ `AppErrorHandler.swift:154` คืน `false` เมื่อ save ล้มเหลว แล้วผู้เรียกยังเดินหน้าปิดหน้าจอ/พิมพ์/เล่นเสียงสำเร็จ
- `processCheckout` มี `try save` และ rollback อยู่แล้วที่ประมาณบรรทัด 1298 แต่มีการเพิ่มแต้มและแก้สถานะออเดอร์หลัง save แรก จึงต้องทบทวนขอบเขต commit ให้ข้อมูลที่ใช้ยืนยันการขายอยู่ครบในธุรกรรมเดียว หากแยกแต้มเป็นงานภายหลัง ต้องมีงานค้างที่บันทึกถาวรและทำซ้ำได้อย่างปลอดภัย

**แนวทาง:** ให้บริการชำระคืนผลสำเร็จ/ล้มเหลวชัดเจน และใช้สถานะ `editing → committing → committed / failed` ร่วมกันทั้งบิลโต๊ะและขายหน้าร้าน เปิด success/เสียง/พิมพ์หลัง commit สำเร็จเท่านั้น เมื่อผิดพลาดให้คงข้อมูลรับเงินและเปิดให้ลองใหม่ด้วย transaction ID เดิม ป้องกันการกดซ้ำทั้ง UI และชั้นข้อมูล; ห้ามพึ่ง Boolean ของหน้าจอเพียงอย่างเดียว

### P1 — เอาการขอเลขจากเซิร์ฟเวอร์ออกจากจังหวะยืนยันเงินสด

`allocateCounterServiceIdentifiersIfNeeded` เรียก `generateQueueNumber()` และ `generateReceiptNumber()` ต่อกัน เมื่อเกิดข้อผิดพลาดจึงใช้ local fallback การรอ network ไม่จำเป็นต้องทำให้แอนิเมชั่นค้าง แต่ทำให้การขายยังไม่ถูกบันทึกทันที

**แนวทาง:** จัดเตรียมเลขล่วงหน้า เช่นจองช่วงเลขต่อสาขา/เครื่องและบันทึกช่วงนั้นลงเครื่อง ใช้ transaction UUID เป็นตัวตนถาวรแยกจากเลขที่แสดง กำหนดวิธีใช้เลขเมื่อ offline/ช่วงเลขหมดให้ชัดเจนก่อนนำไปใช้จริง ตรวจเงื่อนไขการออกเอกสารของกิจการ; ห้ามเปลี่ยนเลขในใบเสร็จที่ออกแล้วเงียบ ๆ การจองต้องรองรับหลายเครื่องและการเปิดแอปใหม่ ไม่ใช่ cache ในหน่วยความจำอย่างเดียว

### P1 — ลดงานฐานข้อมูลบน main actor

`POSViewModel` เป็น `@Observable @MainActor` ที่บรรทัด 85–86 และ `processCheckout` เป็น synchronous ทำทั้งสร้าง order/items/modifiers/tax lines, stock movement, payment และ ledger ก่อน save นอกจากนี้:

- บรรทัด 1166 เป็นต้นไป fetch `InventoryItem` ทั้งหมดแล้วค่อยกรองสาขาในหน่วยความจำ แม้มี cache ช่วยลดการค้นซ้ำแล้วก็ยังโหลดกว้างเกินรายการที่ขาย
- `deductIngredientsLocally` บรรทัด 1827 เป็นต้นไป fetch เมนูใหม่รายรายการ ตรวจธุรกรรมซ้ำรายวัตถุดิบ และเรียก FEFO จึงมีโอกาสโตตามจำนวนรายการ/สูตร/ล็อต ต้องวัด query count จริงก่อนเลือกปรับ
- `Task { @MainActor ... }` และการเพิ่ม `async` ให้ฟังก์ชันไม่ทำให้งาน synchronous ย้ายออกจาก main actor อัตโนมัติ ตามคำอธิบายของ [Apple เรื่อง responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)

**แนวทาง:** แยก UI state ออกจากบริการ commit ที่มี actor/context ของตนเอง เช่น SwiftData `@ModelActor`; ส่ง immutable `Sendable` snapshot กับ ID ข้ามขอบเขต แล้ว fetch model ภายใน context เจ้าของ ห้ามส่ง `Order`, `MenuItem`, `ModelContext` ของ UI เข้า `Task.detached` โดยตรง และต้องตรวจ actor isolation/executor จริงใน Instruments ไม่ถือว่าการติด macro เพียงอย่างเดียวรับประกันผลแล้ว ดู [SwiftData concurrency support](https://developer.apple.com/documentation/swiftdata/concurrencysupport)

ใช้ predicate จำกัดสาขาและรายการที่ต้องใช้, batch lookup สูตร/ล็อต/transaction references, ตรวจ index ตาม query จริง และรวมงานเขียนเป็นหน่วยที่ชัดเจน โดยรักษาการตัดสต็อก/แต้ม/ledger ไม่ให้ซ้ำ ยังคงตรวจสต็อกและยอดล่าสุดตอน commit; snapshot ที่เตรียมไว้ไม่ใช่สิทธิให้ข้าม validation

### P1 — ซิงก์และพิมพ์ไม่ควรแย่งเวลาป้อนข้อมูล

`SyncEngine.swift:18` และ `PrintService.swift:13` เป็น `@MainActor` แม้ผู้เรียกใช้ `Task` แล้ว ช่วง fetch/แปลงข้อมูล/เตรียมพิมพ์แบบ synchronous ก็ยังมีโอกาสแย่ง main actor ขณะเริ่มบิลถัดไป ต้องตรวจแต่ละช่วงแยกจากเวลารอ I/O

- `syncAll` ที่ `SyncEngine+Notifications.swift:144` มีการรวมการเรียกซ้ำผ่าน `activeSyncTask` อยู่แล้ว ควรรักษาไว้ แต่การชำระยังเรียกวงจรซิงก์รวมที่ครอบคลุมข้อมูลหลายประเภท
- `PrintService.dispatchReceipt:143` รอ `retryPendingPrintJobs()` ก่อนใบเสร็จปัจจุบัน จึงควรวัดว่า backlog ของเครื่องพิมพ์ทำให้รู้สึกว่าบันทึกช้าหรือไม่
- `SyncEngine+Outbox.swift:8` เป็นการ claim งานจาก **server outbox** ผ่าน RPC ไม่ใช่หลักฐานว่าการชำระในเครื่องมี durable local outbox ครบแล้ว

**แนวทาง:** บันทึก local outbox สำหรับ sync/print พร้อมธุรกรรมขาย ใช้ worker ส่งเฉพาะรายการเปลี่ยนแปลง พร้อม retry/backoff และ idempotency key; แยกงาน reconciliation เต็มระบบออกจากจังหวะรับเงิน รักษาลำดับ parent/child และป้องกันสถานะโต๊ะเก่าทับสถานะปิดแล้ว ให้คิวเครื่องพิมพ์ทำงานตามลำดับของอุปกรณ์และนโยบาย backlog ที่ชัดเจน โดย UI แสดง “บันทึกแล้ว / รอซิงก์ / รอพิมพ์” แยกกัน

การพิมพ์ลงกระดาษไม่สามารถรับประกัน exactly-once ด้วย Boolean เพียงตัวเดียว หากผลส่งไม่แน่นอน ให้มีสถานะตรวจสอบและพิมพ์สำเนา ห้าม retry โดยสร้างการชำระใหม่ และรักษาลำดับใบเสร็จ/คำสั่งเปิดลิ้นชักที่มีอยู่

### P2 — จำกัดการคำนวณและการอัปเดตหน้าจอ

`POSView.groupedOrderedItems:176` ทำ flatten/filter/group/sort; `sessionFinancials:238` รวมยอดใหม่ทุกครั้งที่ถูกอ่าน และ getter ยอดหลายตัวอ่านซ้ำ `POSViewModel.checkoutCalculation:523` มี cache แล้ว แต่ `clearPricingCacheAfterCurrentUpdate:143` ล้างหลัง `Task.yield()` จึงไม่ใช่ cache ที่คงอยู่จนข้อมูลธุรกิจเปลี่ยน

**แนวทาง:** คง snapshot ของรายการจัดกลุ่มและยอดตาม revision ของออเดอร์/ราคา/ภาษี/ส่วนลด/ลูกค้า อัปเดตเฉพาะเมื่อ dependency เหล่านั้นเปลี่ยน แยก state ช่องรับเงินออกจาก order/catalog/printer status และตรึงยอดที่แสดงตอนเปิด payment session พร้อมตรวจ revision อีกครั้งก่อน commit หากออเดอร์เปลี่ยนจริง ให้แจ้งยอดใหม่ก่อนรับเงิน

อย่าสรุปว่าทุกการกดตัวเลขทำให้ `POSView` ทั้งต้นไม้ render ใหม่: state ปัจจุบันอยู่ใน modal แล้ว ต้องใช้ SwiftUI Instruments ดูว่า view ใดถูก invalidated จริง การแยกไฟล์หรือทำ subview อย่างเดียวไม่รับประกันว่า dependency ลดลง ตามแนวทาง [Apple เรื่อง SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)

## 4. ปุ่มตัวเลขและ UI native บน iPadOS 27

Apple มีหน้า [What’s new in iPadOS 27](https://developer.apple.com/ipados/whats-new/) แล้ว แต่ต้องยืนยัน SDK/build ที่ติดตั้งจริงก่อนใช้ API เฉพาะรุ่น โครงการตั้ง deployment target เป็น **18.6** และ default actor isolation เป็น **MainActor** (`project.pbxproj:447,460`) จึงควรใช้ availability checks ต่อไปหากยังรองรับเครื่องเก่า การทำ UI native บน iPadOS 27 ไม่ได้บังคับให้ตัดการรองรับรุ่นเก่า

| จุดปัจจุบัน | คำแนะนำที่เจาะจง |
|---|---|
| `CashReceivedNumberView:5508` ใช้ `.monospacedDigit()` และปิด animation แล้ว; handler parse หนึ่งครั้งต่อ tap | รักษาไว้ ห้าม debounce/throttle การรับเลข ให้ยอด เงินทอน และปุ่มยืนยันตรงกันใน state update เดียว |
| `CashKeypadGrid:5369` ใช้ `Button` และ `.apGlassButton()` | wrapper ที่ `DesignSystem.swift:531` เรียก native `.glass/.glassProminent` และมี `.bordered` fallback อยู่แล้ว ไม่ใช่ custom shader; เปรียบเทียบ `.bordered` กับ `.glass` บนเครื่องจริงก่อนตัดสินใจลดเอฟเฟกต์ |
| ช่อง “เงินยังไม่พอ” ยังมี `.posRollingNumber` ที่ `POSView.swift:5311` | ยกเลิกการ rolling เฉพาะค่าที่เปลี่ยนทุกครั้งที่พิมพ์ ใช้ native press feedback ของปุ่มแทน; ไม่ซ้อนแอนิเมชั่นทั้ง container |
| เสียง `keypadTap:955` ไป `APSoundManager.playTap:889` | ใช้ `AVAudioPlayer` ที่ stop/reset/play บน main queue แม้ comment เรียกว่า system sound; ไม่ใช่ system keyboard click จริง ให้ A/B ปิดเสียงก่อน หากเป็นคอขวดค่อยลด/เปลี่ยน feedback |
| `APSoundEffect.prepare()` ใน modal `.onAppear:5045` | singleton มี `preparePlayers()` ใน initializer; แยกวัดเปิดครั้งแรกกับครั้งถัดไป หากต้นทุนสูงให้เตรียมครั้งเดียวก่อนเปิดรับเงิน โดยไม่ย้ายงานที่ต้องอยู่ main actor อย่างผิดวิธี |
| `fullScreenCover` + `NavigationStack` | เป็นระบบ presentation อยู่แล้ว รักษาไว้ได้ ใช้ toolbar/native transition และทดสอบแนวตั้ง แนวนอน Split View/หน้าต่างแคบ ไม่เปลี่ยนเป็น sheet เพียงเพราะคาดว่าจะเร็วกว่า |
| success overlay ค้าง 2–3 วินาที | พร้อมกดเสร็จสิ้นทันทีหลัง commit; ทำเวลาค้างเงินทอนเป็นตัวเลือก ไม่ใช้ timer เป็นตัวกำหนดว่างานเสร็จแล้ว และยกเลิก timer เมื่อปิดหน้าจอ |

ให้ `Button`, `Text`, `Label`, `List`, `NavigationStack`, toolbar และสี/ตัวอักษรระบบเป็นฐาน ลด shadow/gradient/overlay ซ้อนในพื้นที่ที่เปลี่ยนบ่อยก่อนเพิ่มของใหม่ หากจำเป็นต้องมี custom glass หลายชิ้น ใช้ `GlassEffectContainer` ตาม [แนวทาง Apple](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) แต่ไม่ต้องสร้าง custom glass มาแทนปุ่มมาตรฐานที่ใช้อยู่

ใช้แอนิเมชั่นระบบเฉพาะเปิด/ปิดหน้าต่าง เปลี่ยนสถานะ และ feedback หลัง commit; เคารพ Reduce Motion, Reduce Transparency, Dynamic Type และ VoiceOver ตาม [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) ไม่มีเหตุผลจากโค้ดที่ตรวจให้เพิ่ม Lottie, shader, blur แบบทำเอง หรือไลบรารี UI เพิ่ม และไม่มีเหตุผลให้ใช้ AI model กับการคำนวณรับเงิน; คำว่า model ในข้อเสนอนี้หมายถึง data model/view model

สำหรับยอดเงิน ให้ใช้ Decimal หรือจำนวนสตางค์แบบ integer ตั้งแต่ parsing → validation → persistence ตามนโยบายปัดเศษเดียวกัน ลดการไปกลับผ่าน `Double` ประเด็นนี้เป็นความถูกต้องของธุรกรรม ไม่ใช่คำรับประกันว่าจะเร็วกว่า

## 5. สถาปัตยกรรมเป้าหมาย

1. **ก่อนเปิดรับเงิน:** เตรียม order summary, revision, ข้อมูลอ้างอิงที่จำเป็นและเลขเอกสารที่พร้อมใช้; อ่าน cache ในเครื่องก่อน โหลดเฉพาะส่วนที่ขาด ไม่โหลดข้อมูลร้านทั้งหมด
2. **ขณะกดเลข:** local UI state เท่านั้น ไม่มี network, persistence, inventory lookup หรือการโหลดรูป เก็บข้อความที่กำลังพิมพ์และยอดเงินทอนให้สอดคล้องกัน
3. **ยืนยัน:** ส่งคำสั่งหนึ่งครั้งพร้อม transaction ID, order revision และยอด; writer ตรวจเงื่อนไขล่าสุดและบันทึกข้อมูลขายที่จำเป็นพร้อม durable jobs หากล้มเหลวต้องไม่เหลือรายการบางส่วน
4. **หลัง commit:** คืน receipt snapshot ให้ UI แสดงผลจริง เปิดให้เริ่มบิลถัดไป; งาน sync/print/งานรองทำต่อโดยไม่คุมการปิดหน้ารับเงิน
5. **เมื่อเปิดแอปใหม่:** อ่านสถานะธุรกรรมและงานค้างจาก storage, retry ด้วย ID เดิม ไม่ถือว่างานสำเร็จเพราะหน้าจอเคยแสดง checkmark

หากอีกเครื่องสามารถเปลี่ยนออเดอร์เดียวกัน ต้องกำหนดเจ้าของการรับชำระ/lock และตรวจ version ฝั่ง server ด้วย การทำ offline-first เพียงอย่างเดียวไม่รับประกันว่าจะป้องกันรับเงินซ้ำข้ามเครื่องได้ทั้งหมด

## 6. เกณฑ์วัดและแผนลงมือที่ประหยัดที่สุด

ตัวเลขต่อไปนี้เป็น **เป้าหมายเริ่มต้นของโครงการ** ไม่ใช่ผลทดสอบปัจจุบันหรือมาตรฐานบังคับของ Apple

| ตัววัด | เป้าหมายเริ่มต้น |
|---|---|
| แตะเลข → ตัวเลขแสดงถูกต้อง | p95 ≤ 50 ms, p99 ≤ 100 ms; ไม่ตกหล่นเมื่อแตะเร็ว |
| เลือกออเดอร์ที่พร้อมใน cache → เริ่มเห็นข้อมูล | p95 ≤ 100 ms |
| แตะเงินสด → เฟรมแรกของหน้า | p95 ≤ 100 ms; แยกเวลาจบ system transition ออกจากเวลารอข้อมูล |
| ยืนยัน → durable local commit | p95 ≤ 300 ms, p99 ≤ 1 s สำหรับบิลทดสอบที่กำหนดร่วมกัน |
| rendering | รักษางบประมาณเฟรมประมาณ 16.7 ms ที่ 60 Hz / 8.3 ms ที่ 120 Hz เมื่ออุปกรณ์รองรับ; วัด hitch จริง |
| ความถูกต้อง | กดซ้ำ/เปิดใหม่/ลองใหม่แล้วไม่สร้างยอดรับเงินหรือหักสต็อกซ้ำ |

ใช้ Release build บน iPad รุ่นต่ำสุดที่รองรับและ iPad เป้าหมาย 27; บันทึกรุ่นเครื่อง, OS/SDK build, จำนวนข้อมูล และจำนวนรอบทดสอบ แยก cold/warm start ใช้ Time Profiler, SwiftUI Instruments และ Hangs พร้อม signpost ที่ `paymentOpen`, `keyTap`, `commitStart`, `commitEnd`, `receiptQueued`, `receiptSent` เพื่อไม่ปนเวลาซิงก์ พิมพ์ และการค้างหน้าเงินทอน

ลำดับงานแนะนำ:

1. วัด baseline สั้น ๆ ครบสามจังหวะ เปิดเงินสด/กดเลข/ยืนยัน และบันทึก network กับ main actor แยกกัน
2. แก้ P0 การส่งผล commit/error และหน้าสำเร็จ แล้วเอาการรอเลขออกจากเส้นทางเงินสด
3. จำกัด fetch และแยก writer/context; ทำ local outbox โดยคง ledger, stock และ retry semantics
4. ลด invalidation กับเอฟเฟกต์เฉพาะที่ profiler ชี้ ทดสอบเสียงเปิด/ปิดและ bordered/glass; ไม่รื้อ UI ทั้งแอป
5. ตรวจรับในโหมด online, offline, network ช้า, printer offline, มี print backlog, save ล้มเหลว, กดซ้ำ, ออเดอร์เปลี่ยนระหว่างจ่าย และเปิดแอปใหม่หลัง commit ก่อน sync ใช้บิล 1/20/100 รายการ พร้อมฐานข้อมูลขนาดใช้งานจริง

ควรขยาย regression tests จาก `OrderSettlementTests.swift` และ `POSTests.swift` เฉพาะพฤติกรรมที่เปลี่ยนในงาน implementation ภายหลัง งานเอกสารครั้งนี้ไม่ได้เพิ่มหรือรัน tests

## 7. แผนที่ไฟล์ที่ควรเปิดเมื่อเริ่มแก้

พาธด้านล่างอ้างอิงจากราก repository; เลขบรรทัดเป็น snapshot ณ วันที่ตรวจ

| ไฟล์ | จุดที่เกี่ยวข้อง |
|---|---|
| [POSView.swift](../AlphaPos/Features/POS/Views/POSView.swift) | order summary, table/direct checkout, cash modal, keypad, success overlay |
| [POSViewModel.swift](../AlphaPos/Features/POS/ViewModels/POSViewModel.swift) | เลขคิว/ใบเสร็จ, pricing cache, persistence, stock/FEFO, sync/print dispatch |
| [DesignSystem.swift](../AlphaPos/Core/Design/DesignSystem.swift) | native button wrapper, rolling number, haptic, custom audio player |
| [AppErrorHandler.swift](../AlphaPos/Core/Utilities/AppErrorHandler.swift) | `saveWithLogging` คืนผลที่ caller ต้องตรวจ |
| [AccountingLedgerService.swift](../AlphaPos/Core/Financial/AccountingLedgerService.swift), [BusinessDayContext.swift](../AlphaPos/Core/Business/BusinessDayContext.swift) | ledger idempotency และบริบทธุรกรรม/กะที่ต้องรักษา |
| [SyncEngine.swift](../AlphaPos/Data/Sync/SyncEngine.swift), [SyncEngine+Notifications.swift](../AlphaPos/Data/Sync/SyncEngine+Notifications.swift), [SyncEngine+Outbox.swift](../AlphaPos/Data/Sync/SyncEngine+Outbox.swift) | actor isolation, full sync, server outbox |
| [PrintService.swift](../AlphaPos/Core/Print/PrintService.swift) | retry backlog ก่อนพิมพ์ใบเสร็จปัจจุบัน และลำดับลิ้นชัก |
| [POSProductPanel.swift](../AlphaPos/Features/POS/Views/POSProductPanel.swift) | `POSCatalogStore` มี snapshot/pagination 80 รายการอยู่แล้ว; รักษาสิ่งที่ทำไว้และตรวจ reload ที่ล้างรายการก่อนโหลดเมื่อปรับ UX |
| [POSOrderPanel.swift](../AlphaPos/Features/POS/Views/POSOrderPanel.swift) | เป็นโครง layout; business state ยังอยู่ใน `POSView` |
| [PaymentGatewayView.swift](../AlphaPos/Features/POS/Views/PaymentGatewayView.swift) | เป็นหน้าตั้งค่าวิธีชำระ/ประวัติ ไม่ใช่ cash keypad; มี query payment กว้าง แต่ยังไม่มีหลักฐานว่าหน้านี้เป็นต้นเหตุของอาการที่รายงาน |

ข้อเสนอทั้งหมดเป็นแนวทางวิศวกรรมอิง Apple documentation และหลัก transaction integrity, isolation, idempotency, durable queue และการวัด latency ไม่ใช่การรับรองมาตรฐาน ISO หรือการรับรองความเร็วที่ยังไม่ได้ทดสอบ
