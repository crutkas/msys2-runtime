#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stddef.h>
#include <stdint.h>

struct _TEB
{
  NT_TIB Tib;
  BYTE reserved_to_deallocation_stack[0x1478 - sizeof (NT_TIB)];
  PVOID DeallocationStack;
};
typedef struct _TEB TEB, *PTEB;

static_assert (offsetof (TEB, DeallocationStack) == 0x1478,
	       "Windows ARM64 TEB layout drift");

#define __CYGTLS_PADSIZE__ 12800

extern "C" int __isthreaded;

static inline void
cfree (void *allocation)
{
  HeapFree (GetProcessHeap (), 0, allocation);
}

struct layer4_wincap
{
  ULONG def_guard_page_size () const { return 4096; }
  ULONG page_size () const { return 4096; }
};

extern layer4_wincap wincap;

struct layer4_cygtls
{
  DWORD64 magic;
  void *entry;

  void init_thread (void *, DWORD (*func) (void *, void *))
  {
    magic = 0xc763173f;
    entry = (void *) func;
  }
};

#define _my_tls \
  (*(layer4_cygtls *) ((PBYTE) NtCurrentTeb ()->Tib.StackBase \
		       - __CYGTLS_PADSIZE__))

[[noreturn]] static inline void
api_fatal (const char *)
{
  ExitProcess (69);
}
