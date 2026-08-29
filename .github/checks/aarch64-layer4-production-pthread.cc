#define AARCH64_LAYER4_PTHREAD_CONTROL
#include "../../winsup/cygwin/create_posix_thread.cc"

extern "C" int __isthreaded;
int __isthreaded;
layer4_wincap wincap;

struct thread_control
{
  LONG *ready;
  DWORD result;
  PBYTE expected_stackbase;
};

static DWORD
controlled_thread (void *opaque)
{
  thread_control *control = (thread_control *) opaque;
  PBYTE stack_pointer;

  __asm__ volatile ("mov %0, sp" : "=r" (stack_pointer));
  if (((uintptr_t) stack_pointer & 15) != 0
      || NtCurrentTeb ()->Tib.StackBase != control->expected_stackbase
      || _my_tls.magic != 0xc763173f
      || _my_tls.entry != (void *) controlled_thread)
    ExitThread (70);

  InterlockedIncrement (control->ready);
  while (InterlockedCompareExchange (control->ready, 0, 0) != 2)
    SwitchToThread ();

  ExitThread (control->result);
}

static HANDLE
start_controlled_thread (thread_control *control)
{
  const SIZE_T stack_size = 1024 * 1024;
  PBYTE stack = (PBYTE) VirtualAlloc (NULL, stack_size,
				      MEM_RESERVE | MEM_COMMIT,
				      PAGE_READWRITE);
  pthread_wrapper_arg *wrapper;

  if (!stack)
    return NULL;

  wrapper = (pthread_wrapper_arg *) HeapAlloc (GetProcessHeap (),
						HEAP_ZERO_MEMORY,
						sizeof *wrapper);
  if (!wrapper)
    {
      VirtualFree (stack, 0, MEM_RELEASE);
      return NULL;
    }

  control->expected_stackbase = stack + stack_size;
  wrapper->func = controlled_thread;
  wrapper->arg = control;
  wrapper->stackaddr = stack;
  wrapper->stackbase = control->expected_stackbase;
  wrapper->stacklimit = stack;
  wrapper->guardsize = 0;
  return CreateThread (NULL, 256 * 1024, pthread_wrapper, wrapper, 0, NULL);
}

extern "C" int
mainCRTStartup ()
{
  LONG ready = 0;
  thread_control controls[2] =
    {
      { &ready, 71, NULL },
      { &ready, 72, NULL }
    };
  HANDLE threads[2];
  DWORD results[2];

  threads[0] = start_controlled_thread (&controls[0]);
  threads[1] = start_controlled_thread (&controls[1]);
  if (!threads[0] || !threads[1])
    ExitProcess (73);

  if (WaitForMultipleObjects (2, threads, TRUE, 30000) != WAIT_OBJECT_0
      || !GetExitCodeThread (threads[0], &results[0])
      || !GetExitCodeThread (threads[1], &results[1])
      || results[0] != controls[0].result
      || results[1] != controls[1].result
      || controls[0].expected_stackbase == controls[1].expected_stackbase
      || __isthreaded != 1)
    ExitProcess (74);

  CloseHandle (threads[0]);
  CloseHandle (threads[1]);
  ExitProcess (0);
}
