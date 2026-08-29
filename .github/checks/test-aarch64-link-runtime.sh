#!/bin/sh

set -eu

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
work=${RUNNER_TEMP:-/tmp}/aarch64-layer3.$$
import_lib="$work/mkimport path.[x]/layer3 import.[x].dll.a"
cc=${CC:-clang}
ld=${LAYER3_LD:?LAYER3_LD is required}
as=${LAYER3_AS:?LAYER3_AS is required}
ar=${LAYER3_AR:?LAYER3_AR is required}
objdump=${LAYER3_OBJDUMP:?LAYER3_OBJDUMP is required}
perl=${NATIVE_PERL:?NATIVE_PERL is required}
llvm_nm=${LLVM_NM:-llvm-nm}
llvm_objcopy=${LLVM_OBJCOPY:-llvm-objcopy}
clang_lib=${CLANGARM64_LIB:-/clangarm64/lib}

cleanup()
{
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$work/objects" "$work/programs" "$work/mkimport path.[x]"

"$cc" -target aarch64-w64-windows-gnu -E -P -x c \
  -D__aarch64__ -D__MSYS__ \
  "$repo_root/winsup/cygwin/cygwin.sc.in" -o "$work/cygwin.sc"

case "$("$cc" -dumpmachine)" in
aarch64-*-windows-* | aarch64-*-mingw*) ;;
*)
  echo "compiler is not targeting native Windows ARM64" >&2
  exit 1
  ;;
esac

for tool in "$ld" "$as" "$ar" "$objdump" "$perl" "$llvm_nm" "$llvm_objcopy"; do
  test -x "$tool"
done
test -f "$clang_lib/libkernel32.a"

grep -Fq 'adr        x16, 3f' "$repo_root/winsup/cygwin/autoload.cc"
grep -Fq 'stur       x0, [x2, #12]' "$repo_root/winsup/cygwin/autoload.cc"
grep -Fq 'ldr        x0, [sp, #16] // func_info from dll_chain' \
  "$repo_root/winsup/cygwin/autoload.cc"
grep -Fq 'add        sp, sp, #16       // consume incoming dll_chain frame' \
  "$repo_root/winsup/cygwin/autoload.cc"
if grep -Fq 'str        x0, [x2, #12]' \
    "$repo_root/winsup/cygwin/autoload.cc"; then
  echo "autoload uses an unencodable scaled store for the +12 slot" >&2
  exit 1
fi
grep -Fq '((opcode1 & 0x9f00001f) == 0x90000010)' \
  "$repo_root/winsup/cygwin/mm/malloc_wrapper.cc"
grep -Fq 'case 12:' "$repo_root/winsup/cygwin/pseudo-reloc.cc"
grep -Fq 'case 21:' "$repo_root/winsup/cygwin/pseudo-reloc.cc"
grep -Fq 'FlushInstructionCache' "$repo_root/winsup/cygwin/pseudo-reloc.cc"

compile()
{
  "$cc" -target aarch64-w64-windows-gnu -O2 -Wall -Wextra -Werror \
    -ffreestanding -fno-stack-protector -fno-asynchronous-unwind-tables \
    -c "$1" -o "$2"
}

compile_cxx()
{
  "$cc" -target aarch64-w64-windows-gnu -x c++ -O2 -Wall -Wextra -Werror \
    -ffreestanding -fno-exceptions -fno-rtti -fno-stack-protector \
    -fno-asynchronous-unwind-tables -c "$1" -o "$2"
}

link_executable()
{
  output=$1
  shift
  "$ld" -m arm64pe --subsystem console --entry mainCRTStartup \
    --dynamicbase --disable-high-entropy-va --enable-reloc-section \
    -T "$work/cygwin.sc" -L"$clang_lib" -o "$output" "$@" -lkernel32
}

assert_pe()
{
  output=$("$objdump" -f -h -p "$1")
  printf '%s\n' "$output" | grep -q 'file format pei-aarch64-little'
  printf '%s\n' "$output" | grep -q 'architecture: aarch64'
  printf '%s\n' "$output" | grep -Eq 'DllCharacteristics[[:space:]]+00000140'
  printf '%s\n' "$output" | grep -Eq '^[[:space:]]*[0-9]+[[:space:]]+\.reloc[[:space:]]'
}

compile "$repo_root/.github/checks/aarch64-layer3-import-dll.c" \
  "$work/objects/import-dll.o"
"$ld" -m arm64pe --dll --entry DllMainCRTStartup \
  --dynamicbase --disable-high-entropy-va --enable-reloc-section \
  -T "$work/cygwin.sc" \
  --out-implib "$import_lib" \
  -o "$work/programs/layer3_import.dll" \
  "$repo_root/.github/checks/aarch64-layer3-import.def" \
  "$work/objects/import-dll.o"

mkwork="$work/mkimport path.[x]"
"$perl" "$repo_root/winsup/cygwin/scripts/mkimport" \
  --cpu=aarch64 --ar="$ar" --as="$as" --nm="$llvm_nm" \
  --objcopy="$llvm_objcopy" \
  "$mkwork/layer3 rewritten.a" "$import_lib"

compile "$repo_root/.github/checks/aarch64-layer3-import-main.c" \
  "$work/objects/import-main.o"
link_executable "$work/programs/import-main.exe" \
  "$work/objects/import-main.o" "$import_lib"

compile "$repo_root/.github/checks/aarch64-layer3-import-address.c" \
  "$work/objects/import-address.o"
compile_cxx \
  "$repo_root/.github/checks/aarch64-layer3-production-import-address.cc" \
  "$work/objects/production-import-address.o"
link_executable "$work/programs/import-address.exe" \
  "$work/objects/import-address.o" \
  "$work/objects/production-import-address.o" "$mkwork/layer3 rewritten.a"

compile "$repo_root/.github/checks/aarch64-layer3-production-autoload-main.c" \
  "$work/objects/production-autoload-main.o"
compile_cxx "$repo_root/.github/checks/aarch64-layer3-production-autoload.cc" \
  "$work/objects/production-autoload.o"
link_executable "$work/programs/production-autoload.exe" \
  "$work/objects/production-autoload-main.o" \
  "$work/objects/production-autoload.o"

compile "$repo_root/.github/checks/aarch64-layer3-pseudo-reloc.c" \
  "$work/objects/pseudo-reloc.o"
compile_cxx \
  "$repo_root/.github/checks/aarch64-layer3-production-pseudo-reloc.cc" \
  "$work/objects/production-pseudo-reloc.o"
link_executable "$work/programs/pseudo-reloc.exe" \
  "$work/objects/pseudo-reloc.o" "$work/objects/production-pseudo-reloc.o" \
  -lmsvcrt

compile "$repo_root/.github/checks/aarch64-layer3-pseudo-link.c" \
  "$work/objects/pseudo-link.o"
compile_cxx "$repo_root/winsup/cygwin/pseudo-reloc.cc" \
  "$work/objects/runtime-pseudo-reloc.o"
"$ld" -m arm64pe --subsystem console --entry mainCRTStartup \
  --dynamicbase --disable-high-entropy-va --enable-reloc-section \
  --enable-auto-import -T "$work/cygwin.sc" -L"$clang_lib" \
  -o "$work/programs/pseudo-link.exe" \
  "$work/objects/pseudo-link.o" "$work/objects/runtime-pseudo-reloc.o" \
  "$import_lib" -lkernel32 -lmsvcrt

for object in "$work"/objects/*.o; do
  "$objdump" -f "$object" | grep -q 'file format pe-aarch64-little'
done
for image in "$work"/programs/*; do
  assert_pe "$image"
done

"$objdump" -t "$work/programs/pseudo-reloc.exe" \
  | grep -q 'layer3_pseudo_reloc_shape'
"$objdump" -s -j .rdata "$work/programs/pseudo-reloc.exe" \
  > "$work/pseudo-reloc.rdata"
grep -q '0c000000' "$work/pseudo-reloc.rdata"
grep -q '15000000' "$work/pseudo-reloc.rdata"
"$objdump" -r "$work/objects/pseudo-link.o" > "$work/pseudo-link.relocs"
grep -q 'IMAGE_REL_ARM64_PAGEBASE_REL21.*layer3_import_data' \
  "$work/pseudo-link.relocs"
grep -q 'IMAGE_REL_ARM64_PAGEOFFSET_12L.*layer3_import_data' \
  "$work/pseudo-link.relocs"
"$objdump" -t "$work/programs/pseudo-link.exe" > "$work/pseudo-link.symbols"
symbol_offset()
{
  wanted=$1
  while IFS= read -r line; do
    case "$line" in
    *" $wanted"*)
      previous=
      penultimate=
      for field in $line; do
	penultimate=$previous
	previous=$field
      done
      printf '%s\n' "${penultimate#0x}"
      return
      ;;
    esac
  done < "$work/pseudo-link.symbols"
}
pseudo_start=$(symbol_offset __RUNTIME_PSEUDO_RELOC_LIST__)
pseudo_end=$(symbol_offset __RUNTIME_PSEUDO_RELOC_LIST_END__)
test -n "$pseudo_start"
test -n "$pseudo_end"
test "$pseudo_start" != "$pseudo_end"
"$objdump" -s -j .rdata "$work/programs/pseudo-link.exe" \
  > "$work/pseudo-link.rdata"
grep -q '40000000' "$work/pseudo-link.rdata"
"$objdump" -p "$work/programs/import-main.exe" \
  | grep -q 'DLL Name: layer3_import.dll'
"$objdump" -p "$work/programs/import-main.exe" \
  | grep -q 'layer3_import_add'

(
  cd "$work/programs"
  ./import-main.exe
  ./import-address.exe
  ./production-autoload.exe
  LAYER3_AUTOLOAD_CASE=a ./production-autoload.exe
  LAYER3_AUTOLOAD_CASE=d ./production-autoload.exe
  LAYER3_AUTOLOAD_CASE=g ./production-autoload.exe
  LAYER3_AUTOLOAD_CASE=n ./production-autoload.exe
  LAYER3_AUTOLOAD_CASE=l ./production-autoload.exe
  if LAYER3_AUTOLOAD_CASE=p ./production-autoload.exe; then
    echo "fatal production autoload procedure path unexpectedly returned" >&2
    exit 1
  else
    test "$?" -eq 91
  fi
  if LAYER3_AUTOLOAD_CASE=f ./production-autoload.exe; then
    echo "fatal production autoload DLL path unexpectedly returned" >&2
    exit 1
  else
    test "$?" -eq 91
  fi
  ./pseudo-reloc.exe
  ./pseudo-link.exe
)

for rejected in --disable-dynamicbase --disable-reloc-section; do
  output="$work/programs/rejected-${rejected#--}.exe"
  if "$ld" -m arm64pe --subsystem console --entry mainCRTStartup \
      "$rejected" -T "$work/cygwin.sc" -L"$clang_lib" -o "$output" \
      "$work/objects/pseudo-reloc.o" -lkernel32 \
      >"$output.log" 2>&1; then
    echo "linker accepted forbidden ARM64 option $rejected" >&2
    exit 1
  fi
  test ! -e "$output"
  grep -q 'not supported for AArch64 PE targets' "$output.log"
done

"$ar" t "$mkwork/layer3 rewritten.a" | grep -q .
"$objdump" -dr "$mkwork/layer3 rewritten.a" > "$work/mkimport.dis"
grep -Eq '[[:space:]]adrp[[:space:]]+x16,' "$work/mkimport.dis"
grep -Eq '[[:space:]]ldr[[:space:]]+x16, \[x16' "$work/mkimport.dis"
grep -Eq '[[:space:]]br[[:space:]]+x16' "$work/mkimport.dis"

compile "$repo_root/.github/checks/aarch64-layer3-import-main.c" \
  "$work/objects/mkimport-main.o"
link_executable "$work/programs/mkimport-main.exe" \
  "$work/objects/mkimport-main.o" "$mkwork/layer3 rewritten.a"
assert_pe "$work/programs/mkimport-main.exe"
(
  cd "$work/programs"
  ./mkimport-main.exe
)

(
  cd "$work"
  "$perl" "$repo_root/winsup/cygwin/scripts/gendef" \
    --cpu=aarch64 --output-def="$work/msys-aarch64.def" \
    "$repo_root/winsup/cygwin/aarch64/cygwin.din" \
    "$repo_root/winsup/cygwin/cygwin.din"
  "$perl" "$repo_root/winsup/cygwin/scripts/gendef" \
    --cpu=x86_64 --output-def="$work/msys-x86_64.def" \
    "$repo_root/winsup/cygwin/x86_64/cygwin.din" \
    "$repo_root/winsup/cygwin/cygwin.din"
)
grep -q '^LIBRARY "msys-2.0.dll"' "$work/msys-aarch64.def"
grep -q '^EXPORTS' "$work/msys-aarch64.def"
if grep -q '^_alloca' "$work/msys-aarch64.def"; then
  echo "x86-only _alloca leaked into AArch64 exports" >&2
  exit 1
fi
grep -q '^_alloca = __alloca' "$work/msys-x86_64.def"

grep -q '^OUTPUT_FORMAT(pei-aarch64-little)' "$work/cygwin.sc"
grep -q 'aarch64-pc-msys/lib/w32api' "$work/cygwin.sc"
grep -q '\.rdata_runtime_pseudo_reloc' "$work/cygwin.sc"
grep -Eq 'LONG *\(-1\); LONG *\(-1\).*LONG *\(0\); LONG *\(0\)' \
  "$work/cygwin.sc"

printf '%s\n' \
  "Native ARM64 layer-3 validation passed:" \
  "  AA64 import DLL, rewritten mkimport archive, and consumers executed" \
  "  production autoload load/retry/reentrancy/WSAStartup chains executed" \
  "  production 12/21-bit and linked pseudo-relocation paths executed" \
  "  malformed thunk/width and forbidden loader options failed closed" \
  "  DYNAMICBASE, base relocations, linker script, and split exports verified"
