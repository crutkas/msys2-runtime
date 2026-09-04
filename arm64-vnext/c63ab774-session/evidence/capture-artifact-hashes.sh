#!/bin/bash
# READ-ONLY. sha256sum/stat only. Writes nothing into any other session's evidence.
# Captures the built-artifact identities that s36-hashes.sh computed but never persisted.
cd /root/xc || exit 1
echo "# ARM64 vNext -- built-artifact hash manifest"
echo "# Captured $(date -u '+%Y-%m-%dT%H:%M:%SZ') by supervisor heartbeat (session 290c9aaf)."
echo "# Source: live WSL state /root/xc. READ-ONLY capture; nothing modified."
echo "# Reason: s36-hashes.sh computed these but the values reached only the session"
echo "#         transcript, never disk. RESULT.md records sizes but zero sha256 values."
echo
printf '%-58s %12s  %s\n' "PATH" "BYTES" "SHA256"
hashone() {
  printf '%-58s %12s  %s\n' "$1" "$(stat -c%s "$1" 2>/dev/null || echo MISSING)" \
    "$(sha256sum "$1" 2>/dev/null | cut -c1-64)"
}
for f in \
  bld/newlib/libc.a \
  bld/newlib/libm.a \
  build-gcc2/aarch64-pc-cygwin/libgcc/libgcc.a \
  implibs/lib/libkernel32.a \
  implibs/lib/libntdll.a \
  implibs/lib/libadvapi32.a \
  implibs/lib/libuser32.a \
  bld/winsup/cygwin/cygwin.sc \
  bld/winsup/cygwin/msys.def \
  bld/winsup/cygwin/sigfe.s \
  bld/winsup/cygwin/libdll.a \
  bld/winsup/cygwin/msysdll.a ; do
  hashone "$f"
done

echo
echo "# --- toolchain driver binaries (identity of the compiler that built the above) ---"
for f in inst/bin/aarch64-pc-cygwin-g++ inst/bin/aarch64-pc-cygwin-gcc \
         inst/bin/aarch64-pc-cygwin-ld inst/bin/aarch64-pc-cygwin-as ; do
  hashone "$f"
done

echo
echo "# --- confirmations ---"
echo -n "# no msys-2.0.dll anywhere: "
if [ -z "$(find /root/xc -name 'msys-2.0.dll' 2>/dev/null | head -1)" ]; then echo "CONFIRMED (none)"; else echo "A DLL EXISTS"; fi
export PATH=/root/xc/inst/bin:$PATH
echo "# g++ : $(aarch64-pc-cygwin-g++ --version 2>/dev/null | head -1)"
echo "# ld  : $(aarch64-pc-cygwin-ld  --version 2>/dev/null | head -1)"
