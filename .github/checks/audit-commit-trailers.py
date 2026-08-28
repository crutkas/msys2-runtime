#!/usr/bin/env python3
"""Raw-byte trailer audit for the diagnostic commit range.

Commit objects are read with ``git cat-file commit``, their object ids are
recomputed independently from the raw bytes, and the terminal trailer block is
validated byte for byte.  Nothing here relies on git's message-normalising
porcelain, and no commit byte is ever routed through a shell variable, so
carriage returns, NUL bytes and byte order marks cannot be silently stripped
before the check sees them.

A set of synthetic malformed commit objects is validated first.  Each one must
be rejected, which proves the validator still discriminates the shapes it is
meant to reject rather than accepting everything it is shown.
"""

import hashlib
import subprocess
import sys

BOM = b"\xef\xbb\xbf"
SIGNOFF_PREFIX = b"Signed-off-by: "
COAUTHOR_LINE = (b"Co-authored-by: Copilot App "
                 b"<223556219+Copilot@users.noreply.github.com>")
SESSION_PREFIX = b"Copilot-Session: "
TRAILER_LINES = 3


class TrailerError(Exception):
    """Raised for any provenance defect; always fatal."""


def git_bytes(*args):
    process = subprocess.run(("git",) + args, stdout=subprocess.PIPE)
    if process.returncode != 0:
        raise TrailerError("git %s exited %d" % (" ".join(args),
                                                 process.returncode))
    return process.stdout


def is_ancestor(commit, other):
    process = subprocess.run(("git", "merge-base", "--is-ancestor",
                              commit, other))
    if process.returncode == 0:
        return True
    if process.returncode == 1:
        return False
    raise TrailerError("git merge-base --is-ancestor %s %s exited %d"
                       % (commit, other, process.returncode))


def object_id(raw):
    header = b"commit " + str(len(raw)).encode("ascii") + b"\x00"
    return hashlib.sha1(header + raw).hexdigest()


def validate(raw, commit_id, dco, session):
    if not raw:
        raise TrailerError("empty commit object")

    computed = object_id(raw)
    if computed != commit_id:
        raise TrailerError("recomputed object id %s does not match %s"
                           % (computed, commit_id))

    if BOM in raw:
        raise TrailerError("byte order mark in commit object")
    if b"\r" in raw:
        raise TrailerError("carriage return in commit object")
    if b"\x00" in raw:
        raise TrailerError("NUL byte in commit object")

    separator = raw.find(b"\n\n")
    if separator < 0:
        raise TrailerError("no header/message separator")

    message = raw[separator + 2:]
    if not message:
        raise TrailerError("empty commit message")
    if not message.endswith(b"\n"):
        raise TrailerError("commit message does not end with LF")
    if message.endswith(b"\n\n"):
        raise TrailerError("commit message ends with more than one LF")

    lines = message[:-1].split(b"\n")
    expected = [SIGNOFF_PREFIX + dco, COAUTHOR_LINE, SESSION_PREFIX + session]
    if len(lines) < TRAILER_LINES + 1:
        raise TrailerError("commit message is too short for a trailer block")
    if lines[-TRAILER_LINES:] != expected:
        raise TrailerError("terminal trailer block is %r, expected %r"
                           % (lines[-TRAILER_LINES:], expected))
    if lines[-TRAILER_LINES - 1] != b"":
        raise TrailerError("trailer block is not preceded by a blank line")

    for needle in expected:
        occurrences = sum(1 for line in lines if line == needle)
        if occurrences != 1:
            raise TrailerError("trailer %r occurs %d times"
                               % (needle, occurrences))
    for prefix in (SIGNOFF_PREFIX, COAUTHOR_LINE, SESSION_PREFIX):
        occurrences = sum(1 for line in lines if line.startswith(prefix))
        if occurrences != 1:
            raise TrailerError("trailer prefix %r occurs %d times"
                               % (prefix, occurrences))


def self_test():
    """Reject synthetic malformed commit objects before auditing real ones."""
    dco = b"Test User <test@example.invalid>"
    session = b"00000000-0000-0000-0000-000000000000"
    header = (b"tree " + b"0" * 40 + b"\n"
              + b"author T <t@example.invalid> 0 +0000\n"
              + b"committer T <t@example.invalid> 0 +0000\n")
    block = (SIGNOFF_PREFIX + dco + b"\n" + COAUTHOR_LINE + b"\n"
             + SESSION_PREFIX + session + b"\n")

    def build(message):
        return header + b"\n" + message

    good = build(b"subject\n\nbody\n\n" + block)

    def rejects(name, raw, commit_id=None):
        try:
            validate(raw, commit_id or object_id(raw), dco, session)
        except TrailerError:
            return
        raise TrailerError("malformed fixture %r was accepted" % name)

    validate(good, object_id(good), dco, session)

    rejects("empty-object", b"")
    rejects("wrong-object-id", good, "0" * 40)
    rejects("no-message", header + b"\n")
    rejects("carriage-return", build(b"subject\r\n\nbody\n\n" + block))
    rejects("byte-order-mark", build(BOM + b"subject\n\nbody\n\n" + block))
    rejects("nul-byte", build(b"subject\x00\n\nbody\n\n" + block))
    rejects("missing-terminal-lf", good[:-1])
    rejects("double-terminal-lf", good + b"\n")
    rejects("no-blank-line", build(b"subject\nbody\n" + block))
    rejects("duplicate-signoff",
            build(b"subject\n\n" + SIGNOFF_PREFIX + dco + b"\n\n" + block))
    rejects("missing-session",
            build(b"subject\n\nbody\n\n" + SIGNOFF_PREFIX + dco + b"\n"
                  + COAUTHOR_LINE + b"\n"))
    rejects("non-contiguous-block",
            build(b"subject\n\nbody\n\n" + SIGNOFF_PREFIX + dco + b"\n"
                  + COAUTHOR_LINE + b"\n\n" + SESSION_PREFIX + session
                  + b"\n"))
    rejects("reordered-block",
            build(b"subject\n\nbody\n\n" + COAUTHOR_LINE + b"\n"
                  + SIGNOFF_PREFIX + dco + b"\n" + SESSION_PREFIX + session
                  + b"\n"))
    rejects("foreign-dco",
            build(b"subject\n\nbody\n\n" + SIGNOFF_PREFIX
                  + b"Someone Else <else@example.invalid>\n" + COAUTHOR_LINE
                  + b"\n" + SESSION_PREFIX + session + b"\n"))
    print("self_test_fixtures=14")


def resolve(candidate):
    if not candidate:
        raise TrailerError("empty object id")
    resolved = git_bytes("rev-parse", "--verify",
                         candidate + "^{commit}").strip()
    if not resolved:
        raise TrailerError("object %s resolved to nothing" % candidate)
    return resolved.decode("ascii")


def main(argv):
    if len(argv) < 5:
        raise TrailerError(
            "usage: BASE HEAD DCO DEFAULT_SESSION [BOUNDARY=SESSION ...]")

    base = resolve(argv[1])
    head = resolve(argv[2])
    dco = argv[3].encode("utf-8")
    default_session = argv[4].encode("ascii")
    if not argv[3] or not argv[4]:
        raise TrailerError("DCO identity and default session are required")

    boundaries = []
    for item in argv[5:]:
        boundary, marker, session_id = item.partition("=")
        if not marker or not boundary or not session_id:
            raise TrailerError("malformed boundary %r" % item)
        boundaries.append((resolve(boundary), session_id.encode("ascii")))

    self_test()

    revision_range = "%s..%s" % (base, head)
    commits = git_bytes("rev-list", "--reverse", revision_range).split()
    if not commits:
        raise TrailerError("commit range %s is empty" % revision_range)

    for commit in commits:
        commit_id = commit.decode("ascii")
        session = default_session
        for boundary, boundary_session in boundaries:
            if is_ancestor(commit_id, boundary):
                session = boundary_session
                break
        raw = git_bytes("cat-file", "commit", commit_id)
        try:
            validate(raw, commit_id, dco, session)
        except TrailerError as error:
            raise TrailerError("%s: %s" % (commit_id, error))
        print("trailer_ok=%s session=%s"
              % (commit_id, session.decode("ascii")))

    print("audited_commits=%d" % len(commits))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except TrailerError as failure:
        sys.stderr.write("commit trailer audit failed: %s\n" % failure)
        sys.exit(1)
