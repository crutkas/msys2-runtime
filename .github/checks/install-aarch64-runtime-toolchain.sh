#!/usr/bin/env bash

set -euo pipefail

if test "$#" -gt 1; then
  echo "usage: $0 [TOOLCHAIN-ROOT]" >&2
  exit 2
fi

requested_root="${1:-/}"
root="$(cygpath -u "$requested_root")"
if test "$(cygpath -am /)" != "$(cygpath -am "$root")"; then
  echo "toolchain root must be the root of this private MSYS installation" >&2
  exit 1
fi
root=/
packages="${root%/}/packages"
prefix="${root%/}/opt"
release="https://github.com/crutkas/MSYS2-packages/releases/download"

mkdir -p "$packages" "$prefix"

download()
{
  local tag="$1"
  local file="$2"
  local size="$3"
  local hash="$4"
  local path="$packages/$file"

  if ! test -f "$path"; then
    curl --fail --location --retry 3 --output "$path" "$release/$tag/$file"
  fi
  test "$(wc -c < "$path")" -eq "$size"
  printf '%s  %s\n' "$hash" "$path" | sha256sum --check -
}

binutils=mingw-w64-cross-cygwinarm64-binutils-2.44.50-2-x86_64.pkg.tar.zst
gcc=mingw-w64-cross-msysarm64-gcc-15.0.1dev-1-x86_64.pkg.tar.zst
gcc_libs=mingw-w64-cross-msysarm64-gcc-libs-15.0.1dev-1-x86_64.pkg.tar.zst
libstdcxx=mingw-w64-cross-msysarm64-libstdc++-headers-15.0.1dev-1-x86_64.pkg.tar.zst
w32api=mingw-w64-cross-msysarm64-w32api-runtime-14.0.0.r0.g9b3dd0125-1-x86_64.pkg.tar.zst
headers=mingw-w64-cross-msysarm64-headers-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
manifest=mingw-w64-cross-msysarm64-windows-default-manifest-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
sysroot=mingw-w64-cross-msysarm64-sysroot-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
runtime=mingw-w64-cross-msysarm64-runtime-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
runtime_devel=mingw-w64-cross-msysarm64-runtime-devel-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst

download cygwinarm64-binutils-pr21-3356eec-20260827 "$binutils" 6545114 \
  3c7b47529181dab726d22cf6ed045184260af915eea583488c13c07e478ac02b
download msysarm64-gcc-pr13-20260826 "$gcc" 83876291 \
  a74887c76a933ec424933bf662729d94975b83138af783bd93f2e7acd95c3a22
download msysarm64-gcc-pr13-20260826 "$gcc_libs" 4963824 \
  990f163cacf9ffce1b58445be91fedc57f135cc26a88d7dba109806446b41438
download msysarm64-gcc-pr13-support-20260826 "$libstdcxx" 1520166 \
  9715aab6894379bf5ab936a3a559f286fb4aedbb64f0774d7457182e00648e08
download msysarm64-gcc-pr13-support-20260826 "$w32api" 2349635 \
  7727936f4212e5af04e9739eca60f157c0875796c1e82fcfb79fd4398b111e24
download msysarm64-runtime-pr10-a527-20260824 "$headers" 9319013 \
  263f8f7e3614ac41337ce3a223f2bb26b6459aef6f34670525cdd4c03ec3ae21
download msysarm64-runtime-pr10-a527-20260824 "$manifest" 4743 \
  33861708e7f981b4eef5b93ef135ab3a43d2757533f64df6f61a146d823c355f
download msysarm64-runtime-pr10-a527-20260824 "$sysroot" 86822 \
  e30609e09eab2fa07aba2e6196b05f34e5e9107abc4ab8832966684758c743ca
download msysarm64-runtime-pr10-a527-20260824 "$runtime" 9893043 \
  158c505f45025a466950faa7c85c9fd85e9d32384dd27b53586ffc75d71ca78e
download msysarm64-runtime-pr10-a527-20260824 "$runtime_devel" 4426157 \
  c18b51e483991770b8e06cc2d8f7002d06784d3071ac213a8fee24bb831267d1

export MSYS="${MSYS:+$MSYS }winsymlinks:sys"
for package in \
  "$binutils" "$gcc" "$gcc_libs" "$libstdcxx" "$w32api" \
  "$headers" "$manifest" "$sysroot" "$runtime" "$runtime_devel"
do
  /usr/bin/tar.exe -xf "$packages/$package" -C "$root"
done

mkdir -p "$prefix/aarch64-pc-msys/bin"
for tool in ar nm ranlib
do
  rm -f "$prefix/aarch64-pc-msys/bin/$tool.exe"
  ln "$prefix/aarch64-pc-cygwin/bin/$tool.exe" \
    "$prefix/aarch64-pc-msys/bin/$tool.exe"
done

# The source tree still uses the historical aarch64-pc-cygwin build triplet.
# Keep that configure surface while making every compiler invocation execute
# the exact aarch64-pc-msys GCC above.
for tool in gcc g++ c++ cpp
do
  cat > "$prefix/bin/aarch64-pc-cygwin-$tool" <<EOF
#!/usr/bin/env bash
exec "/opt/bin/aarch64-pc-msys-$tool.exe" "\$@"
EOF
  chmod +x "$prefix/bin/aarch64-pc-cygwin-$tool"
done

for tool in gcc-ar gcc-nm gcc-ranlib
do
  cat > "$prefix/bin/aarch64-pc-cygwin-$tool" <<EOF
#!/usr/bin/env bash
exec "/opt/bin/aarch64-pc-msys-$tool.exe" "\$@"
EOF
  chmod +x "$prefix/bin/aarch64-pc-cygwin-$tool"
done

for alias in \
  "$prefix/bin/aarch64-pc-msys-gcc.exe" \
  "$prefix/bin/aarch64-pc-msys-g++.exe" \
  "$prefix/bin/aarch64-pc-cygwin-as.exe" \
  "$prefix/bin/aarch64-pc-cygwin-ld.exe"
do
  ls -li "$alias"
  if test -L "$alias"; then
    readlink "$alias"
  fi
  test -x "$alias"
done

compiler="$prefix/bin/aarch64-pc-msys-gcc.exe"
test "$("$compiler" -dumpmachine)" = aarch64-pc-msys
ld_program="$("$compiler" -print-prog-name=ld)"
case "$ld_program" in
  /opt/bin/aarch64-pc-cygwin-ld|/opt/bin/aarch64-pc-cygwin-ld.exe) ;;
  *)
    echo "unexpected linker program: $ld_program" >&2
    exit 1
    ;;
esac
test -e "$ld_program" || ld_program="$ld_program.exe"
test -x "$ld_program"
printf '%s  %s\n' \
  075ed377a430eb120a994dfdc7c3187e937331239204578d696f08ee1c72fb1f \
  "$ld_program" | sha256sum --check -
"$compiler" -print-search-dirs

printf 'void arm64_toolchain_probe (void) {}\n' \
  | "$prefix/bin/aarch64-pc-cygwin-gcc" -x c -c -o "${root%/}/probe.o" -
"$prefix/bin/aarch64-pc-cygwin-objdump.exe" -f "${root%/}/probe.o" \
  | grep -Fq 'file format pe-aarch64-little'
"$prefix/bin/aarch64-pc-cygwin-gcc" -v -nostdlib \
  -Wl,-e,arm64_toolchain_probe "${root%/}/probe.o" -o "${root%/}/probe.exe"
"$prefix/bin/aarch64-pc-cygwin-objdump.exe" -f "${root%/}/probe.exe" \
  | grep -Fq 'file format pei-aarch64-little'
rm "${root%/}/probe.o" "${root%/}/probe.exe"

if test -n "${GITHUB_ENV:-}"; then
  {
    printf 'TOOLCHAIN_DIR=%s\n' "$prefix"
    printf 'TARGET_ROOT=%s\n' "$prefix/aarch64-pc-msys"
  } >> "$GITHUB_ENV"
fi
if test -n "${GITHUB_PATH:-}"; then
  cygpath -aw "$prefix/bin" >> "$GITHUB_PATH"
fi
