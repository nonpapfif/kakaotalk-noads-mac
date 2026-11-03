"""Select explicitly reviewed version profiles; never guess a patch for an unknown build."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
from typing import Any

PROFILE_ROOT = Path(__file__).resolve().parent / 'profiles'
BUNDLE_ID = 'local.elsholtzia.KakaoTalkReconnectExperiment'


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1_048_576), b''):
            value.update(chunk)
    return value.hexdigest()


def load_profile(version: str, build: str, directory: Path = PROFILE_ROOT) -> dict[str, Any]:
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', version) or not re.fullmatch(r'[0-9]+', build):
        raise ValueError('Invalid app version or build')
    path = directory / f'{version}-{build}.json'
    if not path.is_file():
        raise ValueError(f'Unsupported app version: {version} build {build}; review a new profile first')
    profile = json.loads(path.read_text())
    if profile.get('version') != version or profile.get('build') != build:
        raise ValueError('Profile version mismatch')
    if profile.get('approved_for_build') is not True:
        raise ValueError('This compatibility profile has not been approved for building')
    if profile.get('output_bundle_id') != BUNDLE_ID:
        raise ValueError('Profile would change the data container identity')
    if not re.fullmatch(r'[a-f0-9]{64}', profile.get('source_sha256', '')):
        raise ValueError('Profile has an invalid source hash')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', profile.get('minimum_macos', '')):
        raise ValueError('Invalid minimum macOS version')
    if not re.fullmatch(re.escape('v' + version) + r'-reconnect\.[0-9]+',
                        profile.get('patch_release', '')):
        raise ValueError('Invalid patch release tag')
    patches = profile.get('patches', [])
    if not patches:
        raise ValueError('Profile has no patches')
    occupied: set[int] = set()
    for patch in patches:
        offset = int(patch['offset'], 16)
        before, after = bytes.fromhex(patch['before']), bytes.fromhex(patch['after'])
        if offset < 0 or not before or len(before) != len(after):
            raise ValueError('Invalid patch range')
        positions = set(range(offset, offset + len(before)))
        if occupied & positions:
            raise ValueError('Overlapping patch ranges')
        occupied.update(positions)
    return profile


def require_source(profile: dict[str, Any], info: dict[str, Any], executable: Path) -> None:
    if info.get('CFBundleIdentifier') != profile['source_bundle_id']:
        raise ValueError('Expected an unmodified official KakaoTalk application')
    if digest(executable) != profile['source_sha256']:
        raise ValueError('Unknown source hash; do not reuse this profile on a different binary')
