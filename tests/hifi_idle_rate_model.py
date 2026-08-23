#!/usr/bin/env python3
"""Model the final-stop marker after Xiaomi's inline tree lookup."""


IDLE_HANDOFF = 1


def selected_rate(strategy: str, update_changed: bool, all_stopped: bool,
                  tree_rate: int) -> int:
    if strategy == "first_lock":
        return tree_rate
    if update_changed and all_stopped:
        return IDLE_HANDOFF
    return tree_rate


def main() -> None:
    assert selected_rate("latest_max", True, True, 384_000) == IDLE_HANDOFF
    assert selected_rate("latest_max", True, False, 96_000) == 96_000
    assert selected_rate("latest_max", False, True, 48_000) == 48_000
    assert selected_rate("first_lock", True, True, 48_000) == 48_000
    print("HIFI idle-rate handoff model: 4 lifecycle cases passed")


if __name__ == "__main__":
    main()
