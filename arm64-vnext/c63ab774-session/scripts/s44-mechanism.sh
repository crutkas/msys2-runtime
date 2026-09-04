#!/bin/bash
# READ-ONLY. Characterise the mechanism that decides the struct tag name.
SDK="/mnt/c/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um/winnt.h"
CLA="/mnt/c/Users/crutkasLocal/.copilot/session-state/aabca41f-e845-47dd-97cd-bc99428bc7d4/files/arm64-local-workload/toolchain-root/clangarm64/include/winnt.h"

echo "############ Windows SDK 10.0.26100.0 : lines 7090-7155 ############"
sed -n '7090,7155p' "$SDK" | cat -n | awk '{printf "%5d  %s\n", $1+7089, substr($0, index($0,$2))}'

echo
echo "############ CLANGARM64 : lines 2470-2500 ############"
sed -n '2470,2500p' "$CLA" | cat -n | awk '{printf "%5d  %s\n", $1+2469, substr($0, index($0,$2))}'
