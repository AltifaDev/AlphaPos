#!/usr/bin/env python3
"""Exercise production Promotion logic without SwiftData macro tooling.

Only persistence annotations are removed in a temporary copy. This verifies
business rules, not the iOS UI or SwiftData schema migration (requires Xcode).
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'AlphaPos/Models/Promotion.swift').read_text()
source = source.replace('import SwiftData\n', '').replace('@Model\n', '')
source = source.replace('@Attribute(.unique) ', '')
source = '\n'.join(line for line in source.splitlines() if '@Relationship(' not in line)
tests = r'''
final class PromotionBundleItem {}
let normal = Promotion(title: "Customer", discountType: "percentage", discountValue: 10)
precondition(normal.isPublicPromotion && normal.allowsAutomaticApplication)
precondition(normal.discountAmount(for: 200) == 20)
let staff = Promotion(title: "Staff", discountType: "percentage", discountValue: 25)
staff.audience = "staff"
precondition(!staff.isPublicPromotion && staff.isStaffDiscount && !staff.allowsAutomaticApplication)
precondition(staff.discountAmount(for: 200) == 50)
staff.discountValue = 150
precondition(staff.discountAmount(for: 200) == 200)
staff.discountType = "fixed"; staff.discountValue = 50
precondition(staff.discountAmount(for: 200) == 50)
staff.discountValue = 300
precondition(staff.discountAmount(for: 200) == 200)
staff.minimumSpend = 250
precondition(staff.discountAmount(for: 200) == 0)
staff.minimumSpend = 0; staff.isActive = false
precondition(staff.discountAmount(for: 200) == 0)
staff.isActive = true; staff.endsAt = Date().addingTimeInterval(-1)
precondition(staff.discountAmount(for: 200) == 0)
staff.endsAt = nil; staff.maxRedemptions = 1
staff.incrementRedemption()
precondition(staff.discountAmount(for: 200) == 0)
let pos = Promotion(title: "POS", discountType: "fixed", discountValue: 30)
pos.audience = "pos"
precondition(!pos.isPublicPromotion && !pos.isStaffDiscount && pos.allowsAutomaticApplication)
precondition(pos.discountAmount(for: 100) == 30)
pos.isDeleted = true
precondition(pos.discountAmount(for: 100) == 0)
let automaticCandidates = [normal, staff].filter { $0.allowsAutomaticApplication }
precondition(automaticCandidates.count == 1 && automaticCandidates[0].id == normal.id)
print("PASS: public compatibility, private scopes, manual-only staff, percentage/fixed, caps, minimum spend, inactive/expired/deleted and usage limits")
'''
with tempfile.TemporaryDirectory(prefix='alphapos-promotion-tests-') as temp:
    path = Path(temp) / 'main.swift'
    path.write_text(source + '\n' + tests)
    binary = Path(temp) / 'tests'
    subprocess.run(['swiftc', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
