#!/usr/bin/env bash

set -euo pipefail

if test "$#" -ne 2; then
  echo "usage: $0 BUILD-DIRECTORY OUTPUT-DIRECTORY" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$(cd "$1" && pwd)"
output="$2"
target=aarch64-pc-cygwin
cygwin="$build/$target/winsup/cygwin"
target_root="${TARGET_ROOT:-/opt/$target}"
cc="${CC:-$target-gcc}"
objdump="${OBJDUMP:-$target-objdump}"
nm="${NM:-$target-nm}"

mkdir -p "$output"
output="$(cd "$output" && pwd)"

for tool in "$cc" "$objdump" "$nm"; do
  command -v "$tool" >/dev/null
done
for file in \
    "$cygwin/crt0.o" \
    "$cygwin/libmsys-2.0.a" \
    "$cygwin/new-msys-2.0.dll" \
    "$target_root/lib/default-manifest.o"; do
  test -s "$file"
done

common=(
  -std=gnu11
  -D__MSYS__
  -O0
  -g
  -Wall
  -Wextra
  -Werror
  -I"$repo_root/.github/checks"
  -L"$cygwin"
  -L"$target_root/lib"
  -L"$target_root/usr/lib"
)

for module in 1 2; do
  "$cc" \
    "${common[@]}" \
    -DUNLOAD_PROBE_MODULE="$module" \
    -shared \
    "$repo_root/.github/checks/aarch64-dll-unload-probe.c" \
    -o "$output/aarch64-dll-unload-probe-$(
      test "$module" -eq 1 && printf one || printf two
    ).dll"
done

"$cc" \
  "${common[@]}" \
  -shared \
  "$repo_root/.github/checks/aarch64-dll-unload-minimal.c" \
  -o "$output/aarch64-dll-unload-minimal.dll"

"$cc" \
  "${common[@]}" \
  -shared \
  -Wl,-e,0 \
  "$repo_root/.github/checks/aarch64-dll-unload-minimal.c" \
  -o "$output/aarch64-dll-unload-data.dll"

"$cc" \
  "${common[@]}" \
  -nostdlib \
  -Wl,--no-insert-timestamp \
  -Wl,--subsystem,console \
  -Wl,-e,mainCRTStartup \
  "$repo_root/.github/checks/aarch64-dll-unload-native.c" \
  "$target_root/lib/default-manifest.o" \
  -lkernel32 \
  -o "$output/aarch64-dll-unload-native.exe"

gccdir="$(dirname "$("$cc" -print-file-name=libgcc.a)")"
"$cc" \
  "${common[@]}" \
  -c "$repo_root/.github/checks/aarch64-dll-unload-dlopen.c" \
  -o "$output/aarch64-dll-unload-dlopen.o"
"$cc" \
  -nostdlib \
  -Wl,--no-insert-timestamp \
  -Wl,--subsystem,console \
  -Wl,-e,mainCRTStartup \
  -o "$output/aarch64-dll-unload-dlopen.exe" \
  "$cygwin/crt0.o" \
  "$gccdir/crtbegin.o" \
  "$output/aarch64-dll-unload-dlopen.o" \
  -L"$cygwin" \
  -L"$target_root/lib" \
  -L"$target_root/usr/lib" \
  -Wl,--start-group \
  -lmsys-2.0 \
  -lgcc \
  -Wl,--end-group \
  "$gccdir/crtend.o" \
  "$target_root/lib/default-manifest.o" \
  -lkernel32 \
  -lntdll

for image in "$output"/*.dll "$output"/*.exe; do
  name="$(basename "$image")"
  "$objdump" -f -h -p "$image" > "$output/$name.txt"
  "$nm" -a "$image" > "$output/$name.symbols.txt"
  grep -Fq 'file format pei-aarch64-little' "$output/$name.txt"
  if grep -Eiq 'pei-x86-64|i386:x86-64' "$output/$name.txt"; then
    echo "$name is not a native AArch64 image" >&2
    exit 1
  fi
done

native="$output/aarch64-dll-unload-native.exe.txt"
grep -Fq 'DLL Name: KERNEL32.dll' "$native"
if grep -Eiq 'msys-2\.0\.dll|cygwin1\.dll' "$native"; then
  echo "native unload loader imported a POSIX runtime" >&2
  exit 1
fi

for name in \
    aarch64-dll-unload-minimal.dll \
    aarch64-dll-unload-probe-one.dll \
    aarch64-dll-unload-probe-two.dll \
    aarch64-dll-unload-dlopen.exe; do
  grep -Fq 'DLL Name: msys-2.0.dll' "$output/$name.txt"
done

entry="$(
  awk '$1 == "AddressOfEntryPoint" { print $2; exit }' \
    "$output/aarch64-dll-unload-data.dll.txt"
)"
test "$((0x$entry))" -eq 0

sha256sum \
  "$output"/*.dll \
  "$output"/*.exe \
  > "$output/SHA256SUMS"
