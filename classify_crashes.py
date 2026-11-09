#!/usr/bin/env python3
"""Replay a fuzzer's crashing inputs and map each FSan location to one input.

Usage: classify_crashes.py FUZZER [--signatures FILE]

Prints "input: location" on stdout, one line per distinct location, naming the
first input that hit it. Everything else goes to stderr. The build must be
compiled with -fsanitize-recover=hwaddress so that recover_report=summary works.

With a triage build (-mllvm -fsan-triage, replayed with fsan_triage=1), the
runtime also says what each violation hit, with a verdict: bounds, array
misindexing, inter-object or type. The hits are then grouped by signature (the
verdict, the pointer's field, the memory's type and field, read or write),
the funnel (reports, sites, signatures) goes to stderr, and --signatures writes
one line per signature to FILE.
"""
import argparse
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

OUT_DIR = Path("/out")
TIMEOUT_SECONDS = 10
DEFAULT_HWASAN_OPTIONS = (
    "verbosity=0:symbolize=1:halt_on_error=0:detect_leaks=0:exitcode=99:"
    "recover_report=summary:dedup_stack_depth=3:fsan_triage=1"
)

# ==123==FSan: 12 violations at 6 sites:
SUMMARY_HEADER = re.compile(r"FSan: (\d+) violations at \d+ sites:")
#   WRITE of size 4 at 0x4007d3ff7260960  (/out/fuzzer+0x66710d), 2 times
#   READ of size 1 at 0x4007d3ff7260960 in foo /src/a.c:3:1, 1 time from 2 call paths
SUMMARY_SITE = re.compile(
    r"^\s+(?:READ|WRITE) of size \d+ at 0x[0-9a-fA-F]+\s*(.*?), \d+ times?"
    r"(?: from \d+ call paths)?\s*$"
)
SUMMARY_DROPPED = re.compile(r"^\s+and \d+ more distinct violations")

# ==123==FSan: what the violations at the 6 sites hit (fsan_triage):
TRIAGE_HEADER = re.compile(r"FSan: what the violations at the \d+ sites hit")
#   READ of size 4 at 0x7a0e0a1e0020 in f /src/a.c:10:65, 1 time: inter-object, 0
#   bytes after the pointer's field in the previous object, heap struct.B; pointer
#   struct.B [+12,+16); memory heap struct.A +0: field [+0,+4) tag 01; tags 04/01
TRIAGE_HIT = re.compile(
    r"^\s+(READ|WRITE) of size \d+ at 0x[0-9a-fA-F]+\s*(.*?), (\d+) times?: "
    r"(.*?); pointer (.*?); memory (.*?); tags [0-9a-f]{2}/[0-9a-f]{2}\s*$"
)
TRIAGE_OTHERS = re.compile(r"^\s+and (\d+) more violations there")
#   heap struct.A +13: field [+12,+16) tag 03
#   global g struct.A +13: padding [+13,+16) tag ff
TYPED_MEMORY = re.compile(
    r"^(\w+) (.+) \+\d+: (field|padding|untagged) (\[[^)]*\)) tag [0-9a-f]{2}$"
)


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


def count_violations(output):
    """The violations that the summary counts, 0 without one."""
    header = SUMMARY_HEADER.search(output)
    return int(header.group(1)) if header else 0


def signature(access, verdict, pointer, memory):
    """The root cause that a hit belongs to: what the access did, the pointer's
    field, the memory's type and field, read or write. Not the site, nor the
    kind or place of the object, nor how far the access went."""
    kind = verdict.split(",")[0]
    typed = TYPED_MEMORY.match(memory)
    if typed:
        memory_kind, what, field_kind, field = typed.groups()
        if memory_kind == "global" and " " in what:
            what = what.split(" ", 1)[1]  # without the global's name
        memory = f"{what} {field_kind} {field}"
    return (kind, access, pointer, memory)


def parse_hits(output):
    """Return the triage block's hits as (signature, location, count), and the
    violations that it did not describe (more hits than a site keeps)."""
    hits = []
    others = 0
    in_triage = False
    for line in output.splitlines():
        if TRIAGE_HEADER.search(line):
            in_triage = True
            continue
        if not in_triage:
            continue
        hit = TRIAGE_HIT.match(line)
        if hit:
            access, location, count, verdict, pointer, memory = hit.groups()
            location = location.strip().strip("()")
            hits.append((signature(access, verdict, pointer, memory), location,
                         int(count)))
            continue
        more = TRIAGE_OTHERS.match(line)
        if more:
            others += int(more.group(1))
        else:
            in_triage = False
    return hits, others


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


class Funnel:
    """Reports, then sites, then signatures, over all the inputs."""

    def __init__(self):
        self.reports = 0
        self.undescribed = 0
        # signature -> violations, sites, inputs, first input, first site
        self.signatures = {}

    def add(self, crash_input, output):
        self.reports += count_violations(output)
        hits, others = parse_hits(output)
        self.undescribed += others
        for sig, location, count in hits:
            entry = self.signatures.setdefault(
                sig, {"violations": 0, "sites": set(), "inputs": set(),
                      "first_input": crash_input, "first_site": location})
            entry["violations"] += count
            entry["sites"].add(location)
            entry["inputs"].add(crash_input)
        return bool(hits)

    def log(self, sites):
        log(f"# FUNNEL: {self.reports} reports, {sites} sites, "
            f"{len(self.signatures)} signatures")
        if self.undescribed:
            log(f"# NOT DESCRIBED: {self.undescribed} violations")
        kinds = Counter()
        violations = Counter()
        for (kind, *_), entry in self.signatures.items():
            kinds[kind] += 1
            violations[kind] += entry["violations"]
        for kind, n in kinds.most_common():
            log(f"# VERDICT {kind}: {n} signatures, {violations[kind]} violations")

    def write(self, path):
        with open(path, "w") as out:
            out.write("verdict\taccess\tpointer\tmemory\tviolations\tsites\t"
                      "inputs\tfirst input\tfirst site\n")
            for sig, entry in sorted(self.signatures.items(),
                                     key=lambda item: -item[1]["violations"]):
                out.write("\t".join(sig) + f"\t{entry['violations']}\t"
                          f"{len(entry['sites'])}\t{len(entry['inputs'])}\t"
                          f"{entry['first_input']}\t{entry['first_site']}\n")


def classify(fuzzer, folder, first_hit, funnel, suffix=None):
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
            log(f"# NO REPRO: {crash_input}")
            continue
        locations, dropped = parse_locations(output)
        if dropped:
            log(f"# DROPPED VIOLATIONS: {crash_input}")
        if not locations:
            log(f"# NO FSAN SUMMARY (exit code {code}): {crash_input}")
        elif not funnel.add(crash_input, output):
            log(f"# NO TRIAGE (a build without fsan_triage?): {crash_input}")
        for location in locations:
            if location not in first_hit:
                first_hit[location] = crash_input
                print(f"{crash_input}: {location}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("fuzzer")
    parser.add_argument("--signatures", type=Path,
                        help="write one line per signature to this file")
    args = parser.parse_args()
    fuzzer = os.path.basename(args.fuzzer)
    # os.environ.setdefault("HWASAN_OPTIONS", DEFAULT_HWASAN_OPTIONS)
    os.environ["HWASAN_OPTIONS"] = DEFAULT_HWASAN_OPTIONS # override the opts

    first_hit = {}
    funnel = Funnel()
    classify(fuzzer, Path(f"/crashes-{fuzzer}"), first_hit, funnel, "99")
    classify(fuzzer, Path(f"/crashes-{fuzzer}"), first_hit, funnel, "134")
    fuzzpath = Path(f"/fuzzing-campaign/{fuzzer}_0/default")
    for dir in fuzzpath.iterdir():
        print(f"# CHECKING {dir}")
        if dir.is_dir() and dir.name.startswith("crashes"):
            classify(fuzzer, dir , first_hit, funnel)
    log(f"# DISTINCT LOCATIONS: {len(first_hit)}")
    funnel.log(len(first_hit))
    if args.signatures:
        funnel.write(args.signatures)
        log(f"# SIGNATURES IN: {args.signatures}")


if __name__ == "__main__":
    main()
