"""Build the standalone, non-sandboxed helper used after KakaoTalk exits."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


def build(output: Path) -> None:
    if output.exists():
        raise FileExistsError(output)
    root = Path(__file__).resolve().parents[1]
    contents = output / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Resources').mkdir()
    (contents / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'local.elsholtzia.KakaoTalkUpdater',
        'CFBundleName': 'KakaoTalk Updater', 'CFBundleExecutable': 'Updater',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0.0',
        'CFBundleVersion': '2', 'LSMinimumSystemVersion': '13.0', 'LSUIElement': True,
        'CFBundleDocumentTypes': [{'CFBundleTypeName': 'KakaoTalk update launch',
                                  'CFBundleTypeRole': 'Viewer',
                                  'LSItemContentTypes': ['com.apple.property-list']}],
    }))
    shutil.copy(root / 'installer/install-app.sh', contents / 'Resources/install-app.sh')
    with tempfile.TemporaryDirectory(prefix='kakao-updater-build-') as temporary:
        directory = Path(temporary)
        binaries = []
        for arch in ('arm64', 'x86_64'):
            binary = directory / arch
            subprocess.run(['xcrun', 'swiftc', '-O', '-warnings-as-errors',
                            '-module-cache-path', str(directory / 'modules'), '-target',
                            arch + '-apple-macosx13.0', str(root / 'updater/UpdateValidation.swift'),
                            str(root / 'updater/Updater.swift'), '-o', str(binary)], check=True)
            binaries.append(str(binary))
        subprocess.run(['lipo', '-create', *binaries, '-output',
                        str(contents / 'MacOS/Updater')], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime',
                    str(output)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(output)], check=True)
