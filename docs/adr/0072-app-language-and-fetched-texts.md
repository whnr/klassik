# 0072. App language, fetched texts and the fallback language

Date: 2026-11-25. Status: Proposed. Flo reviews it. The rules come from Flo's spec on sz-odf9 of 2026-11-25.

## Context

Klassik had English text only, in 150 literals of the views. Wikidata labels, descriptions and Wikipedia leads were fetched in English only. Flo wants English and German now, a language picker in the app, and no German text that is cut off.

## Decision

- The app speaks English and German. String Catalogs hold the texts: `Klassik/Localizable.xcstrings` and `Klassik/InfoPlist.xcstrings`. English is the source language.
- The app follows the device language until the listener picks one in Settings. The pick lives in the app and applies at once: SwiftUI literals follow the `locale` of the environment, and other strings come from `L(...)`, which reads the catalog of the app language. Numbers, dates, durations, lists and plurals follow the same locale.
- Composer names, work titles and every tag stay as tagged. MusicBrainz and the music server give no translated text, so nothing else is fetched in the app language.
- A Wikidata description and a Wikipedia lead come in the app language. When the app language has no text, the fallback language gives it. The fallback is English by default. The listener can pick the other app language or turn it off. With the fallback off and no text in the app language, the text stays empty.
- Each saved person keeps the text languages it was fetched for. A change of the app or fallback language marks the people with other languages. The background pass of [0042](0042-wikidata-pass-in-the-background.md) loads them again at its own pace. The old text stays on the page until the new text arrives. A page that opens loads its person at once.
- A CI check refuses a key without German text, a literal that is not in the catalog, and text that a view truncates without a reason.
- The UI walk shows Settings, Library, Search, a work page and the player in both languages. A pseudo-language run doubles the German texts and checks that no text leaves the screen.

## Alternatives

- Open the per-app language setting of iOS instead of a picker. The system chrome would follow, but a change would restart the app. Flo asked for a picker that applies at once. Cost of the choice: the keyboard and system sheets keep the device language.
- One cache for each language. A change of language would show texts at once, but the cache would grow with each language. One saved text and a reload keep the cache small.

## Consequences

- A change of language fetches the Wikidata and Wikipedia texts of the whole library again, in the background and at the pace that Wikimedia asks for.
- A new language needs a catalog column, a Wikipedia edition in `AppLanguage` and a pass of the walk. More languages are follow-up work after 1.0.
- The engine library holds no catalog. Its messages reach the listener through `Localization.translated`, which maps each English message to the catalog.
- The Gapless Test page is a developer tool and stays English.
