#!/usr/bin/env bash
# Exercise the production routines with deterministic failed Win32 calls.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir=$(cd "$here/../../cygwin" && pwd)
work=$(mktemp -d)
trap 'rm -f -- "$work/check.cc" "$work/check"; rmdir -- "$work"' EXIT
cat > "$work/check.cc" <<'EOF'
#include <cassert>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cerrno>
using DWORD = unsigned long;
using SIZE_T = unsigned long;
using LPVOID = void *;
using HANDLE = void *;
using BOOL = int;
constexpr DWORD ERROR_SUCCESS = 0;
constexpr DWORD MEM_RESERVE = 0x2000, MEM_COMMIT = 0x1000;
constexpr DWORD PAGE_NOACCESS = 1, PAGE_READWRITE = 4;
constexpr uintptr_t CYGHEAP_GUARD_LOW = 0x7ffff0000UL;
constexpr uintptr_t CYGHEAP_GUARD_HIGH = 0x800000000UL;
constexpr uintptr_t CYGHEAP_STORAGE_LOW = 0x800000000UL;
constexpr uintptr_t CYGHEAP_STORAGE_HIGH = 0xa00000000UL;
struct init_cygheap {};
struct Failure { const char *message; DWORD error; };
static int calls, fail_call, copy_mode, terminated, error_value;
static DWORD win_error;
static char diagnostic[1024];
static DWORD GetLastError () { return win_error; }
[[noreturn]] static void api_fatal (const char *fmt, ...) {
  throw Failure { fmt, win_error };
}
static LPVOID VirtualAlloc (LPVOID address, SIZE_T size, DWORD type, DWORD protection) {
  ++calls;
  if (calls == 1) {
    assert (address == (LPVOID) CYGHEAP_GUARD_LOW);
    assert (size == CYGHEAP_GUARD_HIGH - CYGHEAP_GUARD_LOW);
    assert (type == MEM_RESERVE && protection == PAGE_NOACCESS);
  } else if (calls == 2) {
    assert (address == (LPVOID) CYGHEAP_STORAGE_LOW);
    assert (type == MEM_RESERVE && protection == PAGE_NOACCESS);
  } else {
    assert (calls == 3 && address == (LPVOID) CYGHEAP_STORAGE_LOW);
    assert (size == 0x300000 && type == MEM_COMMIT && protection == PAGE_READWRITE);
  }
  win_error = 87;
  return calls == fail_call ? nullptr : address;
}
struct Proc { DWORD dwProcessId = 42; } proc, *myself = &proc;
static BOOL ReadProcessMemory (HANDLE, void *, void *, SIZE_T count, SIZE_T *done) {
  *done = copy_mode == 1 ? count - 1 : count;
  win_error = copy_mode == 2 ? 299 : 123;
  return copy_mode != 2;
}
static BOOL WriteProcessMemory (HANDLE h, void *a, void *b, SIZE_T count, SIZE_T *done) {
  return ReadProcessMemory (h, a, b, count, done);
}
static int geterrno_from_win_error (DWORD x) { assert (x == 299); return EFAULT; }
static void set_errno (int x) { error_value = x; }
static void debug_printf (const char *fmt, ...) {
  va_list ap; va_start (ap, fmt); vsnprintf (diagnostic, sizeof diagnostic, fmt, ap); va_end (ap);
  win_error = 999; // Diagnostics must not change the captured copy error.
}
static void system_printf (const char *fmt, ...) {
  va_list ap; va_start (ap, fmt); vsnprintf (diagnostic, sizeof diagnostic, fmt, ap); va_end (ap);
  win_error = 999;
}
static void TerminateProcess (HANDLE, int) { ++terminated; }
EOF
awk '/^static init_cygheap \*/ { emit=1 } emit {print} emit && /^}/ {exit}' \
    "$source_dir/mm/cygheap.cc" >> "$work/check.cc"
printf 'bool\n' >> "$work/check.cc"
awk '/^child_copy \(/ { emit=1 } emit {print} emit && /^}/ {exit}' \
    "$source_dir/fork.cc" >> "$work/check.cc"
cat >> "$work/check.cc" <<'EOF'
int main () {
  for (int fail = 0; fail <= 3; ++fail) {
    calls = 0; fail_call = fail;
    init_cygheap *heap = (init_cygheap *) 0x1234;
    try {
      heap = reserve_cygheap (0x300000);
      assert (fail == 0 && calls == 3 && heap == (LPVOID) CYGHEAP_STORAGE_LOW);
    } catch (const Failure& f) {
      assert (fail != 0 && calls == fail && heap == (LPVOID) 0x1234);
      assert (f.error == 87);
      assert (strstr (f.message, fail == 1 ? "guard" : fail == 2 ? "reserve cygheap" : "commit"));
    }
  }
  char buffer[16];
  for (int write = 0; write != 2; ++write)
    for (int silent = 0; silent != 2; ++silent)
      for (copy_mode = 0; copy_mode != 3; ++copy_mode) {
        terminated = 0; error_value = 0;
        bool result = child_copy ((HANDLE) 1, write, silent, (char *) "fixture",
                                  buffer, buffer + sizeof buffer, (char *) nullptr);
        assert (result == (copy_mode == 0));
        if (copy_mode != 0) {
          assert (terminated == 1 && error_value == EAGAIN);
          assert (strstr (diagnostic, "requested 16"));
          assert (strstr (diagnostic, copy_mode == 1 ? "done 15" : "done 16"));
          assert (strstr (diagnostic, copy_mode == 1 ? "Win32 error 0" : "Win32 error 299"));
        }
      }
  puts ("PASS allocation fail-closed paths and child-copy short/error diagnostics");
}
EOF
"${CXX_FOR_BUILD:-g++}" -std=c++11 -Wall -Wextra -Werror "$work/check.cc" -o "$work/check"
"$work/check"
