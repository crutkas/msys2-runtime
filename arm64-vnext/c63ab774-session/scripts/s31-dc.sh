#!/bin/bash
W=/root/xc/inst/aarch64-pc-cygwin/include/w32api
echo "=== how w32api v12.0.0 declares the ARM64 dispatcher context ==="
grep -rn '_DISPATCHER_CONTEXT_ARM64\|} DISPATCHER_CONTEXT\|PDISPATCHER_CONTEXT' $W/winnt.h | head -20
echo
echo "=== compile probe: what does PDISPATCHER_CONTEXT actually mangle to? ==="
export PATH=/root/xc/inst/bin:$PATH
cat > /tmp/dc.cc <<'EOF'
#include <windows.h>
struct exception { static EXCEPTION_DISPOSITION handle (EXCEPTION_RECORD *, void *,
                        CONTEXT *, PDISPATCHER_CONTEXT); };
EXCEPTION_DISPOSITION exception::handle (EXCEPTION_RECORD *, void *,
                        CONTEXT *, PDISPATCHER_CONTEXT) { return ExceptionContinueSearch; }
EOF
aarch64-pc-cygwin-g++ -c -fno-rtti -fno-exceptions \
  -isystem $W -isystem /root/xc/bld/newlib/targ-include \
  -isystem /root/xc/runtime/newlib/libc/include /tmp/dc.cc -o /tmp/dc.o 2>&1 | head -5
aarch64-pc-cygwin-nm /tmp/dc.o | grep ' T _ZN9exception6handle'
