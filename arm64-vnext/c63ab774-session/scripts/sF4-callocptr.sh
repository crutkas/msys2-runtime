#!/bin/bash
# Read the dispatch flag and the function pointer that calloc branches through.
#   1800efba4:  adrp x2, 180230000 ; ldrb w2, [x2, #2352]   -> flag at 0x180230930
#   1800efbcc:  adrp x2, 18021e000 ; ldr  x2, [x2, #2872]   -> ptr  at 0x18021EB38
#   1800efbd4:  blr  x2
export PATH=/root/xc/inst/bin:$PATH
D=/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll
FLAG=$((0x180230000 + 2352))
PTR=$((0x18021e000 + 2872))
printf 'dispatch flag VA : 0x%X\n' $FLAG
printf 'function ptr  VA : 0x%X\n\n' $PTR

echo "############ what symbol lives at the function-pointer slot? ############"
aarch64-pc-cygwin-nm -n $D 2>/dev/null | awk -v t=$PTR '
  { a=strtonum("0x" $1); if (a<=t) l=$0; if (a>t && !done) { print "  slot is inside: " l; print "  next symbol   : " $0; done=1 } }'

echo
echo "############ initial contents of that slot in the image ############"
python3 -B - <<PY
import struct
D="$D"
d=open(D,"rb").read()
pe=struct.unpack_from("<I",d,0x3C)[0]
nsec=struct.unpack_from("<H",d,pe+6)[0]; optsz=struct.unpack_from("<H",d,pe+20)[0]
base=struct.unpack_from("<Q",d,pe+24+24)[0]; sh=pe+24+optsz
def foff(va):
    rva=va-base
    for i in range(nsec):
        o=sh+i*40; vs,r,rs,ro=struct.unpack_from("<IIII",d,o+8)
        if r<=rva<r+max(vs,rs): return ro+(rva-r)
    return None
for name,va in (("flag",$FLAG),("funcptr",$PTR)):
    f=foff(va)
    if f is None: print(name,"-> not in a raw section (likely .bss)"); continue
    if name=="flag":
        print("flag byte at 0x%X = 0x%02X" % (va, d[f]))
    else:
        v=struct.unpack_from("<Q",d,f)[0]
        print("funcptr at 0x%X = 0x%X" % (va,v))
PY

echo
echo "############ which function does that value name? ############"
aarch64-pc-cygwin-nm -n $D 2>/dev/null | grep -iE ' (T|t) ' | awk '{print $1, $3}' > /tmp/syms.txt
echo "(resolved below if the pointer is non-zero)"

echo
echo "############ the malloc-interposition source ############"
grep -rn 'use_internal_malloc\|export_malloc\|malloc_init\|user_data->malloc' \
  /root/xc/w-link/runtime/winsup/cygwin/mm/malloc_wrapper.cc 2>/dev/null | head -20
