#!/usr/bin/env python3
"""Verify the Dada hooks preserve the stock call site's live registers."""

from pathlib import Path
import sys


def require_once(blob: bytes, pattern: bytes, description: str) -> None:
    count = blob.count(pattern)
    if count != 1:
        raise SystemExit(f"{description}: expected once, found {count}")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: dada_payload_binary_contract.py PARAMETER_BIN WORKER_BIN")

    parameter = Path(sys.argv[1]).read_bytes()
    worker = Path(sys.argv[2]).read_bytes()

    # sub sp,#16; stp x1,x2,[sp]
    if not parameter.startswith(bytes.fromhex("ff4300d1e10b00a9")):
        raise SystemExit("Dada parameter hook does not save stock x1/x2")
    # ldp x1,x2,[sp]; add sp,#16; mov x0,x22
    require_once(
        parameter,
        bytes.fromhex("e10b40a9ff430091e00316aa"),
        "Dada parameter resume sequence",
    )

    # sub sp,#16; str x9,[sp]
    if not worker.startswith(bytes.fromhex("ff4300d1e90300f9")):
        raise SystemExit("Dada worker hook does not use a private stack frame")
    # ldr x9,[sp]; add sp,#16; mov w8,wzr
    require_once(
        worker,
        bytes.fromhex("e90340f9ff430091e8031f2a"),
        "Dada worker resume sequence",
    )
    # Binder -> writer handoff is one aligned optional-rate word using a
    # release store and acquire load, never two independent plain accesses.
    require_once(parameter, bytes.fromhex("49fd9fc8"), "Dada release publication")
    if worker.count(bytes.fromhex("4cfddfc8")) != 2:
        raise SystemExit("Dada worker must acquire the mailbox before and after standby")
    print("Dada payload binary contract: PASS")


if __name__ == "__main__":
    main()
