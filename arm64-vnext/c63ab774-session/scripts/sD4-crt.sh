#!/bin/bash
export PATH=/root/xc/inst/bin:$PATH
L=/root/xc/w-link/bld/winsup/cygwin
echo "############ startup objects / import libs available ############"
ls -la $L/crt0.o $L/libcygwin.a $L/libmsys.a $L/msysdll.a $L/lib/*.o 2>&1 | head -20
echo
echo "############ what does Makefile.am call the import library? ############"
grep -n 'LIB_NAME\|mkimport\|crt0' /root/xc/w-link/runtime/winsup/cygwin/Makefile.am | head -12
echo
echo "############ can we build them? ############"
cd $L && make -n libmsys.a 2>&1 | head -5
echo "---"
ls $L/*.a 2>&1
