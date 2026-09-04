#!/bin/bash
# The gendef AArch64 backend from w-gendef is CRLF throughout (957/957 lines),
# so its "#!/usr/bin/perl\r" shebang fails with "cannot execute: required file
# not found" -- exactly the CRLF-shebang failure class recorded in ASSETS-README.md.
# Normalise CRLF -> LF. Content is unchanged; only line endings differ.
set -u
L=/root/xc/w-link
f=$L/runtime/winsup/cygwin/scripts/gendef

echo "=== before ==="
printf 'bytes=%s  CRLF lines=%s  sha=%s\n' "$(stat -c%s $f)" "$(grep -c $'\r$' $f)" "$(sha256sum $f | cut -c1-16)"

cp -p $f $f.crlf.bak
sed -i 's/\r$//' $f
chmod +x $f

echo "=== after ==="
printf 'bytes=%s  CRLF lines=%s  sha=%s\n' "$(stat -c%s $f)" "$(grep -c $'\r$' $f)" "$(sha256sum $f | cut -c1-16)"
head -1 $f | od -c | head -2

echo "=== content identical modulo line endings? ==="
a=$(tr -d '\r' < $f.crlf.bak | sha256sum | cut -c1-64)
b=$(sha256sum $f | cut -c1-64)
[ "$a" = "$b" ] && echo "YES - normalisation only, no content change" || echo "CONTENT CHANGED (unexpected)"

echo "=== does it run now? ==="
perl -c $f 2>&1 | tail -2
$f --help 2>&1 | head -3
echo "exit=$?"
