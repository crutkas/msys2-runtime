#!/bin/bash
cd /root/xc/mingw-w64
echo "=== git log for the mbstate_t hunk in corecrt.h ==="
git log --oneline -5 -- mingw-w64-headers/crt/corecrt.h 2>&1 | head
echo
echo "=== all guards mentioning mbstate in headers ==="
grep -rn 'mbstate_t' mingw-w64-headers/crt/corecrt.h | head
echo
echo "=== is the guard arch- or cygwin-dependent? show it ==="
grep -n -B3 -A6 'typedef int mbstate_t' mingw-w64-headers/crt/corecrt.h
echo
echo "=== does _cygwin.h mention mbstate? ==="
grep -n 'MBSTATE\|mbstate' mingw-w64-headers/crt/_cygwin.h || echo "NO -- _cygwin.h does not suppress mbstate_t"
echo
echo "=== available release tags ==="
git tag 2>/dev/null | tail -20
echo "(shallow clone: $(git rev-parse --is-shallow-repository))"
