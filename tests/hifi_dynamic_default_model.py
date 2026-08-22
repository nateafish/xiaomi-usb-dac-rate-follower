#!/usr/bin/env python3
"""Model the fail-closed profile-name decision in the dynamic-open hook."""


def selected_rate(profile_name: str | None, picked_rate: int) -> int:
    if profile_name == "hifi_playback":
        return 48_000
    return picked_rate


def main() -> None:
    cases = {
        ("hifi_playback", 384_000): 48_000,
        ("hifi_playback", 192_000): 48_000,
        ("deep_buffer_out", 48_000): 48_000,
        ("direct_pcm_out", 192_000): 192_000,
        ("usb_accessory output", 96_000): 96_000,
        ("hifi_playback_extra", 384_000): 384_000,
        ("", 384_000): 384_000,
        (None, 384_000): 384_000,
    }
    for (profile, picked), expected in cases.items():
        actual = selected_rate(profile, picked)
        assert actual == expected, (profile, picked, actual, expected)
    print(f"HIFI dynamic-default model: {len(cases)} exact/fail-closed cases passed")


if __name__ == "__main__":
    main()
