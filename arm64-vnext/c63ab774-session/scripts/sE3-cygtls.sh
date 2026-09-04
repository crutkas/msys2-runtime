#!/bin/bash
# The failure mode changes with stack reserve, pointing at _cygtls placement.
# _cygtls lives at (NtTib.StackBase - __CYGTLS_PADSIZE__).
R=/root/xc/w-link/runtime/winsup/cygwin
echo "############ __CYGTLS_PADSIZE__ and sizeof(_cygtls) ############"
grep -rn '__CYGTLS_PADSIZE__' $R/include/cygwin/config.h $R/local_includes/cygtls.h | head
echo
echo "############ the static assert that PADSIZE >= sizeof(_cygtls) ############"
grep -rn -B3 -A6 'CYGTLS_PADSIZE\|sizeof (_cygtls)\|sizeof(_cygtls)' $R/local_includes/cygtls.h | head -30
echo
echo "############ any arch conditional in cygtls.h? ############"
grep -n '__x86_64__\|__aarch64__\|#else\|#error' $R/local_includes/cygtls.h | head -20
echo
echo "############ stack setup in dcrt0.cc ############"
grep -n 'stackbase\|stacklimit\|stacktop\|_tlsbase\|_tlstop\|StackBase\|StackLimit' $R/dcrt0.cc | head -20
echo
echo "############ where are _tlsbase/_tlstop defined? ############"
grep -rn '_tlsbase\|_tlstop' $R/local_includes/*.h | head -12
