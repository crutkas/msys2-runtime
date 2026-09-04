#!/bin/bash
# Read a real autoload thunk out of the linked DLL and inspect the 8-byte slot
# that `ldr x16, 3f` loads and `br x16` jumps to.
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll

echo "############ .autoload_text section ############"
aarch64-pc-cygwin-objdump -h $D | grep -A1 autoload_text

echo
echo "############ first thunk, disassembled ############"
VMA=$(aarch64-pc-cygwin-objdump -h $D | awk '/autoload_text/{getline_vma=$4; print $4}' | head -1)
echo "section VMA = 0x$VMA"
START=$((0x$VMA))
aarch64-pc-cygwin-objdump -d --start-address=$START --stop-address=$((START+0x60)) $D 2>/dev/null | tail -25

echo
echo "############ raw bytes of that thunk (first 0x40) ############"
aarch64-pc-cygwin-objdump -s --start-address=$START --stop-address=$((START+0x40)) $D 2>/dev/null | tail -8

echo
echo "############ are there BASE RELOCATIONS covering .autoload_text? ############"
printf 'total .reloc entries in image : '
aarch64-pc-cygwin-objdump -p $D 2>/dev/null | grep -c 'RVA'
echo "--- reloc blocks near the autoload_text RVA ---"
RVA=$((START - 0x180000000))
printf 'autoload_text RVA = 0x%X\n' $RVA
aarch64-pc-cygwin-objdump -p $D 2>/dev/null | grep -iA3 'PE File Base Relocations' | head -8
aarch64-pc-cygwin-objdump -p $D 2>/dev/null | awk '/Virtual Address:/{print}' | head -20
