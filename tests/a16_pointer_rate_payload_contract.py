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
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} PAYLOAD RELOCATION_MANIFEST")

    payload = Path(sys.argv[1]).read_bytes()
    manifest = Path(sys.argv[2]).read_text(encoding="utf-8")
    assert len(payload) == 256

    # Exactly three 44.1-kHz-family iterations (44.1/88.2/176.4), then four
    # 48-kHz-family iterations.  This rejects 352.8 kHz consistently with the
    # seven-entry PAL capability list.
    assert word(payload, 0x28) == 0x5280006B  # mov w11, #3
    assert word(payload, 0x44) == 0x5280008B  # mov w11, #4

    # The target-usecase guard must precede every private-state store.
    assert word(payload, 0x60) == 0x7946A2AA  # ldrh w10, [x21, #0x350]
    assert word(payload, 0x64) == 0x71000D5F  # cmp w10, #3
    assert word(payload, 0x68) & 0xFF00001F == 0x54000001  # b.ne

    # Calls use an aligned private frame; a failed standby reaches the stock
    # return without publishing a new rate.  Commit order is value, presence,
    # then cached PAL attribute.
    assert word(payload, 0x90) == 0xD10043FF  # sub sp, sp, #16
    assert word(payload, 0xBC) == 0x910043FF  # add sp, sp, #16
    assert word(payload, 0xC0) & 0x7F000000 == 0x35000000  # cbnz
    assert word(payload, 0xD4) == 0xB9000969  # str w9, [x11, #8]
    assert word(payload, 0xDC) == 0x3900316C  # strb w12, [x11, #0xc]
    assert word(payload, 0xE0) == 0xB9004149  # str w9, [x10, #0x40]

    expected = {
        "STR_PARMS_GET_STR": (16, "BL"),
        "ATOI": (28, "BL"),
        "MUTEX_LOCK": (156, "BL"),
        "PUDDING_STANDBY": (164, "BL"),
        "MUTEX_UNLOCK": (176, "BL"),
        "PUDDING_RATE_RETURN": (232, "B"),
    }
    for symbol, (offset, kind) in expected.items():
        pattern = rf"^A16_POINTER_RATE_{symbol}='{offset}:{kind}'$"
        assert re.search(pattern, manifest, re.MULTILINE), symbol

    print("Android 16 pointer-rate payload binary contract: PASS")


if __name__ == "__main__":
    main()
