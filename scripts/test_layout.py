"""Tests for the layout checks: python3 -m unittest discover -s scripts -p "test_layout.py"."""

from __future__ import annotations

import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import layout_lint  # noqa: E402
import layout_tokens  # noqa: E402


class LintTests(unittest.TestCase):
    def numbers(self, source: str) -> list[str]:
        return [number for _, _, number in layout_lint.findings(source)]

    def test_refuses_literals_in_layout_calls(self):
        source = """
        Text("x").padding(.horizontal, 20)
        VStack(spacing: 4) {}
        Rectangle().frame(width: 36, height: 5)
        EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 32)
        .clipShape(.rect(cornerRadius: 6))
        @ScaledMetric(relativeTo: .body) private var cover: CGFloat = 56
        """
        self.assertEqual(self.numbers(source), ["20", "4", "36", "5", "16", "32", "6", "56"])

    def test_allows_tokens_zero_strings_and_comments(self):
        source = """
        Text("Padding 20").padding(.horizontal, Layout.edge) // 20 pt in the specimen
        VStack(spacing: 0) {}
        .frame(maxWidth: .infinity, minHeight: Layout.capsuleHeight)
        let count = 3
        """
        self.assertEqual(self.numbers(source), [])

    def test_a_call_over_several_lines(self):
        source = """
        .frame(
            width: proxy.size.width * 0.7,
            alignment: .leading)
        """
        self.assertEqual(layout_lint.findings(source), [(3, "width: proxy.size.width * 0.7,", "0.7")])

    def test_the_app_has_no_literal_outside_the_exceptions(self):
        self.assertEqual(layout_lint.main([]), 0)


class TokenTests(unittest.TestCase):
    properties = layout_tokens.custom_properties()

    def check(self, swift: str) -> str | None:
        found = layout_tokens.citations(swift)
        self.assertEqual(len(found), 1)
        return layout_tokens.check(found[0], self.properties)

    def test_a_matching_token(self):
        swift = """
        /// css: specimen.css :root.has-timeline | --pad-right
        static let timelineEdge = Space.l.points + Measure.timeline
        """
        self.assertIsNone(self.check(swift))

    def test_the_cascade_of_one_selector(self):
        swift = """
        /// css: specimen.css .row | padding-top
        static let rowPadding = Space.s.points
        """
        self.assertIn("is 11.335", self.check(swift))

    def test_a_shorthand_gives_its_longhands(self):
        swift = """
        /// css: specimen.css .scrub-label | padding-left
        static let scrubLabelHorizontal = Space.s.points
        """
        self.assertIsNone(self.check(swift))

    def test_a_literal_inside_a_value(self):
        swift = """
        /// css: person.html .pic | height | 471px
        static let pictureMaxHeight: CGFloat = 471
        """
        self.assertIn("does not hold 471px", self.check(swift))

    def test_a_type_role(self):
        swift = """
        /// css: specimen.css h1[class] | font
        static let pageTitle = TypeStyle.title1
        """
        self.assertIn("is not type title1", self.check(swift))

    def test_a_class_list_built_in_script(self):
        swift = """
        /// css: search.html "t-footnote" + (k === kind ? " on" : "" | class
        static let kinds = TypeStyle.footnote
        """
        self.assertIsNone(self.check(swift))

    def test_a_missing_rule(self):
        swift = """
        /// css: specimen.css .nothing | margin-top
        static let none = Space.s.points
        """
        self.assertIn("has no margin-top", self.check(swift))

    def test_a_token_without_a_citation(self):
        self.assertEqual(layout_tokens.undocumented("    /// A gap.\n    static let gap = Space.s.points\n"), ["gap"])

    def test_the_app_tokens_match_the_specimen(self):
        self.assertEqual(layout_tokens.main(["--check"]), 0)


class ScrubLabelTests(unittest.TestCase):
    def test_only_the_filled_background_casts_the_specimen_shadow(self):
        source = (layout_lint.ROOT / "Klassik/TimelineBarView.swift").read_text()
        label = source.split("private func label(", 1)[1].split("private func drag(", 1)[0]
        self.assertIn(".background {", label, "The text must not cast the background shadow")
        background = label.split(".background {", 1)[1].split("}", 1)[0]
        self.assertIn(".fill(Palette.backgroundElevated)", background)
        self.assertIn(".black.opacity(Layout.scrubLabelShadowOpacity)", background)
        self.assertIn("radius: Layout.scrubLabelShadow / 2", background)
        self.assertIn("y: Layout.scrubLabelShadowY", background)
        self.assertEqual(label.count(".shadow("), 1)
        self.assertIn(".typeStyle(.body)", label)


if __name__ == "__main__":
    unittest.main()
