#!/bin/bash
R=/root/xc/w-link/runtime/winsup/cygwin
echo "############ mkimport: architecture-specific emission ############"
grep -n 'jmp\|x86_64\|aarch64\|cpu\|\.text\|asm\|nop' $R/scripts/mkimport | head -40
echo
echo "############ the stub-emitting section, in context ############"
grep -n -B6 -A18 'jmp' $R/scripts/mkimport | head -50
