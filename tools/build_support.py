"""Compile the universal Swift executables shared by the installer and updater."""
from collections.abc import Sequence
from pathlib import Path
import subprocess
import tempfile


def build_universal_swift(
    sources: Sequence[Path], output: Path, *, warnings_as_errors: bool = False
) -> None:
    with tempfile.TemporaryDirectory(prefix='kakao-swift-build-') as temporary:
        directory = Path(temporary)
        binaries = []
        for architecture in ('arm64', 'x86_64'):
            binary = directory / architecture
            command = ['xcrun', 'swiftc', '-O']
            if warnings_as_errors:
                command.append('-warnings-as-errors')
            command.extend([
                '-module-cache-path', str(directory / 'modules'),
                '-target', architecture + '-apple-macosx13.0',
                *(str(source) for source in sources), '-o', str(binary),
            ])
            subprocess.run(command, check=True)
            binaries.append(str(binary))
        subprocess.run(['lipo', '-create', *binaries, '-output', str(output)], check=True)
