import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from compare_catalog_exports import ExportSnapshot, compare_snapshots, normalize_program_url


HEADER = [
    "Section",
    "University",
    "Degree Name",
    "Department",
    "Major or Minor",
    "Requirement Category",
    "Mode",
    "Course Code",
    "Course Title",
    "Course Description",
    "Credits",
    "Program URL",
    "Degree Type",
    "Entity",
    "Issue",
    "Degree Level",
    "Source Catoid",
]


class CompareCatalogExportsTests(unittest.TestCase):
    def test_normalize_program_url_keeps_only_poid_catoid(self):
        raw = "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=6044&returnto=878&print=1"
        self.assertEqual(
            normalize_program_url(raw),
            "https://catalogs.buffalo.edu/preview_program.php?poid=6044&catoid=17",
        )

    def test_compare_snapshots_detects_improvement(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            baseline = tmp_path / "baseline.csv"
            candidate = tmp_path / "candidate.csv"

            rows_base = [
                {
                    "Section": "CATALOG",
                    "University": "University at Buffalo",
                    "Degree Name": "Computer Science, BS",
                    "Department": "CSE",
                    "Major or Minor": "Major",
                    "Requirement Category": "Computer Science Core",
                    "Mode": "required",
                    "Course Code": "CSE 115",
                    "Course Title": "Introduction to Computer Science I",
                    "Course Description": "Intro",
                    "Credits": "",
                    "Program URL": "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=6044",
                    "Degree Type": "BS",
                    "Entity": "",
                    "Issue": "",
                    "Degree Level": "Undergraduate",
                    "Source Catoid": "17",
                },
                {
                    "Section": "AUDIT",
                    "University": "University at Buffalo",
                    "Degree Name": "Computer Science, BS",
                    "Department": "CSE",
                    "Major or Minor": "Major",
                    "Requirement Category": "",
                    "Mode": "",
                    "Course Code": "",
                    "Course Title": "",
                    "Course Description": "",
                    "Credits": "",
                    "Program URL": "https://catalogs.buffalo.edu/preview_program.php?catoid=17&poid=6044",
                    "Degree Type": "BS",
                    "Entity": "MajorEntity",
                    "Issue": "Program saved to database but no requirements found",
                    "Degree Level": "Undergraduate",
                    "Source Catoid": "17",
                },
            ]

            rows_candidate = [
                {
                    "Section": "CATALOG",
                    "University": "University at Buffalo",
                    "Degree Name": "Computer Science, BS",
                    "Department": "CSE",
                    "Major or Minor": "Major",
                    "Requirement Category": "Computer Science Core",
                    "Mode": "required",
                    "Course Code": "CSE 115",
                    "Course Title": "Introduction to Computer Science I",
                    "Course Description": "Intro",
                    "Credits": "4",
                    "Program URL": "https://catalogs.buffalo.edu/preview_program.php?poid=6044&catoid=17",
                    "Degree Type": "BS",
                    "Entity": "",
                    "Issue": "",
                    "Degree Level": "Undergraduate",
                    "Source Catoid": "17",
                },
                {
                    "Section": "AUDIT",
                    "University": "University at Buffalo",
                    "Degree Name": "Computer Science, BS",
                    "Department": "CSE",
                    "Major or Minor": "Major",
                    "Requirement Category": "",
                    "Mode": "",
                    "Course Code": "",
                    "Course Title": "",
                    "Course Description": "",
                    "Credits": "",
                    "Program URL": "https://catalogs.buffalo.edu/preview_program.php?poid=6044&catoid=17",
                    "Degree Type": "BS",
                    "Entity": "CourseCatalogEntity",
                    "Issue": "RESOLVED: Partial course row: missing credits",
                    "Degree Level": "Undergraduate",
                    "Source Catoid": "17",
                },
            ]

            self._write_csv(baseline, rows_base)
            self._write_csv(candidate, rows_candidate)

            baseline_snap = ExportSnapshot(baseline)
            candidate_snap = ExportSnapshot(candidate)
            report = compare_snapshots(baseline_snap, candidate_snap, gate_rate=0.5)

            self.assertGreater(report["deltas"]["codedRowCompleteness"], 0)
            self.assertEqual(report["programChanges"]["regressedCount"], 0)
            self.assertEqual(report["programChanges"]["improvedCount"], 1)

    def _write_csv(self, path: Path, rows: list[dict[str, str]]) -> None:
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=HEADER)
            writer.writeheader()
            writer.writerows(rows)


if __name__ == "__main__":
    unittest.main()
