"""Trust conditions of testflight-lab.yml: python3 -m unittest discover -s scripts -p "test_testflight_lab_*.py"."""

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKFLOW = (ROOT / ".github/workflows/testflight-lab.yml").read_text()
# Every condition a job on a workflow_run event needs, so fork code never meets the App Store Connect secrets.
TRUSTED = (
    "github.event.workflow_run.event == 'push'",
    "github.event.workflow_run.head_branch == 'main'",
    "github.event.workflow_run.head_repository.full_name == github.repository",
)


def job_condition(job):
    body = re.search(rf"^  {job}:\n(.*?)(?=^  \w|\Z)", WORKFLOW, re.S | re.M).group(1)
    return re.search(r"^    if: >-\n((?:      .*\n)+)", body, re.M).group(1)


class TrustedRunTests(unittest.TestCase):
    def test_every_job_requires_a_push_to_main_of_this_repository(self):
        for job in ("gate", "upload"):
            for clause in TRUSTED:
                with self.subTest(job=job, clause=clause):
                    self.assertIn(clause, job_condition(job))

    def test_the_manual_trigger_stays(self):
        self.assertIn("  workflow_dispatch:\n", WORKFLOW)
        for job in ("gate", "upload"):
            self.assertIn("github.event_name == 'workflow_dispatch'", job_condition(job))


if __name__ == "__main__":
    unittest.main()
