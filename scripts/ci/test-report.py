"""Summarise test-results.xml (JUnit) and coverage.xml (Cobertura) for a GitHub Actions job.

Writes `tests` and `coverage` to $GITHUB_OUTPUT and a short table to $GITHUB_STEP_SUMMARY.
Missing or broken reports are shown as "n/a" rather than failing the step.

Usage: python3 scripts/ci/test-report.py
"""

import os
import xml.etree.ElementTree as ET


def tests_line(path="test-results.xml"):
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return "n/a"
    suite = root if root.tag == "testsuite" else root.find("testsuite")
    if suite is None:
        return "n/a"
    total, failures, errors, skipped = (int(suite.get(k, 0)) for k in ("tests", "failures", "errors", "skipped"))
    return f"{total - failures - errors - skipped} passed, {failures + errors} failed, {skipped} skipped"


def coverage_line(path="coverage.xml"):
    try:
        rate = ET.parse(path).getroot().get("line-rate")
        return f"{float(rate) * 100:.1f}%"
    except (OSError, ET.ParseError, TypeError, ValueError):
        return "n/a"


def append(env, text):
    target = os.environ.get(env)
    if target:
        with open(target, "a", encoding="utf-8") as fh:
            fh.write(text)


tests, coverage = tests_line(), coverage_line()
append("GITHUB_OUTPUT", f"tests={tests}\ncoverage={coverage}\n")
append("GITHUB_STEP_SUMMARY", f"| Tests | Line coverage |\n|---|---|\n| {tests} | {coverage} |\n")
print(f"Tests: {tests}; line coverage: {coverage}")
