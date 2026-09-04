#!/bin/bash
# Prepend an unmissable provenance header to runtime-uncommitted.diff, then
# re-verify that the patch is still complete and still parses.
set -u
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
P="$D/runtime-uncommitted.diff"

# strip any header from a previous run so this is idempotent
if grep -q '^# REPRODUCTION ARTIFACT' "$P"; then
  sed -n '/^diff --git /,$p' "$P" > "$P.body"
else
  cp "$P" "$P.body"
fi

cat > "$P.hdr" <<'HDREOF'
# =====================================================================
# ==  REPRODUCTION ARTIFACT -- NOT A PROPOSED PATCH.                 ==
# ==  DO NOT SUBMIT, COMMIT, OR TREAT THIS AS "THE ARM64 PORT".      ==
# =====================================================================
#
# PURPOSE (the only one): rebuilding the preserved /root/xc binaries
# (libc.a, libm.a, libgcc.a, the import libraries, libdll.a). Nothing else.
#
# WHAT IS ACTUALLY IN HERE -- read the attribution, not the raw total:
#
#     REAL PORT WORK      35 files,  846 insertions,  53 deletions
#     AUTOTOOLS NOISE      8 files,  847 insertions, 707 deletions
#     ------------------------------------------------------------
#     raw total           43 files, 1693 insertions, 760 deletions
#
# Roughly HALF of this diff is not port work at all. `config.guess` alone is
# +645/-591 -- a newer upstream copy of the script, pure regeneration noise.
# Also boilerplate: install-sh +107/-67, depcomp +40/-5, config.sub, compile,
# missing, mkinstalldirs, test-driver.
#
# The 760 deletions look alarming and are not: 707 of them (93%) are autotools
# boilerplate, 591 from config.guess alone. Only 53 deletions are port work.
# NOTE: the 12 `ld128` comment-outs are NOT in this diff -- they live in the
# GENERATED file /root/xc/bld/newlib/Makefile, which is not tracked by git.
#
# THE ACTUAL SEALED ARM64 PORT IS A DIFFERENT, SMALLER ARTIFACT:
#     29 files, 785 insertions, 51 deletions
#     preserved at session 724ee2e9's files/arm64-port-backup-2026-09-02
#     (redundant copy in the coordinator chat's session files)
# and even THAT is bring-up evidence, not a shippable change.
#
# This file = that sealed port
#            + throwaway diagnostics from TWO sessions
#            + newlib and build-invocation hacks
#            + the P19_DISPATCHER_CONTEXT token swap AND ITS MISLEADING COMMENTS.
#
# Specifically contains changes that are KNOWN-WRONG outside w32api v12.0.0:
#   winsup/cygwin/local_includes/exception.h:13-18  (comment claims the struct
#     is plain _DISPATCHER_CONTEXT "on every architecture" -- false)
#   winsup/cygwin/local_includes/cygtls.h:365       (comment still says ARM64
#     names it _DISPATCHER_CONTEXT_ARM64 while line 375 emits P19 -- contradictory)
# See ASSETS-README.md "Diagnostic edits carrying misleading comments".
#
# Base commit: d890a845e992638a6f09560efacc26d15b3ffe6a
# Apply with:  git checkout d890a845e && git apply runtime-uncommitted.diff
#              cp -r untracked/* <clone>/      # longdouble.c is NOT in this diff
# =====================================================================

HDREOF

cat "$P.hdr" "$P.body" > "$P"
rm -f "$P.hdr" "$P.body"

echo "=== header prepended; re-verifying integrity ==="
F=$(grep -c '^diff --git ' "$P")
I=$(( $(grep -c '^+[^+]' "$P") + $(grep -cx '+' "$P") ))
E=$(( $(grep -c '^-[^-]' "$P") + $(grep -cx '-' "$P") ))
printf 'expected : 43 files, 1693 insertions, 760 deletions\n'
printf 'actual   : %s files, %s insertions, %s deletions\n' "$F" "$I" "$E"
[ "$F" = 43 ] && [ "$I" = 1693 ] && [ "$E" = 760 ] \
  && echo "COUNTS: PASS (header did not perturb the patch body)" \
  || echo "COUNTS: FAIL"

echo
echo "=== does git still parse it? (reverse-check against the modified tree) ==="
git --no-optional-locks -C /root/xc/runtime apply --reverse --check "$P" \
  && echo "git apply -R --check: PASS - patch parses and matches the tree" \
  || echo "git apply -R --check: FAIL"
echo "(--check is read-only; /root/xc was not modified)"
ls -la "$P"
