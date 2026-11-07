"""Offline checks for the release-to-tap publisher."""
import base64
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import json
import hashlib

spec = importlib.util.spec_from_file_location('homebrew', Path(__file__).resolve().parents[1] / 'scripts/update-homebrew.py')
homebrew = importlib.util.module_from_spec(spec)
spec.loader.exec_module(homebrew)


class HomebrewChecks(unittest.TestCase):
    def test_render_and_validation(self):
        cask = homebrew.render('v0.4.5', 'a' * 64)
        self.assertIn('version "0.4.5"', cask)
        self.assertIn('sha256 "' + 'a' * 64 + '"', cask)
        self.assertIn('depends_on macos: :sequoia', cask)
        for tag in ['v0.4.5-beta', '../bad', 'latest']:
            with self.assertRaises(ValueError):
                homebrew.render(tag, 'a' * 64)
        with self.assertRaises(ValueError):
            homebrew.render('v0.4.5', 'invalid')

    def run_update(self, checksum_ok=True, current=False, same=False, prerelease=False, draft=False, tag="v0.4.5", missing_entry=False):
        calls = []
        def gh(*args, payload=None):
            calls.append((args, payload))
            if args[0] == 'release':
                folder = Path(args[args.index('--dir') + 1])
                (folder / 'ImmichGallery-0.4.5.dmg').write_bytes(b'dmg')
                checksum = hashlib.sha256(b'dmg').hexdigest() if checksum_ok else '0' * 64
                (folder / 'SHA256SUMS.txt').write_text('' if missing_entry else f'{checksum}  ImmichGallery-0.4.5.dmg\n')
                return ''
            if args[1].endswith('releases/latest'):
                return json.dumps({'draft': draft, 'prerelease': prerelease, 'tag_name': tag})
            if 'git/trees' in args[1]:
                return json.dumps({'tree': [{'path': homebrew.CASK, 'sha': 'abc'}] if current else []})
            if 'git/blobs' in args[1]:
                content = homebrew.render('v0.4.5', hashlib.sha256(b'dmg').hexdigest()) if same else 'old'
                return json.dumps({'content': base64.b64encode(content.encode()).decode()})
            return '{}'
        with patch.object(homebrew, 'gh', gh):
            homebrew.update('v0.4.5')
        return calls

    def test_create_update_and_retry(self):
        self.assertNotIn('sha', self.run_update()[-1][1])
        self.assertEqual(self.run_update(current=True)[-1][1]['sha'], 'abc')
        self.assertIsNone(self.run_update(current=True, same=True)[-1][1])

    def test_reject_bad_checksum_and_prerelease(self):
        with self.assertRaises(ValueError):
            self.run_update(checksum_ok=False)
        with self.assertRaises(ValueError):
            self.run_update(prerelease=True)
        for options in [{'draft': True}, {'tag': 'v0.4.4'}, {'missing_entry': True}]:
            with self.assertRaises(ValueError):
                self.run_update(**options)


if __name__ == '__main__':
    unittest.main()
