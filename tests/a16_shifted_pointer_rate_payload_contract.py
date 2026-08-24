#!/usr/bin/env python3
"""Binary contract for the Android 16 +0x28 shifted pointer payload."""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path


def word(blob: bytes, offset: int) -> int:
    return struct.unpack_from("<I", blob, offset)[0]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} PAYLOAD RELOCATION_MANIFEST")

    payload = Path(sys.argv[1]).read_bytes()
    manifest = Path(sys.argv[2]).read_text(encoding="utf-8")
    assert len(payload) == 256

    # The rate allowlist and transactional commit are identical to the base
    # pointer handler.  Only private StreamOutPrimary member offsets move.
    assert word(payload, 0x28) == 0x5280006B
    assert word(payload, 0x44) == 0x5280008B
    assert word(payload, 0x60) == 0x7946F2AA  # usecase +0x378
    assert word(payload, 0x6C) == 0xF9440AAA  # cached PAL attr +0x810
    assert word(payload, 0x74) == 0xF943C6AB  # AudioPortConfig* +0x788
    assert word(payload, 0x88) == 0xF941E6AA  # PAL handle +0x3c8
    assert word(payload, 0x98) == 0x911EE2A0  # configure mutex +0x7b8
    assert word(payload, 0xAC) == 0x911EE2A0
    assert word(payload, 0xC4) == 0xF9440AAA
    assert word(payload, 0xCC) == 0xF943C6AB

    # Commit order remains value, presence discriminator, then PAL cache.
    assert word(payload, 0xD4) == 0xB9000969
    assert word(payload, 0xDC) == 0x3900316C
    assert word(payload, 0xE0) == 0xB9004149

    expected = {
        "STR_PARMS_GET_STR": (16, "BL"),
        "ATOI": (28, "BL"),
        "MUTEX_LOCK": (156, "BL"),
        "PUDDING_STANDBY": (164, "BL"),
        "MUTEX_UNLOCK": (176, "BL"),
        "PUDDING_RATE_RETURN": (232, "B"),
    }
    for symbol, (offset, kind) in expected.items():
        pattern = rf"^A16_SHIFTED_POINTER_RATE_{symbol}='{offset}:{kind}'$"
        assert re.search(pattern, manifest, re.MULTILINE), symbol

    print("Android 16 shifted pointer-rate payload binary contract: PASS")


if __name__ == "__main__":
    main()
