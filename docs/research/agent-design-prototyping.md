# How agents best prototype a design system

Bead: sz-rs30.1.83.1. Read on 2026-11-05 from primary sources. No artifact was made and no Figma file was opened.

## Question

Which source of truth lets coding agents build and change Klassik's design? The design is type, colour in light and dark, spacing, radius, motion and a few hand-drawn signature views. Flo must judge it on his iPhone through HTML prototypes.

## Answer

- A token file in the repo is the only option that agents read and write without a human, that the prototypes and SwiftUI both use, and that costs nothing.
- The claude.ai Design System artifact is a good viewer. It is a poor source of truth for Klassik: it has no motion family, it cannot read W3C token maps, and it lives outside the repo.
- Figma can be read and written by an agent only through an OAuth sign-in and a paid seat. Its variables API needs an Enterprise plan. It adds cost and keeps the design outside the public repo.

## Klassik facts that bound the answer

- `project.yml` sets `ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS: NO`. Its comment says the generator costs about 40 s of each CI build. A colour must therefore be reached by name or by a generated Swift constant, not by an Xcode asset symbol.
- `Klassik/Assets.xcassets` holds only `AppIcon`. No colour set exists yet.
- The scripts in `scripts/` are Python and shell. No Node toolchain exists in the repo or in `test.yml`.
- Prototypes are one self-contained HTML file with no network (`docs/agents/prototyping.md`). Flo opens them at an unlisted URL on `whnr.uber.space`.

## Option 1: claude.ai Design System artifact

What it is (from the type's `SKILL.md`, `format.md`, `from-code.md` and `from-design-tool.md`, read with the Artifact tool from https://claude.ai/artifact/5M7UeXXcx16TP3vzVFNDzd):

- A system keeps its content in files under `project/`: an index `design-system.json`, `tokens.json`, `README.md` as the brand book, `components/<Comp>/preview.html` and `README.md`, a `bundle.js`, fonts and asset uploads. The page generates `tokens.css` from `tokens.json`.
- `tokens.json` families: `color` with up to 8 themes, `type`, `spacing`, `radius`, optional `shadow`, and up to 12 other families of plain CSS values. `format.md` states: "No motion family."
- Each family is a list of `{name, value, usage}`. `format.md` states that a DTCG / W3C name-to-value map "is valid JSON the page cannot read: the family shows empty".
- Type styles are `fontSize` and `lineHeight` in px or rem. Dynamic Type text styles have no place in the format.
- Component previews are React 18 via a hand-written classic script. A preview runs in a frame on the artifact's origin.
- A system can be marked `"editing": "code"`. Then a Claude Code `/design-sync` run publishes it from a codebase, and the page is read-only. `from-code.md` reads a repo's CSS custom properties or a DTCG token file as input.
- Writes go through the Artifact tool in a Claude session. `from-code.md` states: "No other skill, no scripts of ours, no API token." A CI job cannot write it.
- An artifact is private by default. Its uploads are served "to signed-in viewers" (`format.md`, Tiers).

Per criterion:

- Agent read and write unattended: yes, from a Claude session with the Artifact tool. No, from CI or from another agent tool without that tool.
- HTML prototypes use it directly: no. A prototype is self-contained and has no network. A prototype on `whnr.uber.space` cannot load a private artifact's `tokens.css`. The agent must copy values into each prototype.
- Path to SwiftUI: none built in. An agent must read `tokens.json` and write the Swift and asset files by hand or with a script. Motion has nowhere to live.
- Public repo: the design lives on claude.ai, outside the repo. Contributors without access cannot see the source of truth. The repo stays clean of it.
- Cost to Flo per change: no money beyond his Claude plan. He opens one more link and must be signed in to claude.ai on the phone.

## Option 2: token file in the repo

Format facts:

- The Design Tokens Community Group published the Format, Color and Resolver modules as version 2025.10, a Final Community Group Report of 28 October 2025. It "is considered stable". It is not a W3C Standard. https://www.designtokens.org/tr/2025.10/
- The format defines the types `color`, `dimension`, `fontFamily`, `fontWeight`, `duration`, `cubicBezier`, `number`, and composites including `transition`, `shadow` and `typography`. File extension `.tokens` or `.tokens.json`. https://www.designtokens.org/tr/drafts/format/
- `duration` and `cubicBezier` give motion a typed home. Option 1 has none.
- The Resolver module expresses light and dark as a modifier with one context for each theme, and a `resolutionOrder` that applies sets and modifiers in order. https://www.designtokens.org/tr/2025.10/resolver/

To the HTML prototypes:

- A generator writes `tokens.css`: custom properties under `:root`, and dark values under `@media (prefers-color-scheme: dark)`. A prototype build step pastes that file into the HTML, so the prototype stays self-contained.
- The agent changes one token, runs the generator, and the next prototype uses the new value. No copy by hand.

To SwiftUI:

- Colour sets: the asset catalog type is a `.colorset` folder with a `Contents.json`. Each element of `colors` is one variant, with `color-space` and `red`, `green`, `blue`, `alpha` from 0 to 1. https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/Named_Color.html
- Xcode lets a colour set hold values for light and dark appearances, and high-contrast values. https://developer.apple.com/documentation/xcode/specifying-your-apps-color-scheme
- The dark variant carries `"appearances": [{"appearance": "luminosity", "value": "dark"}]`. Apple's archived format reference predates dark mode and does not list this key. The key is seen in Xcode-written files on GitHub. Confirm it once by saving a colour set in Xcode.
- Without an asset catalog: `UIColor(dynamicProvider:)` "uses the specified block to generate its color data dynamically" from the current traits. A generator can write one Swift constant for each colour with this initialiser. It needs no asset symbol generation. https://developer.apple.com/documentation/uikit/uicolor/init(dynamicprovider:)
- Type: `Font.custom(_:size:relativeTo:)` creates a custom font that "scales relative to the given `textStyle`". A system font with a `Font.TextStyle` scales with Dynamic Type directly. The generator maps each type token to a text style, and a size only for a custom face. https://developer.apple.com/documentation/swiftui/applying-custom-fonts-to-text
- Spacing that must grow with text: `ScaledMetric`, "a dynamic property that scales a numeric value". https://developer.apple.com/documentation/swiftui/scaledmetric
- Motion: the generator writes `duration` and `cubicBezier` tokens as SwiftUI `Animation` constants. The views must check `accessibilityReduceMotion`: "UI should avoid large animations". https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion

Generator choice:

- Style Dictionary reads DTCG `$value` and `$type` tokens. Its `ios-swift` transform group writes static `UIColor(red:green:blue:alpha:)` values with no dark variant. It has no built-in colour-set format. A colour set needs a custom action, as in the maintainer's example repo. Style Dictionary is a Node package, so it adds Node to the toolchain. https://styledictionary.com/reference/hooks/formats/predefined/ , https://github.com/dbanksdesign/style-dictionary-example-colorsets
- A hand-written Python script of about 150 lines does the same job with the standard library. It matches the other scripts in `scripts/`. It needs no app dependency and no Node.
- Run the generator by hand and commit its output. Then a build needs no extra step, and a CI lint can check that the output is current.

Per criterion:

- Agent read and write unattended: yes. It is a text file in git. CI can check it.
- HTML prototypes use it directly: yes, through the generated CSS.
- Path to SwiftUI: generated Swift constants or colour sets, text-style mapping and animation constants.
- Public repo: yes. Tokens are not copyrighted assets. Hand-drawn signature views stay as SwiftUI code and HTML in the repo.
- Cost to Flo per change: none. He opens a prototype link as today.

## Option 3: Figma

- Variables REST API: "To use this API, you must have a Full seat in an Enterprise org; guests cannot use the API." Read needs scope `file_variables:read`, write needs `file_variables:write`. https://developers.figma.com/docs/rest-api/variables/
- MCP server: `use_figma` "creates, edits, deletes, and inspects content, including frames, components, and variables". It is remote-only. `get_variable_defs` lists the variables and styles used in a selection. https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/
- Writing needs the remote server and a Full seat outside drafts. Figma calls write "free during the beta". https://developers.figma.com/docs/figma-mcp-server/
- Sign-in: "You sign in with your Figma account the first time you connect." A browser page opens. The page names no token for a headless run. https://developers.figma.com/docs/figma-mcp-server/remote-server-installation/
- Rate limits: View or Collab seat 20 tool calls a month on every plan. Full or Dev seat on Professional 200 a day and 10 a minute. Tools that write to Figma files are exempt. https://developers.figma.com/docs/figma-mcp-server/rate-limits-access/
- Price: Professional Full seat 16 USD a month, Dev seat 12 USD, Collab seat 3 USD. Enterprise Full seat 90 USD a month, billed annually. https://www.figma.com/pricing/

Per criterion:

- Agent read and write unattended: only after Flo signs in once in a browser, and only from a client in Figma's MCP catalog. No path from CI. The variables REST API needs Enterprise.
- HTML prototypes use it directly: no. An agent must export variables to CSS. Figma's own prototypes are not HTML.
- Path to SwiftUI: through an export to a token file. That is Option 2 with an extra step.
- Public repo: the source of truth sits in a private Figma file. Outside contributors need Figma access. The repo holds only an export.
- Cost to Flo per change: at least 16 USD a month for a Full seat to write outside drafts. A sign-in when the OAuth grant ends.

## Comparison

| Criterion | 1. Design System artifact | 2. Token file in repo | 3. Figma |
| --- | --- | --- | --- |
| Agent reads and writes unattended | Claude session only; not CI | Yes, also CI | After browser sign-in; not CI |
| HTML prototypes use it directly | No; copy values | Yes, generated CSS | No; export first |
| Path to SwiftUI | None built in | Generator: Swift or colour sets, text styles, animations | Export to token file, then Option 2 |
| Motion tokens | No family | `duration`, `cubicBezier` | Through `get_motion_context` only |
| Public repo | Lives outside repo | In repo | Lives outside repo |
| Cost to Flo per change | Nothing extra; claude.ai sign-in | Nothing | From 16 USD a month; sign-ins |

## Recommendation

This is a recommendation, not a decision.

- Make `design/klassik.tokens.json` in DTCG 2025.10 format the source of truth, with a Resolver file for light and dark.
- Write `scripts/tokens.py` with the standard library. It writes `tokens.css` for prototypes and a Swift file for the app. Use `UIColor(dynamicProvider:)` constants, so asset symbol generation stays off. Run it by hand, commit the output, and let lint check that it is current.
- Keep the signature views as SwiftUI code, with an HTML twin in the prototype folder that reads the same `tokens.css`.
- If Flo wants a browsable brand book, publish the Design System artifact as a read-only mirror of the repo (`"editing": "code"`). It must convert the DTCG maps to its list format and it drops motion. Treat it as a view, never as the source.
- Do not use Figma. It adds cost and a sign-in, and it gives nothing that the repo file does not give.

## Open points

- Confirm the colour-set `appearances` key in Xcode once, if colour sets are used instead of Swift constants.
- No generator was built or run. Its line count is an estimate.
