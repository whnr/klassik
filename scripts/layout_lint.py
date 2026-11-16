"""Refuses a literal layout number in the app's Swift code (sz-rs30.1.105.70).

Layout values come from Klassik/Layout.swift, which cites the specimen CSS, and from the generated
Klassik/Tokens.swift. A view that types its own number drifts from the specimen. An exception goes into
scripts/layout_literals.txt with the reason.

python3 scripts/layout_lint.py [files...]
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ALLOW = ROOT / "scripts" / "layout_literals.txt"
# The token files are the one place for layout numbers.
EXEMPT = {"Klassik/Tokens.swift", "Klassik/Layout.swift"}

# A call whose whole argument list is layout.
CALLS = (
    ".padding(",
    ".frame(",
    ".offset(",
    ".contentMargins(",
    ".listRowInsets(",
    ".listSectionSpacing(",
    ".lineSpacing(",
    ".kerning(",
    ".tracking(",
    ".safeAreaPadding(",
    "EdgeInsets(",
    ".system(size:",
)
# A labelled argument that is layout, in any call.
LABELS = ("spacing:", "cornerRadius:", "minLength:", "horizontalSpacing:", "verticalSpacing:")
# A size declared in a view: a scaled metric, or a static size.
DECLARATIONS = re.compile(r"(@ScaledMetric\b[^=\n]*|static let \w+: CGFloat)\s*=\s*(?P<value>[^\n]+)")
NUMBER = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?|\.\d+)(?![\w.])")
STRING = re.compile(r'"(?:\\.|[^"\\])*"')
COMMENT = re.compile(r"//.*")


def strip(line: str) -> str:
    """Removes string literals and comments, which hold numbers that are not layout."""
    return COMMENT.sub("", STRING.sub('""', line))


def argument_end(text: str, start: int, stop_at_comma: bool) -> int:
    depth = 0
    for index in range(start, len(text)):
        char = text[index]
        if char in "([{":
            depth += 1
        elif char in ")]}":
            if depth == 0:
                return index
            depth -= 1
        elif char == "," and depth == 0 and stop_at_comma:
            return index
    return len(text)


def numbers(fragment: str) -> list[str]:
    return [value for value in NUMBER.findall(fragment) if float(value) != 0]


def findings(source: str) -> list[tuple[int, str, str]]:
    """Each literal layout number: line number, the trimmed source line, the number."""
    originals = source.splitlines()
    lines = [strip(line) for line in originals]
    text = "\n".join(lines)
    starts = [0]
    for line in lines:
        starts.append(starts[-1] + len(line) + 1)

    def line_of(offset: int) -> int:
        low, high = 0, len(starts) - 1
        while low < high:
            middle = (low + high + 1) // 2
            if starts[middle] <= offset:
                low = middle
            else:
                high = middle - 1
        return low

    spans: list[tuple[int, int]] = []
    for call in CALLS:
        for match in re.finditer(re.escape(call), text):
            begin = match.end()
            spans.append((begin, argument_end(text, begin, stop_at_comma=False)))
    for label in LABELS:
        for match in re.finditer(r"\b" + re.escape(label), text):
            begin = match.end()
            spans.append((begin, argument_end(text, begin, stop_at_comma=True)))
    for match in DECLARATIONS.finditer(text):
        spans.append((match.start("value"), match.end("value")))

    found: dict[tuple[int, str], None] = {}
    for begin, end in spans:
        for number in NUMBER.finditer(text, begin, end):
            if float(number.group()) == 0:
                continue
            line = line_of(number.start())
            found[(line, number.group())] = None
    return [(line + 1, originals[line].strip(), number) for line, number in sorted(found)]


def allowed() -> set[tuple[str, str]]:
    """The exceptions: `<path> | <code of the line, trimmed> | <reason>`. A line without a reason is an error."""
    entries: set[tuple[str, str]] = set()
    for number, raw in enumerate(ALLOW.read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip() or raw.startswith("#"):
            continue
        parts = [part.strip() for part in raw.split(" | ")]
        if len(parts) != 3 or not all(parts):
            raise SystemExit(f"{ALLOW.name}:{number}: write <path> | <code> | <reason>")
        entries.add((parts[0], parts[1]))
    return entries


def swift_files() -> list[pathlib.Path]:
    return sorted((ROOT / "Klassik").rglob("*.swift"))


def main(argv: list[str]) -> int:
    paths = [pathlib.Path(arg).resolve() for arg in argv] or swift_files()
    exceptions = allowed()
    used: set[tuple[str, str]] = set()
    failures = 0
    for path in paths:
        name = path.relative_to(ROOT).as_posix()
        if name in EXEMPT:
            continue
        for line, code, number in findings(path.read_text(encoding="utf-8")):
            if (name, code) in exceptions:
                used.add((name, code))
                continue
            failures += 1
            print(f"{name}:{line}: literal layout number {number}; use a token of Klassik/Layout.swift")
    if not argv:
        for name, code in sorted(exceptions - used):
            failures += 1
            print(f"{ALLOW.name}: unused exception {name} | {code}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
