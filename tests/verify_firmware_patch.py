#!/usr/bin/env python3
"""Verify the policy patch against a privately supplied exact firmware ELF.

The public repository intentionally does not contain Xiaomi's library. Run:

    python3 tests/verify_firmware_patch.py STOCK_POLICY_SO MODULE_ZIP
"""

import hashlib
import sys
import zipfile
from pathlib import Path


V064_SHA256 = "c3747853afee1ccf0734cf144e84190c4814b88ebe3ea57d2b6ec83c779015ab"
V065_SHA256 = "9dcedf72cb0a682f507495f1f048fc89eec614d842412964d98ebcfd635e645b"

V064_PATCHES = {
    "profile_init_patch.bin": 799_328,
    "is_app_allowed_hook.bin": 867_276,
    "strategy_restore_patch.bin": 869_060,
    "effect_gate_patch.bin": 873_908,
    "preferred_hifi_cave.bin": 800_684,
    "hifi_config_branch.bin": 231_424,
    "preferred_hifi_branch.bin": 350_044,
}

V065_PATCHES = {
    "shared_arbiter_cave.bin": 801_064,
    "shared_arbiter_branch.bin": 874_428,
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require_region(data: bytes, offset: int, expected_hex: str, label: str) -> None:
    expected = bytes.fromhex(expected_hex)
    actual = data[offset : offset + len(expected)]
    assert actual == expected, f"{label}: {actual.hex()} != {expected_hex}"


def apply(data: bytes, patches: dict[str, int], archive: zipfile.ZipFile) -> bytes:
    output = bytearray(data)
    for name, offset in patches.items():
        patch = archive.read(f"patches/{name}")
        output[offset : offset + len(patch)] = patch
    return bytes(output)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} STOCK_POLICY_SO MODULE_ZIP")
    stock = Path(sys.argv[1]).read_bytes()
    assert len(stock) >= 873_924
    assert stock[:20] == bytes.fromhex(
        "7f454c460201010000000000000000000300b700"
    )
    require_region(
        stock,
        874_412,
        "a8024039a90a40f91f0100728303899a",
        "arbiter pre-context",
    )
    require_region(
        stock,
        874_428,
        "d9020036",
        "stock arbiter instruction",
    )
    require_region(
        stock,
        874_432,
        "62faffb042140f9160008052e1031faa",
        "arbiter post-context",
    )
    assert not any(stock[801_058:802_816]), "reserved executable cave is occupied"

    with zipfile.ZipFile(sys.argv[2]) as archive:
        v064 = apply(stock, V064_PATCHES, archive)
        assert sha256(v064) == V064_SHA256
        assert not any(v064[801_058:802_816])

        v065 = apply(v064, V065_PATCHES, archive)
        assert sha256(v065) == V065_SHA256
        assert v065[874_428:874_432].hex() == "5bb8ff17"
        cave = archive.read("patches/shared_arbiter_cave.bin")
        assert len(cave) == 440
        assert v065[801_064 : 801_064 + len(cave)] == cave
        assert not any(v065[801_058:801_064])
        assert not any(v065[801_064 + len(cave) : 802_816])

        # Reapplying an exact patch is byte-idempotent.
        assert apply(v065, V064_PATCHES | V065_PATCHES, archive) == v065

    print("firmware patch verification: stock -> v0.6.4 -> v0.6.5 passed")


if __name__ == "__main__":
    main()
