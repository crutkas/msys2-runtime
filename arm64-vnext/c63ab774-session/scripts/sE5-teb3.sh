#!/bin/bash
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api
echo "############ every NtCurrentTeb definition, with its arch guard ############"
grep -n 'NtCurrentTeb' $W/winnt.h
echo
echo "############ the ARM64 region of winnt.h around NtCurrentTeb ############"
awk '/defined\(__aarch64__\)|_ARM64_|__arm__|ARM64/{a=NR} /NtCurrentTeb/{print NR": "$0}' $W/winnt.h | head
echo
echo "--- context around each definition ---"
for n in $(grep -n 'FORCEINLINE struct _TEB \*NtCurrentTeb\|define NtCurrentTeb' $W/winnt.h | cut -d: -f1); do
  echo "===== line $n ====="
  sed -n "$((n-12)),$((n+8))p" $W/winnt.h
done
