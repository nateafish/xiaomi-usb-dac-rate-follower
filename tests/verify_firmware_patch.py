#!/usr/bin/env python3
"""Apply v0.7.8 blobs to private stock captures and verify exact regions."""

import sys
import zipfile
from pathlib import Path


POLICY_PATCHES = {
    "native_hifi_cave.bin": 800_684,
    "usb_output_gate_cave.bin": 801_504,
    "usb_output_arbitration_cave.bin": 801_732,
    "select_output_branch.bin": 356_884,
    "hifi_app_branch.bin": 867_276,
    "usb_output_gate_branch.bin": 515_988,
    "latest_max_final_stop_patch.bin": 864_416,
    "latest_max_idle_rate_patch.bin": 865_840,
    "hifi_dynamic_default_branch.bin": 432_224,
    "hifi_dynamic_default_cave.bin": 801_644,
    "hifi_idle_rate_cave.bin": 801_472,
    "hifi_idle_rate_branch.bin": 873_596,
}
FLINGER_PATCHES = {"flinger_sync_patch.bin": 1_772_164}
USB_PATCHES = {"usb_441_patch.bin": 29_024, "usb_3528_patch.bin": 29_052}
HAL_PATCHES = {
    "hifi_usecase_reconfigure_patch.bin": 2_295_956,
    "hifi_frame_count_stock.bin": 2_595_800,
}


def require(data: bytes, offset: int, expected_hex: str, label: str) -> None:
    expected = bytes.fromhex(expected_hex)
    actual = data[offset : offset + len(expected)]
    assert actual == expected, f"{label}: {actual.hex()} != {expected_hex}"


def apply(data: bytes, patches: dict[str, int], archive: zipfile.ZipFile) -> bytes:
    result = bytearray(data)
    for name, offset in patches.items():
        blob = archive.read(f"patches/{name}")
        result[offset : offset + len(blob)] = blob
    return bytes(result)


def main() -> None:
    if len(sys.argv) != 8:
        raise SystemExit(
            f"usage: {sys.argv[0]} POLICY FLINGER USB HAL COMPONENTS XIAOMI_IMPL MODULE_ZIP"
        )
    policy, flinger, usb, hal, components, impl = (
        Path(path).read_bytes() for path in sys.argv[1:7]
    )
    archive_path = sys.argv[7]

    require(policy, 356_864,
            "a14240f9a2021291a3a20291a43300d1e00315aa", "select setup")
    require(policy, 356_884, "bf0b0294", "stock vendor callback")
    require(policy, 867_276, "3f2303d5", "stock app filter entry")
    require(policy, 515_988, "e20a0034", "stock sender entry")
    require(policy, 864_416, "acffff17", "stock final-stop result")
    require(policy, 865_840, "a80100b4", "stock idle-rate branch")
    require(policy, 432_224, "e0e340fd", "stock dynamic-profile continuation")
    assert not any(policy[800_684:801_730]), "reserved policy cave is occupied"
    assert not any(policy[801_732:802_024]), "USB arbitration cave is occupied"
    require(flinger, 1_772_164, "480d0054", "stock Mixer sync branch")
    require(usb, 29_024, "20620500", "stock USB 352.8 slot")
    require(usb, 29_052, "44ac0000", "stock USB 44.1 slot")
    require(hal, 2_295_956,
            "1f350071600000541f210071e1010054", "stock HIFI usecases")
    require(hal, 2_595_800,
            "087c409309058052097dc99bff0309ebc101005408c9208b",
            "stock HIFI frame count")
    require(components, 292_552,
            "c0035fd681a20391e00313aaf44f49a9f54340f9fd7b47a9ff830291bf2303d5",
            "DeviceVector layout")
    require(impl, 377_928,
            "08810591692a0ba9686200f9880240f968ea00f9c80000b4090140f96142079129815ef80001098b46fc00947fda01b9",
            "mProfile layout")

    with zipfile.ZipFile(archive_path) as archive:
        assert len(archive.read("patches/native_hifi_cave.bin")) == 788
        assert len(archive.read("patches/usb_output_gate_cave.bin")) == 140
        assert len(archive.read("patches/usb_output_arbitration_cave.bin")) == 292
        assert len(archive.read("patches/usb_output_gate_v076_cave.bin")) == 140
        assert len(archive.read("patches/hifi_dynamic_default_cave.bin")) == 86
        assert len(archive.read("patches/hifi_idle_rate_cave.bin")) == 32
        patched_policy = apply(policy, POLICY_PATCHES, archive)
        patched_flinger = apply(flinger, FLINGER_PATCHES, archive)
        patched_usb = apply(usb, USB_PATCHES, archive)
        patched_hal = apply(hal, HAL_PATCHES, archive)

        assert len(patched_policy) == len(policy)
        assert len(patched_flinger) == len(flinger)
        assert len(patched_usb) == len(usb)
        assert len(patched_hal) == len(hal)
        require(patched_policy, 356_884, "66b10114", "patched select hook")
        require(patched_policy, 867_276, "38bfff17", "patched app hook")
        require(patched_policy, 515_988, "d3160114", "patched sender hook")
        require(patched_policy, 801_504, "39000014", "patched sender trampoline")
        require(patched_policy, 801_732, "fd7bbba9", "patched idle arbitration")
        require(patched_policy, 864_416, "86c2ff17", "patched final-stop idle branch")
        require(patched_policy, 865_840, "17c1ff17", "patched idle-rate branch")
        require(patched_policy, 873_596, "91b9ff17", "patched HIFI idle-rate caller")
        require(patched_policy, 432_224, "c3680114", "patched HIFI default hook")
        require(patched_flinger, 1_772_164, "6a000014", "patched Mixer sync")
        require(patched_usb, 29_024, "44ac0000", "patched USB 44.1 slot")
        require(patched_usb, 29_052, "20620500", "patched USB 352.8 slot")
        require(patched_hal, 2_295_956,
                "092184522925c81a090200361f2003d5", "patched HIFI usecases")
        require(patched_hal, 2_595_800,
                "087c409309058052097dc99bff0309ebc101005408c9208b",
                "stock HIFI frame-count calculation")
        assert b"hifi_playback" in patched_policy[800_684:801_419]
        assert b"com.apple.android.music" in patched_policy[800_684:801_419]
        assert b"com.netease.cloudmusic" in patched_policy[800_684:801_419]
        require(patched_policy, 801_420, "092840f9", "application-count idle helper")
        assert b"\x00\x70\x97\x52\xc0\x03\x5f\xd6" in patched_policy[801_420:801_464]
        assert patched_policy[801_472:801_504] == archive.read(
            "patches/hifi_idle_rate_cave.bin"
        )
        assert b"hifi_playback" in patched_policy[801_644:801_730]

        # Exact reapplication is byte-idempotent.
        assert apply(patched_policy, POLICY_PATCHES, archive) == patched_policy
        assert apply(patched_flinger, FLINGER_PATCHES, archive) == patched_flinger
        assert apply(patched_usb, USB_PATCHES, archive) == patched_usb
        assert apply(patched_hal, HAL_PATCHES, archive) == patched_hal

    print("firmware patch verification: stock -> v0.7.8 passed")


if __name__ == "__main__":
    main()
