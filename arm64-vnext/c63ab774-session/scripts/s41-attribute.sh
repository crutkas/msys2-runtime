#!/bin/bash
# READ-ONLY. Independently attribute the diff: autotools boilerplate vs real port work.
R=/root/xc/runtime
G="git --no-optional-locks -C $R"
BOILER='^(compile|config\.guess|config\.sub|depcomp|install-sh|missing|mkinstalldirs|test-driver)$'

$G diff HEAD --numstat > /tmp/numstat.txt
echo "=== per-file numstat (autotools boilerplate) ==="
awk -v b="$BOILER" 'BEGIN{f=0;i=0;d=0} $3 ~ b {printf "  %-16s +%-5s -%-5s\n",$3,$1,$2; f++;i+=$1;d+=$2} END{printf "TOTAL BOILERPLATE : %d files, %d insertions, %d deletions\n",f,i,d}' /tmp/numstat.txt

echo
echo "=== real port work totals ==="
awk -v b="$BOILER" 'BEGIN{f=0;i=0;d=0} $3 !~ b {f++;i+=$1;d+=$2} END{printf "TOTAL PORT WORK   : %d files, %d insertions, %d deletions\n",f,i,d}' /tmp/numstat.txt

echo
echo "=== grand total (must equal 43 / 1693 / 760) ==="
awk 'BEGIN{f=0;i=0;d=0} {f++;i+=$1;d+=$2} END{printf "GRAND TOTAL       : %d files, %d insertions, %d deletions\n",f,i,d}' /tmp/numstat.txt

echo
echo "=== top 12 real-port-work files by insertions ==="
awk -v b="$BOILER" '$3 !~ b {print $1, $2, $3}' /tmp/numstat.txt | sort -rn | head -12 \
  | awk '{printf "  +%-6s -%-5s %s\n",$1,$2,$3}'

echo
echo "=== where are the 760 deletions? top 8 ==="
sort -k2 -rn /tmp/numstat.txt | head -8 | awk '{printf "  -%-6s +%-6s %s\n",$2,$1,$3}'
