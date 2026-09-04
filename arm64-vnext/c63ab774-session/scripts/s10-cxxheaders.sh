#!/bin/bash
# Provide the FREESTANDING C++ headers that winsup/cygwin needs (<new> only, plus its
# three dependencies bits/c++config.h, bits/exception.h, bits/version.h).
#
# NOTE: installs to /root/xc/sysroot-cxx  -- it does NOT touch /root/xc/inst.
# Reproduces the c++config.h generation rule from libstdc++-v3/include/Makefile.am.
set -e
GSRC=/root/xc/gcc-src
LSRC=$GSRC/libstdc++-v3
OUT=/root/xc/sysroot-cxx/include/c++/15.0.1
rm -rf /root/xc/sysroot-cxx
mkdir -p $OUT/bits

date=$(cat $GSRC/gcc/DATESTAMP)
release=$(sed 's/^\([0-9]*\).*$/\1/' $GSRC/gcc/BASE-VER)

# --- minimal CONFIG_HEADER standing in for the configure-generated config.h ---
cat > /tmp/cxxcfg_config.h <<'CFGEOF'
/* minimal freestanding-ish config for header-only use on aarch64-pc-cygwin */
#define _GLIBCXX_HOSTED 1
#define _GLIBCXX_VERBOSE 1
#define _GLIBCXX_USE_DEPRECATED 1
#define _GLIBCXX_USE_C99_STDINT 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define STDC_HEADERS 1
CFGEOF

sed -e "s,define __GLIBCXX__,define __GLIBCXX__ $date," \
    -e "s,define _GLIBCXX_RELEASE,define _GLIBCXX_RELEASE $release," \
    -e "s,define _GLIBCXX_INLINE_VERSION, define _GLIBCXX_INLINE_VERSION 0," \
    -e "s,define _GLIBCXX_HAVE_ATTRIBUTE_VISIBILITY, define _GLIBCXX_HAVE_ATTRIBUTE_VISIBILITY 1," \
    -e "s,define _GLIBCXX_EXTERN_TEMPLATE$, define _GLIBCXX_EXTERN_TEMPLATE 1," \
    -e "s,define _GLIBCXX_USE_DUAL_ABI, define _GLIBCXX_USE_DUAL_ABI 1," \
    -e "s,define _GLIBCXX_USE_CXX11_ABI, define _GLIBCXX_USE_CXX11_ABI 1," \
    -e "s,define _GLIBCXX_USE_ALLOCATOR_NEW, define _GLIBCXX_USE_ALLOCATOR_NEW 1," \
    < $LSRC/include/bits/c++config > $OUT/bits/c++config.h

sed -e 's/HAVE_/_GLIBCXX_HAVE_/g' \
    -e 's/PACKAGE/_GLIBCXX_PACKAGE/g' \
    -e 's/VERSION/_GLIBCXX_VERSION/g' \
    -e 's/WORDS_/_GLIBCXX_WORDS_/g' \
    -e 's/STDC_HEADERS/_GLIBCXX_STDC_HEADERS/g' \
    < /tmp/cxxcfg_config.h >> $OUT/bits/c++config.h
echo "" >> $OUT/bits/c++config.h
echo "#endif // _GLIBCXX_CXX_CONFIG_H" >> $OUT/bits/c++config.h

# --- host/cpu define headers (configure.host: cygwin* -> os/newlib; aarch64 has no
#     cpu_defines.h so the generic one applies) ---
cp $LSRC/config/os/newlib/os_defines.h $OUT/bits/os_defines.h
if [ -f $LSRC/config/cpu/aarch64/cpu_defines.h ]; then
  cp $LSRC/config/cpu/aarch64/cpu_defines.h $OUT/bits/cpu_defines.h
else
  cp $LSRC/config/cpu/generic/cpu_defines.h $OUT/bits/cpu_defines.h
fi
for h in atomic_word.h; do
  if [ -f $LSRC/config/cpu/aarch64/$h ]; then cp $LSRC/config/cpu/aarch64/$h $OUT/bits/$h
  elif [ -f $LSRC/config/cpu/generic/$h ]; then cp $LSRC/config/cpu/generic/$h $OUT/bits/$h; fi
done

# --- the three headers <new> actually pulls in ---
cp $LSRC/libsupc++/new           $OUT/new
cp $LSRC/libsupc++/exception.h   $OUT/bits/exception.h
cp $LSRC/include/bits/version.h  $OUT/bits/version.h
# useful neighbours, same freestanding tier
cp $LSRC/libsupc++/exception     $OUT/exception
cp $LSRC/libsupc++/typeinfo      $OUT/typeinfo
cp $LSRC/libsupc++/initializer_list $OUT/initializer_list 2>/dev/null || true

echo "=== installed ==="
find $OUT -type f | sort
echo
echo "=== compile probe: #include <new> ==="
export PATH=/root/xc/inst/bin:$PATH
cat > /tmp/probe_new.cc <<'PEOF'
#include <new>
void *operator new(std::size_t s) noexcept(false);
std::nothrow_t const *p = &std::nothrow;
static_assert(sizeof(void *) == 8, "LP64 expected");
int probe_ok;
PEOF
aarch64-pc-cygwin-g++ -c -fno-rtti -fno-exceptions \
  -isystem $OUT \
  -isystem /root/xc/inst/aarch64-pc-cygwin/include/w32api \
  /tmp/probe_new.cc -o /tmp/probe_new.o 2>&1 | head -30
echo "PROBE EXIT ${PIPESTATUS[0]}"
ls -la /tmp/probe_new.o 2>/dev/null && aarch64-pc-cygwin-objdump -f /tmp/probe_new.o | head -5
