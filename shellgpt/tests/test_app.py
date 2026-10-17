import unittest
from unittest.mock import patch, mock_open
import io
from shellgpt.app import main


class TestApp(unittest.TestCase):
    @patch('sys.argv', ['sg', '--role', 'typo', '--system', 'You are a bot'])
    @patch('sys.stderr', new_callable=io.StringIO)
    def test_role_and_system_conflict(self, mock_stderr):
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 1)
        self.assertIn(
            'Error: --role, --system, and --system-file cannot be used together.',
            mock_stderr.getvalue(),
        )

    @patch('sys.argv', ['sg', '-r', 'typo', '-s', 'You are a bot'])
    @patch('sys.stderr', new_callable=io.StringIO)
    def test_short_flags_role_and_system_conflict(self, mock_stderr):
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 1)
        self.assertIn(
            'Error: --role, --system, and --system-file cannot be used together.',
            mock_stderr.getvalue(),
        )

    @patch(
        'sys.argv', ['sg', '--system', 'You are a bot', '--system-file', 'prompt.txt']
    )
    @patch('sys.stderr', new_callable=io.StringIO)
    def test_system_and_system_file_conflict(self, mock_stderr):
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 1)
        self.assertIn(
            'Error: --role, --system, and --system-file cannot be used together.',
            mock_stderr.getvalue(),
        )

    @patch('sys.argv', ['sg', '--role', 'typo', '--system-file', 'prompt.txt'])
    @patch('sys.stderr', new_callable=io.StringIO)
    def test_role_and_system_file_conflict(self, mock_stderr):
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 1)
        self.assertIn(
            'Error: --role, --system, and --system-file cannot be used together.',
            mock_stderr.getvalue(),
        )

    @patch('sys.argv', ['sg', '--dump', '--system', 'custom system prompt'])
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_system_option(self, mock_stdout):
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 0)
        output = mock_stdout.getvalue()
        self.assertIn('role: system', output)
        self.assertIn("'system'", output)

    @patch('sys.argv', ['sg', '--dump', '--system-file', '/path/to/prompt.txt'])
    @patch('builtins.open', mock_open(read_data='file prompt content'))
    @patch('sys.stdout', new_callable=io.StringIO)
    def test_system_file_option(self, mock_stdout):
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 0)
        output = mock_stdout.getvalue()
        self.assertIn('role: system', output)
        self.assertIn("'system'", output)

    @patch('sys.argv', ['sg', '--system-file', '/nonexistent/file.txt'])
    @patch('sys.stderr', new_callable=io.StringIO)
    def test_system_file_not_found(self, mock_stderr):
        with self.assertRaises(SystemExit) as cm:
            main()
        self.assertEqual(cm.exception.code, 1)
        self.assertIn(
            "Error: Failed to read system file '/nonexistent/file.txt'",
            mock_stderr.getvalue(),
        )


if __name__ == '__main__':
    unittest.main()
