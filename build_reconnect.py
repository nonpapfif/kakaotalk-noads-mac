#!/usr/bin/env python3
"""Build the version-locked NoAds client with manual reconnect and a native sidebar button."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

import patch_kakaotalk as base
from compatibility import BUNDLE_ID, load_profile, require_source
from reconnect.inject_load_command import inject



def build(source: Path, output: Path) -> None:
    source = source.resolve(strict=True)
    output = output.absolute()
    if output.exists() or output.is_symlink() or output.suffix != '.app':
        raise ValueError('Output must be a new .app path')
    if source == output or source in output.parents:
        raise ValueError('Output must be outside the source app')
    binary_path = Path('Contents/MacOS/KakaoTalk')
    original = (source / binary_path).read_bytes()
    info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    version, build_number = info['CFBundleShortVersionString'], info['CFBundleVersion']
    profile = load_profile(version, build_number)
    require_source(profile, info, source / binary_path)
    actual_arches = subprocess.check_output(['lipo', '-archs', str(source / binary_path)],
                                            text=True).split()
    if sorted(actual_arches) != sorted(profile['architectures']):
        raise ValueError('Source architectures do not match the reviewed profile')
    if any(name.encode() + b'\0' not in original for name in profile['required_selectors']):
        raise ValueError('A required native selector is absent; review compatibility first')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
    manifest_path = output.with_suffix('.build.json')
    if manifest_path.exists():
        raise FileExistsError(manifest_path)
    patched = bytearray(original)
    changes = []
    for patch in profile['patches']:
        offset = int(patch['offset'], 16)
        before, after, purpose = patch['before'], patch['after'], patch['purpose']
        expected, replacement = bytes.fromhex(before), bytes.fromhex(after)
        if len(expected) != len(replacement) or patched[offset:offset + len(expected)] != expected:
            raise ValueError(f'Patch precondition failed: {purpose}')
        patched[offset:offset + len(expected)] = replacement
        changes.append({'offset': hex(offset), 'before': before, 'after': after, 'purpose': purpose})
    patched = inject(bytes(patched), '@executable_path/../Frameworks/SessionReconnect.dylib')
    root = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix='kakao-reconnect-build-') as temporary:
        directory = Path(temporary)
        helper = directory / 'SessionReconnect.dylib'
        subprocess.run([
            'xcrun', 'clang', '-dynamiclib', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
            '-arch', 'arm64', '-arch', 'x86_64',
            '-mmacosx-version-min=' + profile['minimum_macos'], '-framework',
            'Cocoa', '-install_name', '@rpath/SessionReconnect.dylib',
            str(root / 'reconnect/SessionReconnect.m'), '-o', str(helper),
        ], check=True)
        entitlements = base.arm64_entitlements(original)
        entitlements.pop('com.apple.security.application-groups', None)
        entitlements['com.apple.security.cs.disable-library-validation'] = True
        entitlement_file = directory / 'entitlements.plist'
        entitlement_file.write_bytes(plistlib.dumps(entitlements))
        shutil.copytree(source, output, symlinks=True, copy_function=shutil.copy)
        (output / binary_path).write_bytes(patched)
        shutil.copy(helper, output / 'Contents/Frameworks/SessionReconnect.dylib')
        info.update(CFBundleIdentifier=BUNDLE_ID, CFBundleName='KakaoTalk', CFBundleDisplayName='KakaoTalk')
        (output / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        receipt = output / 'Contents/_MASReceipt'
        if receipt.exists():
            shutil.rmtree(receipt)
        subprocess.run(['codesign', '--force', '--deep', '--sign', '-', '--options', 'runtime',
                        '--entitlements', str(entitlement_file), str(output)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(output)], check=True)
    if hashlib.sha256((source / binary_path).read_bytes()).hexdigest() != profile['source_sha256']:
        raise RuntimeError('Source changed during build')
    manifest_path.write_text(json.dumps({
        'version': version, 'build': build_number, 'bundle_id': BUNDLE_ID,
        'source_sha256': profile['source_sha256'], 'patches': changes,
        'executable_sha256': hashlib.sha256((output / binary_path).read_bytes()).hexdigest(),
        'helper_sha256': hashlib.sha256((output / 'Contents/Frameworks/SessionReconnect.dylib').read_bytes()).hexdigest(),
        'user_data_copied': False,
    }, indent=2) + '\n')
    print(f'Built {output}; source and user data were not modified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.source, args.output)
