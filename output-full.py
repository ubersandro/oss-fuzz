#!/usr/bin/env python3
"""Replay a fuzzer's crashing inputs and map each FSan location to one input.

Usage: classify_crashes.py FUZZER

Prints "input: location" on stdout, one line per distinct location, naming the
first input that hit it. Everything else goes to stderr. The build must be
compiled with -fsanitize-recover=hwaddress so that recover_report=summary works.
"""
import os
import re
import subprocess
import sys
from pathlib import Path
VERBOSE = os.environ.get("REPORT_VERBOSE", "0") == "1"
OUT_DIR = Path("/out")
TIMEOUT_SECONDS = 60
HWOPT_SYM = (
    "verbosity=0:symbolize=1:halt_on_error=0:detect_leaks=0:exitcode=99:"
    "recover_report=summary:dedup_stack_depth=3:allocator_may_return_null=1"
)
HWOPT_NOSYM = (
    "verbosity=0:symbolize=0:halt_on_error=0:detect_leaks=0:exitcode=99:"
    "recover_report=summary:dedup_stack_depth=3:allocator_may_return_null=1"
)
#  export HWASAN_OPTIONS=verbosity=0:symbolize=0:halt_on_error=1:abort_on_error=1:detect_leaks=0:recover_report=summary:allocator_may_return_null=1

# ==123==FSan: 12 violations at 6 sites:
SUMMARY_HEADER = re.compile(r"FSan: \d+ violations at \d+ sites:")
#   WRITE of size 4 at 0x4007d3ff7260960  (/out/fuzzer+0x66710d), 2 times
#   READ of size 1 at 0x4007d3ff7260960 in foo /src/a.c:3:1, 1 time from 2 call paths
SUMMARY_SITE = re.compile(
    r"^\s+(?:READ|WRITE) of size \d+ at 0x[0-9a-fA-F]+\s*(.*?), \d+ times?"
    r"(?: from \d+ call paths)?\s*$"
)
SUMMARY_DROPPED = re.compile(r"^\s+and \d+ more distinct violations")


def log(message):
    print(message, file=sys.stderr)


def parse_locations(output):
    """Return (locations in report order, whether the runtime dropped some)."""
    locations = []
    dropped = False
    in_summary = False
    for line in output.splitlines():
        if SUMMARY_HEADER.search(line):
            in_summary = True
            continue
        if not in_summary:
            continue
        site = SUMMARY_SITE.match(line)
        if site:
            # An empty location means the PC could not be symbolized at all.
            location = site.group(1).strip().strip("()")
            if location:
                locations.append(location)
        elif SUMMARY_DROPPED.match(line):
            dropped = True
        else:
            in_summary = False
    return locations, dropped


def list_inputs(folder, suffix=None):
    inputs = []
    for path in folder.rglob("*"):
        if not path.is_file() or path.name == "README.txt" or "*" in path.name:
            continue
        if suffix is None or path.name.endswith(f".{suffix}"):
            inputs.append(path)
    return sorted(inputs)


def replay(binary, crash_input):
    """Return (exit code or None on timeout, combined output)."""
    try:
        result = subprocess.run(
            [str(binary), str(crash_input)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            errors="replace",
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return None, ""
    return result.returncode, result.stdout

def classify(fuzzer, folder, first_hit, suffix=None):
    """Replay the inputs in folder, recording new locations in first_hit."""
    if not folder.is_dir():
        log(f"# SKIP {folder}: not a directory")
        return
    inputs = list_inputs(folder, suffix)
    log(f"# CRASHES for FUZZER {fuzzer} in folder {folder}: {len(inputs)}")

    for crash_input in inputs:
        code, output = replay(OUT_DIR / fuzzer, crash_input)
        if code is None:
            log(f"# TIMEOUT: {crash_input}")
            continue
        if code == 0:
            if VERBOSE:
                log(f"# NO REPRO: {crash_input}")
            continue
        locations, dropped = parse_locations(output)
        # if dropped:
        #     log(f"# DROPPED VIOLATIONS: {crash_input}")
        # if not locations and VERBOSE:
        #     log(f"# NO FSAN SUMMARY (exit code {code}): {crash_input}")
        for location in locations:
            if location not in first_hit:
                # nonsymb per-fuzzer location
                first_hit[location] = (fuzzer, crash_input)
                
                # print(f"{crash_input}: {location}")
                # try:
                #     filepath = location.split(" ")[-1]
                #     file_path, line_number = filepath.rsplit(":", 2)[:2]
                #     line_number = int(line_number)
                #     with open(file_path) as f:
                #         lines = f.readlines()
                #         if 1 <= line_number <= len(lines):
                #             print(f"#\t\t{lines[line_number - 1].rstrip()}" , flush=True)
                # except Exception:
                #     pass


def main():
    fuzzer_list = []
    for path in Path("/fuzzing-campaign").iterdir():
        if path.is_dir() and path.name.endswith("_0"):
            fuzzer_list.append(path.name[:-2])
    if not fuzzer_list:
        sys.exit(f"no fuzzers found in /fuzzing-campaign")
    global_symb_locs = {} # collect unique locations across all fuzzers
    
    for fuzzer in fuzzer_list:
        uniq_symb_locs = {} # collect unique locations per fuzzer first
        log(f"# CLASSIFYING CRASHES FOR {fuzzer}")
        os.environ["HWASAN_OPTIONS"] = HWOPT_NOSYM
        classify(fuzzer, Path(f"/crashes-{fuzzer}"), uniq_symb_locs, "99")
        # find out how many crashes* directories are there from prev. campaigns under /fuzzing-campaign/fuzzer_0/default/crashes*
        for c in Path(f"/fuzzing-campaign/{fuzzer}_0/default").iterdir():
            if c.is_dir() and c.name.startswith("crashes"):
                classify(fuzzer, c, uniq_symb_locs, None)
        # classify(fuzzer, Path(f"/fuzzing-campaign/{fuzzer}_0/default/crashes"), uniq_symb_locs, None)
        os.environ["HWASAN_OPTIONS"] = HWOPT_SYM
        print("Unique locations for fuzzer", fuzzer, file=sys.stderr)
        for location, (fuzzer, crash_input) in uniq_symb_locs.items():
            code, output = replay(OUT_DIR / fuzzer, crash_input)
            locations, dropped = parse_locations(output)
            for symb_location in locations:
                if symb_location not in global_symb_locs:
                    global_symb_locs[symb_location] = (fuzzer, crash_input)
                    print(f"{fuzzer} {crash_input}: {symb_location}")
                    # open file, read at that line number and print it
                    try:
                        filepath = symb_location.split(" ")[-1]
                        file_path, line_number = filepath.rsplit(":", 2)[:2]
                        line_number = int(line_number)
                        with open(file_path) as f:
                            lines = f.readlines()
                            if 1 <= line_number <= len(lines):
                                print(f"#\t\t{lines[line_number - 1].rstrip()}" , flush=True)
                    except Exception:
                        pass
    
    log(f"# DISTINCT LOCATIONS: {len(global_symb_locs)}")


if __name__ == "__main__":
    main()
