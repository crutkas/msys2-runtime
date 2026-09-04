#!/bin/bash
# Regenerate cygwin.sc with the 64-bit ctor markers, relink, verify, ship to Windows.
set -u
export PATH=/root/xc/inst/bin:$PATH
export CPLUS_INCLUDE_PATH=/root/xc/sysroot-cxx/include/c++/15.0.1
L=/root/xc/w-link
R=$L/runtime/winsup/cygwin
cd $L/bld/winsup/cygwin || exit 1

rm -f cygwin.sc
aarch64-pc-cygwin-gcc -E - -P < $R/cygwin.sc.in -o cygwin.sc
echo "=== regenerated cygwin.sc: ctor block ==="
grep -n -A2 'CTOR_LIST__' cygwin.sc | head -8

rm -f new-msys-2.0.dll
aarch64-pc-cygwin-g++ -g -O2 -mno-use-libstdc-wrappers \
  -Wl,--gc-sections -nostdlib -Wl,-Tcygwin.sc -static \
  -Wl,--heap=0 -Wl,--out-implib,msysdll.a -shared -o new-msys-2.0.dll \
  -e dll_entry msys.def \
  -Wl,-whole-archive libdll.a -Wl,-no-whole-archive \
  version.o /root/xc/bld/winsup/cygserver/libcygserver.a \
  $L/bld/newlib/libm.a $L/bld/newlib/libc.a \
  -L/root/xc/build-gcc2/aarch64-pc-cygwin/libgcc -L/root/xc/implibs/lib \
  -lgcc -lkernel32 -lntdll -Wl,-Map,msys.map > /root/xc/link-ctor.log 2>&1
echo "LINK EXIT $?   diagnostics bytes: $(wc -c < /root/xc/link-ctor.log)"
head -5 /root/xc/link-ctor.log

echo
echo "=== verify the ctor list markers are now 8 bytes ==="
python3 -B - <<'PY'
import re, struct, subprocess
D="/root/xc/w-link/bld/winsup/cygwin/new-msys-2.0.dll"
OBJ="/root/xc/inst/bin/aarch64-pc-cygwin-objdump"
nm = subprocess.run([OBJ,"-t",D],capture_output=True,text=True).stdout
m = {}
for line in nm.splitlines():
    for sym in ("__CTOR_LIST__","__DTOR_LIST__"):
        if line.rstrip().endswith(" "+sym) or line.rstrip().endswith("\t"+sym):
            m[sym]=int(line.split()[0],16)
print("symbols:", {k:hex(v) for k,v in m.items()})
if "__CTOR_LIST__" in m and "__DTOR_LIST__" in m:
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
    for sym in ("__CTOR_LIST__","__DTOR_LIST__"):
        f=foff(m[sym])
        if f: print(sym, "first 16 bytes:", d[f:f+16].hex(' '))
PY

cp new-msys-2.0.dll /mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/runtest/msys-2.0-ctorfix.dll
printf 'sha256 %s\n' "$(sha256sum new-msys-2.0.dll | cut -c1-64)"
echo "copied to Windows as msys-2.0-ctorfix.dll"
