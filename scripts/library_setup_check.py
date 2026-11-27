#!/usr/bin/env python3
"""Checks the Library setup format: the JSON Schema is valid, the example follows it, and the schema names the same
enum values as the Swift code. Run: python3 scripts/library_setup_check.py [example.json]
(needs the jsonschema package). A path replaces the example, so that CI can prove that a bad one fails."""

import json
import pathlib
import re
import sys

import jsonschema

ROOT = pathlib.Path(__file__).resolve().parent.parent
FORMAT = ROOT / "docs" / "library-setup"
SWIFT = ROOT / "Klassik" / "LibraryRows.swift"
RECENT = ROOT / "Klassik" / "RecentSearches.swift"


def swift_cases(source, name):
    """The case names of `enum <name>: ...` whose cases sit on its first line."""
    match = re.search(rf"enum {name}\b[^{{]*{{\s*case ([A-Za-z, ]+)\n", source)
    if not match:
        raise SystemExit(f"enum {name} not found")
    return [case.strip() for case in match.group(1).split(",")]


def main(example):
    schema = json.loads((FORMAT / "schema.json").read_text())
    jsonschema.Draft202012Validator.check_schema(schema)
    validator = jsonschema.Draft202012Validator(schema)
    problems = [f"{example.name}: {e.message}" for e in validator.iter_errors(json.loads(example.read_text()))]

    rows = schema["$defs"]["row"]["properties"]
    code = SWIFT.read_text()
    expected = {
        "kind": (rows["kind"]["enum"], swift_cases(code, "LibraryRowKind")),
        "source": (rows["source"]["enum"], swift_cases(code, "LibrarySource")),
        "sort": (rows["sort"]["enum"], swift_cases(code, "LibrarySort")),
        "form": (rows["form"]["enum"], swift_cases(code, "LibraryForm")),
        "term kind": (schema["$defs"]["term"]["properties"]["kind"]["enum"], swift_cases(RECENT.read_text(), "Kind")),
    }
    for field, (in_schema, in_swift) in expected.items():
        if sorted(in_schema) != sorted(in_swift):
            problems.append(f"{field}: schema {in_schema} differs from Swift {in_swift}")
    version = re.search(r"static let version = (\d+)", code)
    if not version or schema["properties"]["version"]["const"] != int(version.group(1)):
        problems.append("version: schema differs from LibrarySetup.version")

    for problem in problems:
        print(f"error: {problem}")
    if problems:
        sys.exit(1)
    print("Library setup format: ok")


main(pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else FORMAT / "example.json")
