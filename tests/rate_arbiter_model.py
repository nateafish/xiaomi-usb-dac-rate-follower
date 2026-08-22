#!/usr/bin/env python3
"""Executable model for the shared Xiaomi USB backend arbitration.

This is not device-side code.  It specifies the required behavior before an
instruction patch is allowed to implement it in HifiSampleRateManager.
"""

from collections import Counter
from dataclasses import dataclass, field
from itertools import product


DEFAULT_RATE = 48_000


@dataclass
class NativeUsbArbiter:
    hifi: Counter[int] = field(default_factory=Counter)
    deep: Counter[int] = field(default_factory=Counter)
    hardware_rate: int = DEFAULT_RATE
    writes: list[int] = field(default_factory=list)

    @staticmethod
    def _update(counter: Counter[int], rate: int, starting: bool) -> None:
        if starting:
            counter[rate] += 1
            return
        if counter[rate] <= 0:
            raise AssertionError(f"unbalanced stop at {rate}")
        counter[rate] -= 1
        if counter[rate] == 0:
            del counter[rate]

    def desired_rate(self) -> int:
        # HIFI activity is the package-scoped enable signal.  While it exists,
        # ordinary Deep Buffer playback has foreground/system priority because
        # both logical outputs drive one physical USB backend.
        if not self.hifi:
            return DEFAULT_RATE
        if self.deep:
            return max(self.deep)
        return max(self.hifi)

    def event(self, profile: str, rate: int, starting: bool) -> int:
        if profile == "hifi_playback":
            self._update(self.hifi, rate, starting)
        elif profile == "deep_buffer_out":
            self._update(self.deep, rate, starting)
        else:
            raise AssertionError(f"unexpected profile {profile}")
        desired = self.desired_rate()
        if desired != self.hardware_rate:
            self.hardware_rate = desired
            self.writes.append(desired)
        return desired


@dataclass
class HookDecisionModel:
    """Model the instruction hook's event-local decision, not just its goal."""

    hifi: Counter[int] = field(default_factory=Counter)
    deep: Counter[int] = field(default_factory=Counter)
    hardware_rate: int = DEFAULT_RATE
    writes: list[int] = field(default_factory=list)

    @staticmethod
    def _maximum(counter: Counter[int]) -> int:
        return max(counter, default=DEFAULT_RATE)

    def event(self, profile: str, rate: int, starting: bool) -> int:
        counter = self.hifi if profile == "hifi_playback" else self.deep
        old_local = self._maximum(counter)
        NativeUsbArbiter._update(counter, rate, starting)
        new_local = self._maximum(counter)
        local_changed = old_local != new_local

        htotal, dtotal = sum(self.hifi.values()), sum(self.deep.values())
        hmax, dmax = self._maximum(self.hifi), self._maximum(self.deep)
        call = False
        desired = self.hardware_rate

        if htotal == 0:
            desired = DEFAULT_RATE
            if profile == "hifi_playback" and not starting:
                previous = dmax if dtotal else rate
                call = previous != DEFAULT_RATE
        elif dtotal == 0:
            desired = hmax
            if profile == "hifi_playback":
                call = local_changed
            elif not starting:
                call = hmax != rate
        else:
            desired = dmax
            if profile == "deep_buffer_out":
                if starting and dtotal == 1:
                    call = dmax != hmax
                else:
                    call = local_changed
            elif starting and htotal == 1:
                call = dmax != DEFAULT_RATE

        if call:
            self.hardware_rate = desired
            self.writes.append(desired)
        return self.hardware_rate


def run_case(events, expected_rates, expected_writes) -> None:
    arbiter = NativeUsbArbiter()
    actual_rates = [arbiter.event(*event) for event in events]
    assert actual_rates == expected_rates, (actual_rates, expected_rates)
    assert arbiter.writes == expected_writes, (arbiter.writes, expected_writes)


def main() -> None:
    # Basic per-track following and return to the stock idle rate.
    run_case(
        [
            ("hifi_playback", 44_100, True),
            ("hifi_playback", 44_100, False),
        ],
        [44_100, 48_000],
        [44_100, 48_000],
    )

    # Gapless overlap uses native counts: the prepared higher-rate track wins,
    # then stopping the old track does not produce a redundant HAL write.
    run_case(
        [
            ("hifi_playback", 44_100, True),
            ("hifi_playback", 48_000, True),
            ("hifi_playback", 44_100, False),
            ("hifi_playback", 48_000, False),
        ],
        [44_100, 48_000, 48_000, 48_000],
        [44_100, 48_000],
    )

    # A normal app temporarily owns the physical USB backend.  When it stops,
    # the still-active selected package regains 44.1 kHz.
    run_case(
        [
            ("hifi_playback", 44_100, True),
            ("deep_buffer_out", 48_000, True),
            ("deep_buffer_out", 48_000, False),
            ("hifi_playback", 44_100, False),
        ],
        [44_100, 48_000, 44_100, 48_000],
        [44_100, 48_000, 44_100, 48_000],
    )

    # Deep Buffer is not adaptive on its own; package-scoped HIFI activity is
    # the enable condition requested by the project.
    run_case(
        [
            ("deep_buffer_out", 96_000, True),
            ("deep_buffer_out", 96_000, False),
        ],
        [48_000, 48_000],
        [],
    )

    # Deep playback already active when the selected app starts remains in
    # control; once Deep stops, HIFI immediately follows its source rate.
    run_case(
        [
            ("deep_buffer_out", 48_000, True),
            ("hifi_playback", 96_000, True),
            ("deep_buffer_out", 48_000, False),
            ("hifi_playback", 96_000, False),
        ],
        [48_000, 48_000, 96_000, 48_000],
        [96_000, 48_000],
    )

    # Duplicate starts/stops at one rate do not create repeated HAL requests.
    run_case(
        [
            ("hifi_playback", 44_100, True),
            ("hifi_playback", 44_100, True),
            ("hifi_playback", 44_100, False),
            ("hifi_playback", 44_100, False),
        ],
        [44_100, 44_100, 44_100, 48_000],
        [44_100, 48_000],
    )

    # Exhaustively compare the event-local hook against the ideal state model
    # across short balanced sequences. This catches missed first/last ownership
    # boundaries and unnecessary same-rate writes before any device install.
    event_types = [
        (profile, rate, starting)
        for profile in ("hifi_playback", "deep_buffer_out")
        for rate in (44_100, 48_000, 96_000)
        for starting in (True, False)
    ]
    checked = 0
    for length in range(1, 6):
        for events in product(event_types, repeat=length):
            ideal = NativeUsbArbiter()
            hook = HookDecisionModel()
            try:
                for event in events:
                    expected = ideal.event(*event)
                    actual = hook.event(*event)
                    assert actual == expected, (events, actual, expected)
            except AssertionError as error:
                if "unbalanced stop" in str(error):
                    continue
                raise
            checked += 1

    print(f"rate arbiter model: 6 scenarios and {checked} balanced traces passed")


if __name__ == "__main__":
    main()
