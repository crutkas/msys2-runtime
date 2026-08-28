#!/usr/bin/env python3
"""Verify the closed machine-readable contract of a passing diagnostic run.

Every DIAG line is part of the contract.  Unknown tests, kinds, fields, duplicate
keys, malformed values, missing records, and extra records are fatal.  The
expected matrices live here rather than being inferred from binary summaries.
"""

import itertools
import re
import sys


EXPECTED_FULL = "RTYXCAD"
EXPECTED_OMIT = "RTCAD"
EXPECTED_MODELS = {"spawnv", "execv", "CreateProcessW"}
EXPECTED_FILLERS = {"0", "1", "15", "16", "17", "31"}
EXPECTED_TAILS = {"1", "23", "24", "511", "640", "1023", "2047",
                  "4095", "4096"}
EXPECTED_RAW_FIXTURES = {
    "accepted": 0,
    "missing-command-line": 107,
    "tail-absent": 108,
    "tail-ambiguous": 109,
    "tail-left-glued": 110,
    "tail-right-glued": 111,
}
EXPECTED_FILLER_CONTROLS = {
    "shortened": 15,
    "extended": 17,
}
EXPECTED_BINDING_CONTROLS = {
    "wrong-path-same-basename": "rejected",
    "path-case": "bound",
    "path-prefix": "bound",
    "hardlink-alias": "rejected",
    "file-symlink": "bound",
    "directory-junction": "bound",
    "directory-symlink-reparse": "bound",
}
EXPECTED_CONTROLS = set(EXPECTED_BINDING_CONTROLS) | {
    "omit", "misassociated"
}

ARGV_SCHEMAS = {
    "wincmdln": {"nowincmdln", "msys", "cygwin", "result"},
    "raw-fixture": {"case", "expected", "observed", "result"},
    "positive": {
        "model", "filler_declared", "filler_observed",
        "tail_declared", "tail_observed", "child", "result",
    },
    "negative": {
        "model", "filler_declared", "filler_observed",
        "tail_declared", "tail_observed", "child", "result",
    },
    "filler-control": {
        "model", "case", "filler_declared", "filler_observed",
        "tail_declared", "tail_observed", "child", "result",
    },
    "summary": {
        "positive", "negative", "filler_controls", "fixtures",
        "models", "fillers", "tails", "result",
    },
}
DLL_SCHEMAS = {
    "executable": {"path", "result"},
    "derived": {"helper", "runtime", "result"},
    "runtime_root_crosscheck": {"performed", "result"},
    "runtime": {
        "volume", "index", "expected", "loaded", "final",
        "expected_handle_open", "loaded_handle_open", "delete_share", "result",
    },
    "export": {"resolved", "static", "distinct", "result"},
    "cycle": {"cycle", "observed", "expected_unit", "repeats", "result"},
    "summary": {"cycles", "controls", "result"},
}
IDENTITY_CONTROL_SCHEMA = {
    "control", "expected", "observed", "path", "result"
}
OMIT_CONTROL_SCHEMA = {
    "control", "observed", "expected", "positive_rejected", "result"
}
MISASSOCIATED_CONTROL_SCHEMA = {"control", "replayed", "result"}

EXPECTED_ARGV = (
    1 + len(EXPECTED_RAW_FIXTURES)
    + len(EXPECTED_MODELS) * len(EXPECTED_FILLERS) * len(EXPECTED_TAILS)
    + len(EXPECTED_MODELS) * len(EXPECTED_TAILS)
    + len(EXPECTED_MODELS) * len(EXPECTED_FILLER_CONTROLS)
    + 1
)
EXPECTED_DLL = 5 + 2 + len(EXPECTED_CONTROLS) + 1
EXPECTED_TOTAL = EXPECTED_ARGV + EXPECTED_DLL

KEY_PATTERN = re.compile(r"\A[A-Za-z_][A-Za-z0-9_-]*\Z")
UINT_PATTERN = re.compile(r"\A(?:0|[1-9][0-9]*)\Z")
HEX8_PATTERN = re.compile(r"\A[0-9a-f]{8}\Z")
HEX16_PATTERN = re.compile(r"\A[0-9a-f]{16}\Z")
POINTER_PATTERN = re.compile(r"\A0x[0-9a-fA-F]+\Z")


class RecordError(Exception):
    """Raised when emitted evidence is not the exact closed contract."""


def require(condition, message):
    if not condition:
        raise RecordError(message)


def parse_field(token, data, source):
    key, separator, value = token.partition("=")
    require(separator and KEY_PATTERN.match(key) and value != "",
            "%s has malformed field %r" % (source, token))
    require(key not in data, "%s repeats field %r" % (source, key))
    data[key] = value
    return key


def parse_record(line, source):
    fields = line.strip().split()
    if not fields or fields[0] != "DIAG":
        return None
    require(len(fields) >= 3, "%s has a truncated DIAG record" % source)
    test = fields[1]
    require(test in {"argv_spawn", "dll_unload"},
            "%s has unknown test %r" % (source, test))

    data = {}
    kind_token = fields[2]
    if "=" in kind_token:
        kind = parse_field(kind_token, data, source)
    else:
        require(KEY_PATTERN.match(kind_token),
                "%s has malformed record kind %r" % (source, kind_token))
        kind = kind_token
    for token in fields[3:]:
        parse_field(token, data, source)
    return (test, kind, data, line.strip(), source)


def read_records(paths):
    records = []
    for path in paths:
        try:
            with open(path, "r", encoding="utf-8", errors="strict") as handle:
                lines = handle.readlines()
        except (OSError, UnicodeError) as error:
            raise RecordError("cannot read %s: %s" % (path, error))
        for number, line in enumerate(lines, 1):
            record = parse_record(line, "%s:%d" % (path, number))
            if record is not None:
                records.append(record)
    return records


def parse_lines(lines, label):
    records = []
    for number, line in enumerate(lines, 1):
        record = parse_record(line, "%s:%d" % (label, number))
        if record is not None:
            records.append(record)
    return records


def canonical_uint(value, label):
    require(UINT_PATTERN.match(value), "%s is not canonical unsigned decimal"
            % label)
    return int(value)


def require_literal(data, key, expected, label):
    require(data[key] == expected, "%s has %s=%r, expected %r"
            % (label, key, data[key], expected))


def require_path(value, label):
    require(value not in ("", "-"), "%s is missing" % label)


def require_schema(record):
    test, kind, data, unused_raw, source = record
    del unused_raw
    if test == "argv_spawn":
        expected = ARGV_SCHEMAS.get(kind)
        if expected is None:
            require(False, "%s has unknown argv_spawn kind %r"
                    % (source, kind))
            return
    else:
        if kind == "control":
            name = data.get("control")
            require(name in EXPECTED_CONTROLS,
                    "%s has unknown dll_unload control %r" % (source, name))
            if name in EXPECTED_BINDING_CONTROLS:
                expected = IDENTITY_CONTROL_SCHEMA
            elif name == "omit":
                expected = OMIT_CONTROL_SCHEMA
            else:
                expected = MISASSOCIATED_CONTROL_SCHEMA
        else:
            require(kind in DLL_SCHEMAS,
                    "%s has unknown dll_unload kind %r" % (source, kind))
            expected = DLL_SCHEMAS[kind]
    actual = set(data)
    require(actual == expected,
            "%s %s/%s fields are %r, expected %r"
            % (source, test, kind, sorted(actual), sorted(expected)))


def records_for(records, test, kind):
    return [record for record in records
            if record[0] == test and record[1] == kind]


def single(records, test, kind):
    found = records_for(records, test, kind)
    require(len(found) == 1, "expected exactly one %s/%s record, saw %d"
            % (test, kind, len(found)))
    return found[0][2]


def unique_keys(data_records, builder, label):
    seen = set()
    for data in data_records:
        key = builder(data)
        require(key not in seen, "duplicate %s record %r" % (label, key))
        seen.add(key)
    return seen


def verify_argv_spawn(records):
    wincmdln = single(records, "argv_spawn", "wincmdln")
    require_literal(wincmdln, "nowincmdln", "0", "wincmdln")
    require_literal(wincmdln, "result", "pass", "wincmdln")

    fixtures = [record[2] for record in
                records_for(records, "argv_spawn", "raw-fixture")]
    fixture_names = unique_keys(fixtures, lambda data: data["case"],
                                "raw fixture")
    require(fixture_names == set(EXPECTED_RAW_FIXTURES),
            "raw fixture cases are %r" % sorted(fixture_names))
    for data in fixtures:
        name = data["case"]
        expected = EXPECTED_RAW_FIXTURES[name]
        require(canonical_uint(data["expected"], "%s expected" % name)
                == expected, "%s declares the wrong expected code" % name)
        require(canonical_uint(data["observed"], "%s observed" % name)
                == expected, "%s observed the wrong code" % name)
        require_literal(data, "result", "pass", "raw fixture " + name)

    positives = [record[2] for record in
                 records_for(records, "argv_spawn", "positive")]
    positive_keys = unique_keys(
        positives,
        lambda data: (
            data["model"], data["filler_declared"], data["tail_declared"]
        ),
        "positive",
    )
    expected_positive = set(itertools.product(
        EXPECTED_MODELS, EXPECTED_FILLERS, EXPECTED_TAILS))
    require(positive_keys == expected_positive,
            "positive records do not cover the exact fixed matrix")
    for data in positives:
        label = "positive %r" % ((
            data["model"], data["filler_declared"], data["tail_declared"]),)
        require(data["model"] in EXPECTED_MODELS,
                "%s has unknown model" % label)
        canonical_uint(data["filler_declared"], label + " filler_declared")
        canonical_uint(data["filler_observed"], label + " filler_observed")
        canonical_uint(data["tail_declared"], label + " tail_declared")
        canonical_uint(data["tail_observed"], label + " tail_observed")
        require_literal(data, "filler_observed", data["filler_declared"],
                        label)
        require_literal(data, "tail_observed", data["tail_declared"], label)
        require_literal(data, "child", "0", label)
        require_literal(data, "result", "pass", label)

    negatives = [record[2] for record in
                 records_for(records, "argv_spawn", "negative")]
    negative_keys = unique_keys(
        negatives,
        lambda data: (data["model"], data["tail_declared"]),
        "negative",
    )
    require(negative_keys == set(itertools.product(
        EXPECTED_MODELS, EXPECTED_TAILS)),
        "negative records do not cover the exact fixed matrix")
    for data in negatives:
        label = "negative %r" % ((
            data["model"], data["tail_declared"]),)
        declared = canonical_uint(data["tail_declared"],
                                  label + " tail_declared")
        observed = canonical_uint(data["tail_observed"],
                                  label + " tail_observed")
        require_literal(data, "filler_declared", "16", label)
        require_literal(data, "filler_observed", "16", label)
        require(observed + 1 == declared,
                "%s is not exactly one byte short" % label)
        require_literal(data, "child", "103", label)
        require_literal(data, "result", "pass", label)

    filler_controls = [record[2] for record in
                       records_for(records, "argv_spawn", "filler-control")]
    filler_keys = unique_keys(
        filler_controls,
        lambda data: (data["model"], data["case"]),
        "filler control",
    )
    require(filler_keys == set(itertools.product(
        EXPECTED_MODELS, EXPECTED_FILLER_CONTROLS)),
        "filler controls do not cover every model and boundary")
    for data in filler_controls:
        label = "filler control %r" % ((
            data["model"], data["case"]),)
        require_literal(data, "filler_declared", "16", label)
        require(canonical_uint(data["filler_observed"],
                               label + " filler_observed")
                == EXPECTED_FILLER_CONTROLS[data["case"]],
                "%s observed the wrong filler length" % label)
        require_literal(data, "tail_declared", "24", label)
        require_literal(data, "tail_observed", "24", label)
        require_literal(data, "child", "102", label)
        require_literal(data, "result", "pass", label)

    summary = single(records, "argv_spawn", "summary")
    expected_summary = {
        "positive": len(expected_positive),
        "negative": len(negative_keys),
        "filler_controls": len(filler_keys),
        "fixtures": len(EXPECTED_RAW_FIXTURES),
        "models": len(EXPECTED_MODELS),
        "fillers": len(EXPECTED_FILLERS),
        "tails": len(EXPECTED_TAILS),
    }
    for key, expected in expected_summary.items():
        require(canonical_uint(summary[key], "argv summary " + key)
                == expected, "argv summary %s is not %d" % (key, expected))
    require_literal(summary, "result", "pass", "argv summary")
    return {
        "positive": len(positive_keys),
        "negative": len(negative_keys),
        "filler_controls": len(filler_keys),
        "raw_fixtures": len(fixture_names),
    }


def verify_dll_unload(records):
    executable = single(records, "dll_unload", "executable")
    require_path(executable["path"], "executable path")
    require_literal(executable, "result", "pass", "executable")

    derived = single(records, "dll_unload", "derived")
    require_path(derived["helper"], "derived helper path")
    require_path(derived["runtime"], "derived runtime path")
    require_literal(derived, "result", "pass", "derived")

    crosscheck = single(records, "dll_unload", "runtime_root_crosscheck")
    require_literal(crosscheck, "performed", "1", "runtime_root crosscheck")
    require_literal(crosscheck, "result", "pass", "runtime_root crosscheck")

    runtime = single(records, "dll_unload", "runtime")
    require(HEX8_PATTERN.match(runtime["volume"]),
            "runtime volume is not eight lowercase hex digits")
    require(HEX16_PATTERN.match(runtime["index"]),
            "runtime index is not sixteen lowercase hex digits")
    for key in ("expected", "loaded", "final"):
        require_path(runtime[key], "runtime " + key)
    for key in ("expected_handle_open", "loaded_handle_open"):
        require_literal(runtime, key, "1", "runtime")
    require_literal(runtime, "delete_share", "0", "runtime")
    require_literal(runtime, "result", "pass", "runtime")

    exported = single(records, "dll_unload", "export")
    require(POINTER_PATTERN.match(exported["resolved"]),
            "resolved export is not a pointer")
    require(POINTER_PATTERN.match(exported["static"]),
            "static shim is not a pointer")
    require(int(exported["resolved"], 16) != 0,
            "resolved export is a null pointer")
    require(int(exported["static"], 16) != 0,
            "static shim is a null pointer")
    require(exported["resolved"].lower() != exported["static"].lower(),
            "resolved export equals the static shim")
    require_literal(exported, "distinct", "1", "export")
    require_literal(exported, "result", "pass", "export")

    cycles = [record[2] for record in
              records_for(records, "dll_unload", "cycle")]
    cycle_numbers = unique_keys(cycles, lambda data: data["cycle"], "cycle")
    require(cycle_numbers == {"1", "2"},
            "cycle numbering is %r" % sorted(cycle_numbers))
    for data in cycles:
        number = canonical_uint(data["cycle"], "cycle number")
        require_literal(data, "expected_unit", EXPECTED_FULL,
                        "cycle %d" % number)
        require(canonical_uint(data["repeats"], "cycle repeats") == number,
                "cycle %d repeats do not match its number" % number)
        require_literal(data, "observed", EXPECTED_FULL * number,
                        "cycle %d" % number)
        require_literal(data, "result", "pass", "cycle %d" % number)

    controls = [record[2] for record in
                records_for(records, "dll_unload", "control")]
    control_names = unique_keys(controls, lambda data: data["control"],
                                "control")
    require(control_names == EXPECTED_CONTROLS,
            "control names are %r" % sorted(control_names))
    by_name = {data["control"]: data for data in controls}
    for name, expected in EXPECTED_BINDING_CONTROLS.items():
        data = by_name[name]
        require_literal(data, "expected", expected, name)
        require_literal(data, "observed", expected, name)
        require_path(data["path"], name + " path")
        require_literal(data, "result", "pass", name)

    omit = by_name["omit"]
    require_literal(omit, "observed", EXPECTED_OMIT, "omit")
    require_literal(omit, "expected", EXPECTED_OMIT, "omit")
    require_literal(omit, "positive_rejected", "1", "omit")
    require_literal(omit, "result", "pass", "omit")
    misassociated = by_name["misassociated"]
    require_literal(misassociated, "replayed", "0", "misassociated")
    require_literal(misassociated, "result", "pass", "misassociated")

    summary = single(records, "dll_unload", "summary")
    require(canonical_uint(summary["cycles"], "dll summary cycles") == 2,
            "dll summary cycle count is not 2")
    require(canonical_uint(summary["controls"], "dll summary controls")
            == len(EXPECTED_CONTROLS),
            "dll summary control count is not %d" % len(EXPECTED_CONTROLS))
    require_literal(summary, "result", "pass", "dll summary")
    return {"cycles": len(cycles), "controls": len(control_names)}


def verify_records(records):
    require(len(records) == EXPECTED_TOTAL,
            "expected exactly %d DIAG records, saw %d"
            % (EXPECTED_TOTAL, len(records)))
    for record in records:
        require_schema(record)
    argv_counts = verify_argv_spawn(records)
    unload_counts = verify_dll_unload(records)
    require(sum(1 for record in records if record[0] == "argv_spawn")
            == EXPECTED_ARGV, "argv record total is not %d" % EXPECTED_ARGV)
    require(sum(1 for record in records if record[0] == "dll_unload")
            == EXPECTED_DLL, "dll record total is not %d" % EXPECTED_DLL)
    return argv_counts, unload_counts


def verify_record_schemas(records):
    require(len(records) == EXPECTED_TOTAL,
            "expected exactly %d DIAG records, saw %d"
            % (EXPECTED_TOTAL, len(records)))
    for record in records:
        require_schema(record)


def replace_once(lines, predicate, old, new):
    changed = list(lines)
    indexes = [index for index, line in enumerate(changed)
               if predicate(line)]
    require(len(indexes) == 1,
            "mutation source matched %d records, expected one" % len(indexes))
    index = indexes[0]
    require(old in changed[index], "mutation source lacks %r" % old)
    changed[index] = changed[index].replace(old, new, 1)
    return changed


def replace_record_once(lines, target_predicate, source_predicate):
    changed = list(lines)
    targets = [index for index, line in enumerate(changed)
               if target_predicate(line)]
    sources = [index for index, line in enumerate(changed)
               if source_predicate(line)]
    require(len(targets) == 1 and len(sources) == 1,
            "record replacement matched %d targets and %d sources"
            % (len(targets), len(sources)))
    changed[targets[0]] = changed[sources[0]]
    return changed


def mutation_self_test(records):
    lines = [record[3] for record in records]
    positive = lambda line: (
        line.startswith("DIAG argv_spawn positive model=spawnv ")
        and "filler_declared=0 " in line
        and "tail_declared=1 " in line
    )
    duplicate_positive = lambda line: (
        line.startswith("DIAG argv_spawn positive model=execv ")
        and "filler_declared=0 " in line
        and "tail_declared=1 " in line
    )
    derived = lambda line: line.startswith("DIAG dll_unload derived ")
    dll_summary = lambda line: line.startswith("DIAG dll_unload summary ")
    crosscheck = lambda line: line.startswith(
        "DIAG dll_unload runtime_root_crosscheck ")
    mutations = [
        ("unknown-record-kind",
         replace_once(lines, positive, "DIAG argv_spawn positive ",
                      "DIAG argv_spawn bogus_kind "),
         "unknown argv_spawn kind 'bogus_kind'", "unknown-argv-kind",
         verify_record_schemas),
        ("unknown-field",
         replace_once(lines, positive, " result=pass",
                      " unknown=1 result=pass"),
         "argv_spawn/positive fields are", "exact-schema", verify_records),
        ("duplicate-field",
         replace_once(lines, positive, " result=pass",
                      " result=fail result=pass"),
         "repeats field 'result'", "duplicate-field", verify_records),
        ("derived-failure",
         replace_once(lines, derived, "result=pass", "result=fail"),
         "derived has result='fail', expected 'pass'", "derived-result",
         verify_records),
        ("dll-summary-failure",
         replace_once(lines, dll_summary, "result=pass", "result=fail"),
         "dll summary has result='fail', expected 'pass'",
         "dll-summary-result", verify_records),
        ("crosscheck-not-performed",
         replace_once(lines, crosscheck, "performed=1", "performed=0"),
         "runtime_root crosscheck has performed='0', expected '1'",
         "runtime-root-performed", verify_records),
        ("missing-record", lines[1:],
         "expected exactly 220 DIAG records, saw 219", "exact-total",
         verify_records),
        ("extra-duplicate-record",
         replace_record_once(lines, positive, duplicate_positive),
         "duplicate positive record ('execv', '0', '1')",
         "duplicate-positive-key", verify_records),
    ]
    outcomes = []
    for name, mutated, expected_error, guard, verifier in mutations:
        expected_count = EXPECTED_TOTAL - (name == "missing-record")
        require(len(mutated) == expected_count,
                "mutation %r has %d records, expected %d"
                % (name, len(mutated), expected_count))
        try:
            verifier(parse_lines(mutated, "mutation-" + name))
        except RecordError as error:
            require(expected_error in str(error),
                    "mutation %r was rejected for the wrong reason: %s"
                    % (name, error))
            outcomes.append((name, guard))
            continue
        raise RecordError("mutation %r was accepted" % name)
    return outcomes


def main(argv):
    if len(argv) < 2:
        raise RecordError("usage: verify-diagnostic-records.py LOG [LOG ...]")
    records = read_records(argv[1:])
    require(records, "no DIAG records were found in %r" % (argv[1:],))
    argv_counts, unload_counts = verify_records(records)
    mutations = mutation_self_test(records)

    print("records_total=%d" % len(records))
    print("argv_positive=%d" % argv_counts["positive"])
    print("argv_negative=%d" % argv_counts["negative"])
    print("argv_filler_controls=%d" % argv_counts["filler_controls"])
    print("argv_raw_fixtures=%d" % argv_counts["raw_fixtures"])
    print("unload_cycles=%d" % unload_counts["cycles"])
    print("unload_controls=%d" % unload_counts["controls"])
    for name, guard in mutations:
        print("record_mutation=%s rejected_by=%s result=pass"
              % (name, guard))
    print("record_mutation_fixtures=%d" % len(mutations))
    print("record_contract=closed")
    print("records_verified=ok")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except RecordError as failure:
        sys.stderr.write("diagnostic record verification failed: %s\n"
                         % failure)
        sys.exit(1)
