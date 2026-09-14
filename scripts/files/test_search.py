"""Run: python3 -m unittest discover -s scripts/files -v"""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from search import Query, Search, candidate, parse_query, sort_key


class FileSearchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.docs = self.home / "Documents"
        self.docs.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def file(self, name, parent=None):
        path = (parent or self.docs) / name
        path.write_text("Never read these contents by search.")
        return path

    def run_search(self, text, **kwargs):
        search = Search({"query": text, "requestId": 42}, home=str(self.home),
                        roots=[str(self.docs)], index_command="/missing-plocate", **kwargs)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            search.run()
        return [json.loads(line) for line in output.getvalue().splitlines()]

    def test_parse_filters_and_quoted_scope(self):
        folder = self.home / "Folder with spaces"
        folder.mkdir()
        q = parse_query(f'Annual REPORT ext:PDF type:file in:"{folder}"')
        self.assertEqual(q.terms, ["annual", "report"])
        self.assertEqual(q.extension, "pdf")
        self.assertEqual(q.directory, str(folder))

    def test_invalid_filters(self):
        for text in ['"unterminated', "type:exe", "ext:", "in:relative", "in:/proc"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_query(text)

    def test_unicode_case_and_metacharacters(self):
        names = ["گزارش نهایی.pdf", "Résumé.PDF", "a #b ?c.txt", "$(touch hacked).txt", "O'Brien.txt"]
        for name in names:
            path = self.file(name)
            q = Query([name.casefold()])
            # '?' is explicitly wildcard syntax, not shell syntax.
            self.assertEqual(candidate(str(path), q, str(self.home))["path"], str(path))
        self.assertFalse((self.home / "hacked").exists())

    def test_uri_encoding(self):
        path = self.file("report #1% final.pdf")
        row = candidate(str(path), Query(["report"]), str(self.home))
        self.assertIn("%23", row["url"])
        self.assertIn("%25", row["url"])
        self.assertIn("%20", row["url"])

    def test_ranking_and_multiple_terms(self):
        paths = [self.file(n) for n in ("report", "report final", "annual report")]
        rows = [candidate(str(p), Query(["report"]), str(self.home)) for p in paths]
        self.assertEqual([r["name"] for r in sorted(rows, key=sort_key)], [p.name for p in paths])
        self.assertIsNotNone(candidate(str(paths[1]), Query(["final", "report"]), str(self.home)))
        self.assertIsNone(candidate(str(paths[0]), Query(["final", "report"]), str(self.home)))

    def test_glob_extension_kind_and_scope(self):
        path = self.file("report-01.PDF")
        self.assertIsNotNone(candidate(str(path), Query(["report-*.pdf"], "pdf", "file"), str(self.home)))
        self.assertIsNone(candidate(str(path), Query(["report"], "", "folder"), str(self.home)))
        self.assertIsNone(candidate(str(path), Query(["report"], "", "", "/etc"), str(self.home)))
        self.assertIsNone(candidate(str(self.docs), Query([], "pdf"), str(self.home)))

    def test_hidden_new_files_and_missing_index(self):
        path = self.file(".brand-new.txt")
        results = self.run_search("brand-new")
        self.assertEqual(results[-1]["results"][0]["path"], str(path))
        self.assertTrue(results[-1]["partial"])
        self.assertFalse(results[-1]["busy"])
        self.assertEqual(results[-1]["requestId"], 42)

    def test_symlinks_deleted_and_permissions(self):
        target = self.file("target.txt")
        link = self.docs / "target-link.txt"
        link.symlink_to(target)
        self.assertIsNotNone(candidate(str(link), Query(["target"]), str(self.home)))
        with patch("search.os.access", return_value=False):
            self.assertIsNone(candidate(str(target), Query(["target"]), str(self.home)))
        target.unlink()
        self.assertIsNone(candidate(str(link), Query(["target"]), str(self.home)))
        self.assertIsNone(candidate(str(target), Query(["target"]), str(self.home)))

    def test_scoped_search_does_not_follow_directory_symlink(self):
        nested = self.docs / "nested"
        nested.mkdir()
        (nested / "loop").symlink_to(self.docs, target_is_directory=True)
        self.file("unique.txt", nested)
        results = self.run_search(f'unique in:"{self.docs}"')
        self.assertEqual(len(results[-1]["results"]), 1)

    def test_limits_and_empty_query(self):
        for i in range(25):
            self.file(f"match-{i}.txt")
        results = self.run_search("match")
        self.assertEqual(len(results[-1]["results"]), 20)
        self.assertEqual(self.run_search("")[-1]["results"], [])
        with patch("search.LIVE_LIMIT", 1):
            self.assertIn("Live scan limited", self.run_search("match")[-1]["message"])

    def test_cancelled_search_emits_nothing(self):
        search = Search({"query": "anything"}, home=str(self.home), roots=[])
        search.stop()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            search.run()
        self.assertEqual(output.getvalue(), "")

    def test_cli_json_and_no_shell_execution(self):
        self.file("$(touch hacked).txt")
        query = f"'$(touch hacked).txt' in:\"{self.docs}\""
        proc = subprocess.run([sys.executable, str(Path(__file__).with_name("search.py")),
                               "--request", json.dumps({"query": query, "requestId": 7})],
                              capture_output=True, text=True, timeout=5)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        final = json.loads(proc.stdout.splitlines()[-1])
        self.assertEqual(final["requestId"], 7)
        self.assertEqual(final["results"][0]["name"], "$(touch hacked).txt")
        self.assertFalse((self.home / "hacked").exists())


if __name__ == "__main__":
    unittest.main()
