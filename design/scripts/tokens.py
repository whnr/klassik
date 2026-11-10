#!/usr/bin/env python3
"""Writes the generated design files from the DTCG token files in design/ (ADR 0021).

It writes the CSS for the specimen, and the Swift file and the colour sets for the app.

Usage: design/scripts/tokens.py [--check]
--check writes nothing and fails when a generated file is not current.
"""

import json
import shutil
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / "design"
RESOLVER = DESIGN / "klassik.resolver.json"
CSS = DESIGN / "tokens.css"
SWIFT = ROOT / "Klassik" / "Tokens.swift"
# The script owns this folder: it removes a colour set that no token names.
COLOUR_SETS = ROOT / "Klassik" / "Assets.xcassets" / "Colors"
# The colour set that the build setting ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME names.
GLOBAL_ACCENT = "AccentColor"

# Point sizes of the iOS text styles at each Dynamic Type size, from Apple's Human Interface
# Guidelines. A type token scales by the ratio of its text style, as Font.custom(relativeTo:) does.
DYNAMIC_TYPE_SIZES = [
    "xSmall",
    "small",
    "medium",
    "large",
    "xLarge",
    "xxLarge",
    "xxxLarge",
    "AX1",
    "AX2",
    "AX3",
    "AX4",
    "AX5",
]
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


def resolve_context(resolver, theme, accent=None):
    """Merges the sources of the resolution order for one theme and one accent family."""
    chosen = {"theme": theme, "accent": accent or resolver["modifiers"]["accent"]["default"]}
    tokens = {}
    for step in resolver["resolutionOrder"]:
        kind, name = step["$ref"].removeprefix("#/").split("/")
        sources = resolver[kind][name]["sources"] if kind == "sets" else resolver[kind][name]["contexts"][chosen[name]]
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
        return ", ".join(
            n if n.startswith("-") or n in ("system-ui", "sans-serif", "serif") else f'"{n}"' for n in names
        )
    if token_type == "fontWeight":
        return str(value)
    if token_type == "number":
        return number(value)
    sys.exit(f"tokens.py: no CSS for type {token_type}")


def declarations(tokens, only_colour):
    lines = []
    for path, token in tokens.items():
        # The palette holds the source values of an accent family; pages read them through the color tokens.
        if path.startswith("palette."):
            continue
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


def accent_selector(selector, accent):
    """The selector for a family other than the default.

    The family attribute sits on the page root or on an ancestor of a theme.
    """
    if accent is None:
        return selector
    attr = f'[data-accent="{accent}"]'
    parts = []
    for part in selector.split(",\n"):
        if part.startswith(":root"):
            parts.append(":root" + attr + part.removeprefix(":root"))
        else:
            parts += [attr + part, f"{attr} {part}"]
    return ",\n".join(parts)


def colour_blocks(resolver, accent):
    contexts = {
        name: flatten(resolve_context(resolver, name, accent)) for name in resolver["modifiers"]["theme"]["contexts"]
    }

    def block(selector, scheme, tokens):
        return (
            f"{accent_selector(selector, accent)} {{\n  color-scheme: {scheme};\n"
            + "\n".join(declarations(tokens, True))
            + "\n}"
        )

    return [
        block(':root,\n[data-theme="light"]', "light", contexts["light"]),
        block('[data-theme="light"][data-contrast="high"]', "light", contexts["lightHighContrast"]),
        block('[data-theme="dark"]', "dark", contexts["dark"]),
        block('[data-theme="dark"][data-contrast="high"]', "dark", contexts["darkHighContrast"]),
        "@media (prefers-color-scheme: dark) {\n"
        + "\n".join("  " + line for line in block(":root:not([data-theme])", "dark", contexts["dark"]).splitlines())
        + "\n}",
    ]


def css(resolver):
    light = flatten(resolve_context(resolver, "light"))
    accents = resolver["modifiers"]["accent"]
    parts = [
        "/* Generated by design/scripts/tokens.py from design/*.tokens.json. Do not edit. */",
        "/* Themes apply to any element, so one page can show light and dark side by side. */",
        ":root {\n" + "\n".join(declarations(light, False)) + "\n}",
        *colour_blocks(resolver, None),
        f"/* Other accent families: data-accent on the root. Without it the page takes {accents['default']}. */",
        *(b for name in accents["contexts"] if name != accents["default"] for b in colour_blocks(resolver, name)),
        *dynamic_type_rules(light),
    ]
    return "\n\n".join(parts) + "\n"


def upper_camel(path):
    return "".join(part[0].upper() + part[1:] for part in path.replace("-", ".").split("."))


def lower_camel(path):
    name = upper_camel(path)
    return name[0].lower() + name[1:]


def colour_paths(tokens):
    return [path for path, token in tokens.items() if token["$type"] == "color" and not path.startswith("palette.")]


def asset_colour(value):
    channels = {name: f"0x{value['hex'][i : i + 2].upper()}" for name, i in (("red", 1), ("green", 3), ("blue", 5))}
    return {"color-space": "srgb", "components": {**channels, "alpha": f"{value.get('alpha', 1):.3f}"}}


def colour_set(path, contexts):
    """One colour set: the value of each appearance, as the asset catalog compiler reads it."""
    appearances = {
        "light": [],
        "dark": [{"appearance": "luminosity", "value": "dark"}],
        "lightHighContrast": [{"appearance": "contrast", "value": "high"}],
        "darkHighContrast": [
            {"appearance": "luminosity", "value": "dark"},
            {"appearance": "contrast", "value": "high"},
        ],
    }
    colours = []
    for theme, appearance in appearances.items():
        tokens = contexts[theme]
        entry: dict[str, Any] = {"idiom": "universal"}
        if appearance:
            entry["appearances"] = appearance
        entry["color"] = asset_colour(dereference(tokens[path]["$value"], tokens))
        colours.append(entry)
    return json.dumps({"colors": colours, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"


def colour_sets(resolver):
    """The asset catalog files: a folder with its own namespace for each accent family, and the global accent."""
    info = {"info": {"author": "xcode", "version": 1}}
    outputs = {COLOUR_SETS / "Contents.json": json.dumps(info, indent=2) + "\n"}
    accents = resolver["modifiers"]["accent"]
    for accent in accents["contexts"]:
        contexts = {
            theme: flatten(resolve_context(resolver, theme, accent))
            for theme in resolver["modifiers"]["theme"]["contexts"]
        }
        folder = COLOUR_SETS / upper_camel(accent)
        outputs[folder / "Contents.json"] = (
            json.dumps({**info, "properties": {"provides-namespace": True}}, indent=2) + "\n"
        )
        for path in colour_paths(contexts["light"]):
            name = upper_camel(path.removeprefix("color."))
            outputs[folder / f"{name}.colorset" / "Contents.json"] = colour_set(path, contexts)
        if accent == accents["default"]:
            outputs[COLOUR_SETS / f"{GLOBAL_ACCENT}.colorset" / "Contents.json"] = colour_set("color.tint", contexts)
    return outputs


FONT_WEIGHTS = {400: ("regular", "Regular"), 500: ("medium", "Medium"), 600: ("semibold", "SemiBold")}


def swift_switch(name, swift_type, doc, cases):
    lines = [f"    /// {doc}", f"    var {name}: {swift_type} {{", "        switch self {"]
    lines += [f"        case .{case}: {value}" for case, value in cases]
    return lines + ["        }", "    }"]


def swift_enum(name, protocols, doc, cases):
    return [f"/// {doc}", f"enum {name}: {protocols} {{", *(f"    case {case}" for case in cases)]


def swift_colours(resolver, tokens):
    accents = resolver["modifiers"]["accent"]
    names = [path.removeprefix("color.") for path in colour_paths(tokens)]
    return [
        *swift_enum(
            "AccentFamily",
            "String, CaseIterable, Sendable",
            "An accent family of ADR 0034. The raw value is the folder of its colour sets.",
            [f'{accent} = "{upper_camel(accent)}"' for accent in accents["contexts"]],
        ),
        "",
        f"    static let standard = AccentFamily.{accents['default']}",
        "}",
        "",
        *swift_enum(
            "Palette",
            "String, CaseIterable, ShapeStyle, Sendable",
            "A colour. The raw value is the name of its colour set in the folder of an accent family.",
            [f'{lower_camel(name)} = "{upper_camel(name)}"' for name in names],
        ),
        "",
        "    /// The name of the colour set in the asset catalog.",
        "    func assetName(in family: AccentFamily = .standard) -> String {",
        '        "\\(family.rawValue)/\\(rawValue)"',
        "    }",
        "",
        "    var color: Color { Color(assetName()) }",
        "",
        "    func resolve(in environment: EnvironmentValues) -> Color.Resolved {",
        "        color.resolve(in: environment)",
        "    }",
        "}",
    ]


def swift_type_styles(tokens):
    styles = []
    for path, token in tokens.items():
        if token["$type"] != "typography":
            continue
        value = dereference(token["$value"], tokens)
        family = value["fontFamily"][0]
        weight, face_weight = FONT_WEIGHTS[value["fontWeight"]]
        styles.append(
            {
                "name": path.removeprefix("type."),
                "size": number(value["fontSize"]["value"]),
                "textStyle": "." + token["$extensions"]["de.whnr.klassik"]["textStyle"],
                "weight": "." + weight,
                # A family that starts with "-" is a CSS keyword for the system face.
                "face": "nil" if family.startswith("-") else f'"{family}-{face_weight}"',
            }
        )

    def cases(key):
        return [(style["name"], style[key]) for style in styles]

    return [
        *swift_enum(
            "TypeStyle",
            "CaseIterable, Sendable",
            "A text style of ADR 0030. `typeStyle(_:)` sets it on a view.",
            [style["name"] for style in styles],
        ),
        "",
        *swift_switch("size", "CGFloat", "The size in points at the default Dynamic Type size.", cases("size")),
        "",
        *swift_switch(
            "textStyle", "Font.TextStyle", "The system text style whose metrics scale the size.", cases("textStyle")
        ),
        "",
        *swift_switch("weight", "Font.Weight", "The weight of the system face.", cases("weight")),
        "",
        *swift_switch(
            "face", "String?", "The PostScript name of a bundled face. The system face has none.", cases("face")
        ),
        "}",
    ]


def swift_constants(name, doc, group, tokens):
    lines = [f"/// {doc}", f"enum {name} {{"]
    for path, token in tokens.items():
        if path.startswith(group + "."):
            value = dereference(token["$value"], tokens)["value"]
            lines.append(f"    static let {lower_camel(path.removeprefix(group + '.'))}: CGFloat = {number(value)}")
    return lines + ["}"]


def swift_space(tokens):
    steps = [
        (path.removeprefix("space."), number(dereference(token["$value"], tokens)["value"]))
        for path, token in tokens.items()
        if path.startswith("space.")
    ]
    return [
        *swift_enum(
            "Space",
            "CaseIterable, Sendable",
            "A gap. `ScaledMetric(space:)` scales it with Dynamic Type.",
            [name for name, _ in steps],
        ),
        "",
        *swift_switch("points", "CGFloat", "The gap in points at the default Dynamic Type size.", steps),
        "}",
    ]


def seconds(duration):
    return number(duration["value"] / 1000 if duration["unit"] == "ms" else duration["value"])


def swift_motion(tokens):
    transitions = []
    for path, token in tokens.items():
        if token["$type"] != "transition":
            continue
        value = dereference(token["$value"], tokens)
        curve = ", ".join(number(v) for v in value["timingFunction"])
        animation = f".timingCurve({curve}, duration: {seconds(value['duration'])})"
        if value["delay"]["value"]:
            animation += f".delay({seconds(value['delay'])})"
        transitions.append((path.removeprefix("motion.transition."), animation))
    reduced = seconds(dereference(tokens["motion.duration.quick"]["$value"], tokens))
    return [
        *swift_enum(
            "Motion",
            "CaseIterable, Sendable",
            "A movement. `motion(_:value:)` runs it on a view.",
            [name for name, _ in transitions],
        ),
        "",
        "    /// The animation. Reduce Motion replaces each one with a short cross-fade.",
        "    func animation(reduceMotion: Bool) -> Animation {",
        f"        if reduceMotion {{ return .linear(duration: {reduced}) }}",
        "        return switch self {",
        *(f"        case .{name}: {animation}" for name, animation in transitions),
        "        }",
        "    }",
        "}",
    ]


def swift(resolver):
    tokens = flatten(resolve_context(resolver, "light"))
    parts = [
        ["// Generated by design/scripts/tokens.py from design/*.tokens.json. Do not edit.", "", "import SwiftUI"],
        swift_colours(resolver, tokens),
        swift_type_styles(tokens),
        swift_space(tokens),
        swift_constants("Radius", "A corner radius in points.", "radius", tokens),
        swift_constants("Measure", "A fixed size in points.", "size", tokens),
        swift_motion(tokens),
    ]
    return "\n\n".join("\n".join(part) for part in parts) + "\n"


def stale_colour_sets(outputs):
    """Folders below the colour set folder that hold no generated file."""
    if not COLOUR_SETS.exists():
        return []
    keep = {parent for path in outputs for parent in path.parents}
    return sorted(path for path in COLOUR_SETS.rglob("*") if path.is_dir() and path not in keep)


def main():
    check = "--check" in sys.argv[1:]
    resolver = json.loads(RESOLVER.read_text())
    outputs = {CSS: css(resolver), SWIFT: swift(resolver), **colour_sets(resolver)}
    stale = [path for path, text in outputs.items() if not path.exists() or path.read_text() != text]
    extra = stale_colour_sets(outputs)
    if check:
        for path in stale + extra:
            print(f"tokens.py: {path.relative_to(ROOT)} is not current. Run design/scripts/tokens.py.", file=sys.stderr)
        sys.exit(1 if stale or extra else 0)
    for path in extra:
        if path.exists():
            shutil.rmtree(path)
            print(f"removed {path.relative_to(ROOT)}")
    for path in stale:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(outputs[path])
        print(f"wrote {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
