#!/usr/bin/env python3
"""Strict raw-byte provenance audit for the diagnostic commit range.

Every object id handled here must be a canonical lowercase 40 character SHA-1
hex string.  Revision syntax, abbreviations, symbolic names such as HEAD and
non-canonical spellings are rejected before git ever sees them, and the
repository object format is checked explicitly so the recomputed hashes mean
what they claim to mean.

Commit objects are read with ``git cat-file commit`` and validated on their
raw bytes: the object id is recomputed independently, the header block is
parsed strictly, and the terminal trailer block is compared byte for byte.
Nothing is routed through git's message-normalising porcelain or through a
shell variable, so carriage returns, NUL bytes and byte order marks cannot be
stripped before the check sees them.

Synthetic malformed fixtures are validated first.  Each one must be rejected,
which proves the auditor still discriminates every shape it is meant to
reject instead of accepting whatever it is shown.
"""

import hashlib
import re
import subprocess
import sys

BOM = b"\xef\xbb\xbf"
SIGNOFF_PREFIX = b"Signed-off-by: "
COAUTHOR_LINE = (b"Co-authored-by: Copilot App "
                 b"<223556219+Copilot@users.noreply.github.com>")
SESSION_PREFIX = b"Copilot-Session: "
TRAILER_LINES = 3
EXPECTED_REVOKED = 4

OID_PATTERN = re.compile(r"\A[0-9a-f]{40}\Z")
HEADER_PATTERN = re.compile(rb"\A(tree|parent|author|committer) (.+)\Z")
IDENT_PATTERN = re.compile(rb"\A(.+ <[^<>]*>) (\d+) ([+-]\d{4})\Z")


class TrailerError(Exception):
    """Raised for any provenance defect; always fatal."""


def run_git(*args):
    process = subprocess.run(("git",) + args, stdout=subprocess.PIPE)
    return process.returncode, process.stdout


def git_bytes(*args):
    code, out = run_git(*args)
    if code != 0:
        raise TrailerError("git %s exited %d" % (" ".join(args), code))
    return out


def git_text(*args):
    return git_bytes(*args).decode("utf-8", "replace").strip()


def require_object_format():
    fmt = git_text("rev-parse", "--show-object-format")
    if fmt != "sha1":
        raise TrailerError("repository object format is %r, expected sha1"
                           % fmt)
    return fmt


def canonical_oid(label, value):
    """Accept only a canonical lowercase 40 hex character SHA-1 object id."""
    if isinstance(value, bytes):
        try:
            value = value.decode("ascii")
        except UnicodeDecodeError:
            raise TrailerError("%s object id is not ASCII" % label)
    if not isinstance(value, str) or not OID_PATTERN.match(value):
        raise TrailerError(
            "%s %r is not a canonical lowercase 40 hex sha1 object id"
            % (label, value))
    return value


def resolve_exact_commit(label, value):
    """The id must already name exactly that commit object."""
    oid = canonical_oid(label, value)
    code, out = run_git("cat-file", "-t", oid)
    if code != 0:
        raise TrailerError("%s %s is absent from the repository"
                           % (label, oid))
    kind = out.decode("ascii", "replace").strip()
    if kind != "commit":
        raise TrailerError("%s %s is a %s, not a commit" % (label, oid, kind))
    code, out = run_git("rev-parse", "--verify", "--end-of-options",
                        oid + "^{commit}")
    if code != 0:
        raise TrailerError("%s %s does not verify as a commit" % (label, oid))
    resolved = out.decode("ascii", "replace").strip()
    if resolved != oid:
        raise TrailerError("%s %s resolves to a different object %s"
                           % (label, oid, resolved))
    return oid


def is_ancestor(commit, other):
    """0 means ancestor, 1 means not; anything else is an audit failure."""
    code = subprocess.run(("git", "merge-base", "--is-ancestor",
                           commit, other)).returncode
    if code == 0:
        return True
    if code == 1:
        return False
    raise TrailerError("git merge-base --is-ancestor %s %s exited %d"
                       % (commit, other, code))


def require_complete_repository(base, head):
    shallow = git_text("rev-parse", "--is-shallow-repository")
    if shallow != "false":
        raise TrailerError("repository is shallow (%s)" % shallow)
    code, _ = run_git("rev-list", "--objects", "%s..%s" % (base, head))
    if code != 0:
        raise TrailerError("object walk over %s..%s is incomplete"
                           % (base, head))


def parse_commit_object(raw, oid, dco, session, expect_parents):
    if not raw:
        raise TrailerError("empty commit object")

    computed = hashlib.sha1(
        b"commit " + str(len(raw)).encode("ascii") + b"\x00" + raw).hexdigest()
    if computed != oid:
        raise TrailerError("recomputed object id %s does not match %s"
                           % (computed, oid))

    if BOM in raw:
        raise TrailerError("byte order mark in commit object")
    if b"\r" in raw:
        raise TrailerError("carriage return in commit object")
    if b"\x00" in raw:
        raise TrailerError("NUL byte in commit object")
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise TrailerError("commit object is not valid UTF-8: %s" % error)

    separator = raw.find(b"\n\n")
    if separator < 0:
        raise TrailerError("no header/message separator")

    order = []
    values = {}
    parents = []
    for line in raw[:separator].split(b"\n"):
        if line.startswith(b" ") or line.startswith(b"\t"):
            raise TrailerError("unsupported header continuation %r" % line)
        match = HEADER_PATTERN.match(line)
        if not match:
            raise TrailerError("malformed or unknown commit header %r" % line)
        key = match.group(1).decode("ascii")
        order.append(key)
        if key == "parent":
            parents.append(match.group(2))
        elif key in values:
            raise TrailerError("duplicate %s header" % key)
        else:
            values[key] = match.group(2)

    for mandatory in ("tree", "author", "committer"):
        if mandatory not in values:
            raise TrailerError("missing %s header" % mandatory)
    if len(parents) != expect_parents:
        raise TrailerError("commit has %d parent headers, expected %d"
                           % (len(parents), expect_parents))
    if order != ["tree"] + ["parent"] * expect_parents + ["author",
                                                          "committer"]:
        raise TrailerError("unexpected header order %r" % (order,))

    canonical_oid("tree", values["tree"])
    for parent in parents:
        canonical_oid("parent", parent)

    for key in ("author", "committer"):
        match = IDENT_PATTERN.match(values[key])
        if not match:
            raise TrailerError("malformed %s header %r" % (key, values[key]))
        if match.group(1) != dco:
            raise TrailerError("%s identity is %r, expected %r"
                               % (key, match.group(1), dco))

    message = raw[separator + 2:]
    if not message:
        raise TrailerError("empty commit message")
    if not message.endswith(b"\n"):
        raise TrailerError("commit message does not end with LF")
    if message.endswith(b"\n\n"):
        raise TrailerError("commit message ends with more than one LF")

    lines = message[:-1].split(b"\n")
    subject = lines[0]
    if not subject.strip():
        raise TrailerError("empty or missing subject")
    if subject != subject.strip():
        raise TrailerError("subject has leading or trailing whitespace")

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

    return {"tree": values["tree"].decode("ascii"),
            "parents": [p.decode("ascii") for p in parents]}


def oid_self_test():
    """Every rejected spelling here is one an auditor asked us to refuse."""
    good = "282caff1360a0f4f43280a797fe7f9f9f1abcb8c"
    canonical_oid("fixture", good)

    rejected = [
        ("symbolic-head", "HEAD"),
        ("symbolic-branch", "refs/heads/crutkas-finish-runtime-diagnostics"),
        ("abbreviated", good[:12]),
        ("short-by-one", good[:39]),
        ("long-by-one", good + "0"),
        ("uppercase", good.upper()),
        ("mixed-case", good[:8].upper() + good[8:]),
        ("caret-suffix", good + "^"),
        ("commit-peel", good + "^{commit}"),
        ("tilde-suffix", good + "~1"),
        ("range-syntax", good + ".." + good),
        ("path-syntax", good + ":winsup"),
        ("leading-space", " " + good),
        ("trailing-newline", good + "\n"),
        ("non-hex", "z" * 40),
        ("empty", ""),
    ]
    for name, value in rejected:
        try:
            canonical_oid("fixture", value)
        except TrailerError:
            continue
        raise TrailerError("object id fixture %r was accepted" % name)
    return len(rejected)


def commit_self_test():
    dco = b"Test User <test@example.invalid>"
    session = b"00000000-0000-0000-0000-000000000000"
    tree = b"0" * 40
    parent = b"1" * 40
    stamp = b" 0 +0000"
    author = b"author " + dco + stamp
    committer = b"committer " + dco + stamp
    block = (SIGNOFF_PREFIX + dco + b"\n" + COAUTHOR_LINE + b"\n"
             + SESSION_PREFIX + session + b"\n")
    body = b"subject\n\nbody\n\n" + block

    def build(headers, message=body):
        return b"\n".join(headers) + b"\n\n" + message

    headers = [b"tree " + tree, b"parent " + parent, author, committer]
    good = build(headers)

    def oid_of(raw):
        return hashlib.sha1(
            b"commit " + str(len(raw)).encode("ascii") + b"\x00"
            + raw).hexdigest()

    parse_commit_object(good, oid_of(good), dco, session, 1)

    fixtures = [
        ("empty-object", b"", None),
        ("wrong-object-id", good, "0" * 40),
        ("no-message", b"\n".join(headers) + b"\n\n", None),
        ("carriage-return", build(headers, b"subject\r\n\nbody\n\n" + block),
         None),
        ("byte-order-mark", build(headers, BOM + b"subject\n\nbody\n\n"
                                  + block), None),
        ("nul-byte", build(headers, b"subject\x00\n\nbody\n\n" + block), None),
        ("invalid-utf8", build(headers, b"subject\xff\n\nbody\n\n" + block),
         None),
        ("missing-terminal-lf", good[:-1], None),
        ("double-terminal-lf", good + b"\n", None),
        ("no-blank-line", build(headers, b"subject\nbody\n" + block), None),
        ("empty-subject", build(headers, b"\n\nbody\n\n" + block), None),
        ("subject-trailing-space",
         build(headers, b"subject \n\nbody\n\n" + block), None),
        ("duplicate-signoff",
         build(headers, b"subject\n\n" + SIGNOFF_PREFIX + dco + b"\n\n"
               + block), None),
        ("missing-session",
         build(headers, b"subject\n\nbody\n\n" + SIGNOFF_PREFIX + dco + b"\n"
               + COAUTHOR_LINE + b"\n"), None),
        ("non-contiguous-block",
         build(headers, b"subject\n\nbody\n\n" + SIGNOFF_PREFIX + dco + b"\n"
               + COAUTHOR_LINE + b"\n\n" + SESSION_PREFIX + session + b"\n"),
         None),
        ("reordered-block",
         build(headers, b"subject\n\nbody\n\n" + COAUTHOR_LINE + b"\n"
               + SIGNOFF_PREFIX + dco + b"\n" + SESSION_PREFIX + session
               + b"\n"), None),
        ("foreign-signoff",
         build(headers, b"subject\n\nbody\n\n" + SIGNOFF_PREFIX
               + b"Someone Else <else@example.invalid>\n" + COAUTHOR_LINE
               + b"\n" + SESSION_PREFIX + session + b"\n"), None),
        ("missing-tree", build([b"parent " + parent, author, committer]),
         None),
        ("missing-parent", build([b"tree " + tree, author, committer]), None),
        ("missing-author", build([b"tree " + tree, b"parent " + parent,
                                  committer]), None),
        ("missing-committer", build([b"tree " + tree, b"parent " + parent,
                                     author]), None),
        ("duplicate-tree", build([b"tree " + tree, b"tree " + tree,
                                  b"parent " + parent, author, committer]),
         None),
        ("duplicate-author", build([b"tree " + tree, b"parent " + parent,
                                    author, author, committer]), None),
        ("multiple-parents", build([b"tree " + tree, b"parent " + parent,
                                    b"parent " + b"2" * 40, author,
                                    committer]), None),
        ("unknown-header", build([b"tree " + tree, b"parent " + parent,
                                  author, committer,
                                  b"gpgsig -----BEGIN-----"]), None),
        ("header-continuation", build([b"tree " + tree, b"parent " + parent,
                                       author, committer,
                                       b" continuation"]), None),
        ("header-out-of-order", build([b"parent " + parent, b"tree " + tree,
                                       author, committer]), None),
        ("malformed-header-line", build([b"tree " + tree, b"parent " + parent,
                                         author, committer, b"bogus"]), None),
        ("uppercase-tree-oid", build([b"tree " + b"A" * 40,
                                      b"parent " + parent, author,
                                      committer]), None),
        ("abbreviated-tree-oid", build([b"tree " + b"0" * 12,
                                        b"parent " + parent, author,
                                        committer]), None),
        ("malformed-author-ident",
         build([b"tree " + tree, b"parent " + parent, b"author Broken",
                committer]), None),
        ("wrong-author-identity",
         build([b"tree " + tree, b"parent " + parent,
                b"author Other <other@example.invalid>" + stamp, committer]),
         None),
        ("wrong-committer-identity",
         build([b"tree " + tree, b"parent " + parent, author,
                b"committer Other <other@example.invalid>" + stamp]), None),
    ]

    for name, raw, forced in fixtures:
        try:
            parse_commit_object(raw, forced or oid_of(raw), dco, session, 1)
        except TrailerError:
            continue
        raise TrailerError("malformed commit fixture %r was accepted" % name)
    return len(fixtures)


def main(argv):
    if len(argv) < 9:
        raise TrailerError(
            "usage: BASE LEGACY_HEAD LEGACY_SESSION PRIOR_HEAD PRIOR_SESSION"
            " HEAD SESSION DCO REVOKED...")

    object_format = require_object_format()
    oid_fixtures = oid_self_test()
    commit_fixtures = commit_self_test()

    base = resolve_exact_commit("base", argv[1])
    legacy_head = resolve_exact_commit("legacy head", argv[2])
    legacy_session = argv[3]
    prior_head = resolve_exact_commit("prior head", argv[4])
    prior_session = argv[5]
    head = resolve_exact_commit("head", argv[6])
    session = argv[7]
    dco_text = argv[8]
    revoked_args = argv[9:]

    for label, value in (("legacy session", legacy_session),
                         ("prior session", prior_session),
                         ("session", session),
                         ("DCO identity", dco_text)):
        if not value or value.strip() != value:
            raise TrailerError("%s %r is empty or padded" % (label, value))

    dco = dco_text.encode("utf-8")

    checked_out = canonical_oid("checked out head", git_text("rev-parse",
                                                             "HEAD"))
    if checked_out != head:
        raise TrailerError("checked out head %s is not the audited head %s"
                           % (checked_out, head))

    require_complete_repository(base, head)

    if not is_ancestor(base, head):
        raise TrailerError("base %s is not an ancestor of head %s"
                           % (base, head))
    if not is_ancestor(base, legacy_head):
        raise TrailerError("base %s is not an ancestor of legacy head %s"
                           % (base, legacy_head))
    if not is_ancestor(legacy_head, prior_head):
        raise TrailerError("legacy head %s is not an ancestor of prior head %s"
                           % (legacy_head, prior_head))
    if not is_ancestor(prior_head, head):
        raise TrailerError("prior head %s is not an ancestor of head %s"
                           % (prior_head, head))

    if len(revoked_args) != EXPECTED_REVOKED:
        raise TrailerError("expected exactly %d revoked commits, received %d"
                           % (EXPECTED_REVOKED, len(revoked_args)))
    revoked = []
    for value in revoked_args:
        oid = resolve_exact_commit("revoked commit", value)
        if oid in revoked:
            raise TrailerError("revoked commit %s supplied more than once"
                               % oid)
        revoked.append(oid)
    if len(set(revoked)) != EXPECTED_REVOKED:
        raise TrailerError("revoked commits are not distinct")
    for oid in revoked:
        if is_ancestor(oid, head):
            raise TrailerError("revoked commit %s is an ancestor of %s"
                               % (oid, head))
        print("revoked_absent=%s" % oid)

    boundaries = [(legacy_head, legacy_session.encode("ascii")),
                  (prior_head, prior_session.encode("ascii"))]

    commits = [canonical_oid("range commit", value.decode("ascii"))
               for value in git_bytes("rev-list", "--reverse",
                                      "%s..%s" % (base, head)).split()]
    if not commits:
        raise TrailerError("commit range %s..%s is empty" % (base, head))

    previous = base
    head_tree = None
    for oid in commits:
        commit_session = session.encode("ascii")
        for boundary, boundary_session in boundaries:
            if is_ancestor(oid, boundary):
                commit_session = boundary_session
                break
        raw = git_bytes("cat-file", "commit", oid)
        try:
            parsed = parse_commit_object(raw, oid, dco, commit_session, 1)
        except TrailerError as error:
            raise TrailerError("%s: %s" % (oid, error))
        if parsed["parents"][0] != previous:
            raise TrailerError(
                "%s has parent %s but follows %s in the linear range"
                % (oid, parsed["parents"][0], previous))
        previous = oid
        head_tree = parsed["tree"]
        print("commit_ok=%s session=%s"
              % (oid, commit_session.decode("ascii")))

    if previous != head:
        raise TrailerError("linear walk ended at %s, expected %s"
                           % (previous, head))

    print("classification=diagnostic")
    print("consumable=false")
    print("object_format=%s" % object_format)
    print("oid_fixtures=%d" % oid_fixtures)
    print("commit_fixtures=%d" % commit_fixtures)
    print("revoked_tested=%d" % len(revoked))
    print("audited_commits=%d" % len(commits))
    print("base=%s" % base)
    print("legacy_head=%s" % legacy_head)
    print("prior_head=%s" % prior_head)
    print("head=%s" % head)
    print("tree=%s" % head_tree)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except TrailerError as failure:
        sys.stderr.write("commit provenance audit failed: %s\n" % failure)
        sys.exit(1)
