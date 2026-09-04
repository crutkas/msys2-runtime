#!/bin/bash
p=/root/xc/mingw-w64/mingw-w64-tools/widl/include/winnt.h
echo "=== widl winnt.h 1955-1970 (macro-rename guard) ==="
sed -n '1955,1970p' "$p" | cat -n | awk '{printf "%5d  %s\n", $1+1954, substr($0, index($0,$2))}'
echo
echo "=== widl winnt.h 2108,2120 (undef / alias) ==="
sed -n '2108,2120p' "$p" | cat -n | awk '{printf "%5d  %s\n", $1+2107, substr($0, index($0,$2))}'
