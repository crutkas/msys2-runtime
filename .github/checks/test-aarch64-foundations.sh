#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=${RUNNER_TEMP:-/tmp}/aarch64-foundations.$$
objects=$work/objects
programs=$work/programs
cc=${CC:-clang}
readobj=${LLVM_READOBJ:-llvm-readobj}

cleanup()
{
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$objects/machine" "$objects/code" "$programs"

case "$("$cc" -dumpmachine)" in
aarch64-*-windows-* | aarch64-*-mingw*) ;;
*)
  echo "compiler is not targeting native Windows ARM64: $("$cc" -dumpmachine)" >&2
  exit 1
  ;;
esac

assert_arm64_coff()
{
  headers=$("$readobj" --file-headers "$1")
  printf '%s\n' "$headers" | grep -q 'Format: COFF-ARM64'
  printf '%s\n' "$headers" |
    grep -q 'Machine: IMAGE_FILE_MACHINE_ARM64 (0xAA64)'
}

assert_arm64_pe()
{
  assert_arm64_coff "$1"
  "$readobj" --file-headers "$1" |
    grep -q 'IMAGE_FILE_EXECUTABLE_IMAGE'
}

machine_count=0
for source in "$repo_root"/newlib/libc/machine/aarch64/*.S
do
  object=$objects/machine/$(basename "${source%.S}").o
  "$cc" -D__CYGWIN__ -DWANT_GNU_PROPERTY=0 \
    -I"$repo_root/newlib/libc/machine/aarch64" \
    -c "$source" -o "$object"
  assert_arm64_coff "$object"
  machine_count=$((machine_count + 1))
done
test "$machine_count" -eq 16

"$cc" -D__CYGWIN__ -D__HAVE_LOCALE_INFO__=1 -Werror -Wall \
  -I"$repo_root/winsup/cygwin/include" \
  -I"$repo_root/newlib/libc/include" \
  -I"$repo_root/newlib/libc/locale" \
  -I"$repo_root/newlib/libc/ctype" \
  -c "$repo_root/newlib/libc/ctype/ctype_.c" \
  -o "$objects/code/ctype.o"
"$readobj" --symbols "$objects/code/ctype.o" | grep -q 'Name: _ctype_'

"$cc" -D__CYGWIN__ -D__BSD_VISIBLE=1 -D__MISC_VISIBLE=1 -Werror -Wall \
  -I"$repo_root/winsup/cygwin/include" \
  -I"$repo_root/newlib/libc/machine/aarch64" \
  -I"$repo_root/newlib/libc/include" \
  -c "$repo_root/winsup/cygwin/fenv.c" -o "$objects/code/fenv.o"
"$cc" -D__CYGWIN__ -Werror -Wall \
  -c "$repo_root/newlib/libm/machine/aarch64/fegetprec.c" \
  -o "$objects/code/fegetprec.o"
"$cc" -D__CYGWIN__ -Werror -Wall \
  -c "$repo_root/newlib/libm/machine/aarch64/fesetprec.c" \
  -o "$objects/code/fesetprec.o"

cat >"$work/architecture-controls.c" <<'EOF'
#include <windows.h>
#include <machine/endian.h>
#include "register.h"

void
probe_stack_initialization(void *address)
{
  __asm__ ("mov fp, %0\n\tmov sp, fp" : : "r" (address) : "memory");
}

void *
probe_stack_pointer(void)
{
  void *stack;
  __asm__ volatile ("mov %0, sp" : "=r" (stack));
  return stack;
}

int
main(void)
{
  CONTEXT context = {0};
  context.Pc = 11;
  context.Sp = 13;
  context.Fp = 17;
  return !(__ntohl(0x11223344u) == 0x44332211u
      && __ntohs(0x1122u) == 0x2211u
      && context._CX_instPtr + context._CX_stackPtr
         + context._CX_framePtr == 41
      && probe_stack_pointer() != 0);
}
EOF
"$cc" -D__CYGWIN__ -O2 -Werror -Wall \
  -I"$repo_root/winsup/cygwin/include" \
  -I"$repo_root/winsup/cygwin/local_includes" \
  -I"$repo_root/newlib/libc/include" \
  "$work/architecture-controls.c" -o "$programs/architecture-controls.exe"

"$cc" -Dsetjmp=layer2_setjmp -Dlongjmp=layer2_longjmp \
  -DWANT_GNU_PROPERTY=0 -I"$repo_root/newlib/libc/machine/aarch64" \
  -c "$repo_root/newlib/libc/machine/aarch64/setjmp.S" \
  -o "$objects/code/setjmp-runtime.o"
cat >"$work/setjmp-runtime.c" <<'EOF'
typedef long long layer2_jmp_buf[22];
extern int layer2_setjmp(layer2_jmp_buf);
extern void layer2_longjmp(layer2_jmp_buf, int);
static volatile int phase;

int
main(void)
{
  layer2_jmp_buf environment;
  int value = layer2_setjmp(environment);
  if (value == 0)
    {
      phase = 1;
      layer2_longjmp(environment, 7);
    }
  return !(value == 7 && phase == 1);
}
EOF
"$cc" -Werror -Wall "$work/setjmp-runtime.c" \
  "$objects/code/setjmp-runtime.o" -o "$programs/setjmp-runtime.exe"

"$cc" -Drawmemchr=layer2_rawmemchr -DWANT_GNU_PROPERTY=0 \
  -I"$repo_root/newlib/libc/machine/aarch64" \
  -c "$repo_root/newlib/libc/machine/aarch64/rawmemchr.S" \
  -o "$objects/code/rawmemchr-runtime.o"
cat >"$work/rawmemchr-runtime.c" <<'EOF'
extern void *layer2_rawmemchr(const void *, int);

int
main(void)
{
  const char text[] = "abcxd";
  return !((char *) layer2_rawmemchr(text, 0) == text + 5
      && (char *) layer2_rawmemchr(text, 'x') == text + 3);
}
EOF
"$cc" -Werror -Wall "$work/rawmemchr-runtime.c" \
  "$objects/code/rawmemchr-runtime.o" -o "$programs/rawmemchr-runtime.exe"

cat >"$work/precision-runtime.c" <<'EOF'
int fegetprec(void);
int fesetprec(int);

int
main(void)
{
  return !(fegetprec() == -1
      && fesetprec(0) == 0
      && fesetprec(-1) == 0);
}
EOF
"$cc" -Werror -Wall "$work/precision-runtime.c" \
  "$objects/code/fegetprec.o" "$objects/code/fesetprec.o" \
  -o "$programs/precision-runtime.exe"

for object in "$objects"/code/*.o
do
  assert_arm64_coff "$object"
done
for program in "$programs"/*.exe
do
  assert_arm64_pe "$program"
  "$program"
done

printf '%s\n' \
  "Native ARM64 foundation validation passed:" \
  "  16 AArch64 machine assembly objects are AA64 COFF" \
  "  retained ctype and floating-environment sources are AA64 COFF" \
  "  setjmp/longjmp, rawmemchr, precision, endian, register, and stack controls executed"
