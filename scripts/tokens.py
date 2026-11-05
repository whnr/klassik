#!/usr/bin/env python3
"""Writes the generated design files from the DTCG token files in design/ (ADR 0021).

Usage: scripts/tokens.py [--check]
--check writes nothing and fails when a generated file is not current.
"""

import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "design"
RESOLVER = DESIGN / "klassik.resolver.json"
CSS = DESIGN / "tokens.css"

# Point sizes of the iOS text styles at each Dynamic Type size, from Apple's Human Interface
# Guidelines. A type token scales by the ratio of its text style, as Font.custom(relativeTo:) does.
DYNAMIC_TYPE_SIZES = ["xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
                      "AX1", "AX2", "AX3", "AX4", "AX5"]
DYNAMIC_TYPE = {
    "largeTitle": [31, 32, 33, 34, 36, 38, 40, 44, 48, 52, 56, 60],
    "title": [25, 26, 27, 28, 30, 32, 34, 38, 43, 48, 53, 58],
    "title2": [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56],
    "title3": [17, 18, 19, 20, 22, 24, 26, 31, 37, 43, 49, 55],
    "headline": [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53],
    "body": [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53],
    "callout": [13, 14, 15, 16, 18, 20, 22, 26, 32, 38, 44, 50],
    "subheadline": [12, 13, 14, 15, 17, 19, 21, 25, 30, 36, 42, 49],
    "footnote": [12, 12, 12, 13, 15, 17, 19, 23, 27, 33, 38, 44],
    "caption": [11, 11, 11, 12, 14, 16, 18, 22, 26, 32, 37, 43],
    "caption2": [11, 11, 11, 11, 13, 15, 17, 20, 24, 29, 34, 41],
}
DEFAULT_SIZE = DYNAMIC_TYPE_SIZES.index("large")


def load(ref, base):
    return json.loads((base / ref).read_text())


def merge(into, source):
    for key, value in source.items():
        if isinstance(value, dict) and "$value" not in value and isinstance(into.get(key), dict):
            merge(into[key], value)
        else:
            into[key] = value


def resolve_context(resolver, context):
    """Merges the sources of the resolution order for one theme context."""
    tokens = {}
    for step in resolver["resolutionOrder"]:
        kind, name = step["$ref"].removeprefix("#/").split("/")
        sources = resolver[kind][name]["sources"] if kind == "sets" else resolver[kind][name]["contexts"][context]
        for source in sources:
            merge(tokens, load(source["$ref"], RESOLVER.parent) if "$ref" in source else source)
    return tokens


def flatten(group, path=(), inherited=None, out=None):
    out = {} if out is None else out
    group_type = group.get("$type", inherited)
    for key, value in group.items():
        if key.startswith("$") or not isinstance(value, dict):
            continue
        if "$value" in value:
            out[".".join(path + (key,))] = dict(value, **{"$type": value.get("$type", group_type)})
        else:
            flatten(value, path + (key,), group_type, out)
    return out


def dereference(value, tokens, seen=()) -> Any:
    if isinstance(value, str) and value.startswith("{") and value.endswith("}"):
        name = value[1:-1]
        if name in seen:
            sys.exit(f"tokens.py: alias loop at {name}")
        return dereference(tokens[name]["$value"], tokens, seen + (name,))
    if isinstance(value, dict):
        return {k: dereference(v, tokens, seen) for k, v in value.items()}
    if isinstance(value, list):
        return [dereference(v, tokens, seen) for v in value]
    return value


def css_name(path):
    return "--" + path.replace(".", "-")


def number(value):
    return f"{value:g}"


def css_colour(value):
    r, g, b = (round(c * 255) for c in value["components"])
    alpha = value.get("alpha", 1)
    return f"rgb({r} {g} {b} / {number(alpha)})" if alpha != 1 else value["hex"].lower()


def css_value(token_type, value):
    if token_type == "color":
        return css_colour(value)
    if token_type in ("dimension", "duration"):
        return f"{number(value['value'])}{value['unit']}"
    if token_type == "cubicBezier":
        return "cubic-bezier(" + ", ".join(number(v) for v in value) + ")"
    if token_type == "fontFamily":
        names = value if isinstance(value, list) else [value]
        return ", ".join(n if n.startswith("-") or n in ("system-ui", "sans-serif", "serif") else f'"{n}"' for n in names)
    if token_type == "fontWeight":
        return str(value)
    if token_type == "number":
        return number(value)
    sys.exit(f"tokens.py: no CSS for type {token_type}")


def declarations(tokens, only_colour):
    lines = []
    for path, token in tokens.items():
        token_type, value = token["$type"], dereference(token["$value"], tokens)
        if (token_type == "color") != only_colour:
            continue
        name = css_name(path)
        if token_type == "typography":
            lines += [
                f"  {name}-family: {css_value('fontFamily', value['fontFamily'])};",
                f"  {name}-size: {number(value['fontSize']['value'])}px;",
                f"  {name}-weight: {value['fontWeight']};",
                f"  {name}-line-height: {number(value['lineHeight'])};",
                f"  {name}-letter-spacing: {number(value['letterSpacing']['value'])}px;",
            ]
        elif token_type == "transition":
            lines += [
                f"  {name}-duration: {css_value('duration', value['duration'])};",
                f"  {name}-delay: {css_value('duration', value['delay'])};",
                f"  {name}-easing: {css_value('cubicBezier', value['timingFunction'])};",
            ]
        else:
            lines.append(f"  {name}: {css_value(token_type, value)};")
    return lines


def dynamic_type_rules(tokens):
    rules = []
    for index, size in enumerate(DYNAMIC_TYPE_SIZES):
        lines = []
        for path, token in tokens.items():
            if token["$type"] != "typography":
                continue
            style = token["$extensions"]["de.whnr.klassik"]["textStyle"]
            points = dereference(token["$value"], tokens)["fontSize"]["value"]
            scaled = points * DYNAMIC_TYPE[style][index] / DYNAMIC_TYPE[style][DEFAULT_SIZE]
            lines.append(f"  {css_name(path)}-size: {round(scaled, 2):g}px;")
        rules.append(f'[data-type-size="{size}"] {{\n' + "\n".join(lines) + "\n}")
    return rules


def css(resolver):
    contexts = {name: flatten(resolve_context(resolver, name)) for name in resolver["modifiers"]["theme"]["contexts"]}
    light, dark = contexts["light"], contexts["dark"]

    def block(selector, scheme, tokens):
        return f"{selector} {{\n  color-scheme: {scheme};\n" + "\n".join(declarations(tokens, True)) + "\n}"

    parts = [
        "/* Generated by scripts/tokens.py from design/*.tokens.json. Do not edit. */",
        "/* Themes apply to any element, so one page can show light and dark side by side. */",
        ":root {\n" + "\n".join(declarations(light, False)) + "\n}",
        block(':root,\n[data-theme="light"]', "light", light),
        block('[data-theme="light"][data-contrast="high"]', "light", contexts["lightHighContrast"]),
        block('[data-theme="dark"]', "dark", dark),
        block('[data-theme="dark"][data-contrast="high"]', "dark", contexts["darkHighContrast"]),
        "@media (prefers-color-scheme: dark) {\n"
        + "\n".join("  " + line for line in block(":root:not([data-theme])", "dark", dark).splitlines())
        + "\n}",
        *dynamic_type_rules(light),
    ]
    return "\n\n".join(parts) + "\n"


def main():
    check = "--check" in sys.argv[1:]
    resolver = json.loads(RESOLVER.read_text())
    outputs = {CSS: css(resolver)}
    stale = [path for path, text in outputs.items() if not path.exists() or path.read_text() != text]
    if check:
        for path in stale:
            print(f"tokens.py: {path.relative_to(ROOT)} is not current. Run scripts/tokens.py.", file=sys.stderr)
        sys.exit(1 if stale else 0)
    for path in stale:
        path.write_text(outputs[path])
        print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
