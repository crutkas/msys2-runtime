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
target_root="${TARGET_ROOT:-${TOOLCHAIN_DIR:?TOOLCHAIN_DIR is required}/aarch64-pc-msys}"

cc="${CC:-$target-gcc}"
cxx="${CXX:-$target-g++}"
nm="${NM:-$target-nm}"
objdump="${OBJDUMP:-$target-objdump}"
initializer_symbols=(
  __pthread_recursive_mutex_initializer_np
  __pthread_normal_mutex_initializer_np
  __pthread_errorcheck_mutex_initializer_np
  __pthread_cond_initializer
  __pthread_rwlock_initializer
)

if test "$#" -eq 2; then
  report="$2"
  mkdir -p "$report"
else
  report="$(mktemp -d)"
  trap 'rm -rf "$report"' EXIT
fi

for tool in "$cc" "$cxx" "$nm" "$objdump"; do
  command -v "$tool" >/dev/null
done

for file in \
    "$cygwin/crt0.o" \
    "$cygwin/libmsys-2.0.a" \
    "$cygwin/new-msys-2.0.dll" \
    "$target_root/lib/default-manifest.o"; do
  test -s "$file"
done

include_flags=(
  -isystem "$repo_root/winsup/cygwin/include"
)
link_flags=(
  -L"$cygwin"
  -L"$target_root/lib"
  -L"$target_root/usr/lib"
)
common_flags=(
  -D__MSYS__
  -O2
  -g
  -Wall
  -Wextra
  -Werror
  "${include_flags[@]}"
)

assert_no_pseudo_relocations()
{
  image="$1"
  symbols="$image.symbols.txt"

  "$nm" -n "$image" > "$symbols"
  start="$(awk '$3 == "__RUNTIME_PSEUDO_RELOC_LIST__" { print $1; exit }' \
    "$symbols")"
  end="$(awk '$3 == "__RUNTIME_PSEUDO_RELOC_LIST_END__" { print $1; exit }' \
    "$symbols")"
  test -z "$start" -a -z "$end" || test "$start" = "$end"
}

pthreadconst="$(find "$cygwin" -type f -name pthreadconst.o -print -quit)"
test -n "$pthreadconst"
"$nm" -a "$pthreadconst" > "$report/pthreadconst.symbols.txt"
"$objdump" -h "$pthreadconst" > "$report/pthreadconst.sections.txt"
grep -Eq '^[[:space:]]*[0-9]+[[:space:]]+\.data[[:space:]]+00000028.*2\*\*3$' \
  "$report/pthreadconst.sections.txt"
for symbol in "${initializer_symbols[@]}"; do
  address="$(awk -v symbol="$symbol" \
    '$2 == "D" && $3 == symbol { print $1; exit }' \
    "$report/pthreadconst.symbols.txt")"
  test -n "$address"
  test "$((0x$address % 8))" -eq 0
done
test "$(
  awk '$2 == "D" && $3 ~ /^__pthread_.*_initializer(_np)?$/ { print $1 }' \
    "$report/pthreadconst.symbols.txt" | sort -u | wc -l
)" -eq 5
if grep -Eq '[[:space:]]A[[:space:]]+__pthread_.*_initializer' \
    "$report/pthreadconst.symbols.txt"; then
  echo "AArch64 pthread initializer retained a low absolute symbol" >&2
  exit 1
fi

compile_pthread_probe()
{
  language="$1"
  compiler="$2"
  standard="$3"
  object="$report/aarch64-pthread-initializers-$language.o"

  "$compiler" \
    -x "$language" \
    -std="$standard" \
    "${common_flags[@]}" \
    -c "$repo_root/.github/checks/aarch64-pthread-initializers.c" \
    -o "$object"

  "$nm" -u "$object" > "$object.undefined.txt"
  "$objdump" -r "$object" > "$object.relocations.txt"
  for symbol in "${initializer_symbols[@]}"; do
    iat_symbol="__imp_$symbol"
    grep -Eq "[[:space:]]U[[:space:]]+$iat_symbol$" \
      "$object.undefined.txt"
    grep -Eq "[[:space:]]$iat_symbol$" "$object.relocations.txt"
    if grep -Eq "[[:space:]]U[[:space:]]+$symbol$" \
	"$object.undefined.txt" \
	|| grep -Eq "[[:space:]]$symbol$" "$object.relocations.txt"; then
      echo "$language pthread initializer probe referenced $symbol directly" >&2
      exit 1
    fi
  done
  if "$nm" -a "$object" | grep -q _GLOBAL__sub_I; then
    echo "$language pthread initializer probe required dynamic initialization" >&2
    exit 1
  fi

  "$cc" \
    -shared \
    -nostdlib \
    -Wl,--no-insert-timestamp \
    -Wl,-e,abi_default_mutex_value \
    -o "$report/aarch64-pthread-initializers-$language.dll" \
    "$object" \
    "${link_flags[@]}" \
    -Wl,--start-group \
    -lmsys-2.0 \
    -lgcc \
    -Wl,--end-group \
    -lkernel32 \
    -lntdll
  "$objdump" -f -p "$report/aarch64-pthread-initializers-$language.dll" \
    > "$report/aarch64-pthread-initializers-$language.dll.txt"
  grep -Fq 'file format pei-aarch64-little' \
    "$report/aarch64-pthread-initializers-$language.dll.txt"
  grep -Fq 'DLL Name: msys-2.0.dll' \
    "$report/aarch64-pthread-initializers-$language.dll.txt"
  assert_no_pseudo_relocations \
    "$report/aarch64-pthread-initializers-$language.dll"
}

compile_pthread_probe c "$cc" gnu11
compile_pthread_probe c++ "$cxx" gnu++20

"$cxx" \
  -std=gnu++20 \
  "${common_flags[@]}" \
  -c "$repo_root/.github/checks/aarch64-std-mutex-constinit.cc" \
  -o "$report/aarch64-std-mutex-constinit.o"
"$nm" -a "$report/aarch64-std-mutex-constinit.o" \
  > "$report/aarch64-std-mutex-constinit.symbols.txt"
"$objdump" -r "$report/aarch64-std-mutex-constinit.o" \
  > "$report/aarch64-std-mutex-constinit.relocations.txt"
grep -Eq '[[:space:]]__imp___pthread_normal_mutex_initializer_np$' \
  "$report/aarch64-std-mutex-constinit.relocations.txt"
if grep -Eq '[[:space:]]__pthread_normal_mutex_initializer_np$' \
    "$report/aarch64-std-mutex-constinit.relocations.txt"; then
  echo "constinit std::mutex referenced the runtime DATA object directly" >&2
  exit 1
fi
if grep -q _GLOBAL__sub_I \
    "$report/aarch64-std-mutex-constinit.symbols.txt"; then
  echo "constinit std::mutex required dynamic initialization" >&2
  exit 1
fi
"$cc" \
  -shared \
  -nostdlib \
  -Wl,--no-insert-timestamp \
  -Wl,-e,abi_std_mutex_address \
  -o "$report/aarch64-std-mutex-constinit.dll" \
  "$report/aarch64-std-mutex-constinit.o" \
  "${link_flags[@]}" \
  -lmsys-2.0
"$objdump" -f -p "$report/aarch64-std-mutex-constinit.dll" \
  > "$report/aarch64-std-mutex-constinit.dll.txt"
grep -Fq 'file format pei-aarch64-little' \
  "$report/aarch64-std-mutex-constinit.dll.txt"
grep -Fq 'DLL Name: msys-2.0.dll' \
  "$report/aarch64-std-mutex-constinit.dll.txt"
assert_no_pseudo_relocations "$report/aarch64-std-mutex-constinit.dll"

"$cc" \
  -std=gnu11 \
  "${common_flags[@]}" \
  -c "$repo_root/.github/checks/aarch64-ctype-compat.c" \
  -o "$report/aarch64-ctype-compat.o"
"$cxx" \
  -std=gnu++17 \
  "${common_flags[@]}" \
  -c "$repo_root/.github/checks/aarch64-newlib-ctype-config.cc" \
  -o "$report/aarch64-newlib-ctype-config.o"

for spec in \
    "aarch64-ctype-compat.o:direct_ctype_table" \
    "aarch64-newlib-ctype-config.o:libstdcxx_newlib_classic_table"; do
  object="${spec%%:*}"
  entry="${spec#*:}"
  dll="${object%.o}.dll"

  "$nm" -u "$report/$object" > "$report/$object.undefined.txt"
  grep -Eq '[[:space:]]U[[:space:]]+__imp__ctype_$' \
    "$report/$object.undefined.txt"
  "$cc" \
    -shared \
    -nostdlib \
    -Wl,--no-insert-timestamp \
    -Wl,-e,"$entry" \
    -o "$report/$dll" \
    "$report/$object" \
    "${link_flags[@]}" \
    -Wl,--start-group \
    -lmsys-2.0 \
    -lgcc \
    -Wl,--end-group \
    -lkernel32 \
    -lntdll
  "$objdump" -f -p "$report/$dll" > "$report/$dll.txt"
  grep -Fq 'file format pei-aarch64-little' "$report/$dll.txt"
  grep -Fq 'DLL Name: msys-2.0.dll' "$report/$dll.txt"
  assert_no_pseudo_relocations "$report/$dll"
done

gccdir="$(dirname "$("$cc" -print-file-name=libgcc.a)")"

link_runtime_probe()
{
  source="$1"
  output="$2"
  object="$report/${output%.exe}.o"

  "$cc" \
    -std=gnu11 \
    -DABI_RUNTIME_TEST \
    "${common_flags[@]}" \
    -c "$repo_root/.github/checks/$source" \
    -o "$object"
  "$cc" \
    -nostdlib \
    -Wl,--no-insert-timestamp \
    -Wl,--subsystem,console \
    -Wl,-e,mainCRTStartup \
    -o "$report/$output" \
    "$cygwin/crt0.o" \
    "$gccdir/crtbegin.o" \
    "$object" \
    "${link_flags[@]}" \
    -Wl,--start-group \
    -lmsys-2.0 \
    -lgcc \
    -Wl,--end-group \
    "$gccdir/crtend.o" \
    "$target_root/lib/default-manifest.o" \
    -lkernel32 \
    -lntdll
  "$objdump" -f -p "$report/$output" > "$report/$output.txt"
  grep -Fq 'file format pei-aarch64-little' "$report/$output.txt"
  grep -Fq 'DLL Name: msys-2.0.dll' "$report/$output.txt"
}

link_runtime_probe \
  aarch64-pthread-initializers.c \
  aarch64-pthread-initializers.exe
link_runtime_probe \
  aarch64-ctype-compat.c \
  aarch64-ctype-compat.exe

"$objdump" -p "$cygwin/new-msys-2.0.dll" \
  > "$report/msys-2.0-public-abi.txt"
grep -Eq '[[:space:]]_ctype_$' "$report/msys-2.0-public-abi.txt"
grep -Eq '[[:space:]]__locale_ctype_ptr$' \
  "$report/msys-2.0-public-abi.txt"
for symbol in "${initializer_symbols[@]}"; do
  grep -Eq "[[:space:]]$symbol$" "$report/msys-2.0-public-abi.txt"
done

"$nm" -A "$cygwin/libmsys-2.0.a" \
  > "$report/libmsys-2.0-public-abi.txt"
grep -Eq '[[:space:]]I[[:space:]]+__imp__ctype_$' \
  "$report/libmsys-2.0-public-abi.txt"
grep -Eq '[[:space:]]I[[:space:]]+__imp___locale_ctype_ptr$' \
  "$report/libmsys-2.0-public-abi.txt"
for symbol in "${initializer_symbols[@]}"; do
  grep -Eq "[[:space:]]I[[:space:]]+__imp_$symbol$" \
    "$report/libmsys-2.0-public-abi.txt"
  if grep -Eq "[[:space:]][AD][[:space:]]+$symbol$" \
      "$report/libmsys-2.0-public-abi.txt"; then
    echo "import library embedded AArch64 initializer object $symbol" >&2
    exit 1
  fi
done

sha256sum \
  "$report"/aarch64-pthread-initializers-*.dll \
  "$report"/aarch64-ctype-compat.dll \
  "$report"/aarch64-newlib-ctype-config.dll \
  "$report"/aarch64-std-mutex-constinit.dll \
  "$report"/aarch64-std-mutex-constinit.o \
  "$report"/aarch64-pthread-initializers.exe \
  "$report"/aarch64-ctype-compat.exe \
  > "$report/public-abi-SHA256SUMS"
