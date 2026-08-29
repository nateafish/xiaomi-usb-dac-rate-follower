#!/usr/bin/env python3
"""Binary contract for the Android 17 case-3 worker handoff payload."""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path


def words(blob: bytes) -> list[int]:
    assert len(blob) % 4 == 0
    return list(struct.unpack(f"<{len(blob) // 4}I", blob))


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} PAYLOAD RELOCATION_MANIFEST")

    payload = Path(sys.argv[1]).read_bytes()
    manifest = Path(sys.argv[2]).read_text(encoding="utf-8")
    payload_words = words(payload)

    assert len(payload) == 768
    assert 0xC85FFD4B in payload_words  # ldaxr x11, [x10]
    assert 0xC80EFD4B in payload_words  # stlxr w14, x11, [x10]
    assert 0xC8DFFD2A in payload_words  # ldar x10, [x9]
    assert 0xC8EDFD2B in payload_words  # casal x13, x11, [x9]
    assert 0xF941E6E8 in payload_words  # ldr x8, [x23, #0x3c8]
    assert 0xB900410A in payload_words  # str w10, [x8, #0x40]
    assert 0x9125E2E0 not in payload_words  # no case-3 mutex +0x978

    expected = {
        "A17_LOCKFREE_A17_PARAMETER_STOCK_RESUME": "16:B",
        "A17_LOCKFREE_ATOI": "32:BL",
        "A17_LOCKFREE_A17_PARAMETER_SKIP_STANDBY": "192:B",
        "A17_LOCKFREE_A17_TRANSFER_LOCK_ENTRY": "224:B",
        "A17_LOCKFREE_A17_WORKER_STANDBY": "288:BL",
        "A17_LOCKFREE_A17_TRANSFER_SKIP_LOCK": "356:B",
        "A17_LOCKFREE_SYMBOL_A17_LOCKFREE_PARAMETER_HOOK": "0",
        "A17_LOCKFREE_SYMBOL_A17_LOCKFREE_TRANSFER_HOOK": "196",
    }
    for name, value in expected.items():
        assert re.search(rf"^{name}='{re.escape(value)}'$", manifest, re.MULTILINE)

    print("Android 17 lock-free payload binary contract: PASS")


if __name__ == "__main__":
    main()
