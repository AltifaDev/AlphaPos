import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case thai = "th"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .thai: return "ไทย"
        }
    }
    
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .thai: return "🇹🇭"
        }
    }
}

final class LanguageManager {
    static let shared = LanguageManager()
    
    private let translations: [String: [String: String]] = [
        "all_items_served_before_checkout": [
            "en": "All items must be served before checkout.",
            "th": "ต้องเสิร์ฟรายการทั้งหมดก่อนชำระเงิน"
        ],
        "biometric_verified": [
            "en": "Biometric verified",
            "th": "ยืนยันชีวภาพสำเร็จ"
        ],
        "completed": [
            "en": "Completed",
            "th": "เสร็จสิ้น"
        ],
        "delete_item_confirm": [
            "en": "Delete this item from the order?",
            "th": "ลบรายการนี้ออกจากออเดอร์หรือไม่?"
        ],
        "table_details": [
            "en": "Table Details",
            "th": "รายละเอียดโต๊ะ"
        ],
        "diagnostics_system_status": [
            "en": "Diagnostics & System Status",
            "th": "การวินิจฉัยและสถานะระบบ"
        ],
        "connection_status": [
            "en": "Connection Status",
            "th": "สถานะการเชื่อมต่อ"
        ],
        "offline_status": [
            "en": "Offline",
            "th": "ออฟไลน์"
        ],
        "online_status": [
            "en": "Online",
            "th": "ออนไลน์"
        ],
        "merchant_uuid_label": [
            "en": "Store ID (Merchant UUID)",
            "th": "รหัสร้านค้า (Merchant UUID)"
        ],
        "not_paired_status": [
            "en": "None (Not Paired)",
            "th": "ไม่มี (ยังไม่ได้จับคู่)"
        ],
        "clear_cache": [
            "en": "Clear Cache",
            "th": "ล้างแคช"
        ],
        "reset_server_data": [
            "en": "Reset Server Data",
            "th": "รีเซ็ตข้อมูลเซิร์ฟเวอร์"
        ],
        "cache_cleared_success": [
            "en": "Cache cleared and data re-synced successfully.",
            "th": "ล้างแคชและซิงค์ข้อมูลใหม่สำเร็จ"
        ],
        "wipe_transactions_title": [
            "en": "Wipe Transactions & Sessions?",
            "th": "ลบธุรกรรมและเซสชันทั้งหมดหรือไม่?"
        ],
        "yes_wipe": [
            "en": "Yes, Wipe",
            "th": "ยืนยันลบ"
        ],
        "wipe_transactions_body": [
            "en": "This will delete all active sessions, orders, and service requests on the server. Menu items and staff profiles will remain untouched.",
            "th": "การดำเนินการนี้จะลบเซสชัน ออเดอร์ และคำขอบริการที่กำลังใช้งานบนเซิร์ฟเวอร์ โดยไม่กระทบเมนูและโปรไฟล์พนักงาน"
        ],
        "wipe_success": [
            "en": "All active sessions and orders wiped from Supabase. Tables reset to vacant.",
            "th": "ลบเซสชันและออเดอร์ที่กำลังใช้งานแล้ว โต๊ะถูกรีเซ็ตเป็นว่าง"
        ],
        "wipe_failed_prefix": [
            "en": "Wipe failed:",
            "th": "ลบข้อมูลไม่สำเร็จ:"
        ],
        "system_notification": [
            "en": "System Notification",
            "th": "การแจ้งเตือนระบบ"
        ],
        "ok": [
            "en": "OK",
            "th": "ตกลง"
        ],
        "sign_out_confirm_body": [
            "en": "Are you sure you want to sign out? You will need to log in again to access your account.",
            "th": "ยืนยันออกจากระบบหรือไม่? คุณจะต้องเข้าสู่ระบบอีกครั้งเพื่อใช้งานบัญชีนี้"
        ],
        "table_system_disabled_title": [
            "en": "Table System Disabled",
            "th": "ระบบโต๊ะอาหารปิดใช้งานอยู่",
            "lo": "ລະບົບໂຕະອາຫານປິດໃຊ້ງານຢູ່",
            "km": "ប្រព័ន្ធតុអាហារត្រូវបានបិទ",
            "vi": "Hệ thống bàn ăn đã tắt",
            "my": "စားပွဲတင်စနစ် ပိတ်ထားသည်"
        ],
        "table_system_disabled_desc": [
            "en": "The dining table system has been disabled by the store owner in iPad settings. Please contact management or turn it on to access tables.",
            "th": "ระบบโต๊ะอาหารถูกปิดการใช้งานจากเครื่องตั้งค่าหลัก (iPad) กรุณาเปิดระบบโต๊ะอาหารในตั้งค่าระบบก่อนเข้าใช้งาน",
            "lo": "ລະບົບໂຕະອາຫານຖືກປິດການໃຊ້ງານຈາກເຄື່ອງຕັ້ງຄ່າຫຼັກ (iPad) ກະລຸນາເປີດລະບົບໂຕະອາຫານໃນຕັ້ງຄ່າລະບົບກ່ອນເຂົ້າໃຊ້ງານ",
            "km": "ប្រព័ន្ធតុអាហារត្រូវបានបិទដោយម្ចាស់ហាងនៅក្នុងการកំណត់ iPad ។ សូមបើកវាเพื่อចូលប្រើតុ។",
            "vi": "Hệ thống bàn ăn đã bị vô hiệu hóa bởi chủ cửa hàng trong cài đặt iPad. Vui lòng bật nó để truy cập bàn.",
            "my": "iPad ဆက်တင်များတွင် ဆိုင်ပိုင်ရှင်က စားပွဲတင်စနစ်ကို ပိတ်ထားသည်။ စားပွဲများဝင်ရောက်ရန် ၎င်းကိုဖွင့်ပါ။"
        ],
        "link_store_title": [
            "en": "Link AlphaPos Store",
            "th": "เชื่อมต่อร้านค้า AlphaPos",
            "lo": "ເຊື່ອມຕໍ່ຮ້ານຄ້າ AlphaPos",
            "km": "ភ្ជាប់ហាង AlphaPos",
            "vi": "Liên kết cửa hàng AlphaPos",
            "my": "AlphaPos ဆိုင် ချိတ်ဆက်ရန်"
        ],
        "link_store_sub": [
            "en": "To begin, pair this device with your iPad POS.",
            "th": "เริ่มต้นจับคู่อุปกรณ์นี้เข้ากับเครื่อง iPad POS ของร้านค้า",
            "lo": "ເລີ່ມຕົ້ນຈັບຄູ່ອຸປະກອນນີ້ກັບເຄື່ອງ iPad POS ຂອງຮ້านຄ້າ",
            "km": "ដើម្បីចាប់ផ្តើម ភ្ជាប់ឧបករណ៍នេះជាមួយ iPad POS របស់អ្នក។",
            "vi": "Để bắt đầu, hãy ghép nối thiết bị này với iPad POS của bạn.",
            "my": "စတင်ရန် ဤစက်ပစ္စည်းကို သင်၏ iPad POS နှင့် ချိတ်ဆက်ပါ။"
        ],
        "scan_qr_code": [
            "en": "Scan Pairing QR Code",
            "th": "สแกน QR Code สำหรับจับคู่",
            "lo": "ສະແກນ QR Code ເພື່ອຈັບຄູ່",
            "km": "ស្កែនកូដ QR សម្រាប់ភ្ជាប់",
            "vi": "Quét mã QR ghép nối",
            "my": "ချိတ်ဆက်ရန် QR ကုဒ်ကို စကင်န်ဖတ်ပါ"
        ],
        "enter_manually": [
            "en": "Enter Store ID Manually",
            "th": "ป้อนรหัสร้านค้าด้วยตนเอง",
            "lo": "ປ້ອນລະຫັດຮ້านຄ້າດ້ວຍຕົນເອງ",
            "km": "បញ្ចូលលេខសម្គាល់ហាងដោយដៃ",
            "vi": "Nhập mã cửa hàng thủ công",
            "my": "ဆိုင် ID ကို ကိုယ်တိုင်ရိုက်ထည့်ပါ"
        ],
        "sandbox_demo": [
            "en": "Connect to Sandbox Demo Store",
            "th": "เชื่อมต่อร้านค้าจำลอง (Sandbox)",
            "lo": "ເຊື່ອມຕໍ່ຮ້านຄ້າຈໍາລອງ (Sandbox)",
            "km": "ភ្ជាប់ទៅកាន់ហាងសាកល្បង Sandbox",
            "vi": "Kết nối với cửa hàng thử nghiệm",
            "my": "Sandbox စမ်းသပ်ဆိုင်သို့ ချိတ်ဆက်ပါ"
        ],
        "scan_pairing_qr_title": [
            "en": "Scan pairing QR Code",
            "th": "สแกน QR Code สำหรับจับคู่",
            "lo": "ສະແກນ QR Code ເພື່ອຈັບຄູ່",
            "km": "ស្កែនកូដ QR សម្រាប់ភ្ជាប់",
            "vi": "Quét mã QR ghép nối",
            "my": "ချိတ်ဆက်ရန် QR ကုဒ်ကို စကင်န်ဖတ်ပါ"
        ],
        "scan_pairing_qr_desc": [
            "en": "Scan the Pairing QR Code in iPad POS Settings",
            "th": "สแกน QR Code สำหรับจับคู่ในหน้าต่างการตั้งค่าของเครื่อง iPad POS",
            "lo": "ສະແກน QR Code ເພື່ອຈັບຄູ່ໃນໜ້າຕັ້ງຄ່າຂອງເຄື່ອງ iPad POS",
            "km": "ស្កែនកូដ QR នៅក្នុងการកំណត់ iPad POS",
            "vi": "Quét mã QR ghép nối trong Cài đặt iPad POS",
            "my": "iPad POS ဆက်တင်များရှိ ချိတ်ဆက်မှု QR ကုဒ်ကို စကင်န်ဖတ်ပါ"
        ],
        "select_simulated_store": [
            "en": "Select store to simulate QR code scan:",
            "th": "เลือกสาขาที่ต้องการจำลองการสแกน QR Code:",
            "lo": "ເລືອກສາຂາທີ່ຕ້ອງການຈໍາລອງການສະແກນ QR Code:",
            "km": "ជ្រើសរើសហាងដើម្បីសាកល្បងស្កែនកូដ QR៖",
            "vi": "Chọn cửa hàng để mô phỏng quét mã QR:",
            "my": "QR ကုဒ်စကင်န်ဖတ်ခြင်းကို စမ်းသပ်ရန် ဆိုင်ကို ရွေးချယ်ပါ-"
        ],
        "simulate_sandbox": [
            "en": "Simulate: AlphaPos HQ (Demo Sandbox)",
            "th": "จำลอง: สำนักงานใหญ่ AlphaPos (Demo)",
            "lo": "ຈໍາລອງ: ສຳນັກງານໃຫຍ່ AlphaPos (Demo)",
            "km": "សាកល្បង៖ การិยាល័យកណ្តាល AlphaPos (Demo)",
            "vi": "Mô phỏng: Trụ sở AlphaPos (Demo)",
            "my": "စမ်းသပ်မှု- AlphaPos HQ (Demo Sandbox)"
        ],
        "simulate_cafe": [
            "en": "Simulate: Cafe Terrace Store",
            "th": "จำลอง: สาขา คาเฟ่ เทอเรซ",
            "lo": "ຈໍາລອງ: ສາຂາ ຄາເຟ່ ເທີເຣຊ",
            "km": "សាកល្បង៖ ហាងកាហ្វេ Terrace",
            "vi": "Mô phỏng: Cửa hàng Cafe Terrace",
            "my": "စမ်းသပ်မှု- Cafe Terrace ဆိုင်ခွဲ"
        ],
        "enter_store_id": [
            "en": "Enter Store ID",
            "th": "ระบุรหัสร้านค้า",
            "lo": "ລະບຸລະຫັດຮ້ານຄ້າ",
            "km": "បញ្ចូលលេខសម្គាល់ហាង",
            "vi": "Nhập ID cửa hàng",
            "my": "ဆိုင် ID ရိုက်ထည့်ပါ"
        ],
        "enter_store_id_sub": [
            "en": "Type or paste the Store UUID from the iPad POS Settings panel.",
            "th": "พิมพ์หรือวางรหัสร้านค้า UUID จากหน้าต่างการตั้งค่าของเครื่อง iPad POS",
            "lo": "ພິມຫຼືວາງລະຫັດຮ້ານຄ້າ UUID ຈາກໜ້າຕັ້ງຄ່າຂອງເຄື່ອງ iPad POS",
            "km": "វាយបញ្ចូល ឬបិទភ្ជាប់លេខសម្គាល់ហាងពីการកំណត់ iPad POS ។",
            "vi": "Nhập hoặc dán UUID cửa hàng từ bảng Cài đặt iPad POS.",
            "my": "iPad POS ဆက်တင်များဘောင်မှ ဆိုင် UUID ကို ရိုက်ထည့်ပါ သို့မဟုတ် ကူးယူထည့်ပါ။"
        ],
        "link_shop": [
            "en": "Link Shop",
            "th": "เชื่อมต่อร้านค้า",
            "lo": "ເຊື່ອມຕໍ່ຮ້ານຄ້າ",
            "km": "ភ្ជាប់ហាង",
            "vi": "Liên kết cửa hàng",
            "my": "ဆိုင်ချိတ်ဆက်မည်"
        ],
        "unlink_store_title": [
            "en": "Unlink Store",
            "th": "ยกเลิกการเชื่อมต่อร้านค้า",
            "lo": "ຍົກເລີກการເຊື່ອມຕໍ່ຮ້ານຄ້າ",
            "km": "ផ្តាច់ទំនាក់ទំនងហាង",
            "vi": "Hủy liên kết cửa hàng",
            "my": "ဆိုင်ချိတ်ဆက်မှု ဖြုတ်ရန်"
        ],
        "unlink_store_msg": [
            "en": "Are you sure you want to disconnect from this store? You will need to pair again to access waitstaff functions.",
            "th": "คุณแน่ใจหรือไม่ที่จะยกเลิกการเชื่อมต่อจากร้านค้านี้? คุณจะต้องทำการจับคู่อีกครั้งเพื่อเข้าถึงระบบปฏิบัติงานพนักงาน",
            "lo": "ທ່ານແນ່ໃຈບໍ່ທີ່ຈະຍົກເລີກການເຊື່ອມຕໍ່ກັບຮ້ານຄ້ານີ້? ທ່ານຕ້ອງໄດ້ຈັບຄູ່ອີກຄັ້ງເພື່ອເຂົ້າເຖິງລະບົບພະນັກງານ",
            "km": "តើអ្នកប្រាកដជាចង់ផ្តាច់ទំនាក់ទំនងពីហាងនេះមែនទេ? អ្នកនឹងត្រូវភ្ជាប់ម្តងទៀតដើម្បីចូលប្រើប្រាស់មុខងារបុគ្គលិក។",
            "vi": "Bạn có chắc chắn muốn ngắt kết nối khỏi cửa hàng này? Bạn sẽ cần ghép nối lại để truy cập các chức năng của nhân viên.",
            "my": "ဤဆိုင်နှင့် ချိတ်ဆက်မှု ဖြုတ်ရန် သေချาပါသလား။ ဝန်ထမ်းလုပ်ဆောင်ချက်များကို အသုံးပြုရန် ထပ်မံချိတ်ဆက်ရပါမည်。"
        ],
        "select_profile_title": [
            "en": "Select your profile to clock-in and manage tables",
            "th": "เลือกบัญชีผู้ใช้เพื่อลงเวลาและจัดการโต๊ะ",
            "lo": "ເລືອກບັນຊີຜູ້ໃຊ້ເພື່ອລົງເວລາແລະຈັດການໂຕະ",
            "km": "ជ្រើសរើសប្រវត្តិរូបរបស់អ្នកដើម្បីចុះឈ្មោះចូល និងគ្រប់គ្រងតុ",
            "vi": "Chọn hồ sơ của bạn để điểm danh và quản lý bàn",
            "my": "အလုပ်ဝင်ရန်နှင့် စားပွဲများစီမံရန် သင်၏ပရိုဖိုင်ကို ရွေးချယ်ပါ"
        ],
        "enter_pin_for": [
            "en": "Enter PIN for",
            "th": "ป้อนรหัส PIN สำหรับ",
            "lo": "ປ້ອນລະຫັດ PIN ສໍາລັບ",
            "km": "បញ្ចូលកូដ PIN សម្រាប់",
            "vi": "Nhập mã PIN cho",
            "my": "အတွက် PIN နံပါတ် ရိုက်ထည့်ပါ-"
        ],
        "pin_error": [
            "en": "Incorrect PIN code, please try again.",
            "th": "รหัส PIN ไม่ถูกต้อง กรุณาลองอีกครั้ง",
            "lo": "ລະຫັດ PIN ບໍ່ຖືກຕ້ອງ ກະລຸນາລອງໃໝ່ອີກຄັ້ງ",
            "km": "កូដ PIN មិនត្រឹមត្រូវទេ សូមព្យាយាមម្តងទៀត។",
            "vi": "Mã PIN không đúng, vui lòng thử lại.",
            "my": "PIN နံပါတ် မှားယွင်းနေပါသည်။ ထပ်မံကြိုးစားပါ။"
        ],
        "biometric_auth": [
            "en": "BIOMETRIC AUTH",
            "th": "สแกนชีวภาพ",
            "lo": "ສະແກນຊີວະພາບ",
            "km": "ការផ្ទៀងផ្ទាត់ជីវមាត្រ",
            "vi": "XÁC THỰC SINH TRẮC HỌC",
            "my": "ဇီဝမက်ထရစ် စစ်ဆေးခြင်း"
        ],
        "biometric_scan_sub": [
            "en": "Scan face / fingerprint to log in as:",
            "th": "สแกนใบหน้า/ลายนิ้วมือเพื่อเข้าสู่ระบบในชื่อ:",
            "lo": "ສະແກນໃບໜ້າ/ລາຍນິ້ວມືເພື່ອເຂົ້າສູ່ລະບົບໃນຊື່:",
            "km": "ស្កែនផ្ទៃមុខ / ស្នាមម្រាមដៃដើម្បីចូលប្រើប្រាស់ជា៖",
            "vi": "Quét khuôn mặt / vân tay để đăng nhập dưới tên:",
            "my": "အဖြစ် ဝင်ရောက်ရန် မျက်နှา/လက်ဗွေ စကင်န်ဖတ်ပါ-"
        ],
        "biometric_success": [
            "en": "Biometric Match Confirmed!",
            "th": "ยืนยันการสแกนสำเร็จ!",
            "lo": "ຢືນຢັນການສະແກນສໍາເລັດ!",
            "km": "ការផ្គូផ្គងជីវមាត្រត្រូវបានបញ្ជាក់!",
            "vi": "Đã xác nhận trùng khớp sinh trắc học!",
            "my": "ဇီဝမက်ထရစ် ကိုက်ညီမှု အတည်ပြုပြီးပါပြီ။"
        ],
        "biometric_scanning": [
            "en": "Scanning metrics...",
            "th": "กำลังสแกน...",
            "lo": "ກຳລັງສະແກນ...",
            "km": "កំពុងស្កែន...",
            "vi": "Đang quét dữ liệu...",
            "my": "စကင်န်ဖတ်နေသည်..."
        ],
        "authenticate_now": [
            "en": "Authenticate Now",
            "th": "เริ่มสแกนตอนนี้",
            "lo": "ເລີ່ມສະແກນຕອນນີ້",
            "km": "ផ្ទៀងផ្ទាត់ឥឡូវនេះ",
            "vi": "Xác thực ngay",
            "my": "ယခု စစ်ဆေးမည်"
        ],
        "tables": [
            "en": "Tables",
            "th": "โต๊ะอาหาร",
            "lo": "ໂຕະອາຫານ",
            "km": "តុ",
            "vi": "Bàn ăn",
            "my": "စားပွဲများ"
        ],
        "active": [
            "en": "Active",
            "th": "ใช้งานอยู่",
            "lo": "ກຳລັງໃຊ້",
            "km": "សកម្ម",
            "vi": "Đang hoạt động",
            "my": "အသုံးပြုဆဲ"
        ],
        "vacant": [
            "en": "Vacant",
            "th": "โต๊ะว่าง",
            "lo": "ໂຕະຫວ່າງ",
            "km": "តុទំនេរ",
            "vi": "Bàn trống",
            "my": "လွတ်သည်"
        ],
        "occupied": [
            "en": "Occupied",
            "th": "ไม่ว่าง",
            "lo": "ໂຕະບໍ່ຫວ່າງ",
            "km": "មានភ្ញៀវ",
            "vi": "Có khách",
            "my": "လူရှိသည်"
        ],
        "reserved": [
            "en": "Reserved",
            "th": "จองแล้ว",
            "lo": "ຈອງແລ້ວ",
            "km": "កក់ទុក",
            "vi": "Đã đặt trước",
            "my": "ကြိုတင်မှာယူထားသည်"
        ],
        "cleaning": [
            "en": "Cleaning",
            "th": "ทำความสะอาด",
            "lo": "ເຮັດຄວາມສະອາດ",
            "km": "សម្អាត",
            "vi": "Đang dọn dẹp",
            "my": "သန့်ရှင်းရေးလုပ်နေသည်"
        ],
        "seats_count": [
            "en": "%d Seats",
            "th": "%d ที่นั่ง",
            "lo": "%d ທີ່ນັ່ງ",
            "km": "%d កៅអី",
            "vi": "%d Chỗ ngồi",
            "my": "%d ခုံ"
        ],
        "guests": [
            "en": "Guests",
            "th": "จำนวนลูกค้า",
            "lo": "ຈຳນວນລູกຄ້າ",
            "km": "ភ្ញៀវ",
            "vi": "Khách",
            "my": "ဧည့်သည်များ"
        ],
        "open_table": [
            "en": "Open Table",
            "th": "เปิดโต๊ะ",
            "lo": "ເປີດໂຕະ",
            "km": "បើកតុ",
            "vi": "Mở bàn",
            "my": "စားပွဲဖွင့်မည်"
        ],
        "select_guest_count": [
            "en": "Select Guest Count",
            "th": "เลือกจำนวนลูกค้า",
            "lo": "ເລືອກຈຳນວນລູກຄ້າ",
            "km": "ជ្រើសរើសចំនួនភ្ញៀវ",
            "vi": "Chọn số lượng khách",
            "my": "ဧည့်သည်အရေအတွက် ရွေးပါ"
        ],
        "sync_tables": [
            "en": "Sync Tables",
            "th": "รีเฟรชข้อมูลโต๊ะ",
            "lo": "ດຶງຂໍ້ມູນໂຕະ",
            "km": "ធ្វើបច្ចុប្បន្នភាពតុ",
            "vi": "Đồng bộ bàn",
            "my": "စားပွဲများ အချက်အလက်ယူမည်"
        ],
        "alerts": [
            "en": "Alerts",
            "th": "การแจ้งเตือน",
            "lo": "ການແຈ້ງເຕືອນ",
            "km": "ការជូនដំណឹង",
            "vi": "Thông báo",
            "my": "သတိပေးချက်များ"
        ],
        "clock_in_out": [
            "en": "Clock In/Out",
            "th": "ลงเวลางาน",
            "lo": "ລົງເວลາງານ",
            "km": "ចុះឈ្មោះចូល/ចេញ",
            "vi": "Điểm danh vào/ra",
            "my": "အလုပ်ဝင်/ထွက်ချိန်"
        ],
        "my_account": [
            "en": "My Account",
            "th": "บัญชีของฉัน",
            "lo": "ບັນຊີຂອງຂ້ອຍ",
            "km": "គណនីរបស់ខ្ញុំ",
            "vi": "Tài khoản của tôi",
            "my": "ကျွန်ုပ်၏အကောင့်"
        ],
        "logged_in_as": [
            "en": "Logged in as",
            "th": "เข้าสู่ระบบในชื่อ",
            "lo": "ເຂົ້າສູ່ລະບົບໃນຊື່",
            "km": "បានចូលប្រើប្រាស់ជា",
            "vi": "Đăng nhập dưới tên",
            "my": "အဖြစ် ဝင်ရောက်ထားသည်"
        ],
        "table_detail": [
            "en": "Table Detail",
            "th": "รายละเอียดโต๊ะ",
            "lo": "ລາຍລະອຽດໂຕະ",
            "km": "ព័ត៌មានលម្អិតតុ",
            "vi": "Chi tiết bàn",
            "my": "စားပွဲအသေးစိတ်"
        ],
        "status": [
            "en": "Status",
            "th": "สถานะ",
            "lo": "ສະຖານະ",
            "km": "ស្ថានភាព",
            "vi": "Trạng thái",
            "my": "အခြေအနေ"
        ],
        "total": [
            "en": "Total",
            "th": "ยอดรวม",
            "lo": "ຍອດລວມ",
            "km": "សរុប",
            "vi": "Tổng cộng",
            "my": "စုစုပေါင်း"
        ],
        "add_item": [
            "en": "Add Item",
            "th": "สั่งอาหารเพิ่ม",
            "lo": "ສັ່ງອາຫານເພີ່ມ",
            "km": "បន្ថែមមុខម្ហូប",
            "vi": "Thêm món",
            "my": "ပစ္စည်းထည့်ရန်"
        ],
        "send_to_kitchen": [
            "en": "Send to Kitchen",
            "th": "ส่งรายการเข้าครัว",
            "lo": "ສົ່ງລາຍການເຂົ້າຄົວ",
            "km": "ផ្ញើទៅចង្ក្រានបាយ",
            "vi": "Gửi vào bếp",
            "my": "မီးဖိုချောင်သို့ ปို့မည်"
        ],
        "billing_payment": [
            "en": "Billing & Payment",
            "th": "เรียกเช็คบิล",
            "lo": "ຮຽກເກັບເງິນ",
            "km": "ការគិតលុយ និងបង់ប្រាក់",
            "vi": "Thanh toán & Hóa đơn",
            "my": "ငွေတောင်းခံလွှာနှင့် ငွေပေးချေမှု"
        ],
        "cart_empty": [
            "en": "Cart is empty",
            "th": "ยังไม่มีรายการในรถเข็น",
            "lo": "ຍັງບໍ່ມີລາຍການໃນກະຕ່າ",
            "km": "មិនទាន់មានមុខម្ហូបក្នុងកន្ត្រកទេ",
            "vi": "Giỏ hàng trống",
            "my": "ပစ္စည်းတွန်းလှည်းထဲတွင် ဘာမှမရှိပါ"
        ],
        "modifiers": [
            "en": "Modifiers",
            "th": "ตัวเลือกเพิ่มเติม",
            "lo": "ຕົວເລືອກເພີ່ມເຕີม",
            "km": "ជម្រើសបន្ថែម",
            "vi": "Lựa chọn thêm",
            "my": "ပြင်ဆင်မှုများ"
        ],
        "select_category": [
            "en": "Select Category",
            "th": "เลือกหมวดหมู่",
            "lo": "ເລືອກໝວດໝູ່",
            "km": "ជ្រើសរើសប្រភេទ",
            "vi": "Chọn danh mục",
            "my": "အမျိုးအစား ရွေးပါ"
        ],
        "total_due": [
            "en": "Total Due",
            "th": "ยอดชำระเงิน",
            "lo": "ຍອດຊຳລະເງິນ",
            "km": "ចំនួនទឹកប្រាក់ត្រូវបង់",
            "vi": "Số tiền cần thanh toán",
            "my": "ပေးချေရန် စုစုပေါင်း"
        ],
        "cash": [
            "en": "Cash",
            "th": "เงินสด",
            "lo": "ເງິນສົດ",
            "km": "ប្រាក់សុទ្ធ",
            "vi": "Tiền mặt",
            "my": "ငွေသား"
        ],
        "promptpay_qr": [
            "en": "PromptPay QR",
            "th": "พร้อมเพย์ QR",
            "lo": "ພ້ອมເພຍ QR",
            "km": "ស្កែន QR",
            "vi": "Quét mã QR",
            "my": "QR ဖြင့် ပေးချေရန်"
        ],
        "credit_card": [
            "en": "Credit Card",
            "th": "บัตรเครดิต",
            "lo": "ບັດເຄຣດິດ",
            "km": "កាតឥណទាន",
            "vi": "Thẻ tín dụng",
            "my": "ခရက်ဒစ်ကတ်"
        ],
        "banknotes": [
            "en": "Banknotes",
            "th": "ธนบัตร",
            "lo": "ທະນາບັດ",
            "km": "ក្រដាសប្រាក់",
            "vi": "Mệnh giá tiền",
            "my": "ငွေစက္ကူများ"
        ],
        "change_due": [
            "en": "Change Due",
            "th": "เงินทอน",
            "lo": "ເງິນທອນ",
            "km": "ប្រាក់អាប់",
            "vi": "Tiền thừa",
            "my": "ပြန်အမ်းငွေ"
        ],
        "amount_missing": [
            "en": "Amount Missing",
            "th": "ยังขาดอีก",
            "lo": "ຍັງຂາດອີກ",
            "km": "នៅខ្វះចំនួន",
            "vi": "Còn thiếu",
            "my": "လိုနေသေးသော ปမာဏ"
        ],
        "confirm_payment": [
            "en": "Confirm Payment",
            "th": "ยืนยันการชำระเงิน",
            "lo": "ຢືນຢັນການຊຳລະເງິນ",
            "km": "បញ្ជាក់ការបង់ប្រាក់",
            "vi": "Xác nhận thanh toán",
            "my": "ငွေပေးချေမှု အတည်ပြုရန်"
        ],
        "payment_successful": [
            "en": "Payment successful",
            "th": "ชำระเงินเสร็จสมบูรณ์",
            "lo": "ຊຳລະເງິນສຳເລັດແລ້ວ",
            "km": "ការបង់ប្រាក់ជោគជ័យ",
            "vi": "Thanh toán thành công",
            "my": "ငွေပေးချေမှု အောင်မြင်ပါသည်"
        ],
        "close": [
            "en": "Close",
            "th": "ปิด",
            "lo": "ປິດ",
            "km": "បិទ",
            "vi": "Đóng",
            "my": "ပိတ်ရန်"
        ],
        "cancel": [
            "en": "Cancel",
            "th": "ยกเลิก",
            "lo": "ຍົກເລີກ",
            "km": "បោះបង់",
            "vi": "Hủy",
            "my": "မလုပ်တော့ပါ"
        ],
        "copy_store_id": [
            "en": "Copy Store ID",
            "th": "คัดลอกรหัสร้านค้า",
            "lo": "ຄັດລອກລະຫັດຮ້ານຄ້າ",
            "km": "ចម្លងលេខសម្គាល់ហាង",
            "vi": "Sao chép ID cửa hàng",
            "my": "ဆိုင် ID ကို ကူးယူပါ"
        ],
        "All": [
            "en": "All Zones",
            "th": "ทุกโซน",
            "lo": "ທຸກໂຊນ",
            "km": "គ្រប់តំបន់",
            "vi": "Tất cả khu vực",
            "my": "ဇုန်အားလုံး"
        ],
        "Indoor": [
            "en": "Indoor",
            "th": "ในร้าน",
            "lo": "ໃນຮ້าน",
            "km": "ក្នុងហាង",
            "vi": "Trong nhà",
            "my": "အိမ်တွင်း"
        ],
        "Outdoor": [
            "en": "Outdoor",
            "th": "นอกร้าน",
            "lo": "ນອກຮ້ាន",
            "km": "ក្រៅហាង",
            "vi": "Ngoài trời",
            "my": "အပြင်ဘက်"
        ],
        "Rooftop": [
            "en": "Rooftop",
            "th": "ดาดฟ้า",
            "lo": "ດາດຟ້າ",
            "km": "ជាន់លើបង្អស់",
            "vi": "Tầng thượng",
            "my": "ခေါင်မိုးပေါ်"
        ],
        "copied": [
            "en": "Copied!",
            "th": "คัดลอกแล้ว!",
            "lo": "ຄັດລອກແລ້ວ!",
            "km": "បានចម្លង!",
            "vi": "Đã sao chép!",
            "my": "ကူးယူပြီးပါပြီ။"
        ],
        "onboarding_guide_title": [
            "en": "Onboarding & Setup Guide",
            "th": "คู่มือการตั้งค่าและเริ่มต้นใช้งาน",
            "lo": "ຄູ່ມືການຕັ້ງຄ່າແລະເລີ່ມຕົ້ນໃຊ້ງານ",
            "km": "សេចក្តីណែនាំអំពីការរៀបចំ និងចាប់ផ្តើម",
            "vi": "Hướng dẫn thiết lập & Bắt đầu",
            "my": "စတင်ခြင်းနှင့် ဆက်တင်လမ်းညွှန်"
        ],
        "onboarding_guide_sub": [
            "en": "Follow these steps to get your team connected",
            "th": "ทำตามขั้นตอนด้านล่างเพื่อเชื่อมต่อบัญชีพนักงานของคุณ",
            "lo": "ເຮັດຕາມຂັ້ນຕອນດ້ານລຸ່ມເພື່ອເຊື່ອມຕໍ່ບັນຊີພະນັກງານຂອງທ່ານ",
            "km": "សូមអនុវត្តតាមជំហានខាងក្រោមដើម្បីភ្ជាប់ក្រុមការងាររបស់អ្នក",
            "vi": "Làm theo các bước sau để kết nối nhân viên của bạn",
            "my": "သင်၏ ဝန်ထမ်းအဖွဲ့အား ချိတ်ဆက်ရန် ဤအဆင့်များကို လုပ်ဆောင်ပါ"
        ],
        "add_employee": [
            "en": "Add Employee",
            "th": "เพิ่มพนักงาน",
            "lo": "ເພີ່ມພະນັກງານ",
            "km": "បន្ថែមបុគ្គលិក",
            "vi": "Thêm nhân viên",
            "my": "ဝန်ထမ်းအသစ်ထည့်ရန်"
        ],
        "edit_employee": [
            "en": "Edit Employee",
            "th": "แก้ไขพนักงาน",
            "lo": "ແກ້ໄຂພະນັກງານ",
            "km": "កែសម្រួលបុគ្គលិក",
            "vi": "Sửa nhân viên",
            "my": "ဝန်ထမ်းအချက်အလက်ပြင်ရန်"
        ],
        "schedule_shift": [
            "en": "Schedule Shift",
            "th": "จัดกะการทำงาน",
            "lo": "ຈັດກະລາຍວັນ",
            "km": "រៀបចំវេនការងារ",
            "vi": "Lên lịch ca",
            "my": "ဂျူတီချိန်သတ်မှတ်ရန်"
        ],
        "add_timecard": [
            "en": "Manual Timecard",
            "th": "บันทึกเวลาทำงานย้อนหลัง",
            "lo": "ບັນທຶກເວລາເຮັດວຽກຍ້ອນຫຼັງ",
            "km": "កាតម៉ោងដោយដៃ",
            "vi": "Điểm danh thủ công",
            "my": "အလုပ်ချိန်ကိုယ်တိုင်ပြင်ဆင်ရန်"
        ],
        "export_report": [
            "en": "Export Report",
            "th": "ส่งออกรายงาน",
            "lo": "ສົ່ງອອກລາຍງານ",
            "km": "នាំចេញរបាយការណ៍",
            "vi": "Xuất báo cáo",
            "my": "အစီရင်ခံစာထုတ်ရန်"
        ],
        "total_payroll": [
            "en": "Total Payroll",
            "th": "ยอดรวมค่าจ้างทั้งหมด",
            "lo": "ຍອດລວມຄ່າຈ້າງທັງໝົດ",
            "km": "សរុបប្រាក់បៀវត្សរ៍",
            "vi": "Tổng chi lương",
            "my": "စုစုပေါင်း ลစာစရိတ်"
        ],
        "total_hours": [
            "en": "Total Hours",
            "th": "ชั่วโมงทำงานรวม",
            "lo": "ຊົ່ວໂມງເຮັດວຽກລວມ",
            "km": "សរុបម៉ោងធ្វើการ",
            "vi": "Tổng số giờ",
            "my": "စုစုပေါင်း နာရီ"
        ],
        "total_ssf": [
            "en": "Total SSF",
            "th": "เงินสมทบประกันสังคมรวม",
            "lo": "ເງິນປະກັນສັງຄົມລວມ",
            "km": "សរុបវិភាគទានសង្គម",
            "vi": "Tổng BHXH",
            "my": "စုစုပေါင်း လူမှုဖူလုံရေး"
        ],
        "shift_planner": [
            "en": "Shift Planner",
            "th": "ตารางกะทำงาน",
            "lo": "ຕາຕະລາງກະລາຍວັນ",
            "km": "ផែនការវេនការងារ",
            "vi": "Lịch làm việc",
            "my": "ဂျူတီစီစဉ်သူ"
        ],
        "staff_registry": [
            "en": "Staff Registry",
            "th": "รายชื่อพนักงาน",
            "lo": "ລາຍຊື່ພະນັກງານ",
            "km": "បញ្ជីឈ្មោះបុគ្គលិក",
            "vi": "Danh sách nhân viên",
            "my": "ဝန်ထမ်းစာရင်း"
        ],
        "timecard_log": [
            "en": "Timecard Log",
            "th": "ประวัติการลงเวลา",
            "lo": "ປະຫວັດການລົງເວລາ",
            "km": "កំណត់ត្រាម៉ោងការងារ",
            "vi": "Lịch sử điểm danh",
            "my": "အလုပ်ချိန်မှတ်တမ်း"
        ],
        "retry": [
            "en": "Retry",
            "th": "ลองใหม่",
            "lo": "ລອງໃໝ່",
            "km": "ព្យាយាមម្តងទៀត",
            "vi": "Thử lại",
            "my": "ပြန်ကြိုးစားရန်"
        ],
        "store": [
            "en": "Store",
            "th": "ร้านค้า",
            "lo": "ຮ້ານຄ້າ",
            "km": "ហាង",
            "vi": "Cửa hàng",
            "my": "ဆိုင်"
        ],
        "clock_in": [
            "en": "Clock In",
            "th": "เข้างาน",
            "lo": "ເຂົ້າງານ",
            "km": "ចុះឈ្មោះចូល",
            "vi": "Vào ca",
            "my": "အလုပ်ဝင်"
        ],
        "clock_out": [
            "en": "Clock Out",
            "th": "เลิกงาน",
            "lo": "ເລີກງານ",
            "km": "ចុះឈ្មោះចេញ",
            "vi": "Ra ca",
            "my": "အလုပ်ထွက်"
        ],
        "worked_time": [
            "en": "Worked Time",
            "th": "เวลาทำงาน",
            "lo": "ເວລາເຮັດວຽກ",
            "km": "ម៉ោងធ្វើការ",
            "vi": "Thời gian làm việc",
            "my": "အလုပ်လုပ်ချိန်"
        ],
        "break": [
            "en": "Break",
            "th": "พัก",
            "lo": "ພັກ",
            "km": "សម្រាក",
            "vi": "Nghỉ giữa ca",
            "my": "နားချိန်"
        ],
        "overtime": [
            "en": "Overtime",
            "th": "ล่วงเวลา",
            "lo": "ລ່ວງເວລາ",
            "km": "ថែមម៉ោង",
            "vi": "Tăng ca",
            "my": "အချိန်ပို"
        ],
        "recent_shifts": [
            "en": "Recent Shifts Log",
            "th": "ประวัติบันทึกกะการทำงาน",
            "lo": "ປະຫວັດບັນທຶກກະການເຮັດວຽກ",
            "km": "កំណត់ហេតុវេនការងារថ្មីៗ",
            "vi": "Lịch sử ca làm việc",
            "my": "မကြာသေးမီက အလုပ်ဆိုင်းမှတ်တမ်း"
        ],
        "employment_type": [
            "en": "Employment Type",
            "th": "ประเภทการจ้างงาน",
            "lo": "ປະເພດການຈ້າງງານ",
            "km": "ប្រភេទការងារ",
            "vi": "Loại hợp đồng",
            "my": "အလုပ်အကိုင် အမျိုးအစား"
        ],
        "pay_rate": [
            "en": "Pay Rate",
            "th": "อัตราค่าจ้าง",
            "lo": "ອັດຕາຄ່າຈ້າງ",
            "km": "អត្រាប្រាក់ឈ្នួល",
            "vi": "Mức lương",
            "my": "လစာနှုန်းထား"
        ],
        "total_shift_hours": [
            "en": "Total Shift Hours",
            "th": "ชั่วโมงทำงานทั้งหมด",
            "lo": "ຊົ່ວໂມງເຮັດວຽກທັງໝົດ",
            "km": "ម៉ោងការងារសរុប",
            "vi": "Tổng số giờ làm",
            "my": "စုစုပေါင်း အလုပ်ချိန်နာရီ"
        ],
        "estimated_earnings": [
            "en": "Estimated Earnings",
            "th": "รายได้สะสมโดยประมาณ",
            "lo": "ລາຍໄດ້ສະສົມໂດຍປະມານ",
            "km": "ប្រាក់ចំណូលប៉ាន់ស្មាន",
            "vi": "Thu nhập ước tính",
            "my": "ခန့်မှန်းခြေ ဝင်ငွေ"
        ],
        "account_profile": [
            "en": "Account Profile Details",
            "th": "ข้อมูลโปรไฟล์ส่วนตัว",
            "lo": "ຂໍ້ມູນໂປຣຟາຍສ່ວນຕົວ",
            "km": "ព័ត៌មានលម្អិតប្រវត្តិរូប",
            "vi": "Chi tiết tài khoản",
            "my": "အကောင့်ပရိုဖိုင် အသေးစိတ်"
        ],
        "customer_service_calls": [
            "en": "Customer Service Calls",
            "th": "คำขอจากโต๊ะลูกค้า",
            "lo": "ຄຳຂໍຈາກໂຕະຮ້ານ",
            "km": "ការហៅសេវាកម្មអតិថិជន",
            "vi": "Yêu cầu phục vụ từ khách hàng",
            "my": "ဧည့်သည် ဝန်ဆောင်မှုတောင်းဆိုမှုများ"
        ],
        "active_requests": [
            "en": "Active Requests",
            "th": "คำขอรอดำเนินการ",
            "lo": "ລາຍການລໍຖ້າດຳເນີນການ",
            "km": "សំណើដែលកំពុងរង់ចាំ",
            "vi": "Yêu cầu đang chờ xử lý",
            "my": "လုပ်ဆောင်ဆဲ တောင်းဆိုချက်များ"
        ],
        "swipe_to_resolve": [
            "en": "Swipe to resolve",
            "th": "ปัดเพื่อทำเครื่องหมายเสร็จสิ้น",
            "lo": "ປັດເພື່ອໝາຍວ່າສຳເລັດ",
            "km": "អូសដើម្បីដោះស្រាយ",
            "vi": "Vuốt để hoàn thành",
            "my": "ဖြေရှင်းရန် ပွတ်ဆွဲပါ"
        ],
        "loading_tables_layout": [
            "en": "Loading tables layout...",
            "th": "กำลังโหลดข้อมูลผังโต๊ะ...",
            "lo": "ກຳลังໂຫລດຂໍ້ມູນຜັງໂຕະ...",
            "km": "កំពុងផ្ទុកប្លង់តុ...",
            "vi": "Đang tải sơ đồ bàn...",
            "my": "စားပွဲပုံစံကို ယူနေသည်..."
        ],
        "capacity_guests": [
            "en": "Capacity: %d guests",
            "th": "ความจุ: %d คน",
            "lo": "ຄວາມຈຸ: %d ຄົນ",
            "km": "ចំណុះ៖ %d នាក់",
            "vi": "Sức chứa: %d khách",
            "my": "ဆံ့ဝင်ဦးရေ: %d ဦး"
        ],
        "guests_count_label": [
            "en": "%d guests",
            "th": "%d คน",
            "lo": "%d ຄົນ",
            "km": "%d នាក់",
            "vi": "%d khách",
            "my": "%d ဦး"
        ],
        "open_session_table": [
            "en": "Open Session: Table %@",
            "th": "เปิดโต๊ะ: โต๊ะ %@",
            "lo": "ເປີດໂຕະ: ໂຕະ %@",
            "km": "បើកតុ៖ តុ %@",
            "vi": "Mở bàn: Bàn %@",
            "my": "စားပွဲဖွင့်မည်- စားပွဲ %@"
        ],
        "manage_tables": [
            "en": "Manage Tables",
            "th": "จัดการโต๊ะอาหาร",
            "lo": "ຈັດการโตะอาหาร",
            "km": "គ្រប់គ្រងតុ",
            "vi": "Quản lý bàn",
            "my": "စားပွဲများ စီမံမည်"
        ],
        "hourly": [
            "en": "Hourly",
            "th": "รายชั่วโมง",
            "lo": "ລາຍຊົ່ວໂມງ",
            "km": "ម៉ោង",
            "vi": "Theo giờ",
            "my": "နာရီအလိုက်"
        ],
        "daily": [
            "en": "Daily",
            "th": "รายวัน",
            "lo": "ລາຍວັນ",
            "km": "ប្រចាំថ្ងៃ",
            "vi": "Theo ngày",
            "my": "နေ့စဉ်"
        ],
        "monthly": [
            "en": "Monthly",
            "th": "รายเดือน",
            "lo": "ລາຍເດືອນ",
            "km": "ប្រចាំខែ",
            "vi": "Theo tháng",
            "my": "လစဉ်"
        ],
        "no_staff_title": [
            "en": "No Staff Profiles Found",
            "th": "ไม่พบข้อมูลพนักงาน",
            "lo": "ບໍ່ພົບຂໍ້ມູນພະນັກງານ",
            "km": "រកមិនឃើញប្រវត្តិរូបបុគ្គលិកទេ",
            "vi": "Không tìm thấy tài khoản nhân viên",
            "my": "ဝန်ထမ်းပရိုဖိုင်များ မတွေ့ပါ"
        ],
        "no_staff_sub": [
            "en": "This store ID does not have any registered staff profiles yet, or the database is empty.",
            "th": "รหัสร้านค้านี้ยังไม่มีการเพิ่มข้อมูลพนักงาน หรือข้อมูลในระบบว่างเปล่า",
            "lo": "ລະຫັດຮ້านຄ້ານີ້ຍັງບໍ່ມີຂໍ້ມູນພະนັກງານ ຫຼື ຂໍ້ມູນໃນລະບົບຫວ່າງເປົ່າ",
            "km": "លេខសម្គាល់ហាងនេះមិនទាន់មានប្រវត្តិរូបបុគ្គលិកដែលបានចុះឈ្មោះទេ ឬទិន្នន័យទទេ",
            "vi": "Mã cửa hàng này chưa đăng ký hồ sơ nhân viên nào, hoặc cơ sở dữ liệu trống.",
            "my": "ဤဆိုင် ID တွင် မည်သည့်ဝန်ထမ်းပရိုဖိုင်မျှ မရှိသေးပါ သို့မဟုတ် ดေတာဗေ့စ်သည် ဗလာဖြစ်နေသည်။"
        ],
        "onboarding_step1": [
            "en": "1. Add staff profiles in the iPad POS admin settings panel.",
            "th": "1. เพิ่มโปรไฟล์พนักงานในหน้าการตั้งค่าเครื่อง iPad POS หลัก",
            "lo": "1. ເພີ່ມຂໍ້ມູນພະนັກງານໃນໜ້າຕັ້ງຄ່າເຄື່ອງ iPad POS ຫຼັກ",
            "km": "1. បន្ថែមប្រវត្តិរូបបុគ្គលិកនៅក្នុងផ្ទាំងកំណត់ iPad POS ធំ។",
            "vi": "1. Thêm tài khoản nhân viên trong bảng cài đặt iPad POS chính.",
            "my": "1. iPad POS စီမံခန့်ခွဲသူ ဆက်တင်များဘောင်တွင် ဝန်ထမ်းပရိုဖိုင်များ ထည့်ပါ။"
        ],
        "onboarding_step2": [
            "en": "2. Ensure your iPhone is paired with the correct Store ID (UUID).",
            "th": "2. ตรวจสอบให้แน่ใจว่า iPhone ของคุณเชื่อมต่อกับ Store ID (UUID) ที่ถูกต้อง",
            "lo": "2. ກວດສອບໃຫ້ແນ່ໃຈว่า iPhone ຂອງເຈົ້າເຊື່ອມຕໍ່ກັບ Store ID (UUID) ທີ່ຖືກຕ້ອງ",
            "km": "2. ប្រាកដថា iPhone របស់អ្នកបានភ្ជាប់ជាមួយលេខសម្គាល់ហាង (UUID) ត្រឹមត្រូវ។",
            "vi": "2. Đảm bảo iPhone của bạn được liên kết đúng ID cửa hàng (UUID).",
            "my": "2. သင်၏ iPhone ကို ဆိုင် ID (UUID) အမှန်နှင့် ချိတ်ဆက်ထားကြောင်း သေချาပါစေ။"
        ],
        "onboarding_step3": [
            "en": "3. Tap Refresh Profiles below to retrieve updated accounts.",
            "th": "3. กดปุ่ม 'รีเฟรชข้อมูลพนักงาน' ด้านล่างเพื่อดึงข้อมูลอัปเดตล่าสุด",
            "lo": "3. ກົດປຸ່ມ 'ດຶງຂໍ້ມູນໃໝ່' ດ້ານລຸ່ມເພື່ອດຶงຂໍ້ມູນຫຼ້າสุด",
            "km": "3. ចុច 'ធ្វើបច្ចុប្បន្នភាព' ខាងក្រោមដើម្បីទាញយកប្រវត្តិរូបថ្មី។",
            "vi": "3. Nhấn 'Tải lại danh sách' bên dưới để cập nhật danh sách.",
            "my": "3. နောက်ဆုံးပေါ် အကောင့်များကို ရယူရန် အောက်ရှိ 'အကောင့်များ ပြန်ယူမည်' ကို နှိပ်ပါ။"
        ],
        "connect_demo_store": [
            "en": "Connect Demo Store (Sandbox)",
            "th": "เชื่อมต่อร้านค้าจำลอง (Sandbox)",
            "lo": "ເຊື່ອມຕໍ່ຮ້ານຄ້າຈໍາລອງ (Sandbox)",
            "km": "ភ្ជាប់ហាងសាកល្បง Demo Store",
            "vi": "Kết nối cửa hàng thử nghiệm (Demo)",
            "my": "စမ်းသပ်ဆိုင်ခွဲနှင့် ချိတ်ဆက်မည် (Sandbox)"
        ],
        "refresh_profiles": [
            "en": "Refresh Profiles",
            "th": "รีเฟรชข้อมูลพนักงาน",
            "lo": "ດຶງຂໍ້ມູນໃໝ່",
            "km": "ធ្វើបច្ចុប្បន្នភាព",
            "vi": "Tải lại danh sách",
            "my": "အကောင့်များ ပြန်ယူမည်"
        ],
        "change_store_id": [
            "en": "Change Store ID / Link Shop",
            "th": "เปลี่ยนรหัสร้านค้า / เชื่อมต่อใหม่",
            "lo": "ປ່ຽນລະຫັດຮ້ານຄ້າ / ເຊື່ອມຕໍ່ໃໝ່",
            "km": "ផ្លាស់ប្តូរលេខសម្គាល់ហាង / ភ្ជាប់ម្តងទៀត",
            "vi": "Thay đổi ID cửa hàng / Liên kết lại",
            "my": "ဆိုင် ID ပြောင်းမည် / ပြန်လည်ချိတ်ဆက်မည်"
        ],
        "ready_to_scan": [
            "en": "Ready to Scan",
            "th": "พร้อมสแกน",
            "lo": "ພ້ອມສະແກນ",
            "km": "ត្រៀមខ្លួនសម្រាប់ស្កែន",
            "vi": "Sẵn sàng quét",
            "my": "စကင်န်ဖတ်ရန် အဆင်သင့်ဖြစ်ပါပြီ"
        ],
        "no_pending_requests": [
            "en": "No pending requests",
            "th": "ไม่มีคำขอรอดำเนินการ",
            "lo": "ບໍ່ມີລາຍການລໍຖ້າດຳເນີນການ",
            "km": "គ្មានសំណើដែលកំពុងរង់ចាំ",
            "vi": "Không có yêu cầu nào",
            "my": "လုပ်ဆောင်ရန် တောင်းဆိုချက်မရှိပါ"
        ],
        "pending_requests_sub": [
            "en": "When customers call or check bills from their phones, alerts will appear here.",
            "th": "เมื่อลูกค้าเรียกพนักงานหรือเรียกเช็คบิลผ่านมือถือ รายการจะแสดงขึ้นที่นี่",
            "lo": "ເມື່ອລູກຄ້າຮຽກພະນັກງານຫຼືຮຽກເກັບເງິນຜ່ານມືຖື ລາຍການຈະສະແດງຢູ່ນີ້",
            "km": "នៅពេលអតិថិជនហៅសេវាកម្ម ឬគិតលុយពីទូរស័ព្ទ សេចក្តីជូនដំណឹងនឹងបង្ហាញនៅទីនេះ។",
            "vi": "Khi khách hàng gọi phục vụ hoặc yêu cầu thanh toán từ điện thoại, thông báo sẽ hiển thị ở đây.",
            "my": "ဧည့်သည်များ ဖုန်းဖြင့် ခေါ်ယူခြင်း သို့မဟုတ် ငွေတောင်းခံခြင်းများ ပြုလုပ်ပါက ဤနေရာတွင် ပေါ်လာပါမည်။"
        ],
        "resolve": [
            "en": "Resolve",
            "th": "ดำเนินการแล้ว",
            "lo": "ດຳເນີນການແລ້ວ",
            "km": "ដោះស្រាយ",
            "vi": "Hoàn thành",
            "my": "ဖြေရှင်းပြီး"
        ],
        "table_label": [
            "en": "Table %@",
            "th": "โต๊ะ %@",
            "lo": "ໂຕະ %@",
            "km": "តុ %@",
            "vi": "Bàn %@",
            "my": "စားပွဲ %@"
        ],
        "on_shift": [
            "en": "ON SHIFT",
            "th": "กำลังเข้างาน",
            "lo": "ກຳລັງເຮັດວຽກ",
            "km": "កំពុងបំពេញការងារ",
            "vi": "ĐANG LÀM VIỆC",
            "my": "အလုပ်ချိန်အတွင်း"
        ],
        "off_duty": [
            "en": "OFF DUTY",
            "th": "ยังไม่ได้เข้างาน",
            "lo": "ຍັງບໍ່ໄດ້ເຂົ້າວຽก",
            "km": "ក្រៅម៉ោងការងារ",
            "vi": "ĐANG NGHỈ CA",
            "my": "အလုပ်ပြင်ပ"
        ],
        "started_at": [
            "en": "Started at",
            "th": "เริ่มงานเมื่อ",
            "lo": "ເລີ່ມວຽກເມື່ອ",
            "km": "ចាប់ផ្តើមនៅ",
            "vi": "Bắt đầu lúc",
            "my": "စတင်ချိန်"
        ],
        "auth_clock_out": [
            "en": "Authenticate & Clock Out",
            "th": "สแกนใบหน้าและเลิกงาน",
            "lo": "ສະແກນໃບໜ້າและເລີກວຽກ",
            "km": "ផ្ទៀងផ្ទាត់ ແລະចុះឈ្មោះចេញ",
            "vi": "Xác thực & Ra ca",
            "my": "စစ်ဆေးပြီး အလုပ်ထွက်ပါ"
        ],
        "not_clocked_in_today": [
            "en": "Not clocked in today",
            "th": "วันนี้ยังไม่ได้ลงเวลาเข้างาน",
            "lo": "ມື້ນີ້ຍັງບໍ່ໄດ້ລົງเวลาເຂົ້າວຽກ",
            "km": "មិនទាន់ចុះឈ្មោះចូលនៅថ្ងៃនេះទេ",
            "vi": "Hôm nay chưa điểm danh vào",
            "my": "ယနေ့ အလုပ်မဝင်ရသေးပါ"
        ],
        "auth_clock_in": [
            "en": "Authenticate & Clock In",
            "th": "สแกนใบหน้าและเข้างาน",
            "lo": "ສະແກນໃบໜ້າและເຂົ້າວຽก",
            "km": "ផ្ទៀងផ្ទាត់ และចុះឈ្មោះចូល",
            "vi": "Xác thực & Vào ca",
            "my": "စစ်ဆေးပြီး အလုပ်ဝင်ပါ"
        ],
        "no_clock_in_records": [
            "en": "No clock in records found.",
            "th": "ไม่พบประวัติการลงเวลางาน",
            "lo": "ບໍ່ພົບປະຫວັດການລົງເວลາງານ",
            "km": "រកមិនឃើញប្រវត្តិចុះឈ្មោះចូលទេ",
            "vi": "Không tìm thấy dữ liệu điểm danh",
            "my": "အလုပ်ချိန်မှတ်တမ်း မရှိပါ"
        ],
        "active_now": [
            "en": "Active Now",
            "th": "กำลังทำอยู่",
            "lo": "ກຳລັງເຮັດວຽກຢູ່",
            "km": "កំពុងដំណើរការ",
            "vi": "Đang làm việc",
            "my": "လက်ရှိ လုပ်ဆောင်ဆဲ"
        ],
        "hours_worked_format": [
            "en": "%.1f hrs",
            "th": "%.1f ชม.",
            "lo": "%.1f ຊມ.",
            "km": "%.1f ម៉ោង",
            "vi": "%.1f giờ",
            "my": "%.1f နာရီ"
        ],
        "timecard_register": [
            "en": "Timecard Register",
            "th": "เครื่องบันทึกเวลาทำงาน",
            "lo": "ເຄື່ອງບັນທຶກເວลາງານ",
            "km": "ម៉ាស៊ីនကត់ត្រាម៉ោងធ្វើការ",
            "vi": "Ghi nhận giờ công",
            "my": "အလုပ်ချိန် မှတ်ပုံတင်"
        ],
        "align_face_camera": [
            "en": "Align face in camera frame",
            "th": "จัดใบหน้าให้อยู่ในกรอบกล้อง",
            "lo": "ຈັດໃບໜ້າໃຫ້ຢູ່ໃນກອບກ້ອງ",
            "km": "តម្រឹមផ្ទៃមុខក្នុងស៊ុមម៉ាស៊ីនថត",
            "vi": "Căn chỉnh khuôn mặt vào khung hình",
            "my": "မျက်နှာကို ကင်မရာဘောင်အတွင်း ထားပါ"
        ],
        "matching_facial": [
            "en": "Matching facial coordinates...",
            "th": "กำลังจับคู่พิกัดใบหน้า...",
            "lo": "ກຳລັງຈັບຄູ່ພິກັດໃບໜ້າ...",
            "km": "កំពុងផ្គូផ្គងកូអរដោនេផ្ទៃមុខ...",
            "vi": "Đang so khớp tọa độ khuôn mặt...",
            "my": "မျက်နှာ ပုံစံများကို တိုက်ဆိုင်စစ်ဆေးနေသည်..."
        ],
        "biometric_verified_percent": [
            "en": "Biometric Match Verified! (%.1f%%)",
            "th": "ยืนยันพิกัดชีวภาพสำเร็จ! (%.1f%%)",
            "lo": "ຢືນຢັນພິກັດຊີວະພາບສໍາເລັດ! (%.1f%%)",
            "km": "ការផ្គូផ្គងជីវមាត្រត្រូវបានបញ្ជាក់! (%.1f%%)",
            "vi": "Xác thực sinh trắc học thành công! (%.1f%%)",
            "my": "ဇီဝမက်ထရစ် ကိုက်ညီမှု အတည်ပြုပြီးပါပြီ။ (%.1f%%)"
        ],
        "hours_worked_label": [
            "en": "Hours Worked",
            "th": "ชั่วโมงทำงาน",
            "lo": "ຊົ່ວໂມງເຮັດວຽກ",
            "km": "ម៉ោងធ្វើការសរុប",
            "vi": "Giờ làm việc",
            "my": "အလုပ်လုပ်ချိန် နာရီ"
        ],
        "accumulated_pay": [
            "en": "Accumulated Pay",
            "th": "รายได้สะสม",
            "lo": "ລາຍໄດ້ສະສົມ",
            "km": "ប្រាក់ចំណូលសរុប",
            "vi": "Lương tích lũy",
            "my": "စုဆောင်းရရှိသော ลစာ"
        ],
        "contract_details": [
            "en": "Contract Details",
            "th": "รายละเอียดสัญญาจ้าง",
            "lo": "ລາຍລະອียดสัญญาจ้าง",
            "km": "ព័ត៌មានលម្អិតកិច្ចសន្យា",
            "vi": "Chi tiết hợp đồng",
            "my": "စာချုပ် အသေးစိတ်"
        ],
        "phone": [
            "en": "Phone",
            "th": "เบอร์โทรศัพท์",
            "lo": "ເບີໂທລະສັບ",
            "km": "លេខទូរស័ព្ទ",
            "vi": "Số điện thoại",
            "my": "ဖုန်းနံပါတ်"
        ],
        "national_id": [
            "en": "National ID",
            "th": "เลขประจำตัวประชาชน",
            "lo": "ເລກບັດປະຈຳຕົວ",
            "km": "អត្តសញ្ញាណប័ណ្ណ",
            "vi": "Số CCCD/CMND",
            "my": "နိုင်ငံသားစိစစ်ရေးကတ်ပြား"
        ],
        "pay_rate_hourly_format": [
            "en": "฿%d/hr",
            "th": "฿%d/ชม.",
            "lo": "฿%d/ຊມ.",
            "km": "฿%d/ម៉ោង",
            "vi": "฿%d/giờ",
            "my": "฿%d/နာရီ"
        ],
        "pay_rate_daily_format": [
            "en": "฿%d/day",
            "th": "฿%d/วัน",
            "lo": "฿%d/ວັນ",
            "km": "฿%d/ថ្ងៃ",
            "vi": "฿%d/ngày",
            "my": "฿%d/ရက်"
        ],
        "pay_rate_monthly_format": [
            "en": "฿%d/month",
            "th": "฿%d/เดือน",
            "lo": "฿%d/ເດືອນ",
            "km": "฿%d/ខែ",
            "vi": "฿%d/tháng",
            "my": "฿%d/လ"
        ],
        "log_out": [
            "en": "Log Out",
            "th": "ออกจากระบบ",
            "lo": "ອອກຈາກລະບົບ",
            "km": "ចាកចេញ",
            "vi": "Đăng xuất",
            "my": "အကောင့်မှ ထွက်ရန်"
        ],
        "staff_space": [
            "en": "Staff Space",
            "th": "พื้นที่พนักงาน",
            "lo": "ພື້ນທີ່ພະນັກງານ",
            "km": "តំបន់បុគ្គលិក",
            "vi": "Khu vực nhân viên",
            "my": "ဝန်ထမ်းနေရာ"
        ],
        "session_orders": [
            "en": "Session Orders",
            "th": "รายการสั่งซื้อในรอบนี้",
            "lo": "ລາຍການສັ່ງຊື້ໃນຮອບນີ້",
            "km": "ការកុម្មង់ក្នុងវគ្គនេះ",
            "vi": "Các món trong lượt",
            "my": "လက်ရှိ မှာယူမှုများ"
        ],
        "table_guests_count_format": [
            "en": "Table %@ · %d Guests",
            "th": "โต๊ะ %@ · ลูกค้า %d คน",
            "lo": "ໂຕະ %@ · ລູກຄ້າ %d ຄົນ",
            "km": "តុ %@ · ភ្ញៀវ %d នាក់",
            "vi": "Bàn %@ · %d Khách",
            "my": "စားပွဲ %@ · ဧည့်သည် %d ဦး"
        ],
        "no_orders_placed": [
            "en": "No orders placed yet",
            "th": "ยังไม่มีรายการอาหารสั่งเข้ามา",
            "lo": "ຍັງບໍ່ມີລายການອາຫານສັ່ງເຂົ้າມา",
            "km": "មិនទាន់មានការកុម្មង់ទេ",
            "vi": "Chưa có món nào được gọi",
            "my": "မှာယူထားသော ဟင်းပွဲမရှိသေးပါ"
        ],
        "order_food": [
            "en": "Order Food",
            "th": "สั่งอาหาร",
            "lo": "ສັ່ງອາຫານ",
            "km": "កុម្មង់ម្ហូប",
            "vi": "Gọi món",
            "my": "အစားအစာ မှာယူရန်"
        ],
        "delete": [
            "en": "Delete",
            "th": "ลบ",
            "lo": "ລຶບ",
            "km": "លុប",
            "vi": "Xóa",
            "my": "ဖျက်မည်"
        ],
        "add_food": [
            "en": "Add Food",
            "th": "เพิ่มรายการอาหาร",
            "lo": "ເພີ່ມອາຫານ",
            "km": "បន្ថែមម្ហូប",
            "vi": "Thêm món ăn",
            "my": "အစားအစာ ထပ်ထည့်ရန်"
        ],
        "bill_payment": [
            "en": "Bill Payment",
            "th": "ชำระเงินเช็คบิล",
            "lo": "ຊຳລະເງິນ",
            "km": "គិតលុយ",
            "vi": "Thanh toán",
            "my": "ငွေပေးချေမည်"
        ],
        "table_details_title": [
            "en": "Table details",
            "th": "รายละเอียดโต๊ะ",
            "lo": "ລາຍລະອຽດໂຕະ",
            "km": "ព័ត៌មានលម្អិតតុ",
            "vi": "Chi tiết bàn",
            "my": "စားပွဲ အသေးစိတ်"
        ],
        "add_items_title": [
            "en": "Add items",
            "th": "เพิ่มรายการอาหาร",
            "lo": "ເພີ່ມລາຍການ",
            "km": "បន្ថែមមុខម្ហូប",
            "vi": "Thêm món",
            "my": "ပစ္စည်းထည့်ရန်"
        ],
        "add_button": [
            "en": "Add",
            "th": "เพิ่ม",
            "lo": "ເພີ່ມ",
            "km": "បន្ថែម",
            "vi": "Thêm",
            "my": "ထည့်မည်"
        ],
        "submit_order_items_format": [
            "en": "Submit Order (%d Items)",
            "th": "ส่งรายการเข้าครัว (%d รายการ)",
            "lo": "ສົ່ງລາຍການເຂົ້າຄົວ (%d ລາຍການ)",
            "km": "បញ្ជូនការកុម្មង់ (%d មុខ)",
            "vi": "Gửi đơn (%d món)",
            "my": "မှာယူမှု ပို့ရန် (%d ခု)"
        ],
        "billing_summary": [
            "en": "Billing Summary",
            "th": "สรุปยอดเช็คบิล",
            "lo": "ສະຫຼຸບຍອດເງິນ",
            "km": "សេចក្តីសង្ខេបវិក្កយបត្រ",
            "vi": "Tóm tắt thanh toán",
            "my": "ငွေတောင်းခံမှု အကျဉ်းချုပ်"
        ],
        "subtotal": [
            "en": "Subtotal",
            "th": "ยอดรวมก่อนภาษี/บริการ",
            "lo": "ຍອດລວμກ່ອນພາສີ",
            "km": "សរុបផ្នែក",
            "vi": "Tạm tính",
            "my": "စုစုပေါင်းခွဲ"
        ],
        "vat_label": [
            "en": "VAT (7%)",
            "th": "ภาษีมูลค่าเพิ่ม (7%)",
            "lo": "ພາສີມູນຄ່າເພີ່ມ (7%)",
            "km": "អាករតម្លៃបន្ថែម (7%)",
            "vi": "Thuế GTGT (7%)",
            "my": "တန်ဖိုးမြှင့်အခွန် (7%)"
        ],
        "service_charge_label": [
            "en": "Service Charge (10%)",
            "th": "ค่าบริการ (10%)",
            "lo": "ຄ່າບໍລິການ (10%)",
            "km": "សេវាកម្មសរុប (10%)",
            "vi": "Phí phục vụ (10%)",
            "my": "ဝန်ဆောင်ခ (10%)"
        ],
        "grand_total": [
            "en": "Grand Total",
            "th": "ยอดรวมทั้งสิ้น",
            "lo": "ຍອດລວμທັງໝົດ",
            "km": "សរុបរួម",
            "vi": "Tổng thanh toán",
            "my": "စုစုပေါင်း အသားတင်"
        ],
        "select_payment_method": [
            "en": "Select Payment Method",
            "th": "เลือกช่องทางการชำระเงิน",
            "lo": "ເລືອກຊ່ອງທາງຊຳລະເງິນ",
            "km": "ជ្រើសរើសវិធីសាស្ត្របង់ប្រាក់",
            "vi": "Chọn phương thức thanh toán",
            "my": "ငွေပေးချေမှုစနစ် ရွေးပါ"
        ],
        "checkout_title": [
            "en": "Checkout",
            "th": "เช็คบิลชำระเงิน",
            "lo": "ຊຳລະເງິນ",
            "km": "ទូទាត់ប្រាក់",
            "vi": "Thanh toán",
            "my": "ငွေရှင်းမည်"
        ],
        "cash_payment": [
            "en": "Cash Payment",
            "th": "การชำระเงินสด",
            "lo": "ຊຳລະເງິນສົດ",
            "km": "ការបង់ប្រាក់សុទ្ធ",
            "vi": "Thanh toán tiền mặt",
            "my": "ငွေသားဖြင့် ပေးချေခြင်း"
        ],
        "cash_payment_sub": [
            "en": "Enter cash received to calculate change",
            "th": "ระบุจำนวนเงินสดที่ได้รับเพื่อคำนวณเงินทอน",
            "lo": "ປ້ອນຈຳນວນເງິນສົດທີ່ໄດ້ຮັບເພື່ອຄິດໄລ່ເງິນທອນ",
            "km": "បញ្ចូលប្រាក់ទទួលបានដើម្បីគណនាប្រាក់អាប់",
            "vi": "Nhập số tiền nhận được để tính tiền thừa",
            "my": "ပြန်အမ်းငွေတွက်ရန် ရရှိသောငွေသားကို ရိုက်ထည့်ပါ"
        ],
        "open_cash_terminal": [
            "en": "Open Cash Terminal",
            "th": "เปิดหน้าต่างระบุเงินสด",
            "lo": "ເປີດປ້ອນເງິນສົດ",
            "km": "បើកផ្ទាំងគិតប្រាក់សុទ្ធ",
            "vi": "Mở bàn phím tiền mặt",
            "my": "ငွေသားလက်ခံစနစ် ဖွင့်ပါ"
        ],
        "scan_promptpay_sub": [
            "en": "Scan to pay via PromptPay QR",
            "th": "สแกนเพื่อชำระเงินผ่าน QR พร้อมเพย์",
            "lo": "ສະແກນເພື່ອຊຳລະເງິນຜ່ານ QR ພ້ອມເພຍ",
            "km": "ស្កែនដើម្បីបង់ប្រាក់តាមកូដ QR",
            "vi": "Quét để thanh toán qua mã QR",
            "my": "QR ဖြင့် ငွေပေးချေရန် စကင်န်ဖတ်ပါ"
        ],
        "emv_simulator": [
            "en": "EMV Tap / Swipe Simulator",
            "th": "ตัวจำลองการแตะ/รูดบัตร (EMV)",
            "lo": "ຕົວຈຳລອງการແຕະ/ຮູດບັດ (EMV)",
            "km": "ការសាកល្បងប៉ះ/អូសកាត (EMV)",
            "vi": "Trình mô phỏng chạm/quẹt thẻ EMV",
            "my": "EMV ကတ်ဖတ်စက် စမ်းသပ်စနစ်"
        ],
        "emv_instruction": [
            "en": "Please present / insert credit card into terminal...",
            "th": "กรุณาแตะ เสียบ หรือรูดบัตรเครดิตเข้ากับเครื่องรับบัตร...",
            "lo": "ກະລຸນາແຕະ ຫຼື ສຽບບັດເຄຣດິດກັບເຄື່ອງ...",
            "km": "សូមដាក់ ឬស៊កកាតឥណទានចូលទៅក្នុងម៉ាស៊ីន...",
            "vi": "Vui lòng chạm / đưa thẻ tín dụng vào máy...",
            "my": "ကျေးဇူးပြု၍ ခရက်ဒစ်ကတ်ကို စက်တွင် ထားပါ သို့မဟုတ် ထည့်သွင်းပါ..."
        ],
        "payment_successful_title": [
            "en": "Payment Successful!",
            "th": "ชำระเงินเสร็จสิ้น!",
            "lo": "ຊຳລະເງິນສຳເລັດແລ້ວ!",
            "km": "ការបង់ប្រាក់ជោគជ័យ!",
            "vi": "Thanh toán thành công!",
            "my": "ငွေပေးချေမှု အောင်မြင်ပါသည်!"
        ],
        "receipt_printed_msg": [
            "en": "Receipt printed and table %@ vacant.",
            "th": "พิมพ์ใบเสร็จแล้วและตั้งสถานะโต๊ะ %@ ให้ว่าง",
            "lo": "ພິມໃບເກັບເງິນແລ້ວ ແລະ ຕັ້ງສະຖານະໂຕະ %@ ໃຫ້ຫວ່າງ",
            "km": "វិក្កយបត្រត្រូវបានបោះពុម្ព ហើយតុ %@ ទំនេរ។",
            "vi": "Đã in hóa đơn và bàn %@ hiện đã trống.",
            "my": "ပြေစာထုတ်ပြီး စားပွဲ %@ လွတ်သွားပါပြီ။"
        ],
        "payment_type": [
            "en": "Payment Type",
            "th": "ประเภทการชำระเงิน",
            "lo": "ປະເພດການຊຳລະ",
            "km": "ប្រភេទការបង់ប្រាក់",
            "vi": "Hình thức thanh toán",
            "my": "ငွေပေးချေမှု အမျိုးအစား"
        ],
        "done": [
            "en": "Done",
            "th": "เสร็จสิ้น",
            "lo": "ສຳເລັດ",
            "km": "រួចរាល់",
            "vi": "Xong",
            "my": "ပြီးပါပြီ"
        ],
        "exact": [
            "en": "Exact",
            "th": "พอดี",
            "lo": "ພໍດີ",
            "km": "គ្រប់ចំនួន",
            "vi": "Đủ tiền",
            "my": "အတိအကျ"
        ],
        "closing_in_seconds_format": [
            "en": "Closing in %.0f seconds...",
            "th": "กำลังปิดในอีก %.0f วินาที...",
            "lo": "ກຳລັງປິດໃນອີກ %.0f ວິນາທີ...",
            "km": "បិទក្នុងរយៈពេល %.0f វិនាទី...",
            "vi": "Đóng trong %.0f giây nữa...",
            "my": "နာရီ %.0f စက္ကန့်အတွင်း ပိတ်ပါမည်..."
        ],
        "missing": [
            "en": "Missing",
            "th": "ยังขาด",
            "lo": "ຍັງຂາດ",
            "km": "នៅខ្វះ",
            "vi": "Còn thiếu",
            "my": "လိုနေသည်"
        ],
        "all": [
            "en": "All",
            "th": "ทั้งหมด",
            "lo": "ທັງໝົດ",
            "km": "ទាំងអស់",
            "vi": "Tất cả",
            "my": "အားလုံး"
        ],
        "appetizers": [
            "en": "Appetizers",
            "th": "ของกินเล่น",
            "lo": "ອາຫານວ່າງ",
            "km": "អាហារសម្រន់",
            "vi": "Món khai vị",
            "my": "အမြည်းများ"
        ],
        "mains": [
            "en": "Mains",
            "th": "อาหารหลัก",
            "lo": "ອາຫານຫຼັກ",
            "km": "ម្ហូបសំខាន់",
            "vi": "Món chính",
            "my": "ပင်မဟင်းလျာများ"
        ],
        "drinks": [
            "en": "Drinks",
            "th": "เครื่องดื่ม",
            "lo": "เครื่องดื่ม",
            "km": "ភេសជ្ជៈ",
            "vi": "Đồ uống",
            "my": "အအေးနှင့်သောက်စရာ"
        ],
        "desserts": [
            "en": "Desserts",
            "th": "ของหวาน",
            "lo": "ຂອງຫວານ",
            "km": "បង្អែម",
            "vi": "Món tráng miệng",
            "my": "အချိုပွဲများ"
        ],
        "enable_notifications": [
            "en": "Enable Notifications",
            "th": "เปิดใช้งานการแจ้งเตือน"
        ],
        "enable_notifications_desc": [
            "en": "Receive alerts for new orders, ready dishes, and service requests.",
            "th": "รับการแจ้งเตือนสำหรับออร์เดอร์ใหม่ อาหารพร้อมเสิร์ฟ และคำเรียกพนักงาน"
        ],
        "settings_section": [
            "en": "SETTINGS",
            "th": "การตั้งค่าแอป"
        ],
        "active_alerts_section": [
            "en": "Active Alerts",
            "th": "รายการที่ต้องจัดการ"
        ],
        "resolved_history_section": [
            "en": "History / Resolved",
            "th": "ประวัติที่ดำเนินการแล้ว"
        ],
        "priority_high": [
            "en": "High",
            "th": "สำคัญมาก"
        ],
        "priority_medium": [
            "en": "Medium",
            "th": "ปานกลาง"
        ],
        "priority_low": [
            "en": "Low",
            "th": "ทั่วไป"
        ],
        "serve_action": [
            "en": "Serve",
            "th": "เสิร์ฟ"
        ],
        "order_ready": [
            "en": "Order Ready",
            "th": "อาหารพร้อมเสิร์ฟ"
        ],
        "order_preparing": [
            "en": "Preparing",
            "th": "กำลังเตรียมอาหาร"
        ],
        "order_served": [
            "en": "Served",
            "th": "เสิร์ฟแล้ว"
        ],
        "order_completed": [
            "en": "Completed",
            "th": "เสร็จสิ้น"
        ],
        "served_items_locked": [
            "en": "Served items are locked",
            "th": "รายการที่เสิร์ฟแล้วถูกล็อก"
        ],
        "shift_required_title": [
            "en": "Clock In Required",
            "th": "ต้องเข้ากะก่อน"
        ],
        "shift_required_subtitle": [
            "en": "You must clock in before placing orders. Please go to Clock In/Out to start your shift.",
            "th": "คุณต้องลงเวลาเข้างานก่อนจึงจะสั่งอาหารได้ กรุณาไปที่หน้าลงเวลาเข้างาน"
        ],
        "shift_guard_nav_title": [
            "en": "Shift Verification",
            "th": "ตรวจสอบกะทำงาน"
        ],
        "shift_guard_info_text": [
            "en": "For security and payroll accuracy, all staff must have an active shift before performing POS operations.",
            "th": "เพื่อความปลอดภัยและความถูกต้องของค่าแรง พนักงานทุกคนต้องเข้ากะก่อนใช้งานระบบ POS"
        ],
        "go_to_clock_in_btn": [
            "en": "Go to Clock In",
            "th": "ไปลงเวลาเข้างาน"
        ],
        "go_back_btn": [
            "en": "Go Back",
            "th": "กลับ"
        ]
    ]
    
    func translate(_ key: String, lang: String) -> String {
        let activeLanguage = AppLanguage(rawValue: lang)?.rawValue ?? "en"
        return translations[key]?[activeLanguage] ?? translations[key]?["en"] ?? key
    }
}

extension String {
    func localized(for lang: String) -> String {
        return LanguageManager.shared.translate(self, lang: lang)
    }
}
