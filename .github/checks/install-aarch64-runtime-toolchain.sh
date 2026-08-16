#!/usr/bin/env bash

set -euo pipefail

if test "$#" -gt 1; then
  echo "usage: $0 [DOWNLOAD-DIRECTORY]" >&2
  exit 2
fi

download_dir="${1:-aarch64-runtime-packages}"
mkdir -p "$download_dir"
cd "$download_dir"

probe_release="https://github.com/crutkas/msys2-runtime/releases/download/aarch64-linker-probe-toolchain-20260814"
package_release="https://github.com/crutkas/MSYS2-packages/releases/download"
static_release="$package_release/cygwinarm64-gcc-static-runtime-20260815"
sysroot_release="$package_release/cygwinarm64-sysroot-pr3-20260813"
w32api_release="$package_release/cygwinarm64-w32api-20260813"
libstdcxx_release="$package_release/cygwinarm64-libstdcxx-headers-pr7-20260815"

download()
{
  curl --fail --location --retry 3 \
    --remote-name "$1/$2"
}

binutils=mingw-w64-cross-cygwinarm64-binutils-2.44.50-1-x86_64.pkg.tar.zst
headers=mingw-w64-cross-cygwinarm64-headers-3.6.10.r0.gee50e0223-1-x86_64.pkg.tar.zst
manifest=mingw-w64-cross-cygwinarm64-windows-default-manifest-3.6.10.r0.gee50e0223-1-x86_64.pkg.tar.zst
w32api=mingw-w64-cross-cygwinarm64-w32api-runtime-14.0.0.r0.g9b3dd0125-1-x86_64.pkg.tar.zst
sysroot=mingw-w64-cross-cygwinarm64-sysroot-3.6.10.r0.gee50e0223-1-x86_64.pkg.tar.zst
gcc_stage0=mingw-w64-cross-cygwinarm64-gcc-stage1-15.0.1dev-1-x86_64.pkg.tar.zst
libstdcxx=mingw-w64-cross-cygwinarm64-libstdc++-headers-15.0.1dev-1-x86_64.pkg.tar.zst
gcc_libs=mingw-w64-cross-cygwinarm64-gcc-libs-stage1-15.0.1dev-2-x86_64.pkg.tar.zst
gcc=mingw-w64-cross-cygwinarm64-gcc-stage1-15.0.1dev-2-x86_64.pkg.tar.zst

download "$static_release" "$binutils"
download "$sysroot_release" "$headers"
download "$sysroot_release" "$manifest"
download "$w32api_release" "$w32api"
download "$sysroot_release" "$sysroot"
download "$probe_release" "$gcc_stage0"
download "$libstdcxx_release" "$libstdcxx"
download "$static_release" "$gcc_libs"
download "$static_release" "$gcc"

printf '%s\n' \
  "8908cb690952788153b60bc4fb659826bbd8a03a26c1073f76c0be7ed6f97518  $binutils" \
  "5266346cc10b142f871704ce4277699b1a5daa3121dc869990b4bedce69c0611  $headers" \
  "cc089511fede6042a25f83fcb5903fddeede89ddd9655360741513ee9015e3dc  $manifest" \
  "53478f9a60e2fdad7d3b4357fa4fb937a1afab16af16a55e5a25ae9fac308fa7  $w32api" \
  "4ed8a30f592317bf7e4def6f3c773139f2565b0f8afaedd820f7ee46d33cad20  $sysroot" \
  "f6260f3190fd602a5311c0c4cc47381405e96d9d049a679589f0b5c7be25fffe  $gcc_stage0" \
  "1e018d384e5e16b76524b69677819b660e6611480a85a7f7b8a412403bf15ea6  $libstdcxx" \
  "17a8fbc22227c541ff3179179d307045302f6b18fbc6207cf9d863a9e4dad98c  $gcc_libs" \
  "063579211851ed69370a6362f2795e39d9be0235a2bfe2f58da1bbd73a1d108e  $gcc" \
  > SHA256SUMS
sha256sum --check SHA256SUMS

pacman --noconfirm -U "$binutils"
pacman --noconfirm -U "$headers"
pacman --noconfirm -U "$manifest"
pacman --noconfirm -U "$w32api"
pacman --noconfirm -U "$sysroot"
pacman --noconfirm -U "$gcc_stage0"
pacman --noconfirm -U "$libstdcxx"
pacman --noconfirm -U "$gcc_libs" "$gcc"
