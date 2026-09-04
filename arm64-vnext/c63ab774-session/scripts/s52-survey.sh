#!/bin/bash
# READ-ONLY survey of the two isolated fix trees.
for T in /root/xc/w-autoload /root/xc/w-gendef; do
  echo "################ $T ################"
  if [ ! -d "$T" ]; then echo "  MISSING"; continue; fi
  du -sh "$T" 2>/dev/null
  ls "$T"
  for sub in runtime bld src; do
    [ -d "$T/$sub" ] && echo "  has $sub/"
  done
done

echo
echo "################ disk / memory headroom ################"
df -h /root | tail -1
free -g | head -2

echo
echo "################ preserved assets still intact? ################"
for p in /root/xc/inst /root/xc/runtime /root/xc/bld; do
  printf '  %-20s %s\n' "$p" "$([ -d "$p" ] && echo present || echo MISSING)"
done
