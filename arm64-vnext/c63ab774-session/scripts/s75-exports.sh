#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll
echo "############ EXPORT COUNT ############"
printf 'Export Address Table entries (hex) : '
aarch64-pc-cygwin-objdump -p $D | grep -m1 'Export Address Table' | awk '{print $NF}'
python3 -B -c "print('decimal:', int('$(aarch64-pc-cygwin-objdump -p $D | grep -m1 "Export Address Table" | awk "{print \$NF}")',16))"
printf 'names in the export name table    : '
aarch64-pc-cygwin-objdump -p $D | awk '/Export Name Pointer Table/,/^$/' | grep -c '\[' 

echo
echo "############ IMPORT CLOSURE ############"
aarch64-pc-cygwin-objdump -p $D | grep -i 'DLL Name' | sort -u
printf 'distinct imported DLLs : %s\n' "$(aarch64-pc-cygwin-objdump -p $D | grep -ci 'DLL Name')"

echo
echo "############ sanity: some real exports present? ############"
aarch64-pc-cygwin-nm -D --defined-only $D 2>/dev/null | wc -l
for s in fork execve cygwin_internal _sigfe_malloc sigdelayed _sigbe dll_entry; do
  printf '  %-18s %s\n' "$s" "$(aarch64-pc-cygwin-nm $D 2>/dev/null | grep -cw "$s")"
done

echo
echo "############ stripped size (debug info dominates) ############"
cp $D /tmp/stripped.dll
aarch64-pc-cygwin-strip /tmp/stripped.dll 2>/dev/null
printf 'with debug : %s bytes\n' "$(stat -c%s $D)"
printf 'stripped   : %s bytes\n' "$(stat -c%s /tmp/stripped.dll)"
printf 'stripped sha256 : %s\n' "$(sha256sum /tmp/stripped.dll | cut -c1-64)"
aarch64-pc-cygwin-objdump -f /tmp/stripped.dll | sed -n '2,3p'
