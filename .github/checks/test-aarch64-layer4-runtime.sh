#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=${RUNNER_TEMP:-/tmp}/aarch64-layer4.$$
cc=${CC:-clang}
as=${LAYER3_AS:?LAYER3_AS is required}
objdump=${LAYER3_OBJDUMP:?LAYER3_OBJDUMP is required}
perl=${NATIVE_PERL:?NATIVE_PERL is required}
readobj=${LLVM_READOBJ:-llvm-readobj}
clang_lib=${CLANGARM64_LIB:-/clangarm64/lib}

cleanup()
{
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$work"

case "$("$cc" -dumpmachine)" in
aarch64-*-windows-* | aarch64-*-mingw*) ;;
*)
  echo "compiler is not targeting native Windows ARM64" >&2
  exit 1
  ;;
esac

grep -q '^#define __CYGTLS_PADSIZE__ 12800' \
  "$repo_root/winsup/cygwin/include/cygwin/config.h"
grep -q '^.equ _cygtls.start_offset, -12800$' \
  "$repo_root/.github/checks/aarch64-layer4-tlsoffsets"

cat >"$work/jump-layout.c" <<'EOF'
#define __CYGWIN__ 1
#define _BEGIN_STD_C
#define _END_STD_C
typedef unsigned long sigset_t;
#include "machine/setjmp.h"
_Static_assert(sizeof(jmp_buf) == 200, "Cygwin AArch64 jmp_buf ABI drift");
_Static_assert(_JBLEN * sizeof(_JBTYPE) == 0xc8,
	       "savemask offset disagrees with gendef");
_Static_assert((_JBLEN + 1) * sizeof(_JBTYPE) == 0xd0,
	       "sigmask offset disagrees with gendef");
EOF
"$cc" -target aarch64-w64-windows-gnu -Werror \
  -I"$repo_root/newlib/libc/include" -c "$work/jump-layout.c" \
  -o "$work/jump-layout.o"

cp "$repo_root/.github/checks/aarch64-layer4-tlsoffsets" "$work/tlsoffsets"
(
  cd "$work"
  "$perl" "$repo_root/winsup/cygwin/scripts/gendef" \
    --cpu=aarch64 --output-def="$work/layer4.def" \
    "$repo_root/.github/checks/aarch64-layer4.din"
)
(
  cd "$work"
  "$as" -c sigfe.s -o sigfe.o
)

"$cc" -target aarch64-w64-windows-gnu -c \
  -I"$work" "$repo_root/.github/checks/aarch64-layer4-control.S" \
  -o "$work/control.o"
"$cc" -target aarch64-w64-windows-gnu -O2 -Wall -Wextra -Werror \
  -c "$repo_root/.github/checks/aarch64-layer4-delayed.c" \
  -o "$work/delayed.o"

link_control()
{
  entry=$1
  output=$2
  "$cc" -target aarch64-w64-windows-gnu -nostdlib \
    -Wl,--subsystem,console -Wl,--entry,"$entry" \
    -Wl,--dynamicbase -Wl,--disable-high-entropy-va \
    -Wl,--enable-reloc-section \
    -L"$clang_lib" -o "$output" \
    "$work/control.o" "$work/delayed.o" "$work/sigfe.o" \
    -lkernel32 -lntdll -lmsvcrt
}

link_control mainCRTStartup "$work/jump-signal-control.exe"
link_control delayed_mainCRTStartup "$work/delayed-unwind-control.exe"

"$cc" -target aarch64-w64-windows-gnu -DNDEBUG -O2 -Wall -Wextra \
  -Werror -I"$repo_root/.github/checks/aarch64-layer4-stubs" \
  -c "$repo_root/winsup/cygwin/aarch64/fastcwd.cc" \
  -o "$work/fastcwd-production.o"
"$cc" -target aarch64-w64-windows-gnu -DNDEBUG -O2 -Wall -Wextra \
  -Werror -DLAYER4_EXPECTED_PROCESS_MACHINE=0xaa64 \
  -c "$repo_root/.github/checks/aarch64-layer4-fastcwd.cc" \
  -o "$work/fastcwd-control.o"
"$cc" -target aarch64-w64-windows-gnu -nostdlib \
  -Wl,--subsystem,console -Wl,--entry,mainCRTStartup \
  -Wl,--dynamicbase -Wl,--disable-high-entropy-va \
  -Wl,--enable-reloc-section \
  -L"$clang_lib" -o "$work/fastcwd-native.exe" \
  "$work/fastcwd-control.o" "$work/fastcwd-production.o" \
  -lkernel32 -lmsvcrt

"$cc" -target aarch64-w64-windows-gnu -DNDEBUG -O2 -Wall -Wextra \
  -Werror -Wno-cast-function-type-mismatch -Wno-inline-asm \
  -fno-exceptions -fno-rtti \
  -I"$repo_root/.github/checks/aarch64-layer4-stubs" \
  -c "$repo_root/.github/checks/aarch64-layer4-production-pthread.cc" \
  -o "$work/pthread-production.o"
"$cc" -target aarch64-w64-windows-gnu -nostdlib \
  -Wl,--subsystem,console -Wl,--entry,mainCRTStartup \
  -Wl,--dynamicbase -Wl,--disable-high-entropy-va \
  -Wl,--enable-reloc-section \
  -L"$clang_lib" -o "$work/pthread-tls-control.exe" \
  "$work/pthread-production.o" -lkernel32 -lmsvcrt

cat >"$work/cpu-relax.c" <<EOF
#include "cpu_relax.h"
void layer4_cpu_relax(void) { CPU_RELAX(); }
EOF
"$cc" -target aarch64-w64-windows-gnu -O2 \
  -I"$repo_root/winsup/testsuite/winsup.api/pthread" \
  -c "$work/cpu-relax.c" \
  -o "$work/cpu-relax.o"
"$objdump" -d "$work/cpu-relax.o" >"$work/cpu-relax.dis"
grep -Eq '[[:space:]]dmb[[:space:]]+ishst' "$work/cpu-relax.dis"
grep -Eq '[[:space:]]yield' "$work/cpu-relax.dis"

for object in "$work"/*.o
do
  "$readobj" --file-headers "$object" |
    grep -q 'Machine: IMAGE_FILE_MACHINE_ARM64 (0xAA64)'
done
for image in "$work"/*.exe
do
  "$readobj" --file-headers "$image" |
    grep -q 'Machine: IMAGE_FILE_MACHINE_ARM64 (0xAA64)'
  "$readobj" --file-headers "$image" |
    grep -q 'IMAGE_FILE_EXECUTABLE_IMAGE'
  printf 'Executing %s\n' "$(basename "$image")"
  "$image"
done

"$readobj" --unwind "$work/sigfe.o" >"$work/sigfe.unwind"
grep -q 'Function: sigdelayed' "$work/sigfe.unwind"
grep -q 'Function: sigsetjmp' "$work/sigfe.unwind"
grep -q 'Function: longjmp' "$work/sigfe.unwind"

printf '%s\n' \
  "Native ARM64 layer-4 validation passed:" \
  "  generated signal entry/bypass and TLS stack control flow executed" \
  "  setjmp/sigsetjmp and longjmp state, masks, canaries, FPCR/FPSR executed" \
  "  sigdelayed capture and Windows RtlVirtualUnwind path executed" \
  "  production pthread stack switch and per-thread TLS isolation executed" \
  "  production native ARM64 fastcwd scanner executed" \
  "  ARM64 pthread dmb/yield barrier and PE/COFF architecture verified"
