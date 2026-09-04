#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
echo "############ MD5 PRECONDITIONS (coordinator-requested) ############"
printf '%-52s %-34s %s\n' FILE MD5 NOTE
for t in /root/xc/runtime /root/xc/w-autoload/runtime /root/xc/w-link/runtime; do
  f=$t/winsup/cygwin/autoload.cc
  [ -f "$f" ] && printf '%-52s %-34s balign=%s\n' "${t}/…/autoload.cc" "$(md5sum $f | cut -d' ' -f1)" "$(grep -c balign $f)"
done
echo
for t in /root/xc/runtime /root/xc/w-autoload/runtime /root/xc/w-link/runtime; do
  f=$t/winsup/cygwin/scripts/gendef
  [ -f "$f" ] && printf '%-52s %-34s lines=%s\n' "${t}/…/gendef" "$(md5sum $f | cut -d' ' -f1)" "$(wc -l < $f)"
done
f=/root/xc/w-gendef/gendef
printf '%-52s %-34s lines=%s (CRLF source)\n' "w-gendef/gendef (as delivered)" "$(md5sum $f | cut -d' ' -f1)" "$(wc -l < $f)"
printf '%-52s %-34s\n' "w-gendef/gendef LF-normalised" "$(sed 's/\r$//' $f | md5sum | cut -d' ' -f1)"

echo
echo "############ is w-autoload REALLY only bld/? ############"
ls -d /root/xc/w-autoload/*/ 2>/dev/null

echo
echo "############ sigfe.o reproducibility check ############"
cd /root/xc/w-link/bld/winsup/cygwin
printf 'my sigfe.o    : %9s B  sha256 %s\n' "$(stat -c%s sigfe.o)" "$(sha256sum sigfe.o | cut -c1-16)"
printf 'w-gendef      : %9s B  sha256 %s\n' "$(stat -c%s /root/xc/w-gendef/sigfe.o)" "$(sha256sum /root/xc/w-gendef/sigfe.o | cut -c1-16)"
printf 'my sigfe.s    : %9s B  sha256 %s\n' "$(stat -c%s sigfe.s)" "$(sha256sum sigfe.s | cut -c1-16)"
printf 'w-gendef      : %9s B  sha256 %s\n' "$(stat -c%s /root/xc/w-gendef/sigfe.s)" "$(sha256sum /root/xc/w-gendef/sigfe.s | cut -c1-16)"

echo
echo "############ SEH directive counts in MY regenerated sigfe.s ############"
for d in .seh_proc .seh_endproc .seh_endprologue .seh_handler; do
  printf '  %-20s %s\n' "$d" "$(grep -c "^[[:space:]]*$d\b" sigfe.s)"
done
printf '  %-20s %s\n' "globals(.global)" "$(grep -c '^[[:space:]]*\.global' sigfe.s)"
printf '  %-20s %s\n' "_sigfe_ symbols" "$(grep -c '^_sigfe_' sigfe.s)"

echo
echo "############ raw vs unique cannot-export in MY link ############"
Lg=/root/xc/link-combined.log
printf '  raw lines : %s\n' "$(grep -c 'cannot export' $Lg)"
printf '  unique    : %s\n' "$(grep -o 'cannot export [A-Za-z0-9_@]*' $Lg | awk '{print $3}' | sort -u | wc -l)"
