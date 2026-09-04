#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll
echo "############ IDENTITY ############"
printf 'size    : %s bytes\n' "$(stat -c%s $D)"
printf 'sha256  : %s\n' "$(sha256sum $D | cut -c1-64)"
printf 'file    : %s\n' "$(file -b $D 2>/dev/null)"

echo
echo "############ PE MACHINE (must be 0xAA64 for ARM64) ############"
aarch64-pc-cygwin-objdump -f $D | head -6
echo "--- raw COFF machine field from the PE header ---"
off=$(od -An -tu4 -j60 -N4 $D | tr -d ' ')
printf 'PE header offset : %s\n' "$off"
printf 'Machine bytes    : '; od -An -tx1 -j$((off+4)) -N2 $D
echo "  (64 aa little-endian == 0xAA64 == IMAGE_FILE_MACHINE_ARM64)"

echo
echo "############ SECTION LAYOUT ############"
aarch64-pc-cygwin-objdump -h $D | sed -n '4,40p'

echo
echo "############ EXPORT COUNT ############"
aarch64-pc-cygwin-objdump -p $D | grep -A4 'Export Address Table\|Ordinal base\|Number of' | head -12
printf 'exported names counted : '
aarch64-pc-cygwin-objdump -p $D | sed -n '/\[Ordinal\/Name Pointer\] Table/,/^$/p' | grep -c '^\s*\[' 

echo
echo "############ IMPORT CLOSURE ############"
aarch64-pc-cygwin-objdump -p $D | grep -i 'DLL Name:' | sort -u

echo
echo "############ ENTRY POINT ############"
aarch64-pc-cygwin-objdump -p $D | grep -i 'entry point\|ImageBase\|SectionAlignment' | head -5
