#include <windows.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include "../../cygwin/local_includes/memory_layout.h"

static void *
check_stack (void *unused)
{
  NT_TIB *tib = (NT_TIB *) NtCurrentTeb ();
  uintptr_t top = (uintptr_t) tib->StackBase;
  if (top > THREAD_STORAGE_LOW && top <= CYGHEAP_STORAGE_LOW
      && top > THREAD_STORAGE_HIGH)
    return (void *) 1;
  return NULL;
}

int
main (void)
{
  MEMORY_BASIC_INFORMATION guard, heap;
  if (VirtualQuery ((void *) CYGHEAP_GUARD_LOW, &guard, sizeof guard)
      != sizeof guard
      || guard.State != MEM_RESERVE
      || guard.AllocationBase != (void *) CYGHEAP_GUARD_LOW
      || (uintptr_t) guard.BaseAddress + guard.RegionSize < CYGHEAP_GUARD_HIGH
      || guard.AllocationProtect != PAGE_NOACCESS)
    {
      fprintf (stderr, "Missing reserved stack/cygheap guard\n");
      return 1;
    }
  if (VirtualQuery ((void *) CYGHEAP_STORAGE_LOW, &heap, sizeof heap)
      != sizeof heap || heap.State != MEM_COMMIT
      || heap.AllocationBase != (void *) CYGHEAP_STORAGE_LOW
      || heap.Protect != PAGE_READWRITE)
    return 2;
  unsigned char byte;
  SIZE_T done = 0;
  if (ReadProcessMemory (GetCurrentProcess (),
			(void *) (CYGHEAP_GUARD_HIGH - 1), &byte, 1, &done)
      || done != 0)
    return 3;
  if (check_stack (NULL))
    return 4;
  pthread_t thread;
  void *result = NULL;
  if (pthread_create (&thread, NULL, check_stack, NULL)
      || pthread_join (thread, &result) || result)
    return 5;
  return 0;
}
