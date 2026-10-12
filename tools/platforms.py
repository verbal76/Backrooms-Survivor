#!/usr/bin/env python3
"""Single definition of the platform selector used by the build/release workflows and verifiers.

  platforms.py require <all|android|windows|linux>   -> comma list for verify_release.py --require (always includes patch)
  platforms.py check   <value>                       -> exit 1 unless the value is a valid selector
"""
import sys

PLATFORMS = ("android", "windows", "linux")
SELECTORS = ("all",) + PLATFORMS


def selected(sel):
    if sel not in SELECTORS:
        raise ValueError(f"invalid platform '{sel}' (expected one of {', '.join(SELECTORS)})")
    return list(PLATFORMS) if sel == "all" else [sel]


def required(sel):
    return selected(sel) + ["patch"]


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("require", "check"):
        print(__doc__); sys.exit(2)
    try:
        r = required(sys.argv[2])
    except ValueError as e:
        print(f"::error::{e}"); sys.exit(1)
    if sys.argv[1] == "require":
        print(",".join(r))
