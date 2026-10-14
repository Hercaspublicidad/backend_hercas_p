"""Regression coverage for the Python package uploaded to Vercel."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeploymentTests(unittest.TestCase):
    def test_filtered_package_starts_without_local_files(self):
        paths = subprocess.check_output(
            ['git', 'ls-files', 'app'], cwd=ROOT, text=True
        ).splitlines()
        result = subprocess.run(
            ['git', '-c', 'core.excludesFile=.vercelignore', 'check-ignore',
             '--no-index', '-z', '--stdin'], cwd=ROOT,
            input=('\0'.join(paths + ['supabase/migrations/example.sql', '.env']) + '\0').encode(),
            capture_output=True, check=False,
        )
        self.assertIn(result.returncode, (0, 1), result.stderr)
        excluded = set(result.stdout.decode().split('\0'))
        self.assertIn('supabase/migrations/example.sql', excluded)
        self.assertIn('.env', excluded)
        self.assertNotIn('app/integrations/supabase/client.py', excluded)
        with tempfile.TemporaryDirectory() as directory:
            for name in paths:
                if name not in excluded and name.endswith('.py'):
                    target = Path(directory) / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(subprocess.check_output(
                        ['git', 'show', f'HEAD:{name}'], cwd=ROOT))
            env = os.environ.copy()
            env.pop('PYTHONPATH', None)
            env['APP_ENV'] = 'development'
            smoke = subprocess.run(
                [sys.executable, '-c',
                 'from fastapi.testclient import TestClient; '
                 'from app.main import app; '
                 'client = TestClient(app); '
                 'assert client.get("/health").status_code == 200; '
                 'assert client.get("/api/v1/auth/sesion").status_code == 401'],
                cwd=directory, env=env, text=True, capture_output=True,
            )
            self.assertEqual(smoke.returncode, 0, smoke.stdout + smoke.stderr)
