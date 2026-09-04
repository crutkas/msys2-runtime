#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
# regenerate the analysis temp files, then collect evidence
bash /root/xc/t/s27.sh > /root/xc/analysis-final.txt 2>&1
tail -30 /root/xc/analysis-final.txt

echo
echo "############ where do the 8 orphan exports live in the tree? ############"
for s in __alloca _ctype_ _fe_nomask_env fedisableexcept fegetexcept fegetprec fesetprec msys_dll_init; do
  echo -n "$s : "
  grep -rl "\b$s\b" /root/xc/runtime/newlib /root/xc/runtime/winsup 2>/dev/null \
    | grep -v '\.din$' | head -3 | tr '\n' ' '
  echo
done

echo
echo "############ EVIDENCE COLLECTION ############"
D=/mnt/c/Users/crutkasLocal/.copilot/session-state/c63ab774-a023-4e57-9bc4-53f727507ada/files/evidence
mkdir -p $D
for f in undef undef_other undef_autoload cantexport dll_objs_missing dll_objs_have; do
  [ -f /tmp/$f.txt ] && cp /tmp/$f.txt $D/$f.txt && echo "copied $f.txt ($(wc -l < /tmp/$f.txt) lines)"
done
[ -f /tmp/cantexport.txt ] && grep -v '^_sigfe_' /tmp/cantexport.txt > $D/cannot-export-non-sigfe.txt
cp /root/xc/analysis-final.txt $D/
ls -la $D
