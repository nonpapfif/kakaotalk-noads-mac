"""Build the standalone, non-sandboxed helper used after KakaoTalk exits."""
from pathlib import Path
import plistlib
import shutil
import subprocess

from tools.build_support import build_universal_swift


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
    build_universal_swift(
        [root / 'updater/UpdateValidation.swift', root / 'updater/Updater.swift'],
        contents / 'MacOS/Updater', warnings_as_errors=True,
    )
    subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime',
                    str(output)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(output)], check=True)
