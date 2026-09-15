import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('validate_performance', pathlib.Path(__file__).with_name('validate-performance.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
COMMIT = 'a' * 40


class PerformanceValidationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        (self.root / 'COMMIT.txt').write_text(COMMIT)
        (self.root / 'execution.json').write_text(json.dumps({'sourceCommit': COMMIT, 'testExitCode': 0}))
        self.report = {'schemaVersion': 2, 'buildConfiguration': 'release-instrumented', 'entries': 2000,
                       'selectionBodyEvaluations': 23, 'maximumLiveRowAnchors': 96}
        for phase, count in module.SAMPLES.items():
            self.report[phase] = {'samples': count, 'medianMilliseconds': 1, 'p95Milliseconds': 3, 'maximumMilliseconds': 8}

    def runReport(self, report=None, commit=COMMIT):
        (self.root / 'large-directory-performance.json').write_text(json.dumps(self.report if report is None else report))
        return module.validate(self.root, commit)

    def test_valid_exact_commit_evidence(self):
        result = self.runReport()
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(len(result['reportSHA256']), 64)
        self.assertTrue((self.root / 'performance-validation.json').is_file())

    def test_debug_missing_counters_and_wrong_fixture_are_rejected(self):
        for key, values in [('buildConfiguration', ['debug', None]), ('entries', [1, True]),
                            ('selectionBodyEvaluations', [0, 240, True]), ('maximumLiveRowAnchors', [0, 500, None])]:
            for value in values:
                with self.subTest(key=key, value=value):
                    changed = copy.deepcopy(self.report); changed[key] = value
                    with self.assertRaises(ValueError): self.runReport(changed)

    def test_missing_nonfinite_and_inconsistent_timings_are_rejected(self):
        for key, value in [('samples', 0), ('medianMilliseconds', float('nan')),
                           ('p95Milliseconds', float('inf')), ('maximumMilliseconds', -1),
                           ('medianMilliseconds', 99)]:
            changed = copy.deepcopy(self.report); changed['keyDispatch'][key] = value
            with self.assertRaises(ValueError): self.runReport(changed)
        changed = copy.deepcopy(self.report); del changed['continuousScrollLayout']
        with self.assertRaises(ValueError): self.runReport(changed)

    def test_wrong_commit_or_failed_test_cannot_pass(self):
        with self.assertRaises(ValueError): self.runReport(commit='b' * 40)
        (self.root / 'execution.json').write_text(json.dumps({'sourceCommit': COMMIT, 'testExitCode': 1}))
        with self.assertRaises(ValueError): self.runReport()


if __name__ == '__main__':
    unittest.main()
