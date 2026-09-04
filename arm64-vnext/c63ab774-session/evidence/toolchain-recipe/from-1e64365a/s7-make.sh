#!/bin/bash
export PATH=/root/xc/inst/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
BLD=/root/xc/bld
cd $BLD/winsup/cygwin
ulimit -u 4096
# -k so we keep going and can count how much of the runtime actually compiles.
time make -k -j12 V=1 > /root/xc/winsup-build.log 2>&1
echo "MAKE_EXIT=$?"
echo "=================== SUMMARY ==================="
echo "objects (.o) produced: $(find $BLD/winsup/cygwin -name '*.o' | wc -l)"
echo "error lines: $(grep -c 'error:' /root/xc/winsup-build.log)"
echo "files with errors: $(grep -o '^[^ ]*\.\(cc\|c\|h\|S\):' /root/xc/winsup-build.log | sort -u | wc -l)"
echo "=================== FIRST 60 ERROR LINES ==================="
grep -n 'error:\|Error \|No rule to make' /root/xc/winsup-build.log | head -60
