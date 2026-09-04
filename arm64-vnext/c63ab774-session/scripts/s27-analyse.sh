#!/bin/bash
# Categorise the diagnostic link failure.
cd /root/xc/bld/winsup/cygwin
L=/root/xc/link1.log
A=/root/xc/runtime/winsup/cygwin/autoload.cc

echo "############ 1. EXPORT FAILURES (empty sigfe.s) ############"
grep -o "cannot export [A-Za-z0-9_@]*" $L | awk '{print $3}' | sort -u > /tmp/cantexport.txt
echo -n "total 'cannot export' symbols: "; wc -l < /tmp/cantexport.txt
echo -n "  of which _sigfe_* : "; grep -c '^_sigfe_' /tmp/cantexport.txt
echo -n "  of which other    : "; grep -vc '^_sigfe_' /tmp/cantexport.txt
echo "  --- non-_sigfe_ export failures ---"
grep -v '^_sigfe_' /tmp/cantexport.txt | head -40

echo
echo "############ 2. UNDEFINED REFERENCES ############"
grep -o "undefined reference to \`[^']*'" $L | sed "s/.*\`//; s/'//" | sort -u > /tmp/undef.txt
echo -n "total unique undefined references: "; wc -l < /tmp/undef.txt

# symbols autoload.cc would have defined
grep -oE '^[[:space:]]*LoadDLLfunc(Ex[0-9]?)?[[:space:]]*\([[:space:]]*[A-Za-z0-9_]+' $A \
  | sed 's/.*(//; s/[[:space:]]//g' | sort -u > /tmp/autoload_syms.txt
echo -n "symbols autoload.cc defines (LoadDLLfunc*): "; wc -l < /tmp/autoload_syms.txt

comm -12 /tmp/undef.txt /tmp/autoload_syms.txt > /tmp/undef_autoload.txt
comm -23 /tmp/undef.txt /tmp/autoload_syms.txt > /tmp/undef_other.txt
echo -n "  undefined that autoload.cc WOULD have provided: "; wc -l < /tmp/undef_autoload.txt
echo -n "  undefined NOT explained by autoload.cc        : "; wc -l < /tmp/undef_other.txt
echo "  --- the unexplained ones (the real residue) ---"
cat /tmp/undef_other.txt

echo
echo "############ 3. any other linker error kinds? ############"
grep -v 'cannot export\|undefined reference' $L | grep -i 'error\|cannot\|warning' | sort -u | head -20

echo
echo "############ 4. artefacts ############"
ls -la new-msys-2.0.dll msysdll.a msys.map 2>&1
