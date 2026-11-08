#!/usr/bin/env bash

set -euo pipefail

if test "$#" -gt 1; then
  echo "usage: $0 [DOWNLOAD-DIRECTORY]" >&2
  exit 2
fi

download_dir="${1:-msysarm64-gcc-packages}"
mkdir -p "$download_dir"
cd "$download_dir"

package_release="https://github.com/crutkas/MSYS2-packages/releases/download"
runtime_release="$package_release/msysarm64-runtime-pr10-a527-20260824"
gcc_release="$package_release/msysarm64-gcc-pr13-20260826"
# This public support repack has the same installed header payload as the
# smoke-run archive; only package metadata and diagnostics differ.
gcc_deps_release="$package_release/msysarm64-gcc-pr13-support-20260826"

download()
{
  curl --fail --location --retry 3 --remote-name "$1/$2"
}

headers=mingw-w64-cross-msysarm64-headers-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
manifest=mingw-w64-cross-msysarm64-windows-default-manifest-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
runtime=mingw-w64-cross-msysarm64-runtime-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
runtime_devel=mingw-w64-cross-msysarm64-runtime-devel-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
sysroot=mingw-w64-cross-msysarm64-sysroot-3.6.10.r0.ga527ace21-1-x86_64.pkg.tar.zst
gcc=mingw-w64-cross-msysarm64-gcc-15.0.1dev-1-x86_64.pkg.tar.zst
gcc_libs=mingw-w64-cross-msysarm64-gcc-libs-15.0.1dev-1-x86_64.pkg.tar.zst
libstdcxx=mingw-w64-cross-msysarm64-libstdc++-headers-15.0.1dev-1-x86_64.pkg.tar.zst
w32api=mingw-w64-cross-msysarm64-w32api-runtime-14.0.0.r0.g9b3dd0125-1-x86_64.pkg.tar.zst

for package in "$headers" "$manifest" "$runtime" "$runtime_devel" "$sysroot"; do
  download "$runtime_release" "$package"
done
for package in "$gcc" "$gcc_libs"; do
  download "$gcc_release" "$package"
done
for package in "$libstdcxx" "$w32api"; do
  download "$gcc_deps_release" "$package"
done

printf '%s\n' \
  "263f8f7e3614ac41337ce3a223f2bb26b6459aef6f34670525cdd4c03ec3ae21  $headers" \
  "33861708e7f981b4eef5b93ef135ab3a43d2757533f64df6f61a146d823c355f  $manifest" \
  "158c505f45025a466950faa7c85c9fd85e9d32384dd27b53586ffc75d71ca78e  $runtime" \
  "c18b51e483991770b8e06cc2d8f7002d06784d3071ac213a8fee24bb831267d1  $runtime_devel" \
  "e30609e09eab2fa07aba2e6196b05f34e5e9107abc4ab8832966684758c743ca  $sysroot" \
  "a74887c76a933ec424933bf662729d94975b83138af783bd93f2e7acd95c3a22  $gcc" \
  "990f163cacf9ffce1b58445be91fedc57f135cc26a88d7dba109806446b41438  $gcc_libs" \
  "9715aab6894379bf5ab936a3a559f286fb4aedbb64f0774d7457182e00648e08  $libstdcxx" \
  "7727936f4212e5af04e9739eca60f157c0875796c1e82fcfb79fd4398b111e24  $w32api" \
  > SHA256SUMS
sha256sum --check SHA256SUMS

pacman --noconfirm -U \
  "$headers" \
  "$manifest" \
  "$runtime" \
  "$runtime_devel" \
  "$sysroot" \
  "$gcc" \
  "$gcc_libs" \
  "$libstdcxx" \
  "$w32api"

# The published GCC uses an MSYS target prefix while the shared PE/COFF
# binutils package uses the Cygwin target prefix.
for tool in ar as dlltool ld nm objcopy objdump ranlib readelf strip windres; do
  source="/opt/bin/aarch64-pc-cygwin-$tool.exe"
  destination="/opt/bin/aarch64-pc-msys-$tool.exe"
  test -x "$source"
  if test ! -e "$destination"; then
    cp "$source" "$destination"
  fi
done
