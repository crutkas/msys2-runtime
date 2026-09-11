/* Exercise ARM64 context entry layout, stack arguments and linked returns. */
#include <fenv.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <ucontext.h>
#include <unistd.h>

#ifdef __aarch64__
static ucontext_t caller, callee;
static volatile int progress;
static volatile int failed;
static uintptr_t expected[12];
static const size_t stack_size = 256 * 1024;
static int child_pipe;
static _Thread_local int tls_progress;
static int *thread_errno;

static void
entry_zero (void)
{
  sigset_t mask;
  if (sigprocmask (SIG_SETMASK, NULL, &mask)
      || sigismember (&mask, SIGUSR1) != 1)
    failed = 1;
  if (fesetround (FE_DOWNWARD))
    _exit (90);
  for (int i = 1; i <= 32; ++i)
    {
      if (fegetround () != FE_DOWNWARD || tls_progress != i - 1
	  || &errno != thread_errno || errno != EDOM)
	failed = 1;
      progress = i;
      tls_progress = i;
      errno = ERANGE;
      if (swapcontext (&callee, &caller))
	_exit (91);
    }
  progress = 33;
}

static void
entry_one (uintptr_t a0)
{
  if (a0 != expected[0])
    failed = 1;
  progress = 1;
}

static void
entry_eight (uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3,
	     uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7)
{
  uintptr_t actual[] = { a0, a1, a2, a3, a4, a5, a6, a7 };
  if (memcmp (actual, expected, sizeof actual))
    failed = 1;
  progress = 8;
}

static void
entry_nine (uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3,
	    uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7,
	    uintptr_t a8)
{
  uintptr_t actual[] = { a0, a1, a2, a3, a4, a5, a6, a7, a8 };
  if (memcmp (actual, expected, sizeof actual))
    failed = 1;
  progress = 9;
}

static void
entry_args (uintptr_t a0, uintptr_t a1, uintptr_t a2, uintptr_t a3,
	    uintptr_t a4, uintptr_t a5, uintptr_t a6, uintptr_t a7,
	    uintptr_t a8, uintptr_t a9, uintptr_t a10, uintptr_t a11)
{
  uintptr_t actual[] = { a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11 };
  if (memcmp (actual, expected, sizeof actual))
    failed = 1;
  progress = 12;
}

static void
entry_null (void)
{
  if (write (child_pipe, "R", 1) != 1)
    _exit (92);
}

static int
check_layout (ucontext_t *context, void *stack, int argc, void (*entry) (void))
{
  uintptr_t sp = context->uc_mcontext.sp;
  uintptr_t link = context->uc_mcontext.x19;
  unsigned stack_args = argc > 8 ? argc - 8 : 0;
  if ((sp & 15) || context->uc_mcontext.pc != (uintptr_t) entry
      || context->uc_mcontext.lr == 0 || context->uc_mcontext.fp != 0
      || sp < (uintptr_t) stack
      || link != sp + stack_args * sizeof (uintptr_t)
      || link + sizeof (uintptr_t) > (uintptr_t) stack + stack_size
      || *(uintptr_t *) link != (uintptr_t) context->uc_link)
    {
      fprintf (stderr, "invalid makecontext layout for %d arguments\n", argc);
      return 1;
    }
  if (argc)
    {
      uintptr_t registers[8];
      memcpy (registers, &context->uc_mcontext.x0, sizeof registers);
      for (int i = 0; i < argc && i < 8; ++i)
	if (registers[i] != expected[i])
	  return 1;
      for (int i = 8; i < argc; ++i)
	if (((uintptr_t *) sp)[i - 8] != expected[i])
	  return 1;
    }
  return 0;
}

static void
prepare (void *stack)
{
  if (getcontext (&callee))
    {
      perror ("getcontext");
      exit (1);
    }
  callee.uc_stack.ss_sp = stack;
  callee.uc_stack.ss_size = stack_size;
  callee.uc_stack.ss_flags = 0;
  callee.uc_link = &caller;
}
#endif

int
main (int argc, char **argv)
{
#ifndef __aarch64__
  return 77;
#else
  void *stack;
  if (posix_memalign (&stack, 16, stack_size))
    return 1;
  memset (stack, 0, stack_size);
  int layout_only = argc == 2 && strcmp (argv[1], "--layout-only") == 0;
  for (unsigned i = 0; i < 12; ++i)
    expected[i] = UINT64_C (0x1234567800000000) + i;

  prepare (stack);
  makecontext (&callee, entry_zero, 0);
  if (check_layout (&callee, stack, 0, entry_zero))
    return 1;
  prepare (stack);
  makecontext (&callee, (void (*) (void)) entry_one, 1, expected[0]);
  if (check_layout (&callee, stack, 1, (void (*) (void)) entry_one)
      || (!layout_only
	  && (swapcontext (&caller, &callee) || progress != 1 || failed)))
    return 1;
  prepare (stack);
  makecontext (&callee, (void (*) (void)) entry_eight, 8,
	       expected[0], expected[1], expected[2], expected[3],
	       expected[4], expected[5], expected[6], expected[7]);
  if (check_layout (&callee, stack, 8, (void (*) (void)) entry_eight)
      || (!layout_only
	  && (swapcontext (&caller, &callee) || progress != 8 || failed)))
    return 1;
  prepare (stack);
  makecontext (&callee, (void (*) (void)) entry_nine, 9,
	       expected[0], expected[1], expected[2], expected[3],
	       expected[4], expected[5], expected[6], expected[7], expected[8]);
  if (check_layout (&callee, stack, 9, (void (*) (void)) entry_nine)
      || (!layout_only
	  && (swapcontext (&caller, &callee) || progress != 9 || failed)))
    return 1;
  prepare (stack);
  makecontext (&callee, (void (*) (void)) entry_args, 12,
	       expected[0], expected[1], expected[2], expected[3],
	       expected[4], expected[5], expected[6], expected[7],
	       expected[8], expected[9], expected[10], expected[11]);
  if (check_layout (&callee, stack, 12, (void (*) (void)) entry_args))
    return 1;
  if (layout_only)
    {
      free (stack);
      return 0;
    }
  if (swapcontext (&caller, &callee) || progress != 12 || failed)
    return 2;

  prepare (stack);
  sigemptyset (&callee.uc_sigmask);
  sigaddset (&callee.uc_sigmask, SIGUSR1);
  makecontext (&callee, entry_zero, 0);
  int original_round = fegetround ();
  thread_errno = &errno;
  sigset_t mask, original_mask;
  sigemptyset (&mask);
  if (sigprocmask (SIG_SETMASK, &mask, &original_mask)
      || fesetround (FE_UPWARD))
    return 3;
  for (int i = 1; i <= 33; ++i)
    {
      errno = EDOM;
      if (swapcontext (&caller, &callee) || progress != i || failed
	  || fegetround () != FE_UPWARD || &errno != thread_errno
	  || (i <= 32 && (tls_progress != i || errno != ERANGE)))
	return 3;
      if (sigprocmask (SIG_SETMASK, NULL, &mask)
	  || sigismember (&mask, SIGUSR1) != 0)
	return 4;
    }
  if (fesetround (original_round)
      || sigprocmask (SIG_SETMASK, &original_mask, NULL))
    return 4;

  int pipefd[2], status;
  if (pipe (pipefd))
    return 5;
  pid_t child = fork ();
  if (child < 0)
    return 5;
  if (child == 0)
    {
      close (pipefd[0]);
      child_pipe = pipefd[1];
      prepare (stack);
      callee.uc_link = NULL;
      makecontext (&callee, entry_null, 0);
      setcontext (&callee);
      _exit (93);
    }
  close (pipefd[1]);
  char marker;
  if (waitpid (child, &status, 0) != child || !WIFEXITED (status)
      || WEXITSTATUS (status) != 0 || read (pipefd[0], &marker, 1) != 1
      || marker != 'R')
    return 5;
  close (pipefd[0]);
  free (stack);
  return 0;
#endif
}
