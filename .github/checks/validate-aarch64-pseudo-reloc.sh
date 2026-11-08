#!/usr/bin/env bash

set -euo pipefail

if test "$#" -lt 1 || test "$#" -gt 2; then
  echo "usage: $0 BUILD-DIRECTORY [REPORT-DIRECTORY]" >&2
  exit 2
fi

build="$(cd "$1" && pwd)"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
target=aarch64-pc-cygwin
cygwin="$build/$target/winsup/cygwin"
target_root="${TARGET_ROOT:-/opt/$target}"

cc="${CC:-$target-gcc}"
cxx="${CXX:-$target-g++}"
dlltool="${DLLTOOL:-$target-dlltool}"
nm="${NM:-$target-nm}"
objcopy="${OBJCOPY:-$target-objcopy}"
objdump="${OBJDUMP:-$target-objdump}"
host_cxx="${HOST_CXX:-g++}"

if test "$#" -eq 2; then
  report="$2"
  mkdir -p "$report"
  report="$(cd "$report" && pwd)"
else
  report="$(mktemp -d)"
  trap 'rm -rf "$report"' EXIT
fi

for tool in \
    "$cc" "$cxx" "$dlltool" "$nm" "$objcopy" "$objdump" "$host_cxx"; do
  command -v "$tool" >/dev/null
done

"$host_cxx" \
  -std=gnu++17 \
  -O2 \
  -Wall \
  -Wextra \
  -Werror \
  "$repo_root/.github/checks/aarch64-pseudo-reloc-model.cc" \
  -o "$report/aarch64-pseudo-reloc-model"
"$report/aarch64-pseudo-reloc-model"

"$report/aarch64-pseudo-reloc-model" \
  --write-observed-before \
  "$report/observed-before.bin"
"$report/aarch64-pseudo-reloc-model" \
  --write-observed-after \
  "$report/observed-after.bin"
"$objdump" -D -b binary -m aarch64 \
  "$report/observed-before.bin" \
  > "$report/observed-before.dis"
"$objdump" -D -b binary -m aarch64 \
  "$report/observed-after.bin" \
  > "$report/observed-after.dis"
for opcode in 90000001 912de021 90000000 912da000; do
  grep -Eq "^[[:space:]]*[0-9a-f]+:[[:space:]]+$opcode[[:space:]]+" \
    "$report/observed-before.dis"
done
for opcode in d0000021 f9416c21 d0000020 f9416400; do
  grep -Eq "^[[:space:]]*[0-9a-f]+:[[:space:]]+$opcode[[:space:]]+" \
    "$report/observed-after.dis"
done
test "$(grep -Ec '[[:space:]]adrp[[:space:]]' \
  "$report/observed-after.dis")" -eq 2
test "$(grep -Ec '[[:space:]]ldr[[:space:]]' \
  "$report/observed-after.dis")" -eq 2

cat > "$report/abi-import.def" <<'EOF'
LIBRARY "abi-import.dll" BASE=0x180040000

EXPORTS
abi_imported_data DATA
EOF

"$dlltool" \
  -d "$report/abi-import.def" \
  -l "$report/libabi-import.a" \
  -D abi-import.dll

"$cc" \
  -c "$repo_root/.github/checks/aarch64-pseudo-reloc-link.S" \
  -o "$report/aarch64-pseudo-reloc-link.o"
"$objdump" -dr "$report/aarch64-pseudo-reloc-link.o" \
  > "$report/aarch64-pseudo-reloc-link.object.dis"
test "$(grep -c 'IMAGE_REL_ARM64_PAGEBASE_REL21' \
  "$report/aarch64-pseudo-reloc-link.object.dis")" -eq 15
test "$(grep -c 'IMAGE_REL_ARM64_PAGEOFFSET_12A' \
  "$report/aarch64-pseudo-reloc-link.object.dis")" -eq 5
test "$(grep -c 'IMAGE_REL_ARM64_PAGEOFFSET_12L' \
  "$report/aarch64-pseudo-reloc-link.object.dis")" -eq 10

cat > "$report/pseudo-reloc-support.c" <<'EOF'
void
_pei386_runtime_relocator (void)
{
}
EOF
"$cc" \
  -std=gnu11 \
  -O2 \
  -Wall \
  -Wextra \
  -Werror \
  -c "$report/pseudo-reloc-support.c" \
  -o "$report/pseudo-reloc-support.o"

"$cc" \
  -shared \
  -nostdlib \
  -Wl,--no-insert-timestamp \
  -Wl,-e,abi_import_zero \
  -Wl,-u,_pei386_runtime_relocator \
  -o "$report/aarch64-pseudo-reloc-link.dll" \
  "$report/aarch64-pseudo-reloc-link.o" \
  "$report/pseudo-reloc-support.o" \
  -L"$report" \
  -labi-import

"$objdump" -d "$report/aarch64-pseudo-reloc-link.dll" \
  > "$report/aarch64-pseudo-reloc-link.linked.dis"
"$nm" -n "$report/aarch64-pseudo-reloc-link.dll" \
  > "$report/aarch64-pseudo-reloc-link.symbols.txt"
pseudo_start="$(awk \
  '$3 == "__RUNTIME_PSEUDO_RELOC_LIST__" { print $1; exit }' \
  "$report/aarch64-pseudo-reloc-link.symbols.txt")"
pseudo_end="$(awk \
  '$3 == "__RUNTIME_PSEUDO_RELOC_LIST_END__" { print $1; exit }' \
  "$report/aarch64-pseudo-reloc-link.symbols.txt")"
test -n "$pseudo_start"
test -n "$pseudo_end"
test "$((0x$pseudo_end - 0x$pseudo_start))" -eq 372

"$objcopy" \
  --dump-section .rdata="$report/aarch64-pseudo-reloc-link.rdata" \
  "$report/aarch64-pseudo-reloc-link.dll"
rdata_vma="$(
  "$objdump" -h "$report/aarch64-pseudo-reloc-link.dll" \
    | awk '$2 == ".rdata" { print $4; exit }'
)"
test -n "$rdata_vma"
dd \
  if="$report/aarch64-pseudo-reloc-link.rdata" \
  of="$report/aarch64-pseudo-reloc-link.table" \
  bs=1 \
  skip="$((0x$pseudo_start - 0x$rdata_vma))" \
  count="$((0x$pseudo_end - 0x$pseudo_start))" \
  status=none
od -An -v -tu4 -w12 "$report/aarch64-pseudo-reloc-link.table" \
  > "$report/aarch64-pseudo-reloc-link.table.txt"
awk '
  NR == 1 {
    if ($1 != 0 || $2 != 0 || $3 != 1)
      exit 1
    next
  }
  {
    if ($1 == 0 || $2 == 0)
      exit 1
    if ($3 == 21)
      ++pagebase
    else if ($3 == 12)
      ++pageoffset
    else
      exit 1
    ++records
  }
  END {
    if (records != 30 || pagebase != 15 || pageoffset != 15)
      exit 1
  }
' "$report/aarch64-pseudo-reloc-link.table.txt"

"$objdump" -f -p "$report/aarch64-pseudo-reloc-link.dll" \
  > "$report/aarch64-pseudo-reloc-link.dll.txt"
grep -Fq 'file format pei-aarch64-little' \
  "$report/aarch64-pseudo-reloc-link.dll.txt"
grep -Fq 'DLL Name: abi-import.dll' \
  "$report/aarch64-pseudo-reloc-link.dll.txt"

test -s "$cygwin/libmsys-2.0.a"
test -s "$target_root/lib/default-manifest.o"

"$cc" \
  -c "$repo_root/.github/checks/aarch64-pseudo-reloc-provider.S" \
  -o "$report/aarch64-pseudo-reloc-provider.o"
cat > "$report/aarch64-near-import.def" <<'EOF'
LIBRARY "aarch64-near-import.dll" BASE=0x140040000

EXPORTS
aarch64_near_value DATA
EOF
cat > "$report/aarch64-far-import.def" <<'EOF'
LIBRARY "aarch64-far-import.dll" BASE=0x600040000

EXPORTS
aarch64_far_object DATA
EOF

"$cc" \
  -shared \
  -nostdlib \
  -Wl,--no-insert-timestamp \
  -Wl,--disable-dynamicbase \
  -Wl,--image-base,0x140040000 \
  -Wl,-e,DllMainCRTStartup \
  -Wl,--out-implib,"$report/libaarch64-near-import.a" \
  -o "$report/aarch64-near-import.dll" \
  "$report/aarch64-pseudo-reloc-provider.o" \
  "$report/aarch64-near-import.def"
"$cc" \
  -shared \
  -nostdlib \
  -Wl,--no-insert-timestamp \
  -Wl,--disable-dynamicbase \
  -Wl,--image-base,0x600040000 \
  -Wl,-e,DllMainCRTStartup \
  -Wl,--out-implib,"$report/libaarch64-far-import.a" \
  -o "$report/aarch64-far-import.dll" \
  "$report/aarch64-pseudo-reloc-provider.o" \
  "$report/aarch64-far-import.def"

"$cc" \
  -std=gnu11 \
  -D__MSYS__ \
  -O2 \
  -g \
  -Wall \
  -Wextra \
  -Werror \
  -isystem "$repo_root/winsup/cygwin/include" \
  -c "$repo_root/.github/checks/aarch64-pseudo-reloc-native.c" \
  -o "$report/aarch64-pseudo-reloc-native.o"
"$objdump" -dr "$report/aarch64-pseudo-reloc-native.o" \
  > "$report/aarch64-pseudo-reloc-native.object.dis"
grep -Fq 'IMAGE_REL_ARM64_PAGEOFFSET_12A' \
  "$report/aarch64-pseudo-reloc-native.object.dis"
grep -Fq 'IMAGE_REL_ARM64_PAGEOFFSET_12L' \
  "$report/aarch64-pseudo-reloc-native.object.dis"

gccdir="$(dirname "$("$cc" -print-file-name=libgcc.a)")"
"$cc" \
  -nostdlib \
  -Wl,--no-insert-timestamp \
  -Wl,--disable-dynamicbase \
  -Wl,--image-base,0x100400000 \
  -Wl,--subsystem,console \
  -Wl,-e,mainCRTStartup \
  -o "$report/aarch64-pseudo-reloc-native.exe" \
  "$cygwin/crt0.o" \
  "$gccdir/crtbegin.o" \
  "$report/aarch64-pseudo-reloc-native.o" \
  -L"$report" \
  -L"$cygwin" \
  -Wl,--start-group \
  -laarch64-near-import \
  -laarch64-far-import \
  -lmsys-2.0 \
  -lgcc \
  -Wl,--end-group \
  "$gccdir/crtend.o" \
  "$target_root/lib/default-manifest.o" \
  -lkernel32 \
  -lntdll
"$objdump" -d "$report/aarch64-pseudo-reloc-native.exe" \
  > "$report/aarch64-pseudo-reloc-native.linked.dis"
"$nm" -n "$report/aarch64-pseudo-reloc-native.exe" \
  > "$report/aarch64-pseudo-reloc-native.symbols.txt"
native_pseudo_start="$(awk \
  '$3 == "__RUNTIME_PSEUDO_RELOC_LIST__" { print $1; exit }' \
  "$report/aarch64-pseudo-reloc-native.symbols.txt")"
native_pseudo_end="$(awk \
  '$3 == "__RUNTIME_PSEUDO_RELOC_LIST_END__" { print $1; exit }' \
  "$report/aarch64-pseudo-reloc-native.symbols.txt")"
test -n "$native_pseudo_start"
test -n "$native_pseudo_end"
test "$native_pseudo_start" != "$native_pseudo_end"

"$cc" \
  -c "$repo_root/.github/checks/aarch64-pseudo-reloc-far-addend.S" \
  -o "$report/aarch64-pseudo-reloc-far-addend.o"
"$objdump" -dr "$report/aarch64-pseudo-reloc-far-addend.o" \
  > "$report/aarch64-pseudo-reloc-far-addend.object.dis"
grep -Fq 'IMAGE_REL_ARM64_PAGEBASE_REL21' \
  "$report/aarch64-pseudo-reloc-far-addend.object.dis"
grep -Fq 'IMAGE_REL_ARM64_PAGEOFFSET_12A' \
  "$report/aarch64-pseudo-reloc-far-addend.object.dis"
"$cc" \
  -nostdlib \
  -Wl,--no-insert-timestamp \
  -Wl,--disable-dynamicbase \
  -Wl,--image-base,0x100400000 \
  -Wl,--subsystem,console \
  -Wl,-e,mainCRTStartup \
  -o "$report/aarch64-pseudo-reloc-far-addend.exe" \
  "$cygwin/crt0.o" \
  "$gccdir/crtbegin.o" \
  "$report/aarch64-pseudo-reloc-far-addend.o" \
  -L"$report" \
  -L"$cygwin" \
  -Wl,--start-group \
  -laarch64-far-import \
  -lmsys-2.0 \
  -lgcc \
  -Wl,--end-group \
  "$gccdir/crtend.o" \
  "$target_root/lib/default-manifest.o" \
  -lkernel32 \
  -lntdll

msys_cxx="${MSYS_CXX:-aarch64-pc-msys-g++}"
msys_objdump="${MSYS_OBJDUMP:-$objdump}"
msys_nm="${MSYS_NM:-$nm}"
for tool in "$msys_cxx" "$msys_objdump" "$msys_nm"; do
  command -v "$tool" >/dev/null
done

"$msys_cxx" \
  -std=gnu++20 \
  -O2 \
  -g \
  -Wall \
  -Wextra \
  -Werror \
  -pthread \
  -c "$repo_root/.github/checks/aarch64-dynamic-cxx.cc" \
  -o "$report/aarch64-dynamic-cxx.o"
"$msys_objdump" -dr "$report/aarch64-dynamic-cxx.o" \
  > "$report/aarch64-dynamic-cxx.object.dis"
grep -Fq 'IMAGE_REL_ARM64_PAGEBASE_REL21' \
  "$report/aarch64-dynamic-cxx.object.dis"
grep -Fq 'IMAGE_REL_ARM64_PAGEOFFSET_12A' \
  "$report/aarch64-dynamic-cxx.object.dis"

"$msys_cxx" \
  -std=gnu++20 \
  -O2 \
  -g \
  -Wall \
  -Wextra \
  -Werror \
  -pthread \
  -Wl,--no-insert-timestamp \
  -L"$cygwin" \
  "$report/aarch64-dynamic-cxx.o" \
  -o "$report/aarch64-dynamic-cxx.exe"
"$msys_objdump" -f -p "$report/aarch64-dynamic-cxx.exe" \
  > "$report/aarch64-dynamic-cxx.exe.txt"
grep -Fq 'file format pei-aarch64-little' \
  "$report/aarch64-dynamic-cxx.exe.txt"
grep -Fq 'DLL Name: msys-2.0.dll' \
  "$report/aarch64-dynamic-cxx.exe.txt"
grep -Fq 'DLL Name: msys-stdc++-6.dll' \
  "$report/aarch64-dynamic-cxx.exe.txt"
"$msys_nm" -a -n "$report/aarch64-dynamic-cxx.exe" \
  > "$report/aarch64-dynamic-cxx.symbols.txt"
grep -Eq '__fu[0-9]+__ZSt4cout$' \
  "$report/aarch64-dynamic-cxx.symbols.txt"
dynamic_pseudo_start="$(awk \
  '$3 == "__RUNTIME_PSEUDO_RELOC_LIST__" { print $1; exit }' \
  "$report/aarch64-dynamic-cxx.symbols.txt")"
dynamic_pseudo_end="$(awk \
  '$3 == "__RUNTIME_PSEUDO_RELOC_LIST_END__" { print $1; exit }' \
  "$report/aarch64-dynamic-cxx.symbols.txt")"
test -n "$dynamic_pseudo_start"
test -n "$dynamic_pseudo_end"
test "$dynamic_pseudo_start" != "$dynamic_pseudo_end"

cp "$cygwin/new-msys-2.0.dll" "$report/msys-2.0.dll"
for dll in msys-gcc_s-seh-1.dll msys-stdc++-6.dll; do
  source_dll="$(find /opt -type f -name "$dll" -print -quit)"
  test -n "$source_dll"
  cp "$source_dll" "$report/$dll"
done

grep -Fq 'Malformed pseudo relocation table size' \
  "$repo_root/winsup/cygwin/pseudo-reloc.cc"
grep -Fq 'FlushInstructionCache' \
  "$repo_root/winsup/cygwin/pseudo-reloc.cc"
