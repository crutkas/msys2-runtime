#!/bin/bash
f=/root/xc/w-link/runtime/winsup/cygwin/scripts/gendef
echo "=== first line, byte-exact ==="
head -1 "$f" | od -c | head -3
echo "=== CRLF line count in file ==="
grep -c $'\r$' "$f"
echo "=== source in w-gendef: CRLF? ==="
grep -c $'\r$' /root/xc/w-gendef/gendef
echo "=== the preserved original for comparison ==="
head -1 /root/xc/runtime/winsup/cygwin/scripts/gendef | od -c | head -2
grep -c $'\r$' /root/xc/runtime/winsup/cygwin/scripts/gendef
echo "=== perl ==="
which perl; ls -la /usr/bin/perl
