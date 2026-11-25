"""Tests of scripts/l10n_check.py."""

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import l10n_check  # noqa: E402


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def catalog(strings):
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def plural(one, other, state="translated"):
    return {"variations": {"plural": {"one": unit(one, state), "other": unit(other, state)}}}


class CatalogTests(unittest.TestCase):
    def check(self, strings):
        return l10n_check.check_catalog("Test.xcstrings", catalog(strings))

    def test_a_translated_key_passes(self):
        self.assertEqual(self.check({"Pause": {"localizations": {"de": unit("Pause")}}}), [])

    def test_a_key_without_german_fails(self):
        self.assertIn("no de text", self.check({"Pause": {}})[0])

    def test_a_text_that_waits_for_review_fails(self):
        problems = self.check({"Pause": {"localizations": {"de": unit("Pause", "needs_review")}}})
        self.assertIn("not translated", problems[0])

    def test_a_stale_key_fails(self):
        problems = self.check({"Old": {"extractionState": "stale", "localizations": {"de": unit("Alt")}}})
        self.assertIn("stale", problems[0])

    def test_an_empty_text_fails(self):
        self.assertIn("empty", self.check({"Pause": {"localizations": {"de": unit(" ")}}})[0])

    def test_a_missing_specifier_fails(self):
        problems = self.check({"%lld works": {"localizations": {"de": unit("Werke")}}})
        self.assertIn("specifiers", problems[0])

    def test_a_moved_specifier_passes(self):
        strings = {"%@ of %@": {"localizations": {"de": unit("%2$@ von %1$@")}}}
        self.assertEqual(self.check(strings), [])

    def test_a_percent_sign_is_no_specifier(self):
        strings = {"100%% sure": {"localizations": {"de": unit("100%% sicher")}}}
        self.assertEqual(self.check(strings), [])

    def test_plural_keys_need_both_forms_in_both_languages(self):
        good = {"localizations": {"en": plural("%lld work", "%lld works"), "de": plural("%lld Werk", "%lld Werke")}}
        self.assertEqual(self.check({"%lld works": good}), [])
        only_german = {"localizations": {"de": plural("%lld Werk", "%lld Werke")}}
        self.assertIn("no en text", self.check({"%lld works": only_german})[0])
        flat = {"localizations": {"en": plural("%lld work", "%lld works"), "de": unit("%lld Werke")}}
        self.assertIn("no plural forms", self.check({"%lld works": flat})[0])

    def test_the_singular_may_name_the_number_in_words(self):
        strings = {
            "%lld works": {
                "localizations": {"en": plural("one work", "%lld works"), "de": plural("ein Werk", "%lld Werke")}
            }
        }
        self.assertEqual(self.check(strings), [])

    def test_a_catalog_needs_the_source_language(self):
        problems = l10n_check.check_catalog("T", {"sourceLanguage": "fr", "strings": {}})
        self.assertIn("source language", problems[0])


class SwiftTests(unittest.TestCase):
    def keys(self, code):
        return [key for _, key in l10n_check.swift_keys(code)]

    def test_view_calls_give_their_first_literal(self):
        code = 'Text("Library")\nButton("Done", action: done)\nSection("Result") { Text(item.title) }'
        self.assertEqual(self.keys(code), ["Library", "Done", "Result"])

    def test_both_branches_of_a_ternary_count(self):
        self.assertEqual(self.keys('Text(on ? "Yes" : "No")'), ["Yes", "No"])

    def test_a_nested_call_is_its_own_site(self):
        self.assertEqual(self.keys('Text(L("Inner"))'), ["Inner"])

    def test_interpolations_become_specifiers(self):
        self.assertEqual(self.keys('L("\\(count) works in \\(name.uppercased())")'), ["%@ works in %@"])

    def test_a_comparison_is_no_text(self):
        self.assertEqual(self.keys('Text(kind == "composer" ? "A" : "B")'), ["A", "B"])

    def test_verbatim_and_values_are_no_keys(self):
        self.assertEqual(self.keys('Text(verbatim: "raw")\nLabeledContent("Name", value: "x")'), ["Name"])

    def test_modifiers_with_text(self):
        self.assertEqual(self.keys('.accessibilityLabel("Close")\n.navigationTitle("Title")'), ["Close", "Title"])

    def test_escapes_decode(self):
        self.assertEqual(self.keys('L("A\\u{00A0}B \\"q\\"")'), ["A B \"q\""])

    def test_a_dispatch_queue_label_is_no_key(self):
        self.assertEqual(self.keys('DispatchQueue(label: "de.whnr.queue")'), [])

    def test_shapes_ignore_the_argument_type(self):
        self.assertEqual(l10n_check.shape("%lld of %@ on 100%%"), l10n_check.shape("%@ of %@ on 100%%"))


class RepositoryTests(unittest.TestCase):
    def test_the_app_passes_its_own_check(self):
        self.assertEqual(l10n_check.main([]), 0)

    def test_the_table_lists_every_key(self):
        catalogs = l10n_check.load()
        rows = l10n_check.table(catalogs).splitlines()
        self.assertGreater(len(rows), 300)
        self.assertIn("| Settings | Einstellungen |", rows)


if __name__ == "__main__":
    unittest.main()
