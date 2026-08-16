#!/usr/bin/env bash

set -euo pipefail

if test "$#" -lt 1 || test "$#" -gt 2; then
  echo "usage: $0 BUILD-DIRECTORY [REPORT-DIRECTORY]" >&2
  exit 2
fi

build="$(cd "$1" && pwd)"
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
target=aarch64-pc-cygwin
newlib="$build/$target/newlib"
winsup="$build/$target/winsup"
cygwin="$winsup/cygwin"
dll="$cygwin/new-msys-2.0.dll"
implib="$cygwin/libmsys-2.0.a"
map="$cygwin/msys.map"
def="$cygwin/msys.def"

cc="${CC:-$target-gcc}"
ar="${AR:-$target-ar}"
nm="${NM:-$target-nm}"
objdump="${OBJDUMP:-$target-objdump}"

if test "$#" -eq 2; then
  report="$2"
  mkdir -p "$report"
else
  report="$(mktemp -d)"
  trap 'rm -rf "$report"' EXIT
fi

for tool in "$cc" "$ar" "$nm" "$objdump"; do
  command -v "$tool" >/dev/null
done

for cpu in aarch64 x86_64; do
  mkdir -p "$report/$cpu-def"
  (
    cd "$report/$cpu-def"
    "$repo_root/winsup/cygwin/scripts/gendef" \
      --cpu="$cpu" \
      --output-def=msys.def \
      "$repo_root/winsup/cygwin/$cpu/cygwin.din" \
      "$repo_root/winsup/cygwin/cygwin.din"
  )
done
cmp "$report/aarch64-def/msys.def" "$def"
for symbol in \
    _alloca \
    _ctype_ \
    _fe_nomask_env \
    fedisableexcept \
    feenableexcept \
    fegetexcept \
    fegetprec \
    fesetprec; do
  grep -Eq "^$symbol([[:space:]]|$)" "$report/x86_64-def/msys.def"
  if grep -Eq "^$symbol([[:space:]]|$)" "$report/aarch64-def/msys.def"; then
    echo "AArch64 definition retained x86-only export $symbol" >&2
    exit 1
  fi
done

for file in \
    "$newlib/libc.a" \
    "$newlib/libm.a" \
    "$winsup/cygserver/libcygserver.a" \
    "$cygwin/libdll.a" \
    "$dll" \
    "$implib" \
    "$map" \
    "$def"; do
  test -s "$file"
done

"$cc" -D__MSYS__ -dM -E - </dev/null > "$report/compiler-macros.txt"
for macro in __aarch64__ __CYGWIN__ __MSYS__ _WIN64; do
  grep -Eq "^#define $macro([[:space:]]|$)" "$report/compiler-macros.txt"
done
if grep -Eq '^#define __x86_64__([[:space:]]|$)' \
    "$report/compiler-macros.txt"; then
  echo "AArch64 compiler leaked the x86_64 target macro" >&2
  exit 1
fi

find "$newlib" "$cygwin" \
  -path "$newlib/doc" -prune -o \
  -type f -name '*.o' -print0 \
  | sort -z \
  | while IFS= read -r -d '' object; do
      "$objdump" -f "$object"
    done > "$report/object-formats.txt"
object_count="$(grep -Fc 'file format pe-aarch64-little' \
  "$report/object-formats.txt")"
test "$object_count" -gt 1000
if grep -Eiq 'pei-x86-64|i386:x86-64|file format pe-i386' \
    "$report/object-formats.txt"; then
  echo "A foreign object was found in the target build" >&2
  exit 1
fi

audit_archive()
{
  archive="$1"
  name="$(basename "$archive")"
  members="$("$ar" t "$archive" | wc -l)"
  "$objdump" -f "$archive" > "$report/$name-formats.txt"
  arm64="$(grep -Fc 'file format pe-aarch64-little' \
    "$report/$name-formats.txt")"
  test "$members" -eq "$arm64"
  printf '%s\t%s\n' "$archive" "$members"
}

{
  audit_archive "$newlib/libc.a"
  audit_archive "$newlib/libm.a"
  audit_archive "$winsup/cygserver/libcygserver.a"
  audit_archive "$cygwin/libdll.a"
  audit_archive "$implib"
  audit_archive "$("$cc" -print-libgcc-file-name)"
} > "$report/archive-members.txt"

"$objdump" -f -h -p "$dll" > "$report/msys-2.0.dll.txt"
"$nm" -a "$dll" > "$report/msys-2.0.dll.symbols.txt"
sha256sum "$dll" "$implib" > "$report/SHA256SUMS"

pe="$report/msys-2.0.dll.txt"
symbols="$report/msys-2.0.dll.symbols.txt"
grep -Fq 'file format pei-aarch64-little' "$pe"
grep -Fq 'architecture: aarch64' "$pe"
grep -Eq 'Magic[[:space:]]+020b' "$pe"
grep -Eq 'ImageBase[[:space:]]+0000000180040000' "$pe"
grep -Eq 'SectionAlignment[[:space:]]+00001000' "$pe"

entry_rva="$(awk '$1 == "AddressOfEntryPoint" { print $2; exit }' "$pe")"
image_base="$(awk '$1 == "ImageBase" { print $2; exit }' "$pe")"
entry_symbol="$(awk '$2 == "T" && $3 == "dll_entry" { print $1; exit }' \
  "$symbols")"
test -n "$entry_rva"
test -n "$image_base"
test -n "$entry_symbol"
test "$((0x$image_base + 0x$entry_rva))" -eq "$((0x$entry_symbol))"

for section in \
    .text \
    .data \
    .rdata \
    .pdata \
    .xdata \
    .bss \
    .edata \
    .reloc \
    .cygwin_dll_common \
    .idata \
    .rsrc; do
  section_pattern="\\$section"
  grep -Eq "^[[:space:]]*[0-9]+[[:space:]]+${section_pattern}[[:space:]]" \
    "$pe"
done

grep -Eq 'Entry 0 .* Export Directory' "$pe"
grep -Eq 'Entry 1 .* Import Directory' "$pe"
grep -Eq 'Entry 2 .* Resource Directory' "$pe"
grep -Eq 'Entry 3 .* Exception Directory' "$pe"
grep -Eq 'Entry 5 .* Base Relocation Directory' "$pe"
grep -Eq 'Entry 9 0000000000000000 00000000 Thread Storage Directory' "$pe"
grep -Fq 'Number in:' "$pe"
grep -Eq 'Export Address Table[[:space:]]+000006df' "$pe"

for export in dll_entry msys_detach_dll msys_dll_init; do
  grep -Eq "[[:space:]][0-9a-f]+[[:space:]]+$export$" "$pe"
done
for excluded in \
    _alloca \
    _ctype_ \
    _fe_nomask_env \
    fedisableexcept \
    feenableexcept \
    fegetexcept \
    fegetprec \
    fesetprec; do
  if grep -Eq "[[:space:]][0-9a-f]+[[:space:]]+$excluded$" "$pe"; then
    echo "AArch64 DLL exported x86-only symbol $excluded" >&2
    exit 1
  fi
done

awk '/DLL Name:/ { print $3 }' "$pe" | sort -u \
  > "$report/imported-dlls.txt"
printf '%s\n' KERNEL32.dll ntdll.dll | sort \
  | cmp - "$report/imported-dlls.txt"
if grep -Eiq 'cygwin1\.dll|msys-2\.0\.dll' "$report/imported-dlls.txt"; then
  echo "The runtime DLL imported a Cygwin or MSYS runtime" >&2
  exit 1
fi

grep -Eq '[[:space:]]__CTOR_LIST__$' "$symbols"
grep -Eq '[[:space:]]__DTOR_LIST__$' "$symbols"
grep -Eq '[[:space:]]_cygtls' "$symbols"
if grep -Ev '[[:space:]]U[[:space:]]+\$[dx]$' "$symbols" \
    | grep -Eq '[[:space:]]U[[:space:]]'; then
  echo "The linked runtime retained a non-mapping undefined symbol" >&2
  exit 1
fi

grep -Fq 'default-manifest.o' "$map"
grep -Fq 'libgcc.a(' "$map"
grep -Fq 'libkernel32.a(' "$map"
grep -Fq 'libntdll.a(' "$map"
grep -Fq '.ctors' "$map"
grep -Fq '.dtors' "$map"
grep -Fq '.cygwin_dll_common' "$map"
grep -Fq 'Entry: ID: 0x000018' "$pe"
if grep -Eiq 'x86_64-pc|x86_64-w64|aarch64-w64-mingw32' "$map"; then
  echo "The runtime map selected a foreign target input" >&2
  exit 1
fi

sed -n 's#^[[:space:]]*\([^ (]*\.a\)(\([^)]*\)).*#\1\t\2#p' "$map" \
  | sort -u > "$report/selected-archive-members.txt"
test -s "$report/selected-archive-members.txt"
selected=0
while IFS=$'\t' read -r archive member; do
  case "$archive" in
    /*) ;;
    *) archive="$cygwin/$archive" ;;
  esac
  test -f "$archive"
  selected=$((selected + 1))
  "$ar" p "$archive" "$member" > "$report/selected-$selected.o"
  "$objdump" -f "$report/selected-$selected.o"
done < "$report/selected-archive-members.txt" \
  > "$report/selected-archive-formats.txt"
selected_arm64="$(grep -Fc 'file format pe-aarch64-little' \
  "$report/selected-archive-formats.txt")"
test "$selected" -eq "$selected_arm64"
rm -f "$report"/selected-*.o

smoke="$cygwin/aarch64-runtime-smoke.exe"
if test -f "$smoke"; then
  "$objdump" -f -h -p "$smoke" > "$report/aarch64-runtime-smoke.txt"
  grep -Fq 'file format pei-aarch64-little' \
    "$report/aarch64-runtime-smoke.txt"
  grep -Fq 'DLL Name: msys-2.0.dll' "$report/aarch64-runtime-smoke.txt"
  sha256sum "$smoke" >> "$report/SHA256SUMS"
fi

{
  printf 'objects\t%s\n' "$object_count"
  printf 'selected_archive_members\t%s\n' "$selected"
  printf 'exports\t1759\n'
  printf 'entry_symbol\t0x%s\n' "$entry_symbol"
  printf 'image_base\t0x%s\n' "$image_base"
  printf 'pe_tls_directory\tcustom-cygtls-no-pe-directory\n'
} > "$report/summary.txt"
