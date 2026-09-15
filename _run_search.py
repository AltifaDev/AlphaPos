#!/usr/bin/env python3
import os, re, sys

root = "/Users/mac/Applications/AlphaPos"
out = os.path.join(root, "_search_results.txt")
thai_strings = ["ต้องเชื่อมต่อ", "ล็อกอิน"]
lines_out = []

lines_out.append("=" * 80)
lines_out.append("PART 1: Thai string search across ALL files")
lines_out.append("=" * 80)

for thai in thai_strings:
    lines_out.append(f"\n--- Searching for: {thai} ---")
    found = False
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith('.') and d not in ('DerivedData', 'build', 'Pods', '.git')]
        for fn in filenames:
            if fn.startswith('_run_search') or fn == '_search_results.txt':
                continue
            fp = os.path.join(dirpath, fn)
            try:
                with open(fp, 'r', encoding='utf-8', errors='ignore') as f:
                    for i, line in enumerate(f, 1):
                        if thai in line:
                            found = True
                            lines_out.append(f"FILE: {fp}")
                            lines_out.append(f"LINE: {i}")
                            lines_out.append(f"CONTENT: {line.rstrip()}")
                            lines_out.append("")
            except (IsADirectoryError, PermissionError):
                pass
    if not found:
        lines_out.append("(no matches)")

lines_out.append("\n" + "=" * 80)
lines_out.append("PART 2: AppLocalization.swift - keys matching login|internet|connect|offline|network|auth")
lines_out.append("=" * 80)

loc_file = os.path.join(root, "AlphaPos/Core/Localization/AppLocalization.swift")
pattern = re.compile(r'login|internet|connect|offline|network|auth', re.I)

with open(loc_file, 'r', encoding='utf-8') as f:
    file_lines = f.readlines()

for i, line in enumerate(file_lines, 1):
    if pattern.search(line):
        th_match = re.search(r'"th"\s*:\s*"([^"]*)"', line)
        th_val = th_match.group(1) if th_match else None
        lines_out.append(f"FILE: {loc_file}")
        lines_out.append(f"LINE: {i}")
        lines_out.append(f"CONTENT: {line.rstrip()}")
        if th_val is not None:
            lines_out.append(f"TH (th): {th_val}")
        lines_out.append("")

with open(out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines_out))

print('OK', len(lines_out))
