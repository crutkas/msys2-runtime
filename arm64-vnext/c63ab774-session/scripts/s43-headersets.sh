#!/bin/bash
# READ-ONLY verification of two further winnt.h header sets.
# Touches nothing in /root/xc.
probe() {
  local p="$1" label="$2"
  if [ ! -f "$p" ]; then echo "MISSING: $label"; echo "   ($p)"; return; fi
  echo "---- $label ----"
  printf '   path   : %s\n' "$p"
  printf '   size   : %s bytes   lines: %s\n' "$(stat -c%s "$p")" "$(wc -l < "$p")"
  printf '   sha256 : %s\n' "$(sha256sum "$p" | cut -c1-64)"
  # word-boundary matching so ARM64EC is not miscounted as ARM64
  printf '   _DISPATCHER_CONTEXT_ARM64    (genuine, -ow) : %s\n' \
    "$(grep -ow '_DISPATCHER_CONTEXT_ARM64' "$p" | wc -l)"
  printf '   _DISPATCHER_CONTEXT_ARM64EC              : %s\n' \
    "$(grep -ow '_DISPATCHER_CONTEXT_ARM64EC' "$p" | wc -l)"
  printf '   struct _DISPATCHER_CONTEXT (plain)       : %s\n' \
    "$(grep -ow 'struct _DISPATCHER_CONTEXT' "$p" | wc -l)"
  echo "   definition / alias sites:"
  grep -n '_DISPATCHER_CONTEXT_ARM64\b' "$p" | head -8 | sed 's/^/     /'
}

probe "/mnt/c/Users/crutkasLocal/.copilot/session-state/aabca41f-e845-47dd-97cd-bc99428bc7d4/files/arm64-local-workload/toolchain-root/clangarm64/include/winnt.h" \
      "CLANGARM64 (materialised in session aabca41f files)"

echo
for sdk in /mnt/c/Program\ Files\ \(x86\)/Windows\ Kits/10/Include/*/um/winnt.h; do
  [ -f "$sdk" ] && probe "$sdk" "Microsoft Windows SDK $(basename "$(dirname "$(dirname "$sdk")")")"
done

echo
echo "---- re-confirm the two I already measured ----"
probe /root/xc/inst/aarch64-pc-cygwin/include/w32api/winnt.h "build sysroot w32api v12.0.0"
