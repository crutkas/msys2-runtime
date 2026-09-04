#!/bin/bash
# Measure the cygheap header geometry rather than assuming it.
# If sizeof(init_cygheap) > 0x68F0 then the "first entry" at cygheap+0x68F0
# lies INSIDE the header, and the chain walk ran into the struct itself --
# which would mean my "IN-HEAP" range test was too loose and accepted
# addresses inside the header as valid entries.
set -u
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
B=$L/bld/winsup/cygwin
cd $B || exit 1
INCLUDES="$(sed -n 's/^AM_CPPFLAGS = //p' Makefile | head -1)"

cat > /tmp/geom.cc <<'EOF'
#include "winsup.h"
#include <assert.h>
#include <stdlib.h>
#include "cygerrno.h"
#include "security.h"
#include "path.h"
#include "tty.h"
#include "fhandler.h"
#include "dtable.h"
#include "cygheap.h"
#include "child_info.h"
#include "heap.h"
#include "sigproc.h"
#include "pinfo.h"
#include "registry.h"
#include "ntdll.h"
#include "memory_layout.h"
#include <unistd.h>
#include <stddef.h>
extern "C" const unsigned long geom[6] = {
  sizeof (init_cygheap),
  offsetof (init_cygheap, chain),
  sizeof (mini_cygheap),
  sizeof (_cmalloc_entry),
  offsetof (_cmalloc_entry, data),
  (unsigned long) NBUCKETS
};
EOF

aarch64-pc-cygwin-g++ -c -O2 $INCLUDES -I$R -I$R/local_includes -o /tmp/geom.o /tmp/geom.cc 2>&1 | head -20
if [ -f /tmp/geom.o ]; then
  echo "--- geom[] contents (sizeof init_cygheap, offsetof chain, sizeof mini, sizeof entry, offsetof data, NBUCKETS) ---"
  aarch64-pc-cygwin-objdump -s -j .rodata /tmp/geom.o 2>/dev/null | head -12
  aarch64-pc-cygwin-objdump -s -j .data  /tmp/geom.o 2>/dev/null | head -12
fi
