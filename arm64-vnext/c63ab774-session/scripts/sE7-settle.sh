#!/bin/bash
# Settle the retraction. The PRESERVED tree /root/xc/runtime has never been
# modified by me (verified repeatedly this session at 43 files/1693/760).
# w-autoload/runtime is another independent pre-fix copy.
export PATH=/root/xc/inst/bin:$PATH

echo "############ 1. THE PRE-EDIT LINE, quoted verbatim ############"
for t in /root/xc/runtime /root/xc/w-autoload/runtime /root/xc/w-link/runtime; do
  f=$t/winsup/cygwin/cygwin.sc.in
  [ -f "$f" ] || continue
  echo "===== $t ====="
  grep -n -A6 'glue_7)' "$f" | sed -n '2,9p'
done

echo
echo "############ md5 of each cygwin.sc.in ############"
for t in /root/xc/runtime /root/xc/w-autoload/runtime /root/xc/w-link/runtime; do
  f=$t/winsup/cygwin/cygwin.sc.in
  [ -f "$f" ] && printf '  %-34s %s\n' "$t" "$(md5sum $f | cut -d' ' -f1)"
done

echo
echo "############ 2. is the preserved tree still pristine? ############"
git --no-optional-locks -C /root/xc/runtime diff HEAD --shortstat
echo "(expected: 43 files changed, 1693 insertions(+), 760 deletions(-))"
echo "--- and is cygwin.sc.in itself modified there? ---"
git --no-optional-locks -C /root/xc/runtime status --porcelain winsup/cygwin/cygwin.sc.in
echo "(blank == cygwin.sc.in is UNMODIFIED in the preserved tree)"

echo
echo "############ 3. what the ORIGINAL upstream file says at HEAD ############"
git --no-optional-locks -C /root/xc/runtime show HEAD:winsup/cygwin/cygwin.sc.in 2>/dev/null \
  | grep -n -B2 -A8 'CTOR_LIST__' | head -20
