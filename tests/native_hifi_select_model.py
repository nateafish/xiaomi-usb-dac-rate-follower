#!/usr/bin/env python3
"""Behavioral model for the native selectOutput HIFI override."""

from dataclasses import dataclass


USB = frozenset({0x2000, 0x4000, 0x04000000})
ALLOWED = frozenset({"com.apple.android.music", "com.netease.cloudmusic"})


@dataclass(frozen=True)
class Output:
    handle: int
    profile: str | None
    devices: tuple[int, ...]


def usb_only(output: Output | None) -> bool:
    return bool(output and output.devices and all(d in USB for d in output.devices))


def select(package: str, selected: int, outputs: list[Output]) -> int:
    if package not in ALLOWED or not 0 < len(outputs) <= 64:
        return selected
    by_handle = {output.handle: output for output in outputs}
    selected_output = by_handle.get(selected)
    if not selected_output or selected_output.profile is None or not usb_only(selected_output):
        return selected
    for output in outputs:
        if output.profile == "hifi_playback" and usb_only(output):
            return output.handle
    return selected


def latest_max_rate(application_counts: list[int], retained_rates: list[int]) -> int:
    """Model the native idle gate before Xiaomi's retained rate-tree lookup."""
    if not any(count >= 1 for count in application_counts):
        return 48_000
    return max(retained_rates) if retained_rates else 48_000


def main() -> None:
    deep_usb = Output(21, "deep_buffer_out", (0x04000000,))
    hifi_usb = Output(117, "hifi_playback", (0x04000000,))
    hifi_empty = Output(117, "hifi_playback", ())
    duplicate = Output(125, None, ())
    duplicate_usb = Output(125, None, (0x04000000,))
    deep_bt = Output(21, "deep_buffer_out", (0x80,))
    deep_speaker = Output(21, "deep_buffer_out", (0x2,))
    deep_mixed = Output(21, "deep_buffer_out", (0x04000000, 0x80))

    assert select("com.netease.cloudmusic", 21, [deep_usb, hifi_usb]) == 117
    assert select("com.apple.android.music", 21, [deep_usb, hifi_usb]) == 117
    assert select("com.netease.cloudmusic", 117, [deep_usb, hifi_usb]) == 117
    assert select("com.example.player", 21, [deep_usb, hifi_usb]) == 21
    assert select("com.netease.cloudmusic", 21, [deep_bt, hifi_usb]) == 21
    assert select("com.netease.cloudmusic", 21, [deep_speaker, hifi_usb]) == 21
    assert select("com.netease.cloudmusic", 21, [deep_mixed, hifi_usb]) == 21
    assert select("com.netease.cloudmusic", 21, [deep_usb, hifi_empty]) == 21
    assert select("com.netease.cloudmusic", 21, [deep_usb, duplicate]) == 21
    assert select("com.netease.cloudmusic", 125, [duplicate_usb, hifi_usb]) == 125
    assert select("com.netease.cloudmusic", 21, []) == 21
    assert select("com.netease.cloudmusic", 21, [deep_usb] * 65) == 21

    # Xiaomi can retain a synthetic 384 kHz rate node after every real app has
    # stopped.  Application counts, not rate-tree occupancy, define idle.
    assert latest_max_rate([], [384_000]) == 48_000
    assert latest_max_rate([0, 0], [384_000]) == 48_000
    assert latest_max_rate([1], [44_100, 384_000]) == 384_000
    assert latest_max_rate([1], [44_100, 96_000]) == 96_000

    print("native HIFI selection and idle model: 16 cases passed")


if __name__ == "__main__":
    main()
