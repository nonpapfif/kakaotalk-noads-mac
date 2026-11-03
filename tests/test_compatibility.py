"""Verify that unsupported sources cannot enter the patch build path."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from compatibility import BUNDLE_ID, load_profile, require_source


class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.profile = load_profile('26.9.0', '2006')

    def test_current_reviewed_profile_keeps_identity_and_all_patch_sites(self):
        self.assertEqual(self.profile['output_bundle_id'], BUNDLE_ID)
        self.assertEqual(len(self.profile['patches']), 10)

    def test_unknown_version_stops(self):
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            load_profile('99.0.0', '9999')

    def test_same_version_with_unknown_source_hash_stops(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / 'KakaoTalk'
            binary.write_bytes(b'unknown build of the same version')
            with self.assertRaisesRegex(ValueError, 'Unknown source hash'):
                require_source(self.profile, {'CFBundleIdentifier': 'com.kakao.KakaoTalkMac'}, binary)

    def test_unreviewed_profile_cannot_build(self):
        profile = copy.deepcopy(self.profile)
        profile['approved_for_build'] = False
        self.assert_profile_rejected(profile, 'not been approved')

    def test_identity_change_is_rejected(self):
        profile = copy.deepcopy(self.profile)
        profile['output_bundle_id'] = 'example.new.identity'
        self.assert_profile_rejected(profile, 'data container')

    def test_overlapping_patch_is_rejected(self):
        profile = copy.deepcopy(self.profile)
        profile['patches'].append(profile['patches'][0])
        self.assert_profile_rejected(profile, 'Overlapping')

    def test_profile_path_traversal_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Invalid'):
            load_profile('../26.9.0', '2006')

    def assert_profile_rejected(self, profile, message):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / '26.9.0-2006.json').write_text(json.dumps(profile))
            with self.assertRaisesRegex(ValueError, message):
                load_profile('26.9.0', '2006', directory)


if __name__ == '__main__':
    unittest.main()
