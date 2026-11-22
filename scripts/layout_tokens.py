"""Proves each layout token of Klassik/Layout.swift against the specimen CSS that it cites.

A citation is a doc comment line before the token: `css: <file> <selector> | <property>[ | <literal>]`.
The file is in design/specimen/. The selector names a rule of the file, or a quoted text of the file that holds
inline declarations or a class list. The value resolves through the custom properties of design/tokens.css and the
`:root` rule of specimen.css. A `<literal>` names one number of a value that is not a single sum.

python3 scripts/layout_tokens.py --check
"""

from __future__ import annotations

import ast
import operator
import pathlib
import re
import sys
from dataclasses import dataclass

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPECIMEN = ROOT / "design" / "specimen"
TOKENS_CSS = ROOT / "design" / "tokens.css"
LAYOUT = ROOT / "Klassik" / "Layout.swift"

CITATION = re.compile(
    r"///\s*css:\s*(?P<file>\S+)\s+(?P<selector>.+?)\s*\|\s*(?P<property>[\w-]+)(?:\s*\|\s*(?P<literal>\S+))?\s*$"
)
DECLARATION = re.compile(r"static let (?P<name>\w+)(?::\s*\w+)?\s*=\s*(?P<value>.+)$")
SWIFT_TOKEN = re.compile(r"\b(Space\.(\w+)\.points|Measure\.(\w+)|Radius\.(\w+))")
TYPE_STYLE = re.compile(r"^TypeStyle\.(\w+)$")


@dataclass
class Citation:
    line: int
    file: str
    selector: str
    property: str
    literal: str | None
    name: str
    value: str


def strip_comments(css: str) -> str:
    return re.sub(r"/\*.*?\*/", "", css, flags=re.S)


def style_text(path: pathlib.Path) -> str:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".html":
        text = "\n".join(re.findall(r"<style[^>]*>(.*?)</style>", text, flags=re.S))
    return strip_comments(text)


def rules(css: str) -> list[tuple[list[str], str]]:
    """The top-level rules in source order: each selector of the list, and the declaration text.
    At-rule blocks such as @media are skipped: the tokens name the default state."""
    found: list[tuple[list[str], str]] = []
    index = 0
    while index < len(css):
        brace = css.find("{", index)
        if brace < 0:
            break
        prelude = css[index:brace].strip()
        depth, end = 1, brace + 1
        while end < len(css) and depth:
            depth += {"{": 1, "}": -1}.get(css[end], 0)
            end += 1
        body = css[brace + 1 : end - 1]
        if not prelude.startswith("@"):
            selectors = [" ".join(part.split()) for part in split_top(prelude, ",")]
            found.append((selectors, body))
        index = end
    return found


def split_top(text: str, separator: str) -> list[str]:
    """Splits at separators outside parentheses."""
    parts, depth, current = [], 0, ""
    for char in text:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        if char == separator and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += char
    parts.append(current)
    return [part.strip() for part in parts if part.strip()]


def declarations(body: str) -> list[tuple[str, str]]:
    pairs = []
    for item in split_top(body, ";"):
        if ":" in item:
            name, value = item.split(":", 1)
            pairs.append((name.strip(), " ".join(value.split())))
    return pairs


SIDES = ("top", "right", "bottom", "left")
CORNERS = ("top-left", "top-right", "bottom-right", "bottom-left")


def four(values: list[str]) -> list[str]:
    if len(values) == 1:
        return values * 4
    if len(values) == 2:
        return [values[0], values[1], values[0], values[1]]
    if len(values) == 3:
        return [values[0], values[1], values[2], values[1]]
    return values[:4]


def longhands(name: str, value: str) -> dict[str, str]:
    """A declaration as longhands, so a citation of padding-top finds `padding: a b`."""
    parts = split_top(value, " ")
    if name in ("padding", "margin"):
        return {f"{name}-{side}": part for side, part in zip(SIDES, four(parts))}
    if name == "inset":
        return dict(zip(SIDES, four(parts)))
    if name == "border-radius":
        return {f"border-{corner}-radius": part for corner, part in zip(CORNERS, four(parts))}
    if name == "gap":
        row = parts[0]
        return {"gap": value, "row-gap": row, "column-gap": parts[1] if len(parts) > 1 else row}
    return {name: value}


def declared(text: str, selector: str, prop: str) -> str | None:
    """The value of a property in a rule of the file, after the cascade of that one selector."""
    if selector.startswith('"') and selector.endswith('"'):
        snippet = selector[1:-1]
        if snippet not in text:
            return None
        if prop == "class":
            return snippet
        values: dict[str, str] = {}
        for name, value in declarations(snippet):
            values.update(longhands(name, value))
        return values.get(prop)
    values = {}
    for selectors, body in rules(text):
        if selector in selectors:
            for name, value in declarations(body):
                values.update(longhands(name, value))
    return values.get(prop)


def custom_properties() -> dict[str, str]:
    """The custom properties of the default state: the `:root` rules of tokens.css and specimen.css."""
    values: dict[str, str] = {}
    for path in (TOKENS_CSS, SPECIMEN / "specimen.css"):
        for selectors, body in rules(strip_comments(path.read_text(encoding="utf-8"))):
            if selectors == [":root"]:
                values.update(dict(declarations(body)))
    return values


def resolve(value: str, properties: dict[str, str], depth: int = 0) -> str:
    """Replaces each var() by its value, or by its fallback when the property is unset."""
    if depth > 20:
        raise ValueError(f"var() loop in {value}")
    while True:
        match = re.search(r"var\(\s*(--[\w-]+)\s*(?:,\s*)?", value)
        if not match:
            return value
        depth_count, end = 1, match.end()
        while end < len(value) and depth_count:
            depth_count += {"(": 1, ")": -1}.get(value[end], 0)
            end += 1
        fallback = value[match.end() : end - 1].strip()
        name = match.group(1)
        replacement = properties.get(name, fallback)
        value = value[: match.start()] + resolve(replacement, properties, depth + 1) + value[end:]


OPERATORS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv}


def arithmetic(expression: str) -> float:
    def walk(node: ast.AST) -> float:
        if isinstance(node, ast.Expression):
            return walk(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return float(node.value)
        if isinstance(node, ast.BinOp) and type(node.op) in OPERATORS:
            return OPERATORS[type(node.op)](walk(node.left), walk(node.right))
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
            return -walk(node.operand)
        raise ValueError(f"not a sum: {expression}")

    return walk(ast.parse(expression, mode="eval"))


def css_number(value: str) -> float:
    """A resolved CSS length as points: px, or a calc() of px."""
    text = value.replace("calc(", "(").replace("px", "")
    return arithmetic(text)


def literal_number(literal: str) -> float:
    match = re.fullmatch(r"(-?\d*\.?\d+)(px|vw|em|%)?", literal)
    if not match:
        raise ValueError(f"not a literal: {literal}")
    number = float(match.group(1))
    return number / 100 if match.group(2) in ("vw", "%") else number


def swift_number(expression: str, properties: dict[str, str]) -> float:
    def token(match: re.Match[str]) -> str:
        space, measure, radius = match.group(2), match.group(3), match.group(4)
        name = f"--space-{space}" if space else f"--size-{measure}" if measure else f"--radius-{radius}"
        if name not in properties:
            raise ValueError(f"no token {name}")
        return f"({css_number(properties[name])})"

    return arithmetic(SWIFT_TOKEN.sub(token, expression))


def citations(source: str) -> list[Citation]:
    found, pending = [], None
    for number, line in enumerate(source.splitlines(), 1):
        stripped = line.strip()
        match = CITATION.match(stripped)
        if match:
            pending = (number, match)
            continue
        if stripped.startswith("///") or not stripped:
            continue
        declaration = DECLARATION.search(stripped)
        if pending and declaration:
            line_number, cite = pending
            found.append(
                Citation(
                    line_number,
                    cite["file"],
                    cite["selector"],
                    cite["property"],
                    cite["literal"],
                    declaration["name"],
                    declaration["value"].strip(),
                )
            )
        pending = None
    return found


def undocumented(source: str) -> list[str]:
    """Static values without a citation. A function, such as `edges(side:)`, needs none."""
    names = []
    lines = source.splitlines()
    for index, line in enumerate(lines):
        declaration = DECLARATION.search(line.strip())
        if not declaration:
            continue
        above = index - 1
        while above >= 0 and lines[above].strip().startswith("///") and not CITATION.match(lines[above].strip()):
            above -= 1
        if above < 0 or not CITATION.match(lines[above].strip()):
            names.append(declaration["name"])
    return names


def check(citation: Citation, properties: dict[str, str]) -> str | None:
    """None when the Swift value is the CSS value, else the problem."""
    path = SPECIMEN / citation.file
    if not path.exists():
        return f"no file design/specimen/{citation.file}"
    text = path.read_text(encoding="utf-8") if citation.selector.startswith('"') else style_text(path)
    value = declared(text, citation.selector, citation.property)
    if value is None:
        return f"{citation.file} has no {citation.property} in {citation.selector}"
    style = TYPE_STYLE.match(citation.value)
    if style:
        wanted = style.group(1)
        if citation.property == "class":
            # A class list built in script code sits between quotes.
            classes = value.replace('"', " ").split()
            return None if f"t-{wanted}" in classes else f"{citation.selector} is not t-{wanted}"
        return None if f"--type-{wanted}-" in value else f"{citation.property}: {value} is not type {wanted}"
    try:
        swift = swift_number(citation.value, properties)
    except ValueError as error:
        return f"cannot read the Swift value: {error}"
    if citation.literal:
        if citation.literal not in value:
            return f"{citation.property}: {value} does not hold {citation.literal}"
        css = literal_number(citation.literal)
    else:
        try:
            css = css_number(resolve(value, properties))
        except (ValueError, SyntaxError):
            return f"{citation.property}: {value} is not one sum; name the number as a literal"
    if abs(css - swift) > 0.005:
        return f"{citation.property}: {value} is {css:g}, the Swift value is {swift:g}"
    return None


def main(argv: list[str]) -> int:
    if argv != ["--check"]:
        print(__doc__.strip())
        return 2
    source = LAYOUT.read_text(encoding="utf-8")
    properties = custom_properties()
    failures = 0
    for citation in citations(source):
        problem = check(citation, properties)
        if problem:
            failures += 1
            print(f"Klassik/Layout.swift:{citation.line}: {citation.name}: {problem}")
    for name in undocumented(source):
        failures += 1
        print(f"Klassik/Layout.swift: {name} cites no specimen rule")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
