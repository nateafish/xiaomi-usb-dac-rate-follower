#!/usr/bin/env python3
"""Behavioral model for the final sampling-rate USB transport gate."""

from dataclasses import dataclass


USB = frozenset({0x2000, 0x4000, 0x04000000})
IDLE_HANDOFF = 1


@dataclass(frozen=True)
class Output:
    handle: int
    devices: tuple[int, ...]
    active: bool = False


def decision(rate: int, selected: int, outputs: list[Output]) -> str:
    if rate == 0:
        return "stock-zero"
    if not 0 < len(outputs) <= 64:
        return "deny"
    output = next((item for item in outputs if item.handle == selected), None)
    if output is None or not 0 < len(output.devices) <= 16:
        return "deny"
    if not all(device in USB for device in output.devices):
        return "deny"
    if rate != IDLE_HANDOFF:
        return "send"
    return "send-48000" if any(
        item.handle != selected
        and item.active
        and item.devices
        and all(device in USB for device in item.devices)
        for item in outputs
    ) else "deny-idle"


def main() -> None:
    usb = Output(117, (0x04000000,), active=True)
    usb_pair = Output(117, (0x2000, 0x4000), active=True)
    bluetooth = Output(21, (0x80,))
    mixed = Output(21, (0x04000000, 0x80))
    idle_hifi = Output(117, (0x04000000,))
    active_deep = Output(21, (0x04000000,), active=True)
    active_speaker = Output(13, (0x2,), active=True)

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
    assert decision(48_000, 117, [idle_hifi]) == "send"
    assert decision(IDLE_HANDOFF, 117, [idle_hifi]) == "deny-idle"
    assert decision(IDLE_HANDOFF, 117, [idle_hifi, active_deep]) == "send-48000"
    assert decision(IDLE_HANDOFF, 117, [idle_hifi, active_speaker]) == "deny-idle"
    assert decision(44_100, 117, [idle_hifi]) == "send"

    print("USB transport gate model: 15 route, marker, activity and bound cases passed")


if __name__ == "__main__":
    main()
