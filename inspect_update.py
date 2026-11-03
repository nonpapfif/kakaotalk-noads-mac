#!/usr/bin/env python3
"""Inspect a candidate app without modifying it, installing it, or reading user data."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import plistlib
import subprocess

from compatibility import digest, load_profile, require_source


def inspect(app: Path) -> dict[str, object]:
    app = app.resolve(strict=True)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    binary = app / 'Contents/MacOS/KakaoTalk'
    version = str(info['CFBundleShortVersionString'])
    build = str(info['CFBundleVersion'])
    arches = subprocess.check_output(['lipo', '-archs', str(binary)], text=True).split()
    signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)],
                               capture_output=True)
    report: dict[str, object] = {
        'version': version, 'build': build, 'bundle_id': info.get('CFBundleIdentifier'),
        'executable_sha256': digest(binary), 'architectures': arches,
        'code_signature_valid': signature.returncode == 0,
        'app_modified_by_inspector': False, 'user_data_read': False, 'build_allowed': False,
    }
    try:
        profile = load_profile(version, build)
        require_source(profile, info, binary)
    except ValueError as error:
        report['blocking_reason'] = str(error)
        return report
    content = binary.read_bytes()
    selectors = {name: name.encode() + b'\0' in content for name in profile['required_selectors']}
    patches = {patch['purpose']: content[int(patch['offset'], 16):
                int(patch['offset'], 16) + len(bytes.fromhex(patch['before']))] ==
                bytes.fromhex(patch['before']) for patch in profile['patches']}
    report.update({
        'selector_name_presence': selectors,
        'selector_check_limit': 'Names alone do not prove class ownership, ABI, or runtime behavior',
        'original_patch_bytes_match': patches,
        'build_allowed': signature.returncode == 0 and sorted(arches) ==
                         sorted(profile['architectures']) and all(selectors.values()) and
                         all(patches.values()),
        'validation_scope': profile['validation_scope'],
    })
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    result = inspect(args.app)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f"Wrote {args.output}; build_allowed={result['build_allowed']}")
