#!/usr/bin/env bash

set -euo pipefail

if test "$#" -gt 1; then
  echo "usage: $0 [REPORT-DIRECTORY]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
target=aarch64-pc-cygwin
cc="${CC:-$target-gcc}"
dlltool="${DLLTOOL:-$target-dlltool}"
nm="${NM:-$target-nm}"
objcopy="${OBJCOPY:-$target-objcopy}"
objdump="${OBJDUMP:-$target-objdump}"

if test "$#" -eq 1; then
  report="$1"
  mkdir -p "$report"
else
  report="$(mktemp -d)"
  trap 'rm -rf "$report"' EXIT
fi

for tool in "$cc" "$dlltool" "$nm" "$objcopy" "$objdump"; do
  command -v "$tool" >/dev/null
done

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
  > "$report/aarch64-pseudo-reloc-link.dis"
for opcode in \
    90000000 \
    b0000000 \
    90008000 \
    f0ffffe0 \
    90ff8000; do
  grep -Eq "^[[:space:]]*[0-9a-f]+:[[:space:]]+$opcode[[:space:]]+adrp" \
    "$report/aarch64-pseudo-reloc-link.dis"
done

add_immediate()
{
  adrp_opcode="$1"
  add_opcode="$(
    awk -v adrp_opcode="$adrp_opcode" '
      $2 == adrp_opcode && $3 == "adrp" { found = 1; next }
      found && $3 == "add" { print $2; exit }
    ' "$report/aarch64-pseudo-reloc-link.dis"
  )"
  test -n "$add_opcode"
  printf '%u\n' "$(( (0x$add_opcode >> 10) & 0xfff ))"
}

zero_offset="$(add_immediate 90000000)"
test "$(( ($(add_immediate b0000000) - zero_offset) & 0xfff ))" \
  -eq 1
test "$(( ($(add_immediate 90008000) - zero_offset) & 0xfff ))" \
  -eq 0
test "$(( ($(add_immediate f0ffffe0) - zero_offset) & 0xfff ))" \
  -eq 4095
test "$(( ($(add_immediate 90ff8000) - zero_offset) & 0xfff ))" \
  -eq 0

"$nm" -n "$report/aarch64-pseudo-reloc-link.dll" \
  > "$report/aarch64-pseudo-reloc-link.symbols.txt"
pseudo_start="$(awk '$3 == "__RUNTIME_PSEUDO_RELOC_LIST__" { print $1; exit }' \
  "$report/aarch64-pseudo-reloc-link.symbols.txt")"
pseudo_end="$(awk '$3 == "__RUNTIME_PSEUDO_RELOC_LIST_END__" { print $1; exit }' \
  "$report/aarch64-pseudo-reloc-link.symbols.txt")"
test -n "$pseudo_start"
test -n "$pseudo_end"
test "$((0x$pseudo_end - 0x$pseudo_start))" -eq 132

"$objcopy" \
  --dump-section .rdata="$report/aarch64-pseudo-reloc-link.rdata" \
  "$report/aarch64-pseudo-reloc-link.dll"
read -r pagebase_count pageoffset_count < <(
  od -An -tu4 "$report/aarch64-pseudo-reloc-link.rdata" \
    | awk '{
        for (i = 1; i <= NF; ++i) {
          if ($i == 21) ++pagebase;
          if ($i == 12) ++pageoffset;
        }
      }
      END { print pagebase + 0, pageoffset + 0 }'
)
test "$pagebase_count" -eq 5
test "$pageoffset_count" -eq 5

"$objdump" -f -p "$report/aarch64-pseudo-reloc-link.dll" \
  > "$report/aarch64-pseudo-reloc-link.dll.txt"
grep -Fq 'file format pei-aarch64-little' \
  "$report/aarch64-pseudo-reloc-link.dll.txt"
grep -Fq 'DLL Name: abi-import.dll' \
  "$report/aarch64-pseudo-reloc-link.dll.txt"
