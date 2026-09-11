#!/bin/bash
set -euo pipefail
if [[ $# != 3 && $# != 4 ]]; then
    echo "usage: $0 SOURCE PRIVATE_TOOLCHAIN_PREFIX NEW_BUILD_ROOT [QUALIFIED_NEWLIB_BUILD]" >&2
    exit 2
fi
source_dir=$(realpath "$1")
prefix=$(realpath "$2")
root=$(realpath -m "$3")
[[ ! -e $root ]] || { echo "Use a new build root: $root" >&2; exit 1; }
: "${SOURCE_DATE_EPOCH:?Set a fixed source timestamp}"
: "${MSYS2_RUNTIME_COMMIT:?Set the source commit}"
: "${UNAME_DEV_VERSION:?Set the exported source description}"
export LC_ALL=C TZ=UTC USER=builder HOSTNAME=reproducible-build
mkdir -p "$root"
if [[ $# == 4 ]]; then
    newlib=$(realpath "$4")
    (cd "$newlib" && sha256sum libc.a libm.a targ-include/newlib.h) \
        > "$root/reused-newlib.sha256"
    (cd "$source_dir/winsup" && sh autogen.sh) > "$root/prepare.log" 2>&1
else
    bash "$source_dir/winsup/build-arm64.sh" prepare "$source_dir" "$root/a" "$prefix" \
        > "$root/prepare.log" 2>&1
fi
for name in a b; do
    build=$root/$name
    export CFLAGS="-g -O2 -ffile-prefix-map=$source_dir=/usr/src/msys2-runtime -ffile-prefix-map=$build=/usr/src/msys2-build -ffile-prefix-map=$prefix=/opt/arm64-msys2-toolchain"
    export CXXFLAGS="$CFLAGS"
    phases=(headers newlib runtime)
    if [[ $# == 4 ]]; then
        mkdir -p "$build"
        cp -a "$newlib" "$build/newlib"
        (cd "$build/newlib" && sha256sum -c "$root/reused-newlib.sha256") \
            > "$root/$name-newlib-check.log"
        phases=(runtime)
    fi
    for phase in "${phases[@]}"; do
        bash "$source_dir/winsup/build-arm64.sh" "$phase" "$source_dir" "$build" "$prefix" \
            > "$root/$name-$phase.log" 2>&1
    done
done
artifacts=(
    newlib/libc.a newlib/libm.a
    winsup/cygwin/tlsoffsets winsup/cygwin/sigfe.s winsup/cygwin/sigfe.o
    winsup/cygwin/libdll.a winsup/cygwin/new-msys-2.0.dll
    winsup/cygwin/libmsys-2.0.a
)
cd "$root"
: > SHA256SUMS
for artifact in "${artifacts[@]}"; do
    if ! cmp -s "a/$artifact" "b/$artifact"; then
        echo "Non-reproducible artifact: $artifact" >&2
        exit 1
    fi
    sha256sum "a/$artifact" "b/$artifact" >> SHA256SUMS
done
echo "Two independent clean builds match byte-for-byte for ${#artifacts[@]} artifacts."
