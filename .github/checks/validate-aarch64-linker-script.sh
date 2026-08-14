#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
template="$repo_root/winsup/cygwin/cygwin.sc.in"
base_commit="${LINKER_SCRIPT_BASE_COMMIT:-15f88e802f2a2b6b08378f05c51d5efc31302987}"
cc="${CC:-aarch64-pc-cygwin-gcc}"
ar="${AR:-aarch64-pc-cygwin-ar}"
nm="${NM:-aarch64-pc-cygwin-nm}"
objdump="${OBJDUMP:-aarch64-pc-cygwin-objdump}"
host_cc="${HOST_CC:-gcc}"
sysroot="${AARCH64_SYSROOT:-$("$cc" -print-sysroot)}"

if test "$#" -gt 1; then
  echo "usage: $0 [work-directory]" >&2
  exit 2
fi

if test "$#" -eq 1; then
  work="$1"
  mkdir -p "$work"
else
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
fi

for tool in "$cc" "$ar" "$nm" "$objdump" "$host_cc"; do
  command -v "$tool" >/dev/null
done
test -d "$sysroot"
git cat-file -e "$base_commit:winsup/cygwin/cygwin.sc.in"

git show "$base_commit:winsup/cygwin/cygwin.sc.in" \
  > "$work/base.sc.in"

preprocess()
{
  compiler="$1"
  output="$2"
  input="$3"
  shift 3
  "$compiler" "$@" -E -P -x c "$input" -o "$output"
}

preprocess "$cc" "$work/aarch64-cygwin.sc" "$template"
preprocess "$cc" "$work/aarch64-cygwin-second.sc" "$template"
preprocess "$cc" "$work/aarch64-msys.sc" "$template" \
  -D__MSYS__ -U__CYGWIN__
cmp "$work/aarch64-cygwin.sc" "$work/aarch64-cygwin-second.sc"
cmp "$work/aarch64-cygwin.sc" "$work/aarch64-msys.sc"

for runtime in cygwin msys; do
  runtime_flag=-U__MSYS__
  if test "$runtime" = msys; then
    runtime_flag=-D__MSYS__
  fi
  preprocess "$host_cc" "$work/x86_64-$runtime-base.sc" \
    "$work/base.sc.in" -D__x86_64__ -U__aarch64__ "$runtime_flag"
  preprocess "$host_cc" "$work/x86_64-$runtime-current.sc" \
    "$template" -D__x86_64__ -U__aarch64__ "$runtime_flag"
  sed -E \
    's#^SEARCH_DIR\("/usr/x86_64-pc-(cygwin|msys)/lib/w32api"\); SEARCH_DIR\("=/usr/lib/w32api"\);$#SEARCH_DIR("=/usr/lib/w32api")#' \
    "$work/x86_64-$runtime-base.sc" \
    > "$work/x86_64-$runtime-base.canonical.sc"
  cmp \
    "$work/x86_64-$runtime-base.canonical.sc" \
    "$work/x86_64-$runtime-current.sc"
  test "$(
    grep -Fxc 'SEARCH_DIR("=/usr/lib/w32api")' \
      "$work/x86_64-$runtime-current.sc"
  )" -eq 1
  if grep -Fq '/usr/x86_64-' "$work/x86_64-$runtime-current.sc"; then
    echo "x86_64 linker script retained a host-absolute target path" >&2
    exit 1
  fi
done

aarch64_script="$work/aarch64-cygwin.sc"
test "$(grep -Fxc 'OUTPUT_FORMAT(pei-aarch64-little)' "$aarch64_script")" -eq 1
test "$(grep -Fxc 'SEARCH_DIR("=/usr/lib/w32api")' "$aarch64_script")" -eq 1
grep -Fq 'LONG (-1); LONG (-1)' "$aarch64_script"
grep -Fq '.text __image_base__ + __section_alignment__' "$aarch64_script"
grep -Fq '.pdata ALIGN(__section_alignment__)' "$aarch64_script"
grep -Fq '.xdata ALIGN(__section_alignment__)' "$aarch64_script"
if grep -Eiq 'x86|mingw' "$aarch64_script"; then
  echo "AArch64 linker script contains a foreign target search path" >&2
  exit 1
fi

awk '
  /LONG \(0\); LONG \(0\); LONG \(0\); LONG \(0\); LONG \(0\);/ {
    in_imports = 1
  }
  in_imports && /\. = ALIGN\(8\);/ { aligned = 1 }
  in_imports && /\.idata\$4/ {
    saw_selector = 1
    exit aligned ? 0 : 1
  }
  END {
    if (!in_imports || !aligned || !saw_selector)
      exit 1
  }
' "$aarch64_script"

previous=0
for section in \
    .text \
    .autoload_text \
    .data \
    .rdata \
    .eh_frame \
    .pdata \
    .xdata \
    .bss \
    .edata \
    .reloc \
    .cygwin_dll_common \
    .idata \
    .rsrc; do
  line="$(grep -n -m1 -F "  $section " "$aarch64_script" | cut -d: -f1)"
  test -n "$line"
  test "$line" -gt "$previous"
  previous="$line"
done
grep -Fq '  /DISCARD/ :' "$aarch64_script"
grep -Fq '    *(.drectve)' "$aarch64_script"

if test -n "${CONFIGURED_LINKER_SCRIPT:-}"; then
  cmp "$aarch64_script" "$CONFIGURED_LINKER_SCRIPT"
fi

search_dirs="$("$cc" --sysroot="$sysroot" -print-search-dirs)"
printf '%s\n' "$search_dirs" > "$work/aarch64-search-dirs.txt"
printf '%s\n' "$search_dirs" | grep -Fq "$sysroot"
if printf '%s\n' "$search_dirs" \
    | grep -Eiq 'x86_64-pc|x86_64-w64|mingw(32|64)|aarch64-w64-mingw32'; then
  echo "AArch64 compiler search paths contain a foreign target" >&2
  exit 1
fi

libdir=
for candidate in "$sysroot/usr/lib/w32api" "$sysroot/usr/lib"; do
  if test -f "$candidate/libkernel32.a" \
      && test -f "$candidate/libntdll.a"; then
    libdir="$candidate"
    break
  fi
done
test -n "$libdir"

manifest=
for candidate in \
    "$sysroot/lib/default-manifest.o" \
    "$sysroot/usr/lib/default-manifest.o"; do
  if test -f "$candidate"; then
    manifest="$candidate"
    break
  fi
done
test -n "$manifest"

"$cc" \
  --sysroot="$sysroot" \
  -O2 \
  -g \
  -ffreestanding \
  -fno-stack-protector \
  -ffunction-sections \
  -fdata-sections \
  -c "$repo_root/.github/checks/aarch64-linker-script.c" \
  -o "$work/aarch64-linker-script.o"

"$objdump" -f -h -r "$work/aarch64-linker-script.o" \
  > "$work/aarch64-linker-script-object.txt"
grep -Fq 'file format pe-aarch64-little' \
  "$work/aarch64-linker-script-object.txt"
for section in .text .data .bss .rdata .pdata .xdata .tls .ctors .dtors; do
  section_pattern="\\$section"
  grep -Eq "[[:space:]]${section_pattern}"'([$]|[[:space:]])' \
    "$work/aarch64-linker-script-object.txt"
done

link_probe()
{
  output="$1"
  trace="$2"
  map="$3"
  implib="$4"
  "$cc" \
    --sysroot="$sysroot" \
    -nostdlib \
    -shared \
    -Wl,--gc-sections \
    -Wl,--no-insert-timestamp \
    -Wl,--image-base,0x180000000 \
    -Wl,-T,"$aarch64_script" \
    -Wl,-Map,"$map" \
    -Wl,--out-implib,"$implib" \
    -Wl,--trace \
    -Wl,-e,probe_entry \
    "$repo_root/.github/checks/aarch64-linker-script.def" \
    "$work/aarch64-linker-script.o" \
    "$manifest" \
    -lkernel32 \
    -lntdll \
    -o "$output" \
    > "$trace" 2>&1
}

link_probe \
  "$work/aarch64-linker-probe.dll" \
  "$work/aarch64-linker-probe.trace" \
  "$work/aarch64-linker-probe.map" \
  "$work/aarch64-linker-probe.dll.a"
cp "$work/aarch64-linker-probe.dll" \
  "$work/aarch64-linker-probe-first.dll"
link_probe \
  "$work/aarch64-linker-probe.dll" \
  "$work/aarch64-linker-probe-second.trace" \
  "$work/aarch64-linker-probe-second.map" \
  "$work/aarch64-linker-probe-second.dll.a"
cmp \
  "$work/aarch64-linker-probe-first.dll" \
  "$work/aarch64-linker-probe.dll"

for library in libkernel32.a libntdll.a; do
  grep -Fq "$libdir/$library" "$work/aarch64-linker-probe.trace"
done
if grep -Eiq \
    'x86_64-pc|x86_64-w64|mingw(32|64)|aarch64-w64-mingw32|libgcc' \
    "$work/aarch64-linker-probe.trace"; then
  echo "AArch64 link selected a foreign or unavailable runtime library" >&2
  exit 1
fi

"$objdump" -f -h -p "$work/aarch64-linker-probe.dll" \
  > "$work/aarch64-linker-probe.txt"
"$nm" -a "$work/aarch64-linker-probe.dll" \
  > "$work/aarch64-linker-probe.symbols"
"$objdump" -f "$manifest" \
  > "$work/aarch64-default-manifest.txt"

grep -Fq 'file format pei-aarch64-little' \
  "$work/aarch64-linker-probe.txt"
grep -Fq 'architecture: aarch64' "$work/aarch64-linker-probe.txt"
grep -Eq 'Magic[[:space:]]+020b' "$work/aarch64-linker-probe.txt"
grep -Eq 'ImageBase[[:space:]]+0000000180000000' \
  "$work/aarch64-linker-probe.txt"
grep -Eq 'SectionAlignment[[:space:]]+00001000' \
  "$work/aarch64-linker-probe.txt"
grep -Fq 'DLL Name: KERNEL32.dll' "$work/aarch64-linker-probe.txt"
grep -Fq 'DLL Name: ntdll.dll' "$work/aarch64-linker-probe.txt"
grep -Eq '[[:space:]]probe_entry$' "$work/aarch64-linker-probe.txt"
if grep -Eiq 'cygwin1\.dll|msys-2\.0\.dll' \
    "$work/aarch64-linker-probe.txt"; then
  echo "Link probe imported a Cygwin or MSYS runtime" >&2
  exit 1
fi

for section in \
    .text \
    .data \
    .tls \
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
    "$work/aarch64-linker-probe.txt"
done
if grep -Eq '^[[:space:]]*[0-9]+[[:space:]]+\.drectve[[:space:]]' \
    "$work/aarch64-linker-probe.txt"; then
  echo ".drectve escaped the linker script discard list" >&2
  exit 1
fi

for symbol in \
    __CTOR_LIST__ \
    __DTOR_LIST__ \
    __data_start__ \
    __data_end__ \
    __bss_start__ \
    __bss_end__ \
    probe_ctor \
    probe_dtor \
    probe_entry \
    probe_nocopy_data \
    probe_nocopy_rdata \
    probe_tls; do
  grep -Eq "[[:space:]]$symbol$" \
    "$work/aarch64-linker-probe.symbols"
done
if grep -Eq '[[:space:]]U[[:space:]]+probe_' \
    "$work/aarch64-linker-probe.symbols"; then
  echo "A probe section was discarded unexpectedly" >&2
  exit 1
fi

grep -Fq 'file format pe-aarch64-little' \
  "$work/aarch64-default-manifest.txt"
grep -Fq '.ctors' "$work/aarch64-linker-probe.map"
grep -Fq '.dtors' "$work/aarch64-linker-probe.map"
grep -Fq '.drectve' "$work/aarch64-linker-probe.map"
grep -Fq "$manifest" "$work/aarch64-linker-probe.map"

for archive in "$libdir/libkernel32.a" "$libdir/libntdll.a"; do
  archive_name="$(basename "$archive")"
  sed -n "s#.*$archive_name(\\([^)]*\\)).*#\\1#p" \
    "$work/aarch64-linker-probe.map" \
    | sort -u \
    > "$work/$archive_name.members"
  test -s "$work/$archive_name.members"
  while IFS= read -r member; do
    "$ar" p "$archive" "$member" > "$work/$archive_name-$member"
    "$objdump" -f "$work/$archive_name-$member" \
      >> "$work/aarch64-selected-archive-members.txt"
  done < "$work/$archive_name.members"
done

grep -Fq 'file format pe-aarch64-little' \
  "$work/aarch64-selected-archive-members.txt"
if grep -Eiq 'pei-x86-64|i386:x86-64|architecture: i386' \
    "$work/aarch64-selected-archive-members.txt"; then
  echo "An x64 archive member was selected" >&2
  exit 1
fi
