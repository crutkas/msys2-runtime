#!/bin/bash
A=/root/xc/w-link/runtime/winsup/cygwin/autoload.cc
echo "############ LAYOUT COMPARISON (LP64, natural alignment) ############"
cat <<'EOF'
  struct dll_info            offset   assembly emitted by LoadDLLprime   offset
  -------------------------  ------   --------------------------------   ------
  UINT_PTR load_state;          0     .quad _std_dll_init                   0
  HANDLE   handle;              8     .quad no_resolve_on_fork              8
  LONG     here;               16     .long -1                             16
      (padding 20..23)                .balign 8   -> pads 20..23
  void   (*init)();            24     .quad init_also                      24
  WCHAR    name[];             32     UTF-16 name bytes                    32
  => IDENTICAL. No 4-byte shift anywhere.

  struct func_info           offset   aarch64 thunk payload              offset
  -------------------------  ------   --------------------------------   ------
  struct dll_info *dll;         0     2: .quad .<dll>_info                  0
  LONG decoration;              8     .hword notimp / .hword err            8
      (padding 12..15)                .hword 0 / .hword 0                  12
  UINT_PTR func_addr;          16     3: .quad 1b                          16
  char name[];                 24     4: .asciz "<name>"                   24
  => IDENTICAL, and the source carries static_asserts proving 0/8/16/24.
EOF

echo
echo "############ the value at +0x0C is just what the bytes ARE ############"
cat <<'EOF'
  +0x08 handle            = 0            -> bytes 00 00 00 00 00 00 00 00
  +0x10 here (.long -1)   = 0xFFFFFFFF   -> bytes FF FF FF FF
  Any 8-byte window starting at +0x0C therefore reads
      00 00 00 00 | FF FF FF FF  =  0xFFFFFFFF00000000
  That is a property of the DATA, not evidence that any consumer reads there.
  The reporter's own note that this byte pattern occurs 13 times in .data
  supports the same reading: the value is common, not diagnostic.
EOF

echo
echo "############ THE RETURN-PATH MECHANISM (produces an actual branch target) ############"
grep -n -B4 -A14 'union retchain' $A
echo "--- std_dll_init return ---"
sed -n '493,540p' $A
