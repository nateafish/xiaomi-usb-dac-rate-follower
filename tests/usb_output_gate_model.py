#!/usr/bin/env python3
"""Behavioral model for the final sampling-rate USB transport gate."""

from dataclasses import dataclass


USB = frozenset({0x2000, 0x4000, 0x04000000})


@dataclass(frozen=True)
class Output:
    handle: int
    devices: tuple[int, ...]


def decision(rate: int, selected: int, outputs: list[Output]) -> str:
    if rate == 0:
        return "stock-zero"
    if not 0 < len(outputs) <= 64:
        return "deny"
    output = next((item for item in outputs if item.handle == selected), None)
    if output is None or not 0 < len(output.devices) <= 16:
        return "deny"
    return "send" if all(device in USB for device in output.devices) else "deny"


def main() -> None:
    usb = Output(117, (0x04000000,))
    usb_pair = Output(117, (0x2000, 0x4000))
    bluetooth = Output(21, (0x80,))
    mixed = Output(21, (0x04000000, 0x80))

    assert decision(44_100, 117, [usb]) == "send"
    assert decision(96_000, 117, [usb_pair]) == "send"
    assert decision(0, 21, [bluetooth]) == "stock-zero"
    assert decision(48_000, 21, [bluetooth]) == "deny"
    assert decision(48_000, 21, [mixed]) == "deny"
    assert decision(48_000, 999, [usb]) == "deny"
    assert decision(48_000, 117, [Output(117, ())]) == "deny"
    assert decision(48_000, 117, [Output(117, (0x4000,) * 17)]) == "deny"
    assert decision(48_000, 117, []) == "deny"
    assert decision(48_000, 117, [usb] * 65) == "deny"

    print("USB transport gate model: 10 route and bound cases passed")


if __name__ == "__main__":
    main()
