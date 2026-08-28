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
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

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
ZERO_OID = "0" * 40

FORBIDDEN_GIT_ENV = {
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_COMMON_DIR",
    "GIT_DIR",
    "GIT_INDEX_FILE",
    "GIT_OBJECT_DIRECTORY",
    "GIT_REPLACE_REF_BASE",
    "GIT_SHALLOW_FILE",
    "GIT_WORK_TREE",
}
CONFIG_GIT_ENV = {
    "GIT_CONFIG",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_NOSYSTEM",
    "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_SYSTEM",
}
GIT_ENV = None
IGNORED_CONFIG_ENV = ()


class TrailerError(Exception):
    """Raised for any provenance defect; always fatal."""


def reject_git_path_overrides(environ):
    present = sorted(name for name in FORBIDDEN_GIT_ENV if environ.get(name))
    if present:
        raise TrailerError("forbidden Git path/object environment: %s"
                           % ", ".join(present))


def clean_git_environment(environ):
    """Return an environment whose Git behavior cannot use ambient config."""
    clean = {
        key: value for key, value in environ.items()
        if not key.startswith("GIT_")
    }
    clean.update({
        "GIT_CONFIG": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_SYSTEM": os.devnull,
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_TERMINAL_PROMPT": "0",
    })
    ignored = tuple(sorted(
        key for key, value in environ.items()
        if value and (key in CONFIG_GIT_ENV
                      or key.startswith("GIT_CONFIG_KEY_")
                      or key.startswith("GIT_CONFIG_VALUE_"))
    ))
    return clean, ignored


def initialize_git_environment(environ=None):
    global GIT_ENV, IGNORED_CONFIG_ENV
    source = os.environ if environ is None else environ
    reject_git_path_overrides(source)
    GIT_ENV, IGNORED_CONFIG_ENV = clean_git_environment(source)


def run_git(*args, cwd=None, input_data=None):
    if GIT_ENV is None:
        initialize_git_environment()
    process = subprocess.run(
        ("git", "--no-replace-objects", "-c", "core.commitGraph=false") + args,
        cwd=cwd,
        env=GIT_ENV,
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return process.returncode, process.stdout


def git_bytes(*args, cwd=None):
    code, out = run_git(*args, cwd=cwd)
    if code != 0:
        raise TrailerError("git %s exited %d" % (" ".join(args), code))
    return out


def git_text(*args, cwd=None):
    return git_bytes(*args, cwd=cwd).decode("utf-8", "replace").strip()


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
    if value == ZERO_OID:
        raise TrailerError("%s is the all-zero sentinel, not an object id"
                           % label)
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
    code, _ = run_git("merge-base", "--is-ancestor", commit, other)
    if code == 0:
        return True
    if code == 1:
        return False
    raise TrailerError("git merge-base --is-ancestor %s %s exited %d"
                       % (commit, other, code))


def absolute_git_path(path, cwd):
    if os.path.isabs(path):
        return os.path.normpath(path)
    return os.path.normpath(os.path.join(cwd, path))


def dangerous_local_config(key):
    key = key.lower()
    return (
        key in {
            "core.alternaterefscommand",
            "core.replacerefs",
            "core.shallowfile",
            "core.worktree",
            "extensions.objectformat",
            "extensions.partialclone",
            "extensions.worktreeconfig",
        }
        or key.startswith(("include.", "includeif.", "objects."))
        or (key.startswith("remote.")
            and key.endswith((".promisor", ".partialclonefilter")))
        or (key.startswith("url.")
            and key.endswith((".insteadof", ".pushinsteadof")))
    )


def require_safe_repository(cwd=None):
    """Reject graph/object inputs that could make provenance non-canonical."""
    root = os.path.abspath(cwd or os.getcwd())
    git_dir = git_text("rev-parse", "--absolute-git-dir", cwd=root)
    common = absolute_git_path(
        git_text("rev-parse", "--git-common-dir", cwd=root), root)
    object_dir = os.path.join(common, "objects")

    poison_paths = {
        os.path.join(git_dir, "info", "grafts"): "worktree graft file",
        os.path.join(common, "info", "grafts"): "common graft file",
        os.path.join(object_dir, "info", "alternates"): "object alternates",
        os.path.join(object_dir, "info", "commit-graph"):
            "single-file commit graph",
        os.path.join(object_dir, "info", "commit-graphs"):
            "chained commit graphs",
    }
    for path, label in poison_paths.items():
        if os.path.exists(path):
            raise TrailerError("%s is present at %s" % (label, path))

    code, replace_refs = run_git(
        "for-each-ref", "--format=%(refname)", "refs/replace", cwd=root)
    if code != 0:
        raise TrailerError("cannot enumerate replacement refs")
    if replace_refs.strip():
        raise TrailerError("replacement refs are present")

    packed_refs = os.path.join(common, "packed-refs")
    if os.path.isfile(packed_refs):
        try:
            with open(packed_refs, "rb") as handle:
                packed = handle.read()
        except OSError as error:
            raise TrailerError("cannot read packed refs: %s" % error)
        if b" refs/replace/" in packed:
            raise TrailerError("packed replacement refs are present")

    names = []
    for config_path in {
            os.path.join(common, "config"),
            os.path.join(git_dir, "config.worktree")}:
        if not os.path.isfile(config_path):
            continue
        inspect_env = GIT_ENV.copy()
        inspect_env.pop("GIT_CONFIG", None)
        process = subprocess.run(
            ("git", "--no-replace-objects", "config", "--file", config_path,
             "--no-includes", "--name-only", "-z", "--list"),
            cwd=root,
            env=inspect_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if process.returncode != 0:
            raise TrailerError("cannot inspect repository configuration %s"
                               % config_path)
        try:
            names.extend(
                value.decode("utf-8", "strict")
                for value in process.stdout.split(b"\x00") if value
            )
        except UnicodeDecodeError as error:
            raise TrailerError("local configuration is not UTF-8: %s"
                               % error)
    unsafe = sorted(name for name in names if dangerous_local_config(name))
    if unsafe:
        raise TrailerError("dangerous repository-local configuration: %s"
                           % ", ".join(unsafe))


def require_complete_repository(base, head):
    shallow = git_text("rev-parse", "--is-shallow-repository")
    if shallow != "false":
        raise TrailerError("repository is shallow (%s)" % shallow)
    code, listed = run_git(
        "rev-list", "--objects", "--missing=error", "%s..%s" % (base, head))
    if code != 0:
        raise TrailerError("object walk over %s..%s is incomplete"
                           % (base, head))
    counts = {"commit": 0, "tree": 0, "blob": 0}
    seen = set()
    for line in listed.splitlines():
        token = line.split(b" ", 1)[0]
        try:
            oid = canonical_oid("walked object", token.decode("ascii"))
        except (UnicodeDecodeError, TrailerError) as error:
            raise TrailerError("invalid rev-list object line %r: %s"
                               % (line, error))
        if oid in seen:
            raise TrailerError("rev-list repeated object %s" % oid)
        seen.add(oid)
        code, type_bytes = run_git("cat-file", "-t", oid)
        if code != 0:
            raise TrailerError("walked object %s is missing" % oid)
        kind = type_bytes.decode("ascii", "replace").strip()
        if kind not in counts:
            raise TrailerError("walked object %s has unexpected type %s"
                               % (oid, kind))
        raw = git_bytes("cat-file", kind, oid)
        computed = hashlib.sha1(
            kind.encode("ascii") + b" " + str(len(raw)).encode("ascii")
            + b"\x00" + raw).hexdigest()
        if computed != oid:
            raise TrailerError("recomputed %s object id %s does not match %s"
                               % (kind, computed, oid))
        counts[kind] += 1
    if not seen:
        raise TrailerError("object walk over %s..%s is empty" % (base, head))
    return counts


def expect_trailer_error(label, function):
    try:
        function()
    except TrailerError:
        return
    raise TrailerError("environment fixture %r was accepted" % label)


def remove_read_only(function, path, unused):
    del unused
    os.chmod(path, stat.S_IWRITE)
    function(path)


def environment_self_test():
    """Exercise environment, graft, alternate, replacement, and config poison."""
    fixtures = 0
    for name in sorted(FORBIDDEN_GIT_ENV):
        expect_trailer_error(
            "environment-" + name.lower(),
            lambda name=name: reject_git_path_overrides({name: "poison"}),
        )
        fixtures += 1

    fake = {
        "PATH": os.environ.get("PATH", ""),
        "GIT_CONFIG_COUNT": "1",
        "GIT_CONFIG_KEY_0": "core.replaceRefs",
        "GIT_CONFIG_VALUE_0": "true",
        "GIT_CONFIG_PARAMETERS": "'core.replaceRefs=true'",
        "GIT_EXEC_PATH": "poison",
    }
    cleaned, ignored = clean_git_environment(fake)
    if (cleaned.get("GIT_NO_REPLACE_OBJECTS") != "1"
        or cleaned.get("GIT_CONFIG_NOSYSTEM") != "1"
        or cleaned.get("GIT_CONFIG") != os.devnull
        or cleaned.get("GIT_CONFIG_GLOBAL") != os.devnull
        or "GIT_EXEC_PATH" in cleaned
        or set(ignored) != {
            "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0",
            "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_VALUE_0"
        }):
        raise TrailerError("config environment was not neutralized")
    fixtures += 1

    directory = tempfile.mkdtemp(prefix="diagnostic-provenance-")
    try:
        code, _ = run_git("init", "--quiet", "--object-format=sha1",
                          cwd=directory)
        if code != 0:
            raise TrailerError("cannot create provenance poison repository")
        require_safe_repository(directory)

        git_dir = git_text("rev-parse", "--absolute-git-dir", cwd=directory)
        common = absolute_git_path(
            git_text("rev-parse", "--git-common-dir", cwd=directory),
            directory)

        graft = os.path.join(common, "info", "grafts")
        os.makedirs(os.path.dirname(graft), exist_ok=True)
        with open(graft, "wb") as handle:
            handle.write(b"a" * 40 + b"\n")
        expect_trailer_error(
            "graft-file", lambda: require_safe_repository(directory))
        os.remove(graft)
        fixtures += 1

        alternates = os.path.join(common, "objects", "info", "alternates")
        os.makedirs(os.path.dirname(alternates), exist_ok=True)
        with open(alternates, "wb") as handle:
            handle.write(b"C:\\poison\n")
        expect_trailer_error(
            "object-alternates", lambda: require_safe_repository(directory))
        os.remove(alternates)
        fixtures += 1

        commit_graph = os.path.join(common, "objects", "info",
                                    "commit-graph")
        with open(commit_graph, "wb") as handle:
            handle.write(b"poison")
        expect_trailer_error(
            "commit-graph", lambda: require_safe_repository(directory))
        os.remove(commit_graph)
        fixtures += 1

        commit_graphs = os.path.join(common, "objects", "info",
                                     "commit-graphs")
        os.makedirs(commit_graphs)
        expect_trailer_error(
            "commit-graph-chain",
            lambda: require_safe_repository(directory))
        os.rmdir(commit_graphs)
        fixtures += 1

        code, blob = run_git("hash-object", "-w", "--stdin", cwd=directory,
                             input_data=b"fixture\n")
        if code != 0:
            raise TrailerError("cannot create replacement fixture blob")
        blob = blob.decode("ascii").strip()
        tree_input = ("100644 blob %s\tfile\n" % blob).encode("ascii")
        process = subprocess.run(
            ("git", "--no-replace-objects", "mktree"),
            cwd=directory,
            env=GIT_ENV,
            input=tree_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if process.returncode != 0:
            raise TrailerError("cannot create replacement fixture tree")
        tree = process.stdout.decode("ascii").strip()
        commits = []
        for subject in (b"one\n", b"two\n"):
            raw = (
                b"tree " + tree.encode("ascii")
                + b"\nauthor Fixture <fixture@example.invalid> 0 +0000"
                + b"\ncommitter Fixture <fixture@example.invalid> 0 +0000"
                + b"\n\n" + subject
            )
            code, commit = run_git(
                "hash-object", "-t", "commit", "-w", "--stdin",
                cwd=directory, input_data=raw)
            if code != 0:
                raise TrailerError("cannot create replacement fixture commit")
            commits.append(commit.decode("ascii").strip())
        code, _ = run_git("replace", commits[0], commits[1], cwd=directory)
        if code != 0:
            raise TrailerError("cannot create replacement ref fixture")
        expect_trailer_error(
            "replacement-ref", lambda: require_safe_repository(directory))
        code, _ = run_git("replace", "-d", commits[0], cwd=directory)
        if code != 0:
            raise TrailerError("cannot remove replacement ref fixture")
        fixtures += 1

        config_path = os.path.join(git_dir, "config")
        with open(config_path, "rb") as handle:
            clean_config = handle.read()
        with open(config_path, "ab") as handle:
            handle.write(b"\n[core]\n\treplaceRefs = true\n")
        expect_trailer_error(
            "local-config", lambda: require_safe_repository(directory))
        with open(config_path, "wb") as handle:
            handle.write(clean_config)
        fixtures += 1

        include_path = os.path.join(directory, "poison.config")
        with open(config_path, "ab") as handle:
            handle.write(
                b"\n[include]\n\tpath = "
                + include_path.encode("utf-8") + b"\n")
        expect_trailer_error(
            "local-include", lambda: require_safe_repository(directory))
        fixtures += 1
    finally:
        shutil.rmtree(directory, onerror=remove_read_only)
    return fixtures


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
        ("all-zero-sentinel", ZERO_OID),
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
    tree = b"a" * 40
    parent = b"b" * 40
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
                                    b"parent " + b"c" * 40, author,
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

    initialize_git_environment()
    environment_fixtures = environment_self_test()
    require_safe_repository()
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

    object_counts = require_complete_repository(base, head)

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
    print("environment_fixtures=%d" % environment_fixtures)
    print("ignored_config_environment=%d" % len(IGNORED_CONFIG_ENV))
    print("objects_rehashed=%d" % sum(object_counts.values()))
    for kind in ("commit", "tree", "blob"):
        print("%s_objects_rehashed=%d" % (kind, object_counts[kind]))
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
