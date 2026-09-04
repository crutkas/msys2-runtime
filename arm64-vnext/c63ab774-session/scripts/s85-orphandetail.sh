#!/bin/bash
O=/root/xc/w-orphans
echo "############ their link.log ############"
head -30 $O/link.log
echo "..."
echo "--- counts ---"
printf 'cannot export : %s\nundefined ref : %s\nreloc trunc   : %s\n' \
  "$(grep -c 'cannot export' $O/link.log)" \
  "$(grep -c 'undefined reference' $O/link.log)" \
  "$(grep -c 'relocation truncated' $O/link.log)"

echo
echo "############ fenv_aarch64.c ############"
cat $O/fenv_aarch64.c

echo
echo "############ cygwin_din.diff (the arch conditioning) ############"
cat $O/cygwin_din.diff
