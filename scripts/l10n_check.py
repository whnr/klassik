#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Checks the localization of the app (sz-odf9).

The catalogs are Klassik/Localizable.xcstrings and Klassik/InfoPlist.xcstrings. The languages of the app are the
languages that the catalogs hold, and the source language is the catalog's `sourceLanguage`. The check fails when:

- a key lacks a text in a language of the catalogs, or a text is not "translated", or the catalog marks a key stale;
- a plural key lacks a plural form that its language uses, or a text has other format specifiers than its key;
- `CFBundleLocalizations` in project.yml differs from the languages of the catalogs;
- the Swift code draws a literal that the catalog does not hold (Text, Button, L and the other calls below);
- a view truncates text (`lineLimit`, `minimumScaleFactor`, `truncationMode`) without a reason in
  scripts/truncation_allowed.txt.

python3 scripts/l10n_check.py                        runs the check
python3 scripts/l10n_check.py --table --language xx  prints the source texts and the texts of language xx as a
                                                     Markdown table, for the review of that language
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOGS = ("Klassik/Localizable.xcstrings", "Klassik/InfoPlist.xcstrings")
PROJECT = ROOT / "project.yml"
# The plural categories (CLDR) that a language uses, when they are not "one" and "other".
PLURAL_FORMS = {
    **dict.fromkeys(("fr", "es", "it", "pt", "ca"), ("one", "many", "other")),
    **dict.fromkeys(("ru", "uk", "pl", "cs", "lt", "he"), ("one", "few", "many", "other")),
    **dict.fromkeys(("ja", "ko", "zh", "vi", "th", "id", "ms", "tr"), ("other",)),
}
DEFAULT_PLURAL_FORMS = ("one", "other")
ALLOW = ROOT / "scripts" / "truncation_allowed.txt"

# The developer test page and its player stay in the source language: no listener sees them.
EXEMPT_FILES = {
    "Klassik/GaplessTestView.swift",
    "Klassik/GaplessTestPlayer.swift",
    "Klassik/Tokens.swift",
    "Klassik/Layout.swift",
}

# Calls whose first argument is a catalog key. A literal in a nested call is not read: the nested call is its own site.
KEY_CALLS = (
    "Text",
    "Button",
    "Toggle",
    "Picker",
    "Section",
    "LabeledContent",
    "Label",
    "Menu",
    "TextField",
    "SecureField",
    "NavigationLink",
    "InkLabel",
    "SectionHeading",
    "CountedHeading",
    "ContentUnavailableView",
    "Stepper",
    "control",
    "L",
    ".accessibilityLabel",
    ".accessibilityHint",
    ".accessibilityValue",
    ".navigationTitle",
    ".confirmationDialog",
    ".alert",
    ".help",
)
# A named argument that is a catalog key, in any call.
KEY_LABELS = ("title:", "prompt:", "description:", "message:", "label:")
# Modifiers that cut text. Each use needs its line in the allow list, with the reason.
TRUNCATING = re.compile(r"\.(lineLimit|minimumScaleFactor|truncationMode)\(")

SPECIFIER = re.compile(r"%(?:\d+\$)?(?:l|ll|h|hh|z)?[@dDuUxXoOfeEgGcCsSp]|%lld|%lf")
LETTER = re.compile(r"[A-Za-z]")


def specifiers(text: str) -> list[str]:
    """The format specifiers of a text, without position numbers, in order."""
    return [re.sub(r"\d+\$", "", match) for match in SPECIFIER.findall(text.replace("%%", ""))]


def shape(text: str) -> str:
    """A key without its argument types, so that a Swift interpolation matches the catalog key."""
    return SPECIFIER.sub("%@", text.replace("%%", "%"))


# MARK: Catalog


def values(localization: dict) -> dict[str, str]:
    """The texts of one language: "" for a plain text, the plural form for a variation."""
    found: dict[str, str] = {}
    unit = localization.get("stringUnit")
    if unit is not None:
        found["state"] = unit.get("state", "")
        found[""] = unit.get("value", "")
    for form, variation in (localization.get("variations", {}).get("plural", {})).items():
        unit = variation.get("stringUnit", {})
        found["state:" + form] = unit.get("state", "")
        found[form] = unit.get("value", "")
    return found


def plural_forms(language: str) -> tuple[str, ...]:
    return PLURAL_FORMS.get(language.split("-")[0], DEFAULT_PLURAL_FORMS)


def source_language(catalogs: dict[str, dict]) -> str:
    sources = {catalog.get("sourceLanguage") for catalog in catalogs.values()}
    return sources.pop() if len(sources) == 1 else ""


def languages_of(catalogs: dict[str, dict]) -> list[str]:
    """The source language first, then every language that a catalog holds."""
    source = source_language(catalogs)
    found = {source} if source else set()
    for catalog in catalogs.values():
        for entry in catalog.get("strings", {}).values():
            found |= set(entry.get("localizations", {}))
    return sorted(found, key=lambda code: (code != source, code))


def check_project(languages: list[str]) -> list[str]:
    match = re.search(r"CFBundleLocalizations:\s*\[([^\]]*)\]", PROJECT.read_text())
    if match is None:
        return [f"{PROJECT.name}: no CFBundleLocalizations"]
    declared = sorted(code.strip() for code in match.group(1).split(",") if code.strip())
    if declared != sorted(languages):
        return [f"{PROJECT.name}: CFBundleLocalizations {declared} differs from the catalogs {sorted(languages)}"]
    return []


def check_catalog(path: str, catalog: dict, languages: list[str], source: str) -> list[str]:
    problems: list[str] = []
    if not source or catalog.get("sourceLanguage") != source:
        problems.append(f"{path}: its source language differs from the other catalogs")
    for key, entry in catalog.get("strings", {}).items():
        where = f"{path}: {key!r}"
        if entry.get("extractionState") == "stale":
            problems.append(f"{where}: stale; no code uses this key")
        localizations = entry.get("localizations", {})
        plural = any("variations" in localizations.get(language, {}) for language in languages)
        for language in languages:
            localization = localizations.get(language)
            if localization is None:
                # The source text is the key itself.
                if language != source or plural:
                    problems.append(f"{where}: no {language} text")
                continue
            texts = values(localization)
            if plural:
                if "variations" not in localization:
                    problems.append(f"{where}: {language} has no plural forms")
                    continue
                for form in plural_forms(language):
                    if form not in texts:
                        problems.append(f"{where}: {language} lacks the plural form {form}")
            elif "" not in texts:
                problems.append(f"{where}: {language} has no text")
                continue
            for name, text in texts.items():
                if name.startswith("state"):
                    if text != "translated":
                        problems.append(f"{where}: {language} {name or 'text'} is {text!r}, not translated")
                    continue
                if not text.strip():
                    problems.append(f"{where}: {language} {name or 'text'} is empty")
                    continue
                wanted = sorted(specifiers(key))
                has = sorted(specifiers(text))
                # The singular form may name the number in words ("one recording").
                if name == "one" and set(has) <= set(wanted):
                    continue
                if has != wanted:
                    problems.append(f"{where}: {language} {name or 'text'} has the specifiers {has}, the key {wanted}")
    return problems


# MARK: Swift literals


def read_literal(text: str, start: int) -> tuple[str, int]:
    """The string literal that begins at text[start] == '"', as the key it makes, and the index after it."""
    assert text[start] == '"'
    out: list[str] = []
    i = start + 1
    while i < len(text):
        c = text[i]
        if c == '"':
            return "".join(out), i + 1
        if c == "\\":
            n = text[i + 1]
            if n == "(":
                depth, i = 1, i + 2
                while depth:
                    if text[i] == '"':
                        _, i = read_literal(text, i)
                        continue
                    depth += {"(": 1, ")": -1}.get(text[i], 0)
                    i += 1
                out.append("%@")
                continue
            if n == "u":
                end = text.index("}", i)
                out.append(chr(int(text[i + 3 : end], 16)))
                i = end + 1
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    raise ValueError("unterminated string literal")


def skip_string(text: str, start: int) -> int:
    return read_literal(text, start)[1]


def argument(text: str, start: int) -> tuple[str, int]:
    """The text of the call argument list that starts after text[start - 1] == '(', up to its matching ')'."""
    depth, i = 1, start
    while i < len(text):
        c = text[i]
        if c == '"':
            i = skip_string(text, i)
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[start:i], i + 1
        i += 1
    return text[start:], len(text)


def direct_literals(arguments: str, first_only: bool) -> list[str]:
    """The literals of the first argument that no nested call holds, such as both branches of a ternary."""
    found: list[str] = []
    i, depth = 0, 0
    # Parentheses of a call hide their literals. Parentheses that only group do not.
    stack: list[bool] = []
    while i < len(arguments):
        c = arguments[i]
        if c == '"':
            literal, after = read_literal(arguments, i)
            # A literal that a comparison reads is no text to draw.
            if not any(stack) and not arguments[:i].rstrip().endswith(("==", "!=")):
                found.append(literal)
            i = after
            continue
        if c == "(":
            before = arguments[:i].rstrip()
            call = bool(before) and (before[-1].isalnum() or before[-1] in "_.>?!")
            stack.append(call)
            depth += 1
        elif c == ")":
            if stack:
                stack.pop()
            depth -= 1
        elif c == "," and depth == 0 and first_only:
            break
        i += 1
    return found


def swift_keys(text: str) -> list[tuple[int, str]]:
    """(line, key) for each literal that the code draws through a catalog call."""
    found: list[tuple[int, str]] = []
    pattern = re.compile(r"(?<![\w])(" + "|".join(re.escape(call) for call in KEY_CALLS) + r")\(")
    for match in pattern.finditer(text):
        call = match.group(1)
        # `.accessibilityLabel` is a modifier: its dot belongs to the call. A bare name must not follow a dot.
        if not call.startswith(".") and match.start() > 0 and text[match.start() - 1] == ".":
            continue
        arguments, _ = argument(text, match.end())
        if arguments.lstrip().startswith("verbatim:"):
            continue
        line = text.count("\n", 0, match.start()) + 1
        for key in direct_literals(arguments, first_only=True):
            found.append((line, key))
    label = re.compile(r"\b(" + "|".join(re.escape(name) for name in KEY_LABELS) + r")\s*\"")
    for match in label.finditer(text):
        # `title:` of an Item, a CapsuleLabel and the like take a key. A struct field of a plain String does not
        # draw: it appears in a call that is read above, or in an `L(`.
        quote = match.end() - 1
        key, _ = read_literal(text, quote)
        line = text.count("\n", 0, match.start()) + 1
        start = text.rfind("\n", 0, match.start()) + 1
        # A dispatch queue label and a role label are identities. A listener reads a role through `displayLabel`.
        if any(name in text[start : match.start()] for name in ("DispatchQueue(", "Line(", "Entry(", "Roles.")):
            continue
        found.append((line, key))
    return found


def check_swift(catalog_keys: set[str]) -> list[str]:
    shapes = {shape(key) for key in catalog_keys}
    problems: list[str] = []
    for path in sorted((ROOT / "Klassik").rglob("*.swift")):
        relative = path.relative_to(ROOT).as_posix()
        if relative in EXEMPT_FILES:
            continue
        text = path.read_text()
        for line, key in swift_keys(text):
            if not LETTER.search(SPECIFIER.sub("", key)) or shape(key) in shapes:
                continue
            problems.append(f"{relative}:{line}: {key!r} is not in the catalog")
    return problems


# MARK: Truncation


def allowed() -> dict[str, set[str]]:
    """The lines that may truncate, by file. A line of the list is "path: code  # reason"."""
    found: dict[str, set[str]] = {}
    if not ALLOW.exists():
        return found
    for raw in ALLOW.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        entry, _, reason = line.partition("  # ")
        path, _, code = entry.partition(": ")
        if not reason.strip():
            raise SystemExit(f"{ALLOW.name}: the line has no reason: {line}")
        found.setdefault(path.strip(), set()).add(code.strip())
    return found


def check_truncation() -> list[str]:
    listed = allowed()
    problems: list[str] = []
    for path in sorted((ROOT / "Klassik").rglob("*.swift")):
        relative = path.relative_to(ROOT).as_posix()
        if relative in EXEMPT_FILES:
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.strip()
            if code.startswith("//") or not TRUNCATING.search(code):
                continue
            if code not in listed.get(relative, set()):
                problems.append(f"{relative}:{number}: {code} truncates text; wrap it, or list it with a reason")
    return problems


# MARK: Table


def table(catalogs: dict[str, dict], language: str) -> str:
    """The source texts against the texts of `language`."""
    source = source_language(catalogs)
    rows = [f"| {source} | {language} |", "| --- | --- |"]

    def cell(text: str) -> str:
        return text.replace("|", "\\|").replace("\n", " ").replace("\u00a0", "~")

    for catalog in catalogs.values():
        for key, entry in sorted(catalog.get("strings", {}).items()):
            localizations = entry.get("localizations", {})
            other = values(localizations.get(language, {}))
            original = values(localizations.get(source, {}))
            if "" in other:
                rows.append(f"| {cell(original.get('', key))} | {cell(other[''])} |")
            else:
                for form in plural_forms(language):
                    rows.append(f"| {cell(original.get(form, key))} ({form}) | {cell(other.get(form, ''))} ({form}) |")
    return "\n".join(rows)


def load() -> dict[str, dict]:
    return {path: json.loads((ROOT / path).read_text()) for path in CATALOGS if (ROOT / path).exists()}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Checks the localization of the app.")
    parser.add_argument("--table", action="store_true", help="print the texts of one language for review")
    parser.add_argument("--language", help="the language that --table prints (required with --table)")
    args = parser.parse_args(argv)
    catalogs = load()
    languages = languages_of(catalogs)
    if args.table:
        if args.language is None:
            parser.error("--table needs --language, one of: " + ", ".join(languages[1:]))
        if args.language not in languages[1:]:
            parser.error(f"{args.language!r} is not a language of the catalogs: " + ", ".join(languages[1:]))
        print(table(catalogs, args.language))
        return 0
    if args.language:
        parser.error("--language belongs to --table")
    source = source_language(catalogs)
    problems: list[str] = []
    keys: set[str] = set()
    for path, catalog in catalogs.items():
        problems += check_catalog(path, catalog, languages, source)
        keys |= set(catalog.get("strings", {}))
    if not catalogs:
        problems.append("no catalog: " + ", ".join(CATALOGS))
    problems += check_project(languages)
    problems += check_swift(keys)
    problems += check_truncation()
    for problem in problems:
        print(f"::error::{problem}" if "GITHUB_ACTIONS" in os.environ else problem)
    print(f"{len(keys)} keys, {len(languages)} languages, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
