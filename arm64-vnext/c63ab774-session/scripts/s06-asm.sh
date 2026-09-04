#!/bin/bash
S=/root/xc/runtime/newlib/libc/machine/aarch64
echo "=== memchr.S:45-56 ==="; sed -n '45,56p' $S/memchr.S
echo "=== memchr.S:144,152 ==="; sed -n '144,152p' $S/memchr.S
echo "=== memcmp.S:30,40 ==="; sed -n '30,40p' $S/memcmp.S
echo "=== asmdefs.h def_fn / ENTRY ==="
grep -rn 'def_fn\|\.macro\|%function\|\.type' $S/asmdefs.h 2>/dev/null | head -20
echo "=== full error context from log ==="
grep -n -B4 "junk at end of line" /root/xc/newlib-build.log | head -40
