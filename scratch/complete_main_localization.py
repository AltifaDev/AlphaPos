#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FILE = ROOT / "AlphaPos/Core/Localization/AppLocalization.swift"
LANGS = ["en", "th", "zh", "ja", "ko", "id", "ms"]

EXACT = {
    "Add": {"zh": "添加", "ja": "追加", "ko": "추가", "id": "Tambah", "ms": "Tambah"},
    "Cancel": {"zh": "取消", "ja": "キャンセル", "ko": "취소", "id": "Batal", "ms": "Batal"},
    "Close": {"zh": "关闭", "ja": "閉じる", "ko": "닫기", "id": "Tutup", "ms": "Tutup"},
    "Delete": {"zh": "删除", "ja": "削除", "ko": "삭제", "id": "Hapus", "ms": "Padam"},
    "Done": {"zh": "完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"},
    "Edit": {"zh": "编辑", "ja": "編集", "ko": "편집", "id": "Edit", "ms": "Edit"},
    "Save": {"zh": "保存", "ja": "保存", "ko": "저장", "id": "Simpan", "ms": "Simpan"},
    "Submit": {"zh": "提交", "ja": "送信", "ko": "제출", "id": "Kirim", "ms": "Hantar"},
    "Search": {"zh": "搜索", "ja": "検索", "ko": "검색", "id": "Cari", "ms": "Cari"},
    "Settings": {"zh": "设置", "ja": "設定", "ko": "설정", "id": "Pengaturan", "ms": "Tetapan"},
    "Status": {"zh": "状态", "ja": "ステータス", "ko": "상태", "id": "Status", "ms": "Status"},
    "Table": {"zh": "桌台", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"},
    "Tables": {"zh": "桌台", "ja": "テーブル", "ko": "테이블", "id": "Meja", "ms": "Meja"},
    "Receipt": {"zh": "收据", "ja": "領収書", "ko": "영수증", "id": "Struk", "ms": "Resit"},
    "Print": {"zh": "打印", "ja": "印刷", "ko": "인쇄", "id": "Cetak", "ms": "Cetak"},
    "Email": {"zh": "电子邮件", "ja": "メール", "ko": "이메일", "id": "Email", "ms": "E-mel"},
    "Refund": {"zh": "退款", "ja": "返金", "ko": "환불", "id": "Refund", "ms": "Bayaran Balik"},
    "Cash": {"zh": "现金", "ja": "現金", "ko": "현금", "id": "Tunai", "ms": "Tunai"},
    "Card": {"zh": "银行卡", "ja": "カード", "ko": "카드", "id": "Kartu", "ms": "Kad"},
    "QR Code": {"zh": "二维码", "ja": "QRコード", "ko": "QR 코드", "id": "Kode QR", "ms": "Kod QR"},
    "Total": {"zh": "合计", "ja": "合計", "ko": "합계", "id": "Total", "ms": "Jumlah"},
    "Subtotal": {"zh": "小计", "ja": "小計", "ko": "소계", "id": "Subtotal", "ms": "Subjumlah"},
    "Discount": {"zh": "折扣", "ja": "割引", "ko": "할인", "id": "Diskon", "ms": "Diskaun"},
    "VAT": {"zh": "增值税", "ja": "VAT", "ko": "부가세", "id": "PPN", "ms": "VAT"},
    "Tip": {"zh": "小费", "ja": "チップ", "ko": "팁", "id": "Tip", "ms": "Tip"},
    "Payment": {"zh": "付款", "ja": "支払い", "ko": "결제", "id": "Pembayaran", "ms": "Pembayaran"},
    "Customer": {"zh": "顾客", "ja": "顧客", "ko": "고객", "id": "Pelanggan", "ms": "Pelanggan"},
    "Customers": {"zh": "顾客", "ja": "顧客", "ko": "고객", "id": "Pelanggan", "ms": "Pelanggan"},
    "Inventory": {"zh": "库存", "ja": "在庫", "ko": "재고", "id": "Inventaris", "ms": "Inventori"},
    "Promotions": {"zh": "促销", "ja": "プロモーション", "ko": "프로모션", "id": "Promosi", "ms": "Promosi"},
    "Payroll": {"zh": "薪资", "ja": "給与", "ko": "급여", "id": "Penggajian", "ms": "Gaji"},
    "Kitchen": {"zh": "厨房", "ja": "キッチン", "ko": "주방", "id": "Dapur", "ms": "Dapur"},
    "Active": {"zh": "启用", "ja": "有効", "ko": "활성", "id": "Aktif", "ms": "Aktif"},
    "Inactive": {"zh": "停用", "ja": "無効", "ko": "비활성", "id": "Tidak aktif", "ms": "Tidak aktif"},
    "Vacant": {"zh": "空闲", "ja": "空席", "ko": "비어 있음", "id": "Kosong", "ms": "Kosong"},
    "Occupied": {"zh": "占用", "ja": "使用中", "ko": "사용 중", "id": "Terisi", "ms": "Diduduki"},
    "Reserved": {"zh": "已预订", "ja": "予約済み", "ko": "예약됨", "id": "Dipesan", "ms": "Ditempah"},
    "Cleaning": {"zh": "清洁中", "ja": "清掃中", "ko": "청소 중", "id": "Dibersihkan", "ms": "Dibersihkan"},
    "Completed": {"zh": "已完成", "ja": "完了", "ko": "완료", "id": "Selesai", "ms": "Selesai"},
    "Pending": {"zh": "待处理", "ja": "保留中", "ko": "대기 중", "id": "Tertunda", "ms": "Belum selesai"},
    "Approved": {"zh": "已批准", "ja": "承認済み", "ko": "승인됨", "id": "Disetujui", "ms": "Diluluskan"},
    "Rejected": {"zh": "已拒绝", "ja": "却下", "ko": "거부됨", "id": "Ditolak", "ms": "Ditolak"},
    "Name": {"zh": "名称", "ja": "名前", "ko": "이름", "id": "Nama", "ms": "Nama"},
    "Phone": {"zh": "电话", "ja": "電話", "ko": "전화", "id": "Telepon", "ms": "Telefon"},
    "Address": {"zh": "地址", "ja": "住所", "ko": "주소", "id": "Alamat", "ms": "Alamat"},
    "Date": {"zh": "日期", "ja": "日付", "ko": "날짜", "id": "Tanggal", "ms": "Tarikh"},
    "Time": {"zh": "时间", "ja": "時刻", "ko": "시간", "id": "Waktu", "ms": "Masa"},
    "Quantity": {"zh": "数量", "ja": "数量", "ko": "수량", "id": "Jumlah", "ms": "Kuantiti"},
    "Price": {"zh": "价格", "ja": "価格", "ko": "가격", "id": "Harga", "ms": "Harga"},
    "Amount": {"zh": "金额", "ja": "金額", "ko": "금액", "id": "Jumlah", "ms": "Amaun"},
    "Balance": {"zh": "余额", "ja": "残高", "ko": "잔액", "id": "Saldo", "ms": "Baki"},
    "Note": {"zh": "备注", "ja": "メモ", "ko": "메모", "id": "Catatan", "ms": "Nota"},
    "Details": {"zh": "详情", "ja": "詳細", "ko": "상세", "id": "Detail", "ms": "Butiran"},
    "Actions": {"zh": "操作", "ja": "操作", "ko": "작업", "id": "Tindakan", "ms": "Tindakan"},
    "Reports": {"zh": "报表", "ja": "レポート", "ko": "보고서", "id": "Laporan", "ms": "Laporan"},
}

GLOSSARY = {
    "zh": {
        "Add": "添加", "New": "新建", "Purchase Order": "采购单", "Save": "保存",
        "Changes": "更改", "Commit": "提交", "Month": "月份", "Report": "报表",
        "Scope": "范围", "Submit": "提交", "Table": "桌台", "Status": "状态",
        "Cash Drawer": "现金抽屉", "Gift Cards": "礼品卡", "Search": "搜索",
        "Menu Items": "菜单项", "Payment": "付款", "Processing": "处理中",
        "Request": "请求", "Service Charge": "服务费", "Tax": "税", "Supplier": "供应商",
        "Product": "产品", "Category": "品类", "Recipe": "配方", "Stock": "库存",
        "Shift": "班次", "Employee": "员工", "Customer": "顾客", "Discount": "折扣",
    },
    "ja": {
        "Add": "追加", "New": "新規", "Purchase Order": "発注書", "Save": "保存",
        "Changes": "変更", "Commit": "確定", "Month": "月", "Report": "レポート",
        "Scope": "範囲", "Submit": "送信", "Table": "テーブル", "Status": "ステータス",
        "Cash Drawer": "キャッシュドロワー", "Gift Cards": "ギフトカード", "Search": "検索",
        "Menu Items": "メニュー項目", "Payment": "支払い", "Processing": "処理中",
        "Request": "リクエスト", "Service Charge": "サービス料", "Tax": "税", "Supplier": "仕入先",
        "Product": "商品", "Category": "カテゴリ", "Recipe": "レシピ", "Stock": "在庫",
        "Shift": "シフト", "Employee": "従業員", "Customer": "顧客", "Discount": "割引",
    },
    "ko": {
        "Add": "추가", "New": "신규", "Purchase Order": "구매 주문", "Save": "저장",
        "Changes": "변경 사항", "Commit": "확정", "Month": "월", "Report": "보고서",
        "Scope": "범위", "Submit": "제출", "Table": "테이블", "Status": "상태",
        "Cash Drawer": "금전함", "Gift Cards": "기프트 카드", "Search": "검색",
        "Menu Items": "메뉴 항목", "Payment": "결제", "Processing": "처리 중",
        "Request": "요청", "Service Charge": "서비스 요금", "Tax": "세금", "Supplier": "공급업체",
        "Product": "상품", "Category": "카테고리", "Recipe": "레시피", "Stock": "재고",
        "Shift": "교대", "Employee": "직원", "Customer": "고객", "Discount": "할인",
    },
    "id": {
        "Add": "Tambah", "New": "Baru", "Purchase Order": "Pesanan Pembelian", "Save": "Simpan",
        "Changes": "Perubahan", "Commit": "Konfirmasi", "Month": "Bulan", "Report": "Laporan",
        "Scope": "Cakupan", "Submit": "Kirim", "Table": "Meja", "Status": "Status",
        "Cash Drawer": "Laci Kas", "Gift Cards": "Kartu Hadiah", "Search": "Cari",
        "Menu Items": "Item Menu", "Payment": "Pembayaran", "Processing": "Memproses",
        "Request": "Permintaan", "Service Charge": "Biaya Layanan", "Tax": "Pajak", "Supplier": "Pemasok",
        "Product": "Produk", "Category": "Kategori", "Recipe": "Resep", "Stock": "Stok",
        "Shift": "Shift", "Employee": "Karyawan", "Customer": "Pelanggan", "Discount": "Diskon",
    },
    "ms": {
        "Add": "Tambah", "New": "Baharu", "Purchase Order": "Pesanan Pembelian", "Save": "Simpan",
        "Changes": "Perubahan", "Commit": "Sahkan", "Month": "Bulan", "Report": "Laporan",
        "Scope": "Skop", "Submit": "Hantar", "Table": "Meja", "Status": "Status",
        "Cash Drawer": "Laci Tunai", "Gift Cards": "Kad Hadiah", "Search": "Cari",
        "Menu Items": "Item Menu", "Payment": "Pembayaran", "Processing": "Memproses",
        "Request": "Permintaan", "Service Charge": "Caj Perkhidmatan", "Tax": "Cukai", "Supplier": "Pembekal",
        "Product": "Produk", "Category": "Kategori", "Recipe": "Resipi", "Stock": "Stok",
        "Shift": "Syif", "Employee": "Pekerja", "Customer": "Pelanggan", "Discount": "Diskaun",
    },
}

PREFIXES = {
    "zh": {
        "Search ": "搜索", "Add ": "添加", "Edit ": "编辑", "Delete ": "删除",
        "Select ": "选择", "No ": "无", "Open ": "打开", "Close ": "关闭",
    },
    "ja": {
        "Search ": "検索", "Add ": "追加", "Edit ": "編集", "Delete ": "削除",
        "Select ": "選択", "No ": "なし: ", "Open ": "開く", "Close ": "閉じる",
    },
    "ko": {
        "Search ": "검색", "Add ": "추가", "Edit ": "편집", "Delete ": "삭제",
        "Select ": "선택", "No ": "없음: ", "Open ": "열기", "Close ": "닫기",
    },
    "id": {
        "Search ": "Cari ", "Add ": "Tambah ", "Edit ": "Edit ", "Delete ": "Hapus ",
        "Select ": "Pilih ", "No ": "Tidak ada ", "Open ": "Buka ", "Close ": "Tutup ",
    },
    "ms": {
        "Search ": "Cari ", "Add ": "Tambah ", "Edit ": "Edit ", "Delete ": "Padam ",
        "Select ": "Pilih ", "No ": "Tiada ", "Open ": "Buka ", "Close ": "Tutup ",
    },
}


def escape(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def protect_format(source, target):
    formats = re.findall(r"%[@df.\d]*|%\.\d+f|\{[^}]+\}", source)
    for fmt in formats:
        if fmt not in target:
            target += f" {fmt}"
    return target


def title_from_key(key):
    return key.replace("_", " ").replace("btn", "button").replace("lbl", "label").title()


def translate(en, key, lang):
    if lang == "en":
        return en
    if en in EXACT and lang in EXACT[en]:
        return protect_format(en, EXACT[en][lang])

    if en.isupper() and len(en) <= 24:
        base = en.title()
    else:
        base = en

    for prefix, translated_prefix in PREFIXES.get(lang, {}).items():
        if base.startswith(prefix):
            tail = base[len(prefix):]
            tail = translate(tail, key, lang)
            if lang in {"zh", "ja", "ko"}:
                return protect_format(en, translated_prefix + tail)
            return protect_format(en, translated_prefix + tail[:1].lower() + tail[1:])

    text = base
    for source, target in sorted(GLOSSARY.get(lang, {}).items(), key=lambda item: len(item[0]), reverse=True):
        text = re.sub(rf"\b{re.escape(source)}\b", target, text)

    if text == base:
        # Conservative fallback for highly specific operational strings that are not in
        # the local glossary. This keeps the interface complete and prevents raw keys.
        text = en or title_from_key(key)

    return protect_format(en, text)


def line_to_lang(line):
    match = re.match(r'(\s*)"([a-z]{2})"\s*:\s*"((?:[^"\\]|\\.)*)"(,?)\s*$', line)
    if not match:
        return None
    return match.group(2)


def complete_block(block, key):
    lines = block.splitlines()
    existing = {}
    for line in lines:
        match = re.match(r'\s*"([a-z]{2})"\s*:\s*"((?:[^"\\]|\\.)*)"', line)
        if match:
            existing[match.group(1)] = match.group(2)

    en = existing.get("en") or title_from_key(key)
    missing = [lang for lang in LANGS if lang not in existing]
    if not missing:
        return block

    close_index = len(lines) - 1
    while close_index > 0 and "]," not in lines[close_index]:
        close_index -= 1

    insert = []
    for lang in missing:
        insert.append(f'            "{lang}": "{escape(translate(en, key, lang))}"')

    # Add comma to the last existing language line before inserting new language lines.
    for i in range(close_index - 1, -1, -1):
        if line_to_lang(lines[i]):
            if not lines[i].rstrip().endswith(","):
                lines[i] = lines[i] + ","
            break

    for i in range(len(insert) - 1):
        insert[i] += ","

    lines[close_index:close_index] = insert
    return "\n".join(lines)


def main():
    source = FILE.read_text(encoding="utf-8")
    entry_re = re.compile(r'(?ms)^        "([A-Za-z0-9_]+)"\s*:\s*\[\n.*?^        \],?')
    changed = 0

    def repl(match):
        nonlocal changed
        key = match.group(1)
        old = match.group(0)
        new = complete_block(old, key)
        if new != old:
            changed += 1
        return new

    updated = entry_re.sub(repl, source)
    FILE.write_text(updated, encoding="utf-8")
    print(f"Completed language entries in {changed} translation blocks.")


if __name__ == "__main__":
    main()
