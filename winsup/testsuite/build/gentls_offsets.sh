#!/usr/bin/env bash
# Host-side generator regression tests; no Cygwin DLL or cross compiler needed.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
generator=${1:-"$script_dir/../../cygwin/scripts/gentls_offsets"}
generator=$(cd -- "$(dirname -- "$generator")" && pwd)/$(basename -- "$generator")
work_dir=$(mktemp -d)
trap 'rm -f -- "$work_dir/"*; rmdir -- "$work_dir"' EXIT
trap 'exit 1' HUP INT TERM

export CXXCOMPILE="bash ./compiler"
export GENTLS_HEADER="$work_dir/header"
export GENTLS_ASSEMBLY="$work_dir/assembly"
export GENTLS_COMPILE_INPUT="$work_dir/compile-input"
export GENTLS_MODE=success

cd -- "$work_dir"
cp "$script_dir/gentls_offsets-compiler" compiler
cat > expected <<'EOF'
.equ _cygtls.start_offset, -4096
.equ _cygtls.local_clib, -4096
.equ _cygtls.local_clib_p, 0
.equ _cygtls.func, -4088
.equ _cygtls.func_p, 8
.equ _cygtls.context, -4064
.equ _cygtls.context_p, 32
.equ _cygtls.stack, -3968
.equ _cygtls.stack_p, 128
EOF
cat > expected-input <<'EOF'
#include "winsup.h"
#include "cygtls.h"
extern "C" const uint32_t __CYGTLS__start_offset = __CYGTLS_PADSIZE__;
extern "C" const uint32_t __CYGTLS__local_clib = offsetof (class _cygtls, local_clib);
extern "C" const uint32_t __CYGTLS__func = offsetof (class _cygtls, func);
extern "C" const uint32_t __CYGTLS__context = offsetof (class _cygtls, context);
extern "C" const uint32_t __CYGTLS__stack = offsetof (class _cygtls, stack);
EOF
cp expected default-expected

reset_fixture ()
{
  GENTLS_MODE=success
  CXXCOMPILE="bash ./compiler"
  cp default-expected expected
  cat > "$GENTLS_HEADER" <<'EOF'
class _cygtls
{
public:
  struct _reent local_clib;
  void (*func) (int, void *);
  ucontext_t context;
  unsigned long stack[16];
public:
  void ignored_method ();
};
EOF
  cat > "$GENTLS_ASSEMBLY" <<'EOF'
__CYGTLS__start_offset:
	.long 4096
__CYGTLS__local_clib:
	.space 4
__CYGTLS__func:
	.long 8
__CYGTLS__context:
	.long 32
__CYGTLS__stack:
	.long 128
EOF
  printf '%s\n' 'previous valid output' > tlsoffsets
  cp tlsoffsets previous
  rm -f -- "$GENTLS_COMPILE_INPUT"
}

rewrite_assembly ()
{
  gawk "$1" "$GENTLS_ASSEMBLY" > assembly-new
  mv assembly-new "$GENTLS_ASSEMBLY"
}

failures=0
cases=0
check_case ()
{
  local name=$1 expect=$2 output=${3:-tlsoffsets} diagnostic=${4:-} status=0
  (( cases += 1 ))
  bash "$generator" "$GENTLS_HEADER" "$output" > stdout 2> stderr || status=$?
  if [[ $expect == success ]]
  then
    if (( status != 0 )) || ! cmp -s expected "$output" \
       || ! cmp -s expected-input "$GENTLS_COMPILE_INPUT"
    then
      echo "FAIL: $name (exit $status)" >&2
      cat stderr >&2
      diff -u expected "$output" >&2 || :
      diff -u expected-input "$GENTLS_COMPILE_INPUT" >&2 || :
      (( failures += 1 ))
      return
    fi
    if [[ -n $diagnostic ]] && ! grep -Fq -- "$diagnostic" stderr
    then
      echo "FAIL: $name (missing diagnostic: $diagnostic)" >&2
      cat stderr >&2
      (( failures += 1 ))
      return
    fi
    if [[ $GENTLS_MODE == preprocess-failure && -e $GENTLS_COMPILE_INPUT ]]
    then
      echo "FAIL: $name (compiled after preprocessing failed)" >&2
      (( failures += 1 ))
      return
    fi
  elif (( status == 0 )) || [[ ! -s stderr ]] \
       || { [[ $expect == failure ]] && ! cmp -s previous "$output"; } \
       || { [[ $expect == failure-absent ]] && [[ -e $output ]]; }
  then
    echo "FAIL: $name (exit $status; expected failure and unchanged output)" >&2
    cat stderr >&2
    (( failures += 1 ))
    return
  fi
  echo "PASS: $name"
}

reset_fixture
check_case x86_64-long success

reset_fixture
GENTLS_MODE=preprocess-require-include
check_case preprocess-header-as-include success

reset_fixture
rewrite_assembly '{ gsub (/\.long/, ".word"); print }'
check_case aarch64-word success

reset_fixture
rewrite_assembly '{ gsub (/\.long 32/, ".word 0x20 // context"); print }'
check_case mixed-directives-and-hex success

reset_fixture
rewrite_assembly '{ gsub (/\.space 4/, ".zero 4"); print }'
check_case zero-initialized-member success

reset_fixture
rewrite_assembly '{ gsub (/\.space 4/, ".space 4, 0"); print }'
check_case explicit-zero-fill success

reset_fixture
rewrite_assembly 'NR % 2 { label = $0; next }
  { records[++count] = label "\n" $0 }
  END { for (i = count; i > 0; --i) print records[i] }'
cat > expected <<'EOF'
.equ _cygtls.stack, -3968
.equ _cygtls.stack_p, 128
.equ _cygtls.context, -4064
.equ _cygtls.context_p, 32
.equ _cygtls.func, -4088
.equ _cygtls.func_p, 8
.equ _cygtls.local_clib, -4096
.equ _cygtls.local_clib_p, 0
.equ _cygtls.start_offset, -4096
EOF
check_case start-offset-after-members success

reset_fixture
rewrite_assembly '/^__CYGTLS__/ {
    name = $0; sub (/:$/, "", name);
    print "\t.globl " name; print "\t.align 2";
    print "\t" $0; next
  }
  { print $0 " # value"; print "" }'
printf 'unrelated_constant:\n\t.long 99\n' >> "$GENTLS_ASSEMBLY"
check_case assembly-metadata-and-unrelated-symbol success

reset_fixture
gawk 'BEGIN { for (i = 0; i < 10000; ++i) print "int unrelated_" i ";" }' \
  >> "$GENTLS_HEADER"
check_case drain-preprocessor-after-member-block success

reset_fixture
check_case absolute-output-path success "$work_dir/tlsoffsets"

reset_fixture
cp previous 'offsets with spaces'
check_case output-path-with-spaces success 'offsets with spaces'

reset_fixture
GENTLS_MODE=preprocess-failure
check_case preprocess-failure failure tlsoffsets 'fixture: preprocessing failed'

reset_fixture
GENTLS_MODE=compile-failure
check_case compile-failure-after-partial-output failure tlsoffsets 'fixture: compilation failed'

reset_fixture
GENTLS_MODE=compile-no-output
check_case compile-success-without-assembly failure tlsoffsets 'offsets.s'

reset_fixture
CXXCOMPILE=
check_case missing-compiler-setting failure tlsoffsets 'CXXCOMPILE must name'

reset_fixture
CXXCOMPILE=nonexistent-cxx-gentls-fixture
check_case missing-compiler-executable failure tlsoffsets 'nonexistent-cxx-gentls-fixture'

reset_fixture
GENTLS_MODE=compile-failure
rm tlsoffsets
check_case compiler-failure-with-no-previous-output failure-absent tlsoffsets 'fixture: compilation failed'

reset_fixture
rewrite_assembly '!/context/ && !/\.long 32/'
rm tlsoffsets
check_case parser-failure-with-no-previous-output failure-absent tlsoffsets 'missing offset for context'

reset_fixture
: > "$GENTLS_HEADER"
check_case missing-tls-class failure tlsoffsets 'could not find the _cygtls member block'

reset_fixture
gawk 'NR < 8' "$GENTLS_HEADER" > header-new
mv header-new "$GENTLS_HEADER"
check_case unterminated-tls-members failure tlsoffsets 'could not find the _cygtls member block'

reset_fixture
gawk '!/ucontext_t/' "$GENTLS_HEADER" > header-new
mv header-new "$GENTLS_HEADER"
rewrite_assembly '!/context/ && !/\.long 32/'
check_case missing-context-declaration failure tlsoffsets 'missing context offset'

reset_fixture
gawk '{ print; if (/ucontext_t/) print }' "$GENTLS_HEADER" > header-new
mv header-new "$GENTLS_HEADER"
check_case duplicate-member-declaration failure tlsoffsets 'invalid or duplicate member declaration'

reset_fixture
: > "$GENTLS_ASSEMBLY"
check_case empty-assembly failure tlsoffsets 'missing offset for'

reset_fixture
rewrite_assembly 'NR > 2'
check_case missing-start-offset failure tlsoffsets 'missing offset for start_offset'

reset_fixture
rewrite_assembly '!/context/ && !/\.long 32/'
check_case missing-context failure tlsoffsets 'missing offset for context'

reset_fixture
rewrite_assembly '!/stack/ && !/\.long 128/'
check_case missing-noncontext-member failure tlsoffsets 'missing offset for stack'

reset_fixture
rewrite_assembly '{ gsub (/\.long 32/, ".long 33"); print }'
check_case misaligned-context failure tlsoffsets '_cygtls.context member is not 16 bytes aligned'

reset_fixture
rewrite_assembly '{ gsub (/\.long 4096/, ".long 0"); print }'
check_case zero-start-offset failure tlsoffsets 'missing or zero TLS start offset'

reset_fixture
rewrite_assembly '{ gsub (/\.long 32/, ".long invalid"); print }'
check_case nonnumeric-offset failure tlsoffsets 'invalid offset for context'

reset_fixture
rewrite_assembly '{ gsub (/\.long 32/, ".long -32"); print }'
check_case negative-offset failure tlsoffsets 'invalid offset for context'

reset_fixture
rewrite_assembly '{ gsub (/\.long 32/, ".long 4294967296"); print }'
check_case offset-overflows-uint32 failure tlsoffsets 'offset out of uint32_t range for context'

reset_fixture
rewrite_assembly '{ gsub (/\.long 32/, ".long 32, 64"); print }'
check_case multiple-values failure tlsoffsets 'expected one offset value for context'

reset_fixture
rewrite_assembly '{ print; if (/\.long 32/) print "\t.word 64" }'
check_case multiple-value-directives failure tlsoffsets 'multiple offset values for context'

reset_fixture
rewrite_assembly '{ gsub (/\.space 4/, ".space 8"); print }'
check_case wrong-zero-fill-size failure tlsoffsets 'expected four zero bytes for local_clib'

reset_fixture
rewrite_assembly '{ gsub (/\.space 4/, ".space 4, 1"); print }'
check_case nonzero-fill failure tlsoffsets 'expected four zero bytes for local_clib'

reset_fixture
printf '__CYGTLS__context:\n\t.long 32\n' >> "$GENTLS_ASSEMBLY"
check_case duplicate-member failure tlsoffsets 'duplicate offset for context'

reset_fixture
printf '__CYGTLS__unknown:\n\t.long 16\n' >> "$GENTLS_ASSEMBLY"
check_case unexpected-member failure tlsoffsets 'unexpected TLS member: unknown'

reset_fixture
rewrite_assembly '!/\.long 32/'
check_case label-without-value failure tlsoffsets 'missing offset for context'

reset_fixture
rewrite_assembly '{ gsub (/\.long 32/, ".quad 32"); print }'
check_case unsupported-value-directive failure tlsoffsets 'unsupported offset directive for context: .quad'

reset_fixture
rewrite_assembly '{ if (/\.long 32/) print "\t.byte 0"; print }'
check_case unsupported-directive-before-value failure tlsoffsets 'unsupported offset directive for context: .byte'

echo "$cases cases, $failures failures"
(( failures == 0 ))
