#!/usr/bin/env python3
"""Fault-inject the actual configured cygwin make targets in a disposable copy."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import struct
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True,
                        help="Owned copy containing source, prefix and configured build/winsup/cygwin")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--stale-generator", type=Path, required=True)
    parser.add_argument("--stale-tls-generator", type=Path)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    build = root / "build/winsup/cygwin"
    source = root / "source/winsup/cygwin"
    guard = source / "scripts/guard-runtime-generation"
    if not guard.is_file() or str(root) not in (build / "Makefile").read_text():
        raise ValueError("Use the newly configured owned proposal, never a preserved producer tree")
    args.output.mkdir(parents=True, exist_ok=False)
    out = args.output.resolve()
    if not out.is_relative_to(root):
        raise ValueError("Evidence and injected fixtures must stay within the owned proposal")
    fixtures = out / "fixtures"
    fixtures.mkdir()
    env = dict(os.environ, PATH=str(root / "prefix/bin") + ":/usr/bin:/bin", SOURCE_DATE_EPOCH="1788224411")
    names = ("tlsoffsets", "msys.def", "sigfe.s", "sigfe.o",
             "tlsoffsets.generation.json", "sigfe.s.generation.json")
    report = {"schema": 1, "status": "failed", "makefile_sha256": sha(build / "Makefile"),
              "source_makefile_sha256": sha(source / "Makefile.am"), "guard_sha256": sha(guard),
              "test_sha256": sha(Path(__file__).resolve()),
              "stale_generator_sha256": sha(args.stale_generator), "cases": []}

    def inventory():
        return {name: sha(build / name) if (build / name).exists() else None for name in names}

    def make(name, expect_success, *options, preserve=None, target="sigfe.o"):
        command = ["make", "-C", str(build), "-j1", "V=1", target, *options]
        stdout, stderr = out / (name + ".stdout"), out / (name + ".stderr")
        with stdout.open("xb") as a, stderr.open("xb") as b:
            result = subprocess.run(command, env=env, stdout=a, stderr=b, timeout=90)
        after = inventory()
        report["cases"].append({"name": name, "command": command, "exit": result.returncode,
                                "expectedSuccess": expect_success, "outputs": after,
                                "stdout_sha256": sha(stdout), "stderr_sha256": sha(stderr)})
        if (result.returncode == 0) != expect_success:
            raise ValueError(f"Unexpected actual make result: {name}: {stderr.read_text()[-2000:]}")
        if not expect_success and not stderr.stat().st_size:
            raise ValueError(f"Failure was not diagnosed: {name}")
        if preserve is not None and after != preserve:
            raise ValueError(f"Failed generation changed existing artifacts: {name}")

    def signal_fixture(name, action):
        path = fixtures / name
        path.write_text(
            "#!/usr/bin/env perl\nuse strict; use warnings;\n"
            "use Getopt::Long; my ($cpu, $out); my @original = @ARGV;\n"
            "GetOptions('cpu=s'=>\\$cpu,'output-def=s'=>\\$out) or die;\n"
            f"system($^X, {json.dumps(str(source / 'scripts/gendef'))}, @original) == 0 or die;\n"
            + action + "\n", encoding="utf-8", newline="\n")
        return "SIGNAL_GENERATOR=" + str(path)

    try:
        # Recompile the copied object with this configured build's own flags,
        # so the later clean-regeneration comparison has the same debug paths.
        if (build / "sigfe.o").exists():
            (out / "copied-sigfe.o").write_bytes((build / "sigfe.o").read_bytes())
            (build / "sigfe.o").unlink()
        make("initial-valid-generation", True)
        good = inventory()
        tls = (build / "tlsoffsets").read_bytes()
        if (len(tls) != 1822 or tls.count(b".equ ") != 59
                or good["tlsoffsets"] != "49ac682b8f5ed4295d03abc2dab5953fc472684d42eb0b87d779057942b23566"):
            raise ValueError("Actual make did not preserve the qualified 59-entry TLS layout")
        report["qualified_tls"] = {"bytes": len(tls), "entries": tls.count(b".equ "),
                                   "sha256": good["tlsoffsets"]}
        raw = (build / "sigfe.o").read_bytes()
        if struct.unpack_from("<H", raw)[0] != 0xaa64:
            raise ValueError("Successful actual make did not produce ARM64 COFF")
        times = {name: (build / name).stat().st_mtime_ns for name in names}
        make("unchanged-repeat", True, preserve=good)
        if {name: (build / name).stat().st_mtime_ns for name in names} != times:
            raise ValueError("Unchanged make rewrote/reassembled valid generated artifacts")
        saved = {name: (build / name).read_bytes() for name in names}

        make("real-stale-x86-generator", False,
             "SIGNAL_GENERATOR=" + str(args.stale_generator.resolve()), preserve=good)
        make("empty-assembly-after-zero-exit", False,
             signal_fixture("empty-signal", "open my $f, '>', 'sigfe.s' or die; close $f or die;"), preserve=good)
        make("generator-fails-after-writing", False,
             signal_fixture("failed-signal", "die \"injected late generator failure\\n\";"), preserve=good)
        make("missing-trampoline-label", False, signal_fixture("missing-label",
             "local $/; open my $f, '<', 'sigfe.s' or die; my $s=<$f>; close $f;\n"
             "$s =~ s/^_sigfe_malloc:/_removed_malloc:/m or die;\n"
             "open $f, '>', 'sigfe.s' or die; print $f $s; close $f or die;"), preserve=good)
        make("missing-public-provider", False, signal_fixture("missing-public",
             "local $/; open my $f, '<', 'sigfe.s' or die; my $s=<$f>; close $f;\n"
             "$s =~ s/^\\s*\\.global\\s+_sigfe_malloc\\s*$//m or die;\n"
             "open $f, '>', 'sigfe.s' or die; print $f $s; close $f or die;"), preserve=good)
        make("dropped-source-export-from-both", False, signal_fixture("dropped-export",
             "local $/; open my $f, '<', $out or die; my $s=<$f>; close $f;\n"
             "$s =~ s/^malloc\\s*=.*\\n//m or die;\n"
             "open $f, '>', $out or die; print $f $s; close $f or die;\n"
             "open $f, '<', 'sigfe.s' or die; $s=<$f>; close $f;\n"
             "$s =~ s/^_sigfe_malloc:/_removed_malloc:/m or die;\n"
             "open $f, '>', 'sigfe.s' or die; print $f $s; close $f or die;"), preserve=good)

        for name, data in (("zero-offsets", ".equ _cygtls.start_offset, 0\n"),
                           ("malformed-offsets", "not a TLS offset\n")):
            generator = fixtures / name
            generator.write_text("#!/usr/bin/env bash\nset -eu\nprintf '%s' "
                                 + "'" + data.replace("'", "'\\''") + "' > \"$2\"\n",
                                 encoding="utf-8", newline="\n")
            make(name, False, "GENTLS_OFFSETS=" + str(generator), preserve=good)
        make("compiler-failure", False, "CXXCOMPILE=false", preserve=good, target="tlsoffsets")
        if args.stale_tls_generator:
            make("real-long-only-tls-generator", False,
                 "GENTLS_OFFSETS=" + str(args.stale_tls_generator.resolve()), preserve=good)
            # The old script only accepts a basename (it constructs /tmp/$2.$$).
            # Adapt the output pathname, not its parser, to reproduce .word loss.
            adapter = fixtures / "historical-tls-basename"
            captured = fixtures / "historical-tls-output"
            adapter.write_text(
                "#!/usr/bin/env bash\nset -u\n"
                "saved=.historical-tls-$$\ntrap 'rm -f -- \"$saved\"' EXIT\nstatus=0\n"
                f"bash {shlex.quote(str(args.stale_tls_generator.resolve()))} \"$1\" \"$saved\" || status=$?\n"
                "if [[ -f $saved ]]; then\n"
                f"  cp -- \"$saved\" {shlex.quote(str(captured))}\n"
                "  mv -- \"$saved\" \"$2\"\nfi\nexit \"$status\"\n",
                encoding="utf-8", newline="\n")
            make("real-long-only-parser-with-relative-output", False,
                 "GENTLS_OFFSETS=" + str(adapter), preserve=good)
            if not captured.is_file():
                raise ValueError("Historical parser did not produce its invalid offset payload")
            if (captured.stat().st_size != 56
                    or sha(captured) != "95e965fc1beea943c3eadc2cd941c34b01a3151968a0ffbe6917b354d2f0d8a5"):
                raise ValueError("Historical parser did not reproduce the qualified 56-byte payload")
            report["historical_tls_payload"] = {
                "path": str(captured), "bytes": captured.stat().st_size, "sha256": sha(captured),
                "text": captured.read_text(),
                "scope": "Unmodified old parser; wrapper only adapts its basename-only output convention."}

        changed_signal = signal_fixture("unchanged-signal", "")
        changed_tls = fixtures / "unchanged-tls"
        changed_tls.write_bytes((source / "scripts/gentls_offsets").read_bytes())
        for damage in ("corrupt", "missing"):
            for name in ("sigfe.s", "msys.def", "tlsoffsets"):
                try:
                    # Model an output published before its receipt while inputs
                    # also change: a stale signature must not mask the damage.
                    if damage == "corrupt":
                        (build / name).write_bytes(saved[name] + b"\n# interrupted publication\n")
                    else:
                        (build / name).unlink()
                    option = ("GENTLS_OFFSETS=" + str(changed_tls)
                              if name == "tlsoffsets" else changed_signal)
                    make("reject-changed-input-" + damage + "-" + name.replace(".", "-"),
                         False, option, preserve=inventory())
                finally:
                    for artifact in names:
                        (build / artifact).write_bytes(saved[artifact])
                        os.utime(build / artifact,
                                 ns=((build / artifact).stat().st_atime_ns, times[artifact]))

        changed_options = (changed_signal, "GENTLS_OFFSETS=" + str(changed_tls))
        make("valid-changed-input-regeneration", True, *changed_options)
        for name in names[:4]:
            if sha(build / name) != good[name] or (build / name).stat().st_mtime_ns != times[name]:
                raise ValueError(f"Equivalent changed inputs rewrote/reassembled {name}")
        changed_times = {name: (build / name).stat().st_mtime_ns for name in names}
        make("changed-input-unchanged-repeat", True, *changed_options, preserve=inventory())
        if {name: (build / name).stat().st_mtime_ns for name in names} != changed_times:
            raise ValueError("Changed-input no-op rewrote generated artifacts or receipts")
        make("restore-original-inputs", True, preserve=good)

        for name in ("sigfe.s", "tlsoffsets", "msys.def"):
            path = build / name
            try:
                path.write_bytes(b"")
                os.utime(path, ns=(path.stat().st_atime_ns, times[name] + 10_000_000_000))
                corrupt = inventory()
                make("reject-newer-corrupt-" + name.replace(".", "-"), False, preserve=corrupt)
            finally:
                path.write_bytes(saved[name])
                os.utime(path, ns=(path.stat().st_atime_ns, times[name]))

        # Drop all generated outputs/receipts only in this disposable copy;
        # normal make must regenerate both stages with the real compiler.
        for name in names:
            (build / name).unlink()
        make("clean-regeneration", True)
        regenerated = inventory()
        for name in ("tlsoffsets", "msys.def", "sigfe.s", "sigfe.o"):
            if regenerated[name] != good[name]:
                raise ValueError(f"Clean regeneration changes qualified bytes: {name}")
        report.update(status="actual-runtime-make-generation-guards-qualified",
                      casesPassed=len(report["cases"]), generated=regenerated,
                      limits="Host generation/actual make and ARM64 assembly only; no DLL rebuild or changed runtime ABI.")
    finally:
        (out / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(out / "result.json")


if __name__ == "__main__":
    main()
