#!/usr/bin/env python3
"""Build an isolated, version-locked KakaoTalk copy without main-window banners."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import shutil
import struct
import subprocess
from pathlib import Path

EXPECTED_SHA256 = "456e1a3ed7a87168888bdb8c6e4894764a028e62c0af68562a760d9909d2bb65"
ISOLATED_BUNDLE_ID = "local.elsholtzia.KakaoTalkNoAds"
PATCHES = (
    (0x111388C, "ff5610", "31c090", "x86_64 banner eligibility"),
    (0xE2D07C, "e8cf7fe5ff", "31c0909090", "x86_64 separator visibility"),
    (0xE2D0DD, "e86e7fe5ff", "31c0909090", "x86_64 separator height"),
    (0x378A558, "00013fd6", "00008052", "arm64 banner eligibility"),
    (0x350067C, "8d37fa97", "00008052", "arm64 separator visibility"),
    (0x35006D8, "7637fa97", "00008052", "arm64 separator height"),
)


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def arm64_entitlements(binary: bytes) -> dict[str, object]:
    """Read the XML entitlements from the original arm64 code signature."""
    if binary[:4] != b"\xca\xfe\xba\xbe":
        raise ValueError("Expected a 32-bit universal Mach-O header")
    count = struct.unpack_from(">I", binary, 4)[0]
    for index in range(count):
        cpu, _, offset, size, _ = struct.unpack_from(">IIIII", binary, 8 + index * 20)
        if cpu != 0x100000C:
            continue
        image = binary[offset : offset + size]
        cursor = 32
        commands = struct.unpack_from("<I", image, 16)[0]
        for _ in range(commands):
            command, length = struct.unpack_from("<II", image, cursor)
            if command == 0x1D:
                signature = struct.unpack_from("<I", image, cursor + 8)[0]
                slots = struct.unpack_from(">I", image, signature + 8)[0]
                for slot_index in range(slots):
                    slot, position = struct.unpack_from(
                        ">II", image, signature + 12 + slot_index * 8
                    )
                    if slot == 5:
                        start = signature + position
                        blob_length = struct.unpack_from(">I", image, start + 4)[0]
                        result = plistlib.loads(image[start + 8 : start + blob_length])
                        if not isinstance(result, dict):
                            raise ValueError("Invalid entitlement dictionary")
                        return result
            cursor += length
    raise ValueError("Original arm64 XML entitlements were not found")


def build(source: Path, output: Path) -> None:
    source = source.resolve(strict=True)
    output = output.absolute()
    if output.exists() or output.is_symlink():
        raise FileExistsError(f"Refusing to overwrite: {output}")
    if output.suffix != ".app":
        raise ValueError("Output must end in .app")
    if output == source or source in output.parents:
        raise ValueError("Output must be outside the source app")
    entitlement_file = output.with_suffix(".entitlements.plist")
    manifest_file = output.with_suffix(".patch.json")
    for sidecar in (entitlement_file, manifest_file):
        if sidecar.exists():
            raise FileExistsError(f"Refusing to overwrite: {sidecar}")

    executable = Path("Contents/MacOS/KakaoTalk")
    original = (source / executable).read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError(f"Unsupported source executable SHA-256: {digest}")
    info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
    if (info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != (
        "26.9.0", "2006"
    ):
        raise ValueError("Unsupported app version")

    patched = bytearray(original)
    manifest = []
    for offset, before_hex, after_hex, purpose in PATCHES:
        before, after = bytes.fromhex(before_hex), bytes.fromhex(after_hex)
        if len(before) != len(after) or patched[offset : offset + len(before)] != before:
            raise ValueError(f"Patch precondition failed at {offset:#x}")
        patched[offset : offset + len(before)] = after
        manifest.append(
            {"offset": hex(offset), "before": before_hex, "after": after_hex, "purpose": purpose}
        )

    # copy retains executable modes without copying resource forks or Finder metadata.
    shutil.copytree(source, output, symlinks=True, copy_function=shutil.copy)
    (output / executable).write_bytes(patched)
    info["CFBundleIdentifier"] = ISOLATED_BUNDLE_ID
    info["CFBundleName"] = "KakaoTalk"
    info["CFBundleDisplayName"] = "KakaoTalk"
    (output / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    entitlements = arm64_entitlements(original)
    entitlements.pop("com.apple.security.application-groups", None)
    entitlements["com.apple.security.cs.disable-library-validation"] = True
    entitlement_file.write_bytes(plistlib.dumps(entitlements))
    run(
        "codesign", "--force", "--deep", "--sign", "-", "--options", "runtime",
        "--entitlements", str(entitlement_file), str(output)
    )
    run("codesign", "--verify", "--deep", "--strict", str(output))
    if hashlib.sha256((source / executable).read_bytes()).hexdigest() != digest:
        raise RuntimeError("Source executable changed during build")
    manifest_file.write_text(
        json.dumps(
            {
                "source_sha256": digest,
                "output": str(output),
                "patches": manifest,
                "status": "main-window UI verified on arm64; other features unverified",
                "bundle_id": ISOLATED_BUNDLE_ID,
                "sandbox": "retained; isolated container; original app-group entitlement removed",
                "library_validation_exception": "test copy only",
            }, indent=2
        ) + "\n"
    )
    print(f"Created experimental copy: {output}")
    print("The source app was not modified. The output was not launched.")
    print("Uses a separate sandbox container. Sign in inside the new app.")
    print("Main-window banners were verified on arm64. Read README.md for limits.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("/Applications/KakaoTalk.app"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.source, args.output)


if __name__ == "__main__":
    main()
