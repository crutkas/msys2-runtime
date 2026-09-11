#!/bin/bash
set -euo pipefail
export LC_ALL=C

if [[ $# != 4 ]]; then
    echo "usage: $0 {prepare|headers|newlib|runtime|install|utilities|cygpath} SOURCE BUILD_ROOT TOOLCHAIN_PREFIX" >&2
    exit 2
fi
phase=$1
source_dir=$(realpath "$2")
build_root=$(realpath -m "$3")
prefix=$(realpath "$4")
target=aarch64-pc-cygwin
jobs=${JOBS:-2}
build_cflags=${CFLAGS:--g -O2}
build_cxxflags=${CXXFLAGS:-$build_cflags}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be positive' >&2; exit 2; }
export PATH="$prefix/bin:$PATH"
: "${SOURCE_DATE_EPOCH:?Set SOURCE_DATE_EPOCH to a fixed source timestamp}"
: "${MSYS2_RUNTIME_COMMIT:?Set MSYS2_RUNTIME_COMMIT to the source base commit}"
: "${UNAME_DEV_VERSION:?Set UNAME_DEV_VERSION to the exported source description}"
mkdir -p "$build_root/newlib" "$build_root/winsup"
if [[ $phase != prepare ]]; then
    export CC="$prefix/bin/$target-gcc"
    export CXX="$prefix/bin/$target-g++"
    [[ $("$CC" -dumpmachine) == "$target" ]] || {
        echo "A working $target compiler is required; host fallback is forbidden" >&2
        exit 1
    }
    [[ $("$CXX" -dumpmachine) == "$target" ]] || {
        echo "A working $target C++ compiler is required" >&2
        exit 1
    }
    macros=$("$CC" -dM -E -x c /dev/null)
    for definition in '__aarch64__ 1' '__CYGWIN__ 1' '__SIZEOF_LONG__ 8' \
        '__SIZEOF_POINTER__ 8' '__LDBL_MANT_DIG__ 53'; do
        grep -qx "#define $definition" <<< "$macros" || {
            echo "Target ABI mismatch: $definition" >&2
            exit 1
        }
    done
    printf '%s\n' '_Static_assert(sizeof(__builtin_va_list) == 8, "Windows ARM64 va_list must be a pointer");' |
        "$CC" -x c -fsyntax-only -
    printf '%s\n' 'static_assert(sizeof(__builtin_va_list) == 8, "Windows ARM64 C++ va_list must be a pointer");' |
        "$CXX" -x c++ -fsyntax-only -
fi

case $phase in
prepare)
    (cd "$source_dir/newlib" &&
        AUTOCONF=autoconf2.69 AUTOHEADER=autoheader2.69 AUTOM4TE=autom4te2.69 autoreconf -fi)
    (cd "$source_dir/winsup" && sh autogen.sh)
    ;;
headers)
    cd "$build_root/newlib"
    "$source_dir/newlib/configure" \
        --build="$("$source_dir/config.guess")" --host="$target" --target="$target" \
        --prefix="$prefix" --disable-multilib \
        --enable-newlib-mb --enable-newlib-multithread \
        CFLAGS="$build_cflags -D__MSYS__"
    make -j"$jobs" stmp-targ-include
    grep -q '^#define _LDBL_EQ_DBL 1$' targ-include/newlib.h || {
        echo "Generated headers do not describe the Windows ARM64 long-double ABI" >&2
        exit 1
    }
    # Install bootstrap headers without requiring libc, libgcc or a DLL yet.
    mkdir -p "$prefix/$target/include"
    cp -R "$source_dir/newlib/libc/include/." "$prefix/$target/include/"
    cp -R targ-include/. "$prefix/$target/include/"
    cp -R "$source_dir/winsup/cygwin/include/." "$prefix/$target/include/"
    ;;
newlib)
    make -C "$build_root/newlib" -j"$jobs" all
    ;;
runtime|cygpath)
    cd "$build_root/winsup"
    "$source_dir/winsup/configure" \
        --build="$("$source_dir/config.guess")" --host="$target" --target="$target" \
        --prefix="$prefix" --with-cross-bootstrap --disable-doc --disable-dumper \
        --with-msys2-runtime-commit="$MSYS2_RUNTIME_COMMIT" \
        CFLAGS="$build_cflags" CXXFLAGS="$build_cxxflags"
    if [[ $phase == runtime ]]; then
        make -C cygwin -j"$jobs" all
    else
        # Use an already qualified runtime/SDK; do not rebuild or install it.
        # AC_NO_EXECUTABLES leaves EXEEXT empty in this cross configuration.
        make -C utils -j"$jobs" EXEEXT=.exe \
            CC="$prefix/bin/msys2-gcc" CXX="$prefix/bin/msys2-g++" \
            LDFLAGS=-Wl,--no-insert-timestamp cygpath.exe
        make -C utils EXEEXT=.exe bin_PROGRAMS=cygpath.exe \
            program_transform_name= install-binPROGRAMS
    fi
    ;;
install)
    make -C "$build_root/winsup/cygwin" \
        EXPECTED_TOOL_ROOT="$prefix/$target" check-install-layout
    make -C "$build_root/newlib" -j"$jobs" install
    make -C "$build_root/winsup/cygwin" -j"$jobs" install
    ;;
utilities)
    for directory in cygserver utils; do
        make -C "$build_root/winsup/$directory" -j"$jobs" \
            CC="$prefix/bin/msys2-gcc" CXX="$prefix/bin/msys2-g++" all
        make -C "$build_root/winsup/$directory" -j"$jobs" \
            CC="$prefix/bin/msys2-gcc" CXX="$prefix/bin/msys2-g++" install
    done
    ;;
*)
    echo "Unknown phase: $phase" >&2
    exit 2
    ;;
esac
