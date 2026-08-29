#!/usr/bin/env python3
"""State model for Android 16 pointer-layout active rate handoff."""

VALID_RATES = {44_100, 88_200, 176_400, 48_000, 96_000, 192_000, 384_000}


class Stream:
    def __init__(self, usecase: int, cached: int, live: bool, hyper: bool = False) -> None:
        self.usecase = usecase
        self.requested = cached
        self.cached = cached
        self.live = live
        self.hyper = hyper
        self.standby_calls = 0
        self.configure_calls = 0

    def parameter(self, rate: int) -> None:
        # Binder context records intent only.  It never closes PAL and never
        # changes the attributes consumed by the currently live handle.
        if self.usecase == 3 and rate in VALID_RATES:
            self.requested = rate

    def transfer(self, standby_status: int = 0, rate_during_standby: int | None = None) -> None:
        if self.usecase == 3 and self.requested != self.cached:
            if self.live:
                self.standby_calls += 1
                if standby_status != 0:
                    return
                self.live = False
                if rate_during_standby is not None:
                    self.parameter(rate_during_standby)
            self.cached = self.requested
        # The ordinary stock branch configures a null handle immediately.
        # hyperWrite is a pacing path and defers reopening until its first
        # subsequent ordinary transfer; the worker still safely owns teardown.
        if not self.live and not self.hyper:
            self.configure_calls += 1
            self.live = True


def main() -> None:
    active = Stream(3, 48_000, True)
    active.parameter(44_100)
    assert (active.requested, active.cached, active.live) == (44_100, 48_000, True)
    active.transfer()
    assert (active.cached, active.live) == (44_100, True)
    assert (active.standby_calls, active.configure_calls) == (1, 1)

    cold = Stream(3, 48_000, False)
    cold.parameter(96_000)
    cold.transfer()
    assert (cold.cached, cold.live) == (96_000, True)
    assert (cold.standby_calls, cold.configure_calls) == (0, 1)

    failed = Stream(3, 48_000, True)
    failed.parameter(192_000)
    failed.transfer(-1)
    assert (failed.requested, failed.cached, failed.live) == (192_000, 48_000, True)
    assert (failed.standby_calls, failed.configure_calls) == (1, 0)

    raced = Stream(3, 48_000, True)
    raced.parameter(96_000)
    raced.transfer(rate_during_standby=44_100)
    assert (raced.requested, raced.cached, raced.live) == (44_100, 44_100, True)
    assert (raced.standby_calls, raced.configure_calls) == (1, 1)

    hyper = Stream(3, 48_000, True, hyper=True)
    hyper.parameter(88_200)
    hyper.transfer()
    assert (hyper.cached, hyper.live, hyper.configure_calls) == (88_200, False, 0)
    hyper.hyper = False
    hyper.transfer()
    assert (hyper.cached, hyper.live, hyper.configure_calls) == (88_200, True, 1)

    ignored = Stream(2, 48_000, True)
    ignored.parameter(44_100)
    ignored.transfer()
    assert (ignored.requested, ignored.cached, ignored.live) == (48_000, 48_000, True)

    invalid = Stream(3, 48_000, True)
    invalid.parameter(352_800)
    invalid.transfer()
    assert (invalid.requested, invalid.cached, invalid.live) == (48_000, 48_000, True)

    print("Android 16 pointer active-rate handoff model: PASS")


if __name__ == "__main__":
    main()
