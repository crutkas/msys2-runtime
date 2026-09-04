#!/bin/bash
L=/root/xc/link-combined.log
echo "############ error classes ############"
printf 'cannot export        : %s (unique %s)\n' "$(grep -c 'cannot export' $L)" "$(grep -o 'cannot export [A-Za-z0-9_@]*' $L | awk '{print $3}' | sort -u | wc -l)"
printf 'undefined reference  : %s (unique %s)\n' "$(grep -c 'undefined reference' $L)" "$(grep -o "undefined reference to \`[^']*'" $L | sed "s/.*\`//; s/'//" | sort -u | wc -l)"
printf 'reloc truncated      : %s\n' "$(grep -c 'relocation truncated to fit' $L)"
printf 'other error lines    : %s\n' "$(grep -ci 'error' $L)"

echo
echo "############ the 8 cannot-export ############"
grep -o 'cannot export [A-Za-z0-9_@]*' $L | awk '{print $3}' | sort -u

echo
echo "############ the unique undefined references ############"
grep -o "undefined reference to \`[^']*'" $L | sed "s/.*\`//; s/'//" | sort -u

echo
echo "############ relocation types involved ############"
grep -o 'IMAGE_REL_ARM64_[A-Z0-9_]*' $L | sort | uniq -c | sort -rn

echo
echo "############ which symbols do the truncated relocs target? ############"
grep 'relocation truncated to fit' $L | grep -o "against symbol \`[^']*'" | sed "s/.*\`//; s/'//" | sort | uniq -c | sort -rn | head -30

echo
echo "############ which objects are affected? ############"
grep -B1 'relocation truncated to fit' $L | grep -o '^[a-z]*\.a([a-z_0-9]*\.o)' | sort -u | head -20
grep 'relocation truncated to fit' $L | sed 's/:.*//' | sort -u | head -20

echo
echo "############ any other distinct ld message kinds? ############"
grep -v 'cannot export\|undefined reference\|relocation truncated' $L | grep -i 'ld:\|error' | sed 's/.*ld: //' | sort -u | head -20
