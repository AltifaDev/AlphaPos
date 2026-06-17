#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def supported_swift_languages(path):
    source = read(path)
    enum_match = re.search(r"enum AppLanguage:[\s\S]*?^}", source, re.M)
    if not enum_match:
        return []
    return re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', enum_match.group(0))


def swift_translation_entries(path):
    source = read(path)
    keys = {}
    for match in re.finditer(r'^\s*"([A-Za-z0-9_]+)"\s*:\s*\[', source, re.M):
        key = match.group(1)
        start = match.end()
        depth = 1
        i = start
        while i < len(source) and depth:
            if source[i] == "[":
                depth += 1
            elif source[i] == "]":
                depth -= 1
            i += 1
        body = source[start:i]
        keys[key] = set(re.findall(r'"([a-z]{2})"\s*:', body))
    return keys


def swift_literal_usage(paths, include_t=True, include_localized=True):
    used = set()
    for base in paths:
        for path in (ROOT / base).rglob("*.swift"):
            source = path.read_text(encoding="utf-8", errors="ignore")
            if include_t:
                used.update(re.findall(r'"([A-Za-z0-9_]+)"\.t\b', source))
            if include_localized:
                used.update(re.findall(r'"([A-Za-z0-9_]+)"\.localized\(for:', source))
    return used


def web_translation_entries(path):
    source = read(path)
    languages = {}
    for match in re.finditer(r"\n\s*(th|en|zh)\s*:\s*\{", source):
        lang = match.group(1)
        start = match.end()
        depth = 1
        i = start
        while i < len(source) and depth:
            if source[i] == "{":
                depth += 1
            elif source[i] == "}":
                depth -= 1
            i += 1
        body = source[start:i]
        keys = {
            quoted or bare
            for quoted, bare in re.findall(
                r'(?:^|\n)\s*(?:"([^"]+)"|([A-Za-z_$][\w$]*))\s*:', body
            )
        }
        languages[lang] = keys
    return languages


def report_swift(name, lang_file, dict_file, roots, include_t=True, include_localized=True):
    languages = supported_swift_languages(lang_file)
    entries = swift_translation_entries(dict_file)
    used = swift_literal_usage(roots, include_t=include_t, include_localized=include_localized)
    missing_keys = sorted(used - set(entries))
    missing_languages = sorted(
        (key, lang)
        for key, langs in entries.items()
        for lang in languages
        if lang not in langs
    )

    print(f"{name}:")
    print(f"  supported languages: {', '.join(languages)}")
    print(f"  dictionary keys: {len(entries)}")
    print(f"  literal keys used: {len(used)}")
    print(f"  missing dictionary keys: {len(missing_keys)}")
    if missing_keys:
        print("   ", ", ".join(missing_keys[:80]))
    print(f"  missing translations for supported languages: {len(missing_languages)}")
    if missing_languages:
        print("   ", ", ".join(f"{key}:{lang}" for key, lang in missing_languages[:80]))
    return not missing_keys and not missing_languages


def report_web():
    languages = web_translation_entries("customer-order-web/js/i18n.js")
    all_keys = set().union(*languages.values())
    missing = sorted(
        (key, lang)
        for lang, keys in languages.items()
        for key in all_keys
        if key not in keys
    )

    print("Customer order web:")
    print(f"  supported languages: {', '.join(sorted(languages))}")
    print(f"  dictionary keys: {len(all_keys)}")
    print(f"  missing translations: {len(missing)}")
    if missing:
        print("   ", ", ".join(f"{key}:{lang}" for key, lang in missing[:80]))
    return not missing


def main():
    ok = True
    ok &= report_swift(
        "AlphaPos main app",
        "AlphaPos/Core/Localization/AppLocalization.swift",
        "AlphaPos/Core/Localization/AppLocalization.swift",
        ["AlphaPos"],
        include_t=True,
        include_localized=False,
    )
    ok &= report_swift(
        "AlphaPos staff app",
        "AlphaPosStaff/AlphaPosStaff/LanguageManager.swift",
        "AlphaPosStaff/AlphaPosStaff/LanguageManager.swift",
        ["AlphaPosStaff"],
        include_t=False,
        include_localized=True,
    )
    ok &= report_web()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
