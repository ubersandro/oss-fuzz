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
import random
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

def classify(fuzzer, folder, first_hit, suffix=None, logfile=sys.stderr):
    """Replay the inputs in folder, recording new locations in first_hit."""
    if not folder.is_dir():
        log(f"# SKIP {folder}: not a directory")
        return
    inputs = list_inputs(folder, suffix)
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
        for location in locations:
            if location not in first_hit:
                first_hit[location] = (fuzzer, crash_input)
        # copy crashing input to /fuzzing-campaign/triage/others/FUZZER_NAME.hash
        # create folder new_path = Path(f"/fuzzing-campaign/triage/others/")
        md5_hash = subprocess.run(
                            ["md5sum", str(crash_input)],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                        ).stdout.split()[0]
        newfolder = Path(f"/fuzzing-campaign/triage/others/")
        newfolder.mkdir(parents=True, exist_ok=True)
        
        new_name = f"{fuzzer}.{md5_hash}"
        new_path = Path(f"/fuzzing-campaign/triage/others/{new_name}")
        new_path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
                ["cp", str(crash_input), str(new_path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE)
def main():
    fuzzer_list = []
    for path in Path("/fuzzing-campaign").iterdir():
        if path.is_dir() and path.name.endswith("_0"):
            fuzzer_list.append(path.name[:-2])
    if not fuzzer_list:
        sys.exit(f"no fuzzers found in /fuzzing-campaign")
    global_symb_locs = {} # collect unique locations across all fuzzers
    logfile = Path(f"/fuzzing-campaign/triage/TRIAGE.log")
    logfile.parent.mkdir(parents=True, exist_ok=True)
    # open to overwrite, discard prev. content
    with logfile.open("w") as logf:
        for fuzzer in fuzzer_list:
            uniq_symb_locs = {} # collect unique locations per fuzzer first
            os.environ["HWASAN_OPTIONS"] = HWOPT_NOSYM
            
            # dump crashes from oss-fuzz queues all campaigns
            classify(fuzzer, Path(f"/crashes-{fuzzer}"), uniq_symb_locs, "99")
            for c in Path(f"/fuzzing-campaign/{fuzzer}_0/default").iterdir():
                if c.is_dir() and c.name.startswith("crashes"):
                    classify(fuzzer, c, uniq_symb_locs, None)
            
            os.environ["HWASAN_OPTIONS"] = HWOPT_SYM
            for location, (fuzzer, crash_input) in uniq_symb_locs.items():
                code, output = replay(OUT_DIR / fuzzer, crash_input)
                locations, dropped = parse_locations(output)
                for symb_location in locations:
                    if symb_location not in global_symb_locs:
                        global_symb_locs[symb_location] = (fuzzer, crash_input)
                        # copy the file under /fuzzing-campaign/triage/FUZZER_NAME.hash, where has is md5 of name of input and then print OLD_NAME -> NEW_NAME
                        md5_hash = subprocess.run(
                            ["md5sum", str(crash_input)],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                        ).stdout.split()[0]
                        
                        new_name = f"{fuzzer}.{md5_hash}"
                        new_path = Path(f"/fuzzing-campaign/triage/{new_name}")
                        new_path.parent.mkdir(parents=True, exist_ok=True)
                        if not new_path.exists():
                            subprocess.run(
                                ["cp", str(crash_input), str(new_path)],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,
                            )
                        else:
                            # rename and copy
                            new_name = f"{fuzzer}.{md5_hash}." + random.randint(1000, 9999).__str__()
                            new_path = Path(f"/fuzzing-campaign/triage/{new_name}")
                            subprocess.run(
                                ["cp", str(crash_input), str(new_path)],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE,
                            )
                        full_new_path = new_path.resolve()
                        print(f"{fuzzer} {full_new_path}: {symb_location}")
                        logf.write(f"{fuzzer} {full_new_path}: {symb_location}\n")

                        
                        try:
                            filepath = symb_location.split(" ")[-1]
                            file_path, line_number = filepath.rsplit(":", 2)[:2]
                            line_number = int(line_number)
                            with open(file_path) as f:
                                lines = f.readlines()
                                if 1 <= line_number <= len(lines):
                                    print(f"#\t\t{lines[line_number - 1].rstrip()}" , flush=True)
                                    logf.write(f"#\t\t{lines[line_number - 1].rstrip()}\n")
                        except Exception:
                            pass
        print(f"# DISTINCT LOCATIONS: {len(global_symb_locs)}", file=logf)
    
    log(f"# DISTINCT LOCATIONS: {len(global_symb_locs)}")


if __name__ == "__main__":
    main()
