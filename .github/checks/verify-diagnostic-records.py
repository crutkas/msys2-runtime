#!/usr/bin/env python3
"""Verify the machine-readable records a passing diagnostic run emits.

The diagnostics print a DIAG record for every case they clear, not only for
failures, so a green run carries its own evidence.  This checker refuses to
accept those records at face value: it requires the per-case records to be
unique, to cover the complete declared cross product, and to agree with the
summary the binary printed for itself.  Printing a constant is therefore not
enough to satisfy it.

Usage: verify-diagnostic-records.py LOG [LOG ...]
"""

import sys

EXPECTED_FULL = "RTYXCAD"
EXPECTED_OMIT = "RTCAD"
EXPECTED_CONTROLS = {"omit", "misassociated", "wrong-path-same-basename"}
EXPECTED_RAW_FIXTURES = {
    "accepted": 0,
    "missing-command-line": 107,
    "tail-absent": 108,
    "tail-ambiguous": 109,
    "tail-left-glued": 110,
    "tail-right-glued": 111,
}
# The matrix is an external contract, not something the run gets to declare
# for itself.  A binary that silently narrowed its own coverage would still
# emit a self-consistent summary, so the expected values live here and must
# match winsup/testsuite/winsup.api/argv_spawn.c exactly.
EXPECTED_MODELS = {"spawnv", "execv", "CreateProcessW"}
EXPECTED_FILLERS = {"0", "1", "15", "16", "17", "31"}
EXPECTED_TAILS = {"1", "23", "24", "511", "640", "1023", "2047", "4095",
                  "4096"}


class RecordError(Exception):
    """Raised when the emitted evidence is incomplete or inconsistent."""


def read_records(paths):
    records = []
    for path in paths:
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                lines = handle.readlines()
        except OSError as error:
            raise RecordError("cannot read %s: %s" % (path, error))
        for line in lines:
            fields = line.strip().split()
            if len(fields) < 3 or fields[0] != "DIAG":
                continue
            data = {}
            for field in fields[2:]:
                key, sep, value = field.partition("=")
                if sep:
                    data[key] = value
            kind = fields[2].partition("=")[0]
            records.append((fields[1], kind, data))
    return records


def require(condition, message):
    if not condition:
        raise RecordError(message)


def unique_keys(records, builder, label):
    seen = set()
    for data in records:
        key = builder(data)
        if key in seen:
            raise RecordError("duplicate %s record %r" % (label, key))
        seen.add(key)
    return seen


def verify_argv_spawn(records):
    by_kind = {}
    for test, kind, data in records:
        if test == "argv_spawn":
            by_kind.setdefault(kind, []).append(data)

    require(by_kind, "no argv_spawn records were emitted")

    wincmdln = by_kind.get("wincmdln", [])
    require(len(wincmdln) == 1, "expected exactly one wincmdln record")
    require(wincmdln[0].get("nowincmdln") == "0",
            "wincmdln was disabled during the run")
    require(wincmdln[0].get("result") == "pass", "wincmdln record is not pass")

    summaries = by_kind.get("summary", [])
    require(len(summaries) == 1, "expected exactly one argv_spawn summary")
    summary = summaries[0]
    for key in ("positive", "negative", "fixtures", "models", "fillers",
                "tails"):
        require(key in summary, "argv_spawn summary lacks %s" % key)
    models = int(summary["models"])
    fillers = int(summary["fillers"])
    tails = int(summary["tails"])
    require(models == len(EXPECTED_MODELS),
            "summary declares %d models, the contract requires %d"
            % (models, len(EXPECTED_MODELS)))
    require(fillers == len(EXPECTED_FILLERS),
            "summary declares %d filler lengths, the contract requires %d"
            % (fillers, len(EXPECTED_FILLERS)))
    require(tails == len(EXPECTED_TAILS),
            "summary declares %d tail lengths, the contract requires %d"
            % (tails, len(EXPECTED_TAILS)))

    fixtures = by_kind.get("raw-fixture", [])
    observed_fixtures = {}
    for data in fixtures:
        name = data.get("case")
        require(name in EXPECTED_RAW_FIXTURES,
                "unexpected raw fixture %r" % name)
        require(name not in observed_fixtures,
                "duplicate raw fixture %r" % name)
        require(data.get("result") == "pass",
                "raw fixture %r is not pass" % name)
        require(int(data.get("expected", "-1")) == EXPECTED_RAW_FIXTURES[name],
                "raw fixture %r declares the wrong expected code" % name)
        require(data.get("expected") == data.get("observed"),
                "raw fixture %r observed a different code" % name)
        observed_fixtures[name] = data
    require(set(observed_fixtures) == set(EXPECTED_RAW_FIXTURES),
            "missing raw fixtures: %r"
            % sorted(set(EXPECTED_RAW_FIXTURES) - set(observed_fixtures)))
    require(int(summary["fixtures"]) == len(EXPECTED_RAW_FIXTURES),
            "summary fixture count disagrees with the emitted fixtures")

    positive = by_kind.get("positive", [])
    for data in positive:
        require(data.get("result") == "pass", "a positive case is not pass")
        require(data.get("child") == "0", "a positive case has a child code")
        require(data.get("tail") == data.get("declared"),
                "a positive case declared a different length")
    keys = unique_keys(
        positive,
        lambda d: (d.get("model"), d.get("filler"), d.get("tail")),
        "positive")
    require(len(keys) == models * fillers * tails,
            "positive records cover %d of %d declared combinations"
            % (len(keys), models * fillers * tails))
    require(len(keys) == int(summary["positive"]),
            "summary positive count %s disagrees with %d unique records"
            % (summary["positive"], len(keys)))
    require(set(m for m, _, _ in keys) == EXPECTED_MODELS,
            "positive records cover models %r"
            % sorted(set(m for m, _, _ in keys)))
    require(set(f for _, f, _ in keys) == EXPECTED_FILLERS,
            "positive records cover filler lengths %r"
            % sorted(set(f for _, f, _ in keys)))
    require(set(t for _, _, t in keys) == EXPECTED_TAILS,
            "positive records cover tail lengths %r"
            % sorted(set(t for _, _, t in keys)))

    negative = by_kind.get("negative", [])
    for data in negative:
        require(data.get("result") == "pass", "a negative control is not pass")
        require(data.get("child") == "103",
                "a negative control did not observe child=103")
        require(int(data.get("actual", "-1")) == int(data.get("tail")) - 1,
                "a negative control did not send a one-byte-short tail")
        require(data.get("declared") == data.get("tail"),
                "a negative control declared the truncated length")
    negative_keys = unique_keys(
        negative, lambda d: (d.get("model"), d.get("tail")), "negative")
    require(len(negative_keys) == models * tails,
            "negative records cover %d of %d declared combinations"
            % (len(negative_keys), models * tails))
    require(len(negative_keys) == int(summary["negative"]),
            "summary negative count %s disagrees with %d unique records"
            % (summary["negative"], len(negative_keys)))
    require(set(m for m, _ in negative_keys) == EXPECTED_MODELS,
            "negative controls cover models %r"
            % sorted(set(m for m, _ in negative_keys)))
    require(set(t for _, t in negative_keys) == EXPECTED_TAILS,
            "negative controls cover tail lengths %r"
            % sorted(set(t for _, t in negative_keys)))

    return {"positive": len(keys), "negative": len(negative_keys),
            "raw_fixtures": len(observed_fixtures)}


def verify_dll_unload(records):
    by_kind = {}
    for test, kind, data in records:
        if test == "dll_unload":
            by_kind.setdefault(kind, []).append(data)

    require(by_kind, "no dll_unload records were emitted")

    runtime = by_kind.get("runtime", [])
    require(len(runtime) == 1, "expected exactly one runtime binding record")
    binding = runtime[0]
    require(binding.get("result") == "pass", "runtime binding is not pass")
    for key in ("expected", "loaded", "final", "volume", "index"):
        require(binding.get(key) not in (None, "", "-"),
                "runtime binding lacks %s" % key)

    executable = by_kind.get("executable", [])
    require(len(executable) == 1, "expected exactly one executable record")
    require(executable[0].get("path") not in (None, "", "-"),
            "executable record lacks a path")

    derived = by_kind.get("derived", [])
    require(len(derived) == 1, "expected exactly one derived-path record")
    for key in ("helper", "runtime"):
        require(derived[0].get(key) not in (None, "", "-"),
                "derived record lacks %s" % key)

    export = by_kind.get("export", [])
    require(len(export) == 1, "expected exactly one export record")
    require(export[0].get("distinct") == "1",
            "the resolved export was not distinct from the static shim")
    require(export[0].get("resolved") != export[0].get("static"),
            "the resolved export equals the static shim")

    crosscheck = by_kind.get("runtime_root_crosscheck", [])
    require(len(crosscheck) == 1, "expected exactly one crosscheck record")
    require(crosscheck[0].get("result") == "pass", "crosscheck is not pass")

    cycles = by_kind.get("cycle", [])
    require(len(cycles) == 2, "expected exactly 2 unload cycles, saw %d"
            % len(cycles))
    seen_cycles = set()
    for data in cycles:
        number = data.get("cycle")
        require(number not in seen_cycles, "duplicate cycle record %r" % number)
        seen_cycles.add(number)
        require(data.get("result") == "pass", "cycle %r is not pass" % number)
        require(data.get("expected_unit") == EXPECTED_FULL,
                "cycle %r declares the wrong expected unit" % number)
        repeats = int(data.get("repeats", "0"))
        require(repeats == int(number),
                "cycle %r declares %d repeats" % (number, repeats))
        require(data.get("observed") == EXPECTED_FULL * repeats,
                "cycle %r observed %r" % (number, data.get("observed")))
    require(seen_cycles == {"1", "2"}, "cycle numbering is %r"
            % sorted(seen_cycles))

    controls = by_kind.get("control", [])
    seen_controls = set()
    for data in controls:
        name = data.get("control")
        require(name in EXPECTED_CONTROLS, "unexpected control %r" % name)
        require(name not in seen_controls, "duplicate control %r" % name)
        seen_controls.add(name)
        require(data.get("result") == "pass", "control %r is not pass" % name)
    require(seen_controls == EXPECTED_CONTROLS,
            "missing controls: %r" % sorted(EXPECTED_CONTROLS - seen_controls))

    omit = [d for d in controls if d.get("control") == "omit"][0]
    require(omit.get("observed") == EXPECTED_OMIT,
            "omit control observed %r" % omit.get("observed"))
    require(omit.get("positive_rejected") == "1",
            "the omit control was not rejected by the positive verifier")
    misassociated = [d for d in controls
                     if d.get("control") == "misassociated"][0]
    require(misassociated.get("replayed") == "0",
            "the mis-associated registration was replayed at dlclose")
    decoy = [d for d in controls
             if d.get("control") == "wrong-path-same-basename"][0]
    require(decoy.get("rejected") == "1",
            "the same-base-name decoy was not rejected")

    summaries = by_kind.get("summary", [])
    require(len(summaries) == 1, "expected exactly one dll_unload summary")
    require(int(summaries[0].get("cycles", "0")) == len(cycles),
            "dll_unload summary cycle count disagrees with the records")
    require(int(summaries[0].get("controls", "0")) == len(seen_controls),
            "dll_unload summary control count disagrees with the records")

    return {"cycles": len(cycles), "controls": len(seen_controls)}


def main(argv):
    if len(argv) < 2:
        raise RecordError("usage: verify-diagnostic-records.py LOG [LOG ...]")
    records = read_records(argv[1:])
    require(records, "no DIAG records were found in %r" % (argv[1:],))

    argv_counts = verify_argv_spawn(records)
    unload_counts = verify_dll_unload(records)

    print("records_total=%d" % len(records))
    print("argv_positive=%d" % argv_counts["positive"])
    print("argv_negative=%d" % argv_counts["negative"])
    print("argv_raw_fixtures=%d" % argv_counts["raw_fixtures"])
    print("unload_cycles=%d" % unload_counts["cycles"])
    print("unload_controls=%d" % unload_counts["controls"])
    print("records_verified=ok")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except RecordError as failure:
        sys.stderr.write("diagnostic record verification failed: %s\n"
                         % failure)
        sys.exit(1)
