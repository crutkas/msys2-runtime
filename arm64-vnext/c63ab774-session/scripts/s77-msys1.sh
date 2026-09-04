#!/bin/bash
# PRIORITY 1: msys vs cygwin flavour. Measurement, no changes yet.
set -u
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin

# restore the honest cygwin.din (undo the diagnostic export removal)
if [ -f $R/cygwin.din.bak ]; then
  cp -p $R/cygwin.din.bak $R/cygwin.din
  echo "cygwin.din restored: $(wc -l < $R/cygwin.din) lines (honest state)"
fi

echo
echo "############ 1. how many __MSYS__ sites, and where? ############"
printf 'total __MSYS__ occurrences in winsup : %s\n' "$(grep -rc '__MSYS__' $L/runtime/winsup --include=*.cc --include=*.c --include=*.h --include=*.in --include=*.ac --include=*.am 2>/dev/null | awk -F: '{s+=$2} END{print s}')"
echo "--- files, with counts ---"
grep -rc '__MSYS__' $L/runtime/winsup --include=*.cc --include=*.c --include=*.h --include=*.in --include=*.ac --include=*.am 2>/dev/null | awk -F: '$2>0' | sort -t: -k2 -rn | head -30

echo
echo "############ 2. where is __MSYS__ actually DEFINED? ############"
grep -rn 'define __MSYS__\|D__MSYS__\|__MSYS__=' $L/runtime/winsup $L/runtime/config* 2>/dev/null | head -10
echo "--- in configure.ac / Makefile.am? ---"
grep -rn 'MSYS' $L/runtime/winsup/configure.ac | head -20

echo
echo "############ 3. what does configure do for *-msys vs *-cygwin? ############"
grep -n -B3 -A12 'msys' $L/runtime/winsup/configure.ac | head -60
