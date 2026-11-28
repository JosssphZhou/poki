#!/usr/bin/env python3
"""Print version/build outputs for a manual internal IPA build."""
import re
import sys


def main():
    branch_version, main_version, main_count, run_number = sys.argv[1:]
    versions = [branch_version, main_version]
    if any(not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", v) for v in versions):
        sys.exit("Expected X.Y.Z versions from the branch and official main")
    if any(not re.fullmatch(r"[1-9][0-9]*", n) for n in (main_count, run_number)):
        sys.exit("Expected positive main commit count and workflow run number")
    build = 9000 + int(run_number)
    if build > 9999 or int(main_count) >= 9000:
        sys.exit("Internal build range exhausted; choose a new numbering policy before building")
    version = max(versions, key=lambda v: tuple(map(int, v.split("."))))
    print(f"version={version}")
    print(f"build={build}")


if __name__ == "__main__":
    main()
