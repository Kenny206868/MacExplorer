import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location('prioritize_ci', pathlib.Path(__file__).with_name('prioritize-ci.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class RetentionTests(unittest.TestCase):
    def test_only_older_main_integration_runs_are_eligible(self):
        base = dict(id=1, run_number=1, name='CI', event='push', head_branch='main', status='queued',
                    head_repository={'full_name': 'owner/repo'}, display_title='Implement feature', head_commit={'message': 'Implement feature'})
        variants = [base, dict(base, id=2, display_title='[alpha] milestone'), dict(base, id=3, status='completed'),
                    dict(base, id=4, event='pull_request'), dict(base, id=5, name='Publish alpha preview'),
                    dict(base, id=6, head_repository={'full_name': 'other/repo'}), dict(base, id=7, head_branch='feature'),
                    dict(base, id=8, run_number=8), dict(base, id=9, run_number=9)]
        self.assertEqual(module.superseded(variants, 'owner/repo', 8, 8), [1])

    def test_duplicate_ids_and_malformed_ids_do_not_expand_authority(self):
        base = dict(id=4, run_number=1, name='CI', event='push', head_branch='main', status='in_progress',
                    head_repository={'full_name': 'owner/repo'}, display_title='Commit', head_commit={'message': 'Commit'})
        self.assertEqual(module.superseded([base, base, dict(base, id=-1), dict(base, id='abc'), dict(base, id=True)], 'owner/repo', 8, 8), [4])

    def test_truncated_titles_do_not_lose_milestone_protection(self):
        base = dict(id=1, run_number=1, name='CI', event='push', head_branch='main', status='queued',
                    head_repository={'full_name': 'owner/repo'}, display_title='feat: ship native archive workspaces and Terminal navig…')
        runs = [dict(base, head_commit={'message': 'feat: ship native archive workspaces and Terminal navigation [alpha]'}),
                dict(base, id=2, head_commit={'message': 'fix: normal change\n\n[ALPHA] keep all native evidence'}),
                dict(base, id=3, head_commit={'message': 'fix: ordinary change'}),
                dict(base, id=4), dict(base, id=5, head_commit=None), dict(base, id=6, head_commit={'message': ''})]
        self.assertEqual(module.superseded(runs, 'owner/repo', 8, 8), [3])


if __name__ == '__main__':
    unittest.main()
