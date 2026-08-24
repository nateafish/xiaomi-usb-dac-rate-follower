#!/usr/bin/env python3
"""Binary contract for the Android 17 case-3 transfer mutex guard."""

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
    assert len(payload) == 16

    # The same {3, 8, 13} set must guard both setVendorParameters() and
    # transfer().  The relocated TBZ skips the stock mWriteMutex block for all
    # other usecases; matching usecases fall through to the existing lock.
    assert word(payload, 0) == 0x52842109  # mov w9, #0x2108
    assert word(payload, 4) == 0x1AC82529  # lsr w9, w9, w8
    assert word(payload, 8) & 0x7F00001F == 0x36000009  # tbz w9, #0
    assert word(payload, 12) == 0xD503201F  # nop
    assert re.search(
        r"^A17_QTI_TRANSFER_HIFI_TRANSFER_SKIP_LOCK='8:TB14'$",
        manifest,
        re.MULTILINE,
    )

    print("Android 17 QTI transfer-lock binary contract: PASS")


if __name__ == "__main__":
    main()
