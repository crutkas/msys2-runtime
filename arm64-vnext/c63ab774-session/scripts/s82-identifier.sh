#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link
cd $L/bld/winsup/cygwin || exit 1
echo "############ does the -D__MSYS__ dcrt0.o define msys_dll_init? ############"
aarch64-pc-cygwin-nm dcrt0.o 2>&1 | grep -i 'msys_dll_init\|cygwin_dll_init'
echo "--- the cygwin-flavour object for comparison ---"
aarch64-pc-cygwin-nm /tmp/dcrt0.cygwin.o 2>&1 | grep -i 'msys_dll_init\|cygwin_dll_init'

echo
echo "############ what identifier did the DIAGNOSTIC DLL actually carry? ############"
D=$L/bld/winsup/cygwin/new-msys-2.0.dll
if [ -f "$D" ]; then
  echo -n "  'cygwin1' occurrences : "; strings -a "$D" | grep -cx 'cygwin1'
  echo -n "  'msys-2.0' occurrences: "; strings -a "$D" | grep -cx 'msys-2.0'
  echo "  shared-object name strings:"
  strings -a "$D" | grep -E '^(cygwin1|msys-2\.0)\.' | sort -u | head
  strings -a "$D" | grep -iE 'cygwin1S|msys-2.0S' | sort -u | head -5
else
  echo "  (diagnostic DLL was removed by the honest rebuild)"
fi

echo
echo "############ which of the 40 sites are ABI/naming vs behaviour? ############"
cat <<'EOF'
  version.h:513  CYGWIN_VERSION_DLL_IDENTIFIER  "msys-2.0" vs "cygwin1"   <-- ABI/shared-object naming
  version.h:533  registry name                  "MSYS"     vs "Cygwin"    <-- registry key
  dcrt0.cc:1101  msys_dll_init  vs cygwin_dll_init                        <-- EXPORTED SYMBOL NAME
  dll_init.cc:916 / hookapi.cc:382 / dtable.cc:1000                       <-- behaviour
  environ.cc x9  MSYS / MSYSTEM env handling                              <-- behaviour
  cygheap.cc:223 root path two folders up (usr/ layout)                   <-- PATH LAYOUT
  pty.cc x2      \\.\pipe\msys-*  vs  \\.\pipe\cygwin-*                   <-- IPC naming
  syslog.cc:29   log name "MSYS" vs "CYGWIN"                              <-- naming
  uname.cc:30    MSYSTEM-based uname output                               <-- behaviour
  crt0/lib/*     msys_ vs cygwin_ entry-point names                       <-- ABI
EOF
