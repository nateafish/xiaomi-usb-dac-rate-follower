#!/usr/bin/env python3
"""Generate installer relocation offsets from an AArch64 object file."""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


PATCH_TYPES = {
    "R_AARCH64_CALL26": "BL",
    "R_AARCH64_JUMP26": "B",
    "R_AARCH64_CONDBR19": "COND19",
    "R_AARCH64_TSTBR14": "TB14",
}


def parse_expected(values: list[str]) -> dict[str, str]:
    expected: dict[str, str] = {}
    for value in values:
        try:
            symbol, relocation_type = value.split("=", 1)
        except ValueError as error:
            raise SystemExit(f"invalid --expect value: {value}") from error
        if symbol in expected:
            raise SystemExit(f"duplicate expected symbol: {symbol}")
        expected[symbol] = relocation_type
    return expected


def parse_relocations(readelf: str, obj: Path, section: str) -> dict[str, tuple[str, int]]:
    output = subprocess.run(
        [readelf, "--wide", "--relocs", str(obj)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    current_section = ""
    relocations: dict[str, tuple[str, int]] = {}
    for line in output.splitlines():
        header = re.match(r"Relocation section '([^']+)'", line)
        if header:
            current_section = header.group(1)
            continue
        if current_section != section:
            continue
        entry = re.match(
            r"^([0-9a-fA-F]+)\s+\S+\s+(R_AARCH64_\S+)\s+"
            r"[0-9a-fA-F]+\s+(\S+)\s+\+",
            line,
        )
        if not entry:
            continue
        offset = int(entry.group(1), 16)
        relocation_type = entry.group(2)
        symbol = entry.group(3)
        if symbol in relocations:
            raise SystemExit(f"duplicate relocation for {symbol} in {section}")
        relocations[symbol] = (relocation_type, offset)
    return relocations


def parse_symbols(readelf: str, obj: Path) -> dict[str, int]:
    output = subprocess.run(
        [readelf, "--wide", "--symbols", str(obj)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    symbols: dict[str, int] = {}
    for line in output.splitlines():
        entry = re.match(
            r"^\s*\d+:\s+([0-9a-fA-F]+)\s+\d+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)$",
            line,
        )
        if entry:
            symbols[entry.group(2)] = int(entry.group(1), 16)
    return symbols


def variable_name(prefix: str, symbol: str) -> str:
    return f"{prefix}_{re.sub(r'[^A-Za-z0-9_]', '_', symbol).upper()}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--readelf", required=True)
    parser.add_argument("--object", type=Path, required=True)
    parser.add_argument("--section", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect", action="append", default=[])
    parser.add_argument("--symbol", action="append", default=[])
    args = parser.parse_args()

    expected = parse_expected(args.expect)
    actual = parse_relocations(args.readelf, args.object, args.section)
    if set(actual) != set(expected):
        missing = sorted(set(expected) - set(actual))
        unexpected = sorted(set(actual) - set(expected))
        raise SystemExit(
            f"{args.section} relocation symbols changed; "
            f"missing={missing}, unexpected={unexpected}"
        )

    lines = ["# Generated from the object-file relocation table; do not edit."]
    for symbol, wanted_type in expected.items():
        actual_type, offset = actual[symbol]
        if actual_type != wanted_type:
            raise SystemExit(
                f"{symbol}: expected {wanted_type}, found {actual_type}"
            )
        try:
            patch_type = PATCH_TYPES[actual_type]
        except KeyError as error:
            raise SystemExit(f"unsupported relocation type: {actual_type}") from error
        lines.append(f"{variable_name(args.prefix, symbol)}='{offset}:{patch_type}'")
    symbols = parse_symbols(args.readelf, args.object)
    for symbol in args.symbol:
        if symbol not in symbols:
            raise SystemExit(f"missing object symbol: {symbol}")
        lines.append(
            f"{variable_name(args.prefix, f'SYMBOL_{symbol}')}='{symbols[symbol]}'"
        )
    args.output.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
