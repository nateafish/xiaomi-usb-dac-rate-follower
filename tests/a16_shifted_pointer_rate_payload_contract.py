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
    if len(sys.argv) != 5:
        raise SystemExit(
            f"usage: {sys.argv[0]} PARAMETER PARAMETER_RELOCS WORKER WORKER_RELOCS"
        )

    payload = Path(sys.argv[1]).read_bytes()
    manifest = Path(sys.argv[2]).read_text(encoding="utf-8")
    worker = Path(sys.argv[3]).read_bytes()
    worker_manifest = Path(sys.argv[4]).read_text(encoding="utf-8")
    assert len(payload) == 256
    assert len(worker) == 128

    # The rate allowlist and parameter-only publication are identical to the
    # base pointer handler.  Only private StreamOutPrimary member offsets move.
    assert word(payload, 0x28) == 0x5280006B
    assert word(payload, 0x44) == 0x5280008B
    assert word(payload, 0x60) == 0x7946F2AA  # usecase +0x378
    assert word(payload, 0x6C) == 0xF943C6AB  # AudioPortConfig* +0x788
    assert word(payload, 0x88) == 0xB9000969
    assert word(payload, 0x90) == 0x3900316C

    expected = {
        "STR_PARMS_GET_STR": (16, "BL"),
        "ATOI": (28, "BL"),
        "PUDDING_RATE_RETURN": (152, "B"),
    }
    for symbol, (offset, kind) in expected.items():
        pattern = rf"^A16_SHIFTED_POINTER_RATE_{symbol}='{offset}:{kind}'$"
        assert re.search(pattern, manifest, re.MULTILINE), symbol

    assert word(worker, 0x04) == 0xA9000FE9
    assert word(worker, 0x08) == 0xF9000BE4
    assert word(worker, 0x0C) == 0x7946F2E8  # usecase +0x378, this=x23
    assert word(worker, 0x18) == 0xF943C6EA  # config +0x788
    assert word(worker, 0x2C) == 0xF9440AEB  # cache +0x810
    assert word(worker, 0x40) == 0xF941E6EA  # PAL handle +0x3c8
    assert word(worker, 0x4C) == 0xAA1703E0  # standby(this=x23)
    assert word(worker, 0x5C) == 0xF9440AEB  # cache reload
    assert word(worker, 0x64) == 0xB900416C
    assert word(worker, 0x74) == 0x39400128

    worker_expected = {
        "PUDDING_WORKER_STANDBY": (80, "BL"),
        "PUDDING_WORKER_RETURN": (120, "B"),
    }
    for symbol, (offset, kind) in worker_expected.items():
        pattern = rf"^A16_SHIFTED_POINTER_RATE_WORKER_{symbol}='{offset}:{kind}'$"
        assert re.search(pattern, worker_manifest, re.MULTILINE), symbol

    print("Android 16 shifted pointer-rate payload binary contract: PASS")


if __name__ == "__main__":
    main()
