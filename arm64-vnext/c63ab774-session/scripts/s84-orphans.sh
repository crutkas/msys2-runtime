#!/bin/bash
# Survey w-orphans and verify the relayed claims before using anything.
export PATH=/root/xc/inst/bin:$PATH
O=/root/xc/w-orphans
echo "############ contents ############"
ls -la $O 2>&1

echo
echo "############ md5s of the three gendef scripts ############"
for f in /root/xc/w-gendef/gendef $O/gendef $O/gendef2; do
  [ -f "$f" ] && printf '  %-32s %8s B  md5 %s  CRLF=%s\n' \
    "$f" "$(stat -c%s $f)" "$(md5sum $f | cut -d' ' -f1)" "$(grep -c $'\r$' $f)"
done

echo
echo "############ does gendef2 really fail to compile? ############"
[ -f $O/gendef2 ] && perl -c $O/gendef2 2>&1 | head -3

echo
echo "############ does the orphan gendef compile? ############"
[ -f $O/gendef ] && perl -c $O/gendef 2>&1 | head -3

echo
echo "############ is there an arch-conditioned cygwin.din? ############"
find $O -name '*.din' -o -name '*din*' 2>/dev/null | head
for d in $O/cygwin.din $O/*.din; do
  [ -f "$d" ] && printf '  %-36s %6s lines  md5 %s\n' "$d" "$(wc -l < $d)" "$(md5sum $d | cut -d' ' -f1)"
done

echo
echo "############ fenv implementations for aarch64? ############"
find $O -name '*fenv*' -o -name '*except*' 2>/dev/null | head -10
grep -rn 'feenableexcept' $O 2>/dev/null | head -5

echo
echo "############ anything else in /root/xc/w-* ? ############"
ls -d /root/xc/w-* 2>/dev/null
