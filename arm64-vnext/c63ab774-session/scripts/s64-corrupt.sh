#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
echo "############ same object across the three build dirs ############"
for o in devices.o dir.o errno.o fenv.o; do
  echo "---- $o ----"
  for b in /root/xc/bld/winsup/cygwin /root/xc/w-autoload/bld/winsup/cygwin /root/xc/w-link/bld/winsup/cygwin; do
    f=$b/$o
    if [ -f "$f" ]; then
      printf '  %-42s %9s B  %s  %s\n' "$b" "$(stat -c%s $f)" \
        "$(sha256sum $f | cut -c1-12)" \
        "$(aarch64-pc-cygwin-objdump -f $f 2>&1 | sed -n '2p' | cut -c1-46)"
    else
      printf '  %-42s ABSENT\n' "$b"
    fi
  done
done

echo
echo "############ is it a bigobj / section-count thing? ############"
f=/root/xc/w-link/bld/winsup/cygwin/devices.o
echo "first 4 bytes (machine id):"; head -c 4 "$f" | od -An -tx1
echo "preserved copy first 4 bytes:"; head -c 4 /root/xc/bld/winsup/cygwin/devices.o | od -An -tx1
echo
echo "############ how many objects in w-link are unreadable? ############"
cd /root/xc/w-link/bld/winsup/cygwin
bad=0; good=0
while read -r o; do
  if aarch64-pc-cygwin-objdump -f "$o" >/dev/null 2>&1; then good=$((good+1)); else bad=$((bad+1)); echo "  BAD: $o"; fi
done < /tmp/objs_have.txt
echo "good=$good bad=$bad"
