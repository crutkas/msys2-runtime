#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>

#ifdef __aarch64__
static volatile sig_atomic_t handled;
static int armed;
static pthread_t target;

static void
handle_signal (int signo)
{
  handled = signo == SIGUSR1;
}

static void *
send_signal (void *unused)
{
  (void) unused;
  while (!__atomic_load_n (&armed, __ATOMIC_ACQUIRE))
    sched_yield ();
  return (void *) (long) pthread_kill (target, SIGUSR1);
}
#endif

int
main (void)
{
#ifndef __aarch64__
  return 77;
#else
  struct sigaction action = { 0 };
  pthread_t sender;
  void *thread_result;
  unsigned lane;
  action.sa_handler = handle_signal;
  sigemptyset (&action.sa_mask);
  if (sigaction (SIGUSR1, &action, NULL) != 0)
    {
      perror ("sigaction");
      return 1;
    }
  target = pthread_self ();
  if (pthread_create (&sender, NULL, send_signal, NULL) != 0)
    {
      fprintf (stderr, "pthread_create failed\n");
      return 1;
    }

  /* Arm the sender only after q31 is live.  No function call may clobber
     this volatile vector register between setup and signal return. */
  __asm__ volatile (
      "movi v31.16b, #0x79\n"
      "mov w10, #1\n"
      "stlr w10, [%2]\n"
      "mov w9, #0\n"
      "1: ldar w10, [%1]\n"
      "cbnz w10, 2f\n"
      "add w9, w9, #1\n"
      "tbnz w9, #28, 2f\n"
      "b 1b\n"
      "2: umov %w0, v31.b[15]\n"
      : "=r" (lane)
      : "r" (&handled), "r" (&armed)
      : "x9", "x10", "v31", "cc", "memory");
  if (pthread_join (sender, &thread_result) != 0
      || thread_result != NULL || !handled || lane != 0x79)
    {
      fprintf (stderr, "signal context failed: handled=%d q31[15]=%x\n",
	       handled, lane);
      return 1;
    }
  return 0;
#endif
}
