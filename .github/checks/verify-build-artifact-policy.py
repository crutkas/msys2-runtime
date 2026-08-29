#!/usr/bin/env python3
"""Verify the ordinary build workflow's diagnostic-branch artifact policy.

This executes a source-policy model, not live GitHub events.  It reads the
workflow text, requires the two actual job guards to be identical, and models
those guards together with both current trigger filters and explicitly
configured future-event scenarios over the complete policy truth table.
"""

import re
import sys


DIAGNOSTIC_BRANCH = "crutkas-finish-runtime-diagnostics"
REPOSITORY = "crutkas/msys2-runtime"
GUARD = (
    "${{ github.event_name != 'pull_request' || "
    "github.event.pull_request.head.repo.full_name != github.repository || "
    "github.event.pull_request.head.ref != "
    "'crutkas-finish-runtime-diagnostics' }}"
)
FUTURE_EVENTS = ("workflow_dispatch", "schedule", "workflow_call",
                 "merge_group")


class PolicyError(Exception):
    """Raised when workflow source and the asserted policy disagree."""


def require(condition, message):
    if not condition:
        raise PolicyError(message)


def leading_spaces(line):
    return len(line) - len(line.lstrip(" "))


def indented_block(lines, start, indent):
    block = []
    for line in lines[start:]:
        if line.strip() and leading_spaces(line) < indent:
            break
        block.append(line)
    return block


def find_line(lines, value):
    matches = [index for index, line in enumerate(lines) if line == value]
    require(len(matches) == 1, "expected exactly one %r line, saw %d"
            % (value, len(matches)))
    return matches[0]


def configured_events(lines):
    start = find_line(lines, "on:")
    block = indented_block(lines, start + 1, 2)
    events = {
        match.group(1)
        for line in block
        for match in [re.match(r"^  ([A-Za-z_][A-Za-z0-9_]*):", line)]
        if match
    }
    supported = {"push", "pull_request"} | set(FUTURE_EVENTS)
    require({"push", "pull_request"} <= events,
            "build workflow must retain push and pull_request events")
    require(events <= supported,
            "build workflow has an unmodelled event in %r" % sorted(events))
    return events, block


def require_push_filters(on_block):
    text = "\n".join(on_block)
    branch_pattern = (
        r"(?m)^    branches-ignore:\n"
        r"      - " + re.escape(DIAGNOSTIC_BRANCH) + r"$"
    )
    tag_pattern = r"(?m)^    tags:\n      - '\*\*'$"
    require(len(re.findall(branch_pattern, text)) == 1,
            "push does not exclude exactly the diagnostic branch")
    require(len(re.findall(tag_pattern, text)) == 1,
            "push does not explicitly include every tag")


def job_block(lines, name):
    start = find_line(lines, "  %s:" % name)
    return indented_block(lines, start + 1, 4)


def folded_if(block, name):
    indexes = [index for index, line in enumerate(block)
               if line == "    if: >-"]
    require(len(indexes) == 1, "%s must have exactly one folded if guard"
            % name)
    scalar = indented_block(block, indexes[0] + 1, 6)
    value = " ".join(line.strip() for line in scalar if line.strip())
    require(value == GUARD, "%s guard is %r, expected %r"
            % (name, value, GUARD))
    return value


def guard_allows(event, head_repository="", head_ref=""):
    return not (
        event == "pull_request"
        and head_repository == REPOSITORY
        and head_ref == DIAGNOSTIC_BRANCH
    )


def trigger_allows(events, event, ref_type="", ref_name=""):
    if event not in events:
        return False
    if event != "push":
        return True
    if ref_type == "tag":
        return True
    return ref_type == "branch" and ref_name != DIAGNOSTIC_BRANCH


def run_truth_table(events):
    cases = [
        ("diagnostic-branch-push", "push", "branch", DIAGNOSTIC_BRANCH,
         "", "", False, True),
        ("other-branch-push", "push", "branch", "feature", "", "",
         True, True),
        ("tag-push", "push", "tag", "v1.2.3", "", "", True, True),
        ("same-repository-pr", "pull_request", "", "",
         REPOSITORY, DIAGNOSTIC_BRANCH, True, False),
        ("same-leaf-fork-pr", "pull_request", "", "",
         "fork-owner/msys2-runtime", DIAGNOSTIC_BRANCH, True, True),
        ("other-pr", "pull_request", "", "", REPOSITORY, "feature",
         True, True),
    ]
    future_events = set(events) | set(FUTURE_EVENTS)

    for (name, event, ref_type, ref_name, head_repository, head_ref,
         expected_trigger, expected_guard) in cases:
        triggered = trigger_allows(events, event, ref_type, ref_name)
        allowed = guard_allows(event, head_repository, head_ref)
        require(triggered == expected_trigger,
                "%s trigger was %r, expected %r"
                % (name, triggered, expected_trigger))
        require(allowed == expected_guard,
                "%s job guard was %r, expected %r"
                % (name, allowed, expected_guard))
        artifact = triggered and allowed
        print(
            "policy_case=%s event=%s source_configured=%d"
            " scenario_configured=1 workflow_triggered=%d "
            "job_guard=%d artifact_job=%d"
            " basis=executed-source-policy-model "
            "coverage=synthetic-event-input result=pass"
            % (name, event, event in events, triggered, allowed, artifact)
        )

    for event in FUTURE_EVENTS:
        triggered = trigger_allows(future_events, event)
        allowed = guard_allows(event)
        require(triggered, "%s configured-future trigger was suppressed" % event)
        require(allowed, "%s configured-future job guard was suppressed" % event)
        print(
            "policy_case=%s-configured-future event=%s source_configured=%d"
            " scenario_configured=1 workflow_triggered=1 job_guard=1"
            " artifact_job=1 basis=executed-source-policy-model"
            " coverage=synthetic-event-input result=pass"
            % (event, event, event in events)
        )
    return len(cases) + len(FUTURE_EVENTS)


def main(argv):
    if len(argv) != 2:
        raise PolicyError("usage: verify-build-artifact-policy.py WORKFLOW")
    try:
        with open(argv[1], "r", encoding="utf-8", errors="strict") as handle:
            source = handle.read()
    except OSError as error:
        raise PolicyError("cannot read %s: %s" % (argv[1], error))
    require("\x00" not in source, "workflow contains a NUL byte")
    lines = source.splitlines()

    events, on_block = configured_events(lines)
    require_push_filters(on_block)
    build = job_block(lines, "build")
    matrix = job_block(lines, "generate-msys2-tests-matrix")
    require(folded_if(build, "build") == folded_if(
        matrix, "generate-msys2-tests-matrix"),
        "artifact and matrix guards differ")
    require(any("actions/upload-artifact@" in line for line in build),
            "build is no longer the artifact-producing job")
    require(
        sum("actions/upload-artifact@" in line for line in lines)
        == sum("actions/upload-artifact@" in line for line in build),
        "an artifact upload exists outside the guarded build job")
    require(not any("actions/upload-artifact@" in line for line in matrix),
            "matrix generator unexpectedly uploads an artifact")

    tested = run_truth_table(events)
    print("classification=diagnostic")
    print("consumable=false")
    print("evidence_kind=executed-source-policy-model")
    print("configured_events=%s" % ",".join(sorted(events)))
    print("policy_cases=%d" % tested)
    print("build_artifact_policy=ok")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (PolicyError, UnicodeError) as failure:
        sys.stderr.write("build artifact policy verification failed: %s\n"
                         % failure)
        sys.exit(1)
