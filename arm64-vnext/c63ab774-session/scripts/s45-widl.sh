#!/bin/bash
p=/root/xc/mingw-w64/mingw-w64-tools/widl/include/winnt.h
printf 'size %s  sha256 %s\n' "$(stat -c%s $p)" "$(sha256sum $p | cut -c1-64)"
printf 'genuine _DISPATCHER_CONTEXT_ARM64 (-ow) : %s\n' "$(grep -ow '_DISPATCHER_CONTEXT_ARM64' $p | wc -l)"
printf '_DISPATCHER_CONTEXT_ARM64EC             : %s\n' "$(grep -ow '_DISPATCHER_CONTEXT_ARM64EC' $p | wc -l)"
printf 'plain struct _DISPATCHER_CONTEXT         : %s\n' "$(grep -ow 'struct _DISPATCHER_CONTEXT' $p | wc -l)"
echo '--- sites ---'
grep -n '_DISPATCHER_CONTEXT_ARM64\b' $p | head -8
echo '--- is there an _ARM64_ typedef alias? ---'
grep -n -A3 'defined(_ARM64_)' $p | grep -i 'DISPATCHER' | head -5
