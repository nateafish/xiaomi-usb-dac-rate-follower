#!/usr/bin/env python3
"""Binary-level safety contract for the Android 16 pointer-rate payload."""

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

    # Exactly three 44.1-kHz-family iterations (44.1/88.2/176.4), then four
    # 48-kHz-family iterations.  This rejects 352.8 kHz consistently with the
    # seven-entry PAL capability list.
    assert word(payload, 0x28) == 0x5280006B  # mov w11, #3
    assert word(payload, 0x44) == 0x5280008B  # mov w11, #4

    # The target-usecase guard must precede every private-state store.
    assert word(payload, 0x60) == 0x7946A2AA  # ldrh w10, [x21, #0x350]
    assert word(payload, 0x64) == 0x71000D5F  # cmp w10, #3
    assert word(payload, 0x68) & 0xFF00001F == 0x54000001  # b.ne

    # The Binder parameter hook may publish only AudioPortConfig intent.  It
    # must not inspect the PAL handle, modify the cached PAL attribute, or call
    # standby while transfer() can be in pal_stream_write().
    assert word(payload, 0x6C) == 0xF943B2AB  # config +0x760 -> x11
    # Rate and optional-presence are one aligned 64-bit release publication.
    assert word(payload, 0x88) == 0x9100216B  # add x11, x11, #8
    assert word(payload, 0x94) == 0xC89FFD69  # stlr x9, [x11]
    assert 0xF941D2AC not in [word(payload, i) for i in range(0, 0xA0, 4)]
    assert 0xB9004149 not in [word(payload, i) for i in range(0, 0xA0, 4)]

    expected = {
        "STR_PARMS_GET_STR": (16, "BL"),
        "ATOI": (28, "BL"),
        "PUDDING_RATE_RETURN": (156, "B"),
    }
    for symbol, (offset, kind) in expected.items():
        pattern = rf"^A16_POINTER_RATE_{symbol}='{offset}:{kind}'$"
        assert re.search(pattern, manifest, re.MULTILINE), symbol

    # transfer() owns live reconfiguration.  It preserves x9/x3/x4, checks
    # case 3, compares requested versus cached rate, calls standby only for a
    # live PAL handle, and commits the cache after successful teardown.
    assert word(worker, 0x04) == 0xA9000FE9  # stp x9, x3, [sp]
    assert word(worker, 0x08) == 0xF9000BE4  # str x4, [sp, #0x10]
    assert word(worker, 0x0C) == 0x7946A2A8  # usecase +0x350
    assert word(worker, 0x18) == 0xF943B2AA  # config +0x760
    assert word(worker, 0x20) == 0x9100214A  # optional-rate slot +8
    assert word(worker, 0x24) == 0xC8DFFD4C  # ldar x12, [x10]
    assert word(worker, 0x28) & 0xFFF8001F == 0xB600000C  # tbz x12, #32
    assert word(worker, 0x2C) == 0xF943F6AB  # cache +0x7e8
    assert word(worker, 0x40) == 0xF9000FEA  # preserve mailbox pointer
    assert word(worker, 0x44) == 0xF941D2AA  # PAL handle +0x3a0
    assert word(worker, 0x5C) == 0xC8DFFD4C  # refresh rate after standby
    assert word(worker, 0x68) == 0xB900416C  # cached rate +0x40
    assert word(worker, 0x78) == 0x39400128  # displaced ldrb w8, [x9]

    worker_expected = {
        "PUDDING_WORKER_STANDBY": (80, "BL"),
        "PUDDING_WORKER_RETURN": (124, "B"),
    }
    for symbol, (offset, kind) in worker_expected.items():
        pattern = rf"^A16_POINTER_RATE_WORKER_{symbol}='{offset}:{kind}'$"
        assert re.search(pattern, worker_manifest, re.MULTILINE), symbol

    print("Android 16 pointer-rate payload binary contract: PASS")


if __name__ == "__main__":
    main()
