#!/bin/bash
# usage: rd.sh FILE START END
F="$1"; S="$2"; E="$3"
cd /root/xc/w-defects/winsup/cygwin
awk -v s="$S" -v e="$E" 'NR>=s && NR<=e {printf "%d: %s\n", NR, $0}' "$F"
