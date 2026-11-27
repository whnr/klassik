"""Checks that page arguments of specimen_check.py select a page with its URL variants and reject unknown names."""

import importlib.util
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "specimen_check", Path(__file__).resolve().parents[1] / "design/scripts/specimen_check.py"
)
specimen_check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(specimen_check)


class SelectPagesTests(unittest.TestCase):
    def test_no_argument_selects_every_page(self):
        self.assertEqual(specimen_check.select_pages([]), specimen_check.PAGES)

    def test_a_name_selects_the_page_and_its_variants(self):
        selected = specimen_check.select_pages(["library.html"])
        self.assertEqual(
            selected,
            tuple(page for page in specimen_check.PAGES if page.split("?")[0] == "library.html"),
        )
        self.assertIn("library.html?edit=1", selected)

    def test_names_keep_the_order_of_pages(self):
        selected = specimen_check.select_pages(["search.html", "library.html"])
        self.assertEqual(
            selected,
            tuple(page for page in specimen_check.PAGES if page.split("?")[0] in {"library.html", "search.html"}),
        )

    def test_an_unknown_name_is_an_error(self):
        with self.assertRaises(SystemExit) as raised:
            specimen_check.select_pages(["nope.html"])
        self.assertIn("nope.html", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
