set -x
export PATH=/root/xc/inst/bin:\
rm -rf /root/xc/build-libstdcxx
mkdir -p /root/xc/build-libstdcxx
cd /root/xc/build-libstdcxx
/root/xc/gcc-src/libstdc++-v3/configure \
  --host=aarch64-pc-cygwin --build=aarch64-unknown-linux-gnu \
  --prefix=/root/xc/inst \
  --disable-hosted-libstdcxx --disable-shared --disable-nls \
  --disable-libstdcxx-verbose --disable-multilib \
  --with-newlib \
  > cfg.log 2>&1
echo \
