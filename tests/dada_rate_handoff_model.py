#!/usr/bin/env python3
"""Executable model of the Dada parameter/worker handoff invariants."""

VALID_RATES = {
    44_100,
    88_200,
    176_400,
    48_000,
    96_000,
    192_000,
    384_000,
}

STOCK_PRIORITY = [
    384_000,
    352_800,
    192_000,
    176_400,
    96_000,
    88_200,
    64_000,
    48_000,
    44_100,
    32_000,
    24_000,
    22_050,
    16_000,
    11_025,
    8_000,
]


def pal_capability_round_trip(priority: list[int], descriptor_rates: set[int]) -> tuple[list[int], list[int]]:
    """Model AudioReach getSampleRates() plus readSupportedSampleRate()."""
    internal_rates = [rate for rate in priority if rate in descriptor_rates]
    reported_rates = internal_rates[:7]
    return internal_rates, reported_rates


def parameter(usecase: int, requested: int, configured: int) -> int:
    if usecase != 3 or requested not in VALID_RATES:
        return configured
    return requested


def worker(
    usecase: int,
    configured: int,
    cached: int,
    live_handle: bool,
    standby_status: int = 0,
    configured_after_standby: int | None = None,
) -> tuple[int, int]:
    """Return cached rate and standby-call count."""
    if usecase != 3 or configured == cached:
        return cached, 0
    if live_handle and standby_status != 0:
        return cached, 1
    if live_handle and configured_after_standby is not None:
        configured = configured_after_standby
    return configured, int(live_handle)


def main() -> None:
    eight_family_rates = {
        44_100,
        48_000,
        88_200,
        96_000,
        176_400,
        192_000,
        352_800,
        384_000,
    }
    stock_internal, stock_reported = pal_capability_round_trip(
        STOCK_PRIORITY, eight_family_rates
    )
    assert set(stock_internal) == eight_family_rates
    assert stock_reported == [
        384_000,
        352_800,
        192_000,
        176_400,
        96_000,
        88_200,
        48_000,
    ]

    patched_priority = STOCK_PRIORITY.copy()
    patched_priority[1], patched_priority[8] = (
        patched_priority[8],
        patched_priority[1],
    )
    patched_internal, patched_reported = pal_capability_round_trip(
        patched_priority, eight_family_rates
    )
    assert set(patched_internal) == eight_family_rates
    assert patched_reported == [
        384_000,
        44_100,
        192_000,
        176_400,
        96_000,
        88_200,
        48_000,
    ]
    # The priority swap changes capability admission only. It never maps a
    # 44.1 kHz request to 352.8 kHz; both parsing and reporting use the same
    # table, while PAL's internal exact-rate vector still contains all eight.
    assert 44_100 in patched_internal
    assert 352_800 in patched_internal

    for rate in VALID_RATES:
        assert parameter(3, rate, 48_000) == rate
    for rate in (0, 8_000, 44_099, 50_000, 352_800, 705_600, -1):
        assert parameter(3, rate, 48_000) == 48_000
    assert parameter(2, 44_100, 48_000) == 48_000

    assert worker(3, 44_100, 48_000, True) == (44_100, 1)
    assert worker(3, 44_100, 48_000, False) == (44_100, 0)
    assert worker(3, 44_100, 48_000, True, -1) == (48_000, 1)
    assert worker(3, 96_000, 48_000, True, 0, 44_100) == (44_100, 1)
    assert worker(3, 48_000, 48_000, True) == (48_000, 0)
    assert worker(2, 44_100, 48_000, True) == (48_000, 0)
    print('Dada rate handoff model: PASS')


if __name__ == '__main__':
    main()
