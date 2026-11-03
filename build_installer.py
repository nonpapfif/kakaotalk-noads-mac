#!/usr/bin/env python3
"""Build a universal self-contained macOS installer from a validated reconnect app."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from compatibility import BUNDLE_ID, load_profile


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1_048_576), b''):
            value.update(chunk)
    return value.hexdigest()


def build(app: Path, output: Path) -> None:
    app = app.resolve(strict=True)
    output = output.absolute()
    if output.exists():
        raise FileExistsError(output)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version, build_number = info['CFBundleShortVersionString'], info['CFBundleVersion']
    profile = load_profile(version, build_number)
    if info['CFBundleIdentifier'] != BUNDLE_ID:
        raise ValueError('Expected the supported reconnect identity')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    output.mkdir(parents=True)
    installer = output / 'Install KakaoTalk.app'
    contents = installer / 'Contents'
    resources = contents / 'Resources'
    resources.mkdir(parents=True)
    (contents / 'MacOS').mkdir()
    root = Path(__file__).resolve().parent
    shutil.copy(root / 'installer/install-app.sh', resources / 'install-app.sh')
    archive = resources / 'KakaoTalk.zip'
    subprocess.run(['ditto', '-c', '-k', '--norsrc', '--keepParent', str(app), str(archive)], check=True)
    manifest = {'version': version, 'build': build_number, 'archive_sha256': digest(archive),
                'executable_sha256': digest(app / 'Contents/MacOS/KakaoTalk'),
                'helper_sha256': digest(app / 'Contents/Frameworks/SessionReconnect.dylib')}
    (resources / 'Payload.json').write_text(json.dumps(manifest, indent=2) + '\n')
    icon = info.get('CFBundleIconFile', '')
    icon_path = app / 'Contents/Resources' / (icon if icon.endswith('.icns') else icon + '.icns')
    installer_info = {
        'CFBundleIdentifier': 'local.elsholtzia.KakaoTalkNoAdsInstaller',
        'CFBundleName': 'Install KakaoTalk', 'CFBundleDisplayName': 'Install KakaoTalk',
        'CFBundleExecutable': 'Installer', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': '1.1.0', 'CFBundleVersion': '2',
        'KakaoTalkPayloadVersion': version,
        'LSMinimumSystemVersion': profile['minimum_macos'], 'NSHighResolutionCapable': True,
    }
    if icon_path.is_file():
        shutil.copy(icon_path, resources / 'Installer.icns')
        installer_info['CFBundleIconFile'] = 'Installer.icns'
    (contents / 'Info.plist').write_bytes(plistlib.dumps(installer_info))
    with tempfile.TemporaryDirectory(prefix='kakao-installer-build-') as temporary:
        thin = []
        for architecture in ('arm64', 'x86_64'):
            binary = Path(temporary) / architecture
            subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path',
                            str(Path(temporary) / 'modules'), '-target',
                            architecture + '-apple-macosx13.0', str(root / 'installer/Installer.swift'),
                            '-o', str(binary)], check=True)
            thin.append(str(binary))
        subprocess.run(['lipo', '-create', *thin, '-output', str(contents / 'MacOS/Installer')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime', str(installer)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(installer)], check=True)
    zip_path = output / f'KakaoTalk-NoAds-Reconnect-Installer-{version}.zip'
    subprocess.run(['ditto', '-c', '-k', '--norsrc', '--keepParent', str(installer), str(zip_path)], check=True)
    zip_path.with_suffix('.sha256').write_text(digest(zip_path) + '  ' + zip_path.name + '\n')
    dmg = output / f'KakaoTalk-NoAds-Reconnect-Installer-{version}.dmg'
    with tempfile.TemporaryDirectory(prefix='kakao-dmg-content-') as temporary:
        staged = Path(temporary) / installer.name
        shutil.copytree(installer, staged, symlinks=True, copy_function=shutil.copy)
        subprocess.run(['hdiutil', 'create', '-srcfolder', temporary, '-volname',
                        'KakaoTalk Installer', '-format', 'UDZO', str(dmg)], check=True)
    (output / 'SHA256SUMS').write_text(''.join(
        digest(path) + '  ' + path.name + '\n' for path in (dmg, zip_path)
    ))
    print(f'Built {installer}, {zip_path}, and {dmg}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.app, args.output)
