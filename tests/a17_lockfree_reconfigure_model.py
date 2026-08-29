#!/usr/bin/env python3
"""State model for Android 17 case-3 Binder-to-worker PAL handoff."""

VALID_RATES = {44_100, 88_200, 176_400, 48_000, 96_000, 192_000, 384_000}


class Stream:
    def __init__(self, usecase: int, active: int, live: bool) -> None:
        self.usecase = usecase
        self.desired = active
        self.framework_rate = active
        self.active = active
        self.dirty = False
        self.live = live
        self.standby_calls = 0
        self.configure_calls = 0
        self.lock_calls = 0

    def parameter(self, rate: int) -> None:
        if self.usecase == 3 and rate in VALID_RATES:
            self.desired = rate
            self.framework_rate = rate
            self.dirty = rate != self.active
            return
        if self.usecase in {8, 13}:
            self.lock_calls += 1

    def transfer(
        self,
        standby_status: int = 0,
        rate_during_standby: int | None = None,
    ) -> None:
        if self.usecase in {8, 13}:
            self.lock_calls += 1
        elif self.usecase == 3 and self.dirty:
            if self.live:
                self.standby_calls += 1
                if standby_status != 0:
                    return
                self.live = False
                if rate_during_standby is not None:
                    self.parameter(rate_during_standby)
            if self.dirty:
                self.active = self.desired
                self.dirty = False
        if not self.live:
            self.configure_calls += 1
            self.active = self.desired
            self.live = True


def main() -> None:
    steady = Stream(3, 48_000, True)
    steady.parameter(48_000)
    steady.transfer()
    assert (steady.standby_calls, steady.configure_calls) == (0, 0)

    active = Stream(3, 48_000, True)
    active.parameter(44_100)
    assert (active.framework_rate, active.active, active.dirty) == (
        44_100, 48_000, True)
    active.transfer()
    assert (active.framework_rate, active.active, active.live) == (
        44_100, 44_100, True)
    assert (active.standby_calls, active.configure_calls) == (1, 1)

    cancelled = Stream(3, 44_100, True)
    cancelled.parameter(48_000)
    cancelled.parameter(44_100)
    cancelled.transfer()
    assert (cancelled.framework_rate, cancelled.active, cancelled.dirty) == (
        44_100, 44_100, False)
    assert cancelled.standby_calls == 0

    raced = Stream(3, 48_000, True)
    raced.parameter(96_000)
    raced.transfer(rate_during_standby=44_100)
    assert (raced.framework_rate, raced.active, raced.dirty) == (
        44_100, 44_100, False)
    assert (raced.standby_calls, raced.configure_calls) == (1, 1)

    returned = Stream(3, 44_100, True)
    returned.parameter(48_000)
    returned.transfer(rate_during_standby=44_100)
    assert (returned.active, returned.standby_calls,
            returned.configure_calls) == (44_100, 1, 1)

    failed = Stream(3, 48_000, True)
    failed.parameter(192_000)
    failed.transfer(-1)
    assert (failed.framework_rate, failed.active, failed.dirty, failed.live) == (
        192_000, 48_000, True, True)
    failed.transfer()
    assert (failed.active, failed.dirty, failed.live) == (192_000, False, True)

    cold = Stream(3, 48_000, False)
    cold.parameter(88_200)
    cold.transfer()
    assert (cold.active, cold.standby_calls, cold.configure_calls) == (
        88_200, 0, 1)

    for usecase in (8, 13):
        stock = Stream(usecase, 48_000, True)
        stock.parameter(96_000)
        stock.transfer()
        assert stock.lock_calls == 2

    invalid = Stream(3, 48_000, True)
    invalid.parameter(352_800)
    invalid.transfer()
    assert (invalid.framework_rate, invalid.active) == (48_000, 48_000)

    print("Android 17 case-3 lock-free handoff model: PASS")


if __name__ == "__main__":
    main()
