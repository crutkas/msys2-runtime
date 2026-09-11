/* Keep the public jump buffers and signal-mask macros aligned with the DLL. */
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static struct
{
  jmp_buf buffer;
  unsigned char guard[16];
} plain;
static struct
{
  sigjmp_buf buffer;
  unsigned char guard[16];
} saved;
static volatile sig_atomic_t handler_count;
static volatile sig_atomic_t use_function;

static void
handler (int signo)
{
  ++handler_count;
  if (use_function)
    (siglongjmp) (saved.buffer, signo);
  siglongjmp (saved.buffer, signo);
}

static int
guards_intact (const unsigned char *bytes)
{
  for (unsigned i = 0; i < 16; ++i)
    if (bytes[i] != 0xa5)
      return 0;
  return 1;
}

int
main (void)
{
  memset (plain.guard, 0xa5, sizeof plain.guard);
#ifdef __aarch64__
  /* d15 must not replace the public buffer's following word. */
  __asm__ volatile ("fmov d15, xzr" ::: "v15");
#endif
  if (setjmp (plain.buffer) != 0 || !guards_intact (plain.guard))
    {
      fprintf (stderr, "setjmp wrote beyond the public jmp_buf\n");
      return 1;
    }
  memset (saved.guard, 0xa5, sizeof saved.guard);
#ifdef __aarch64__
  __asm__ volatile ("fmov d15, xzr" ::: "v15");
#endif
  if (sigsetjmp (saved.buffer, 1) != 0 || saved.buffer[_SAVEMASK] != 1
      || !guards_intact (saved.guard))
    {
      fprintf (stderr, "sigsetjmp corrupted its save-mask flag or buffer\n");
      return 2;
    }

  struct sigaction action = { 0 };
  action.sa_handler = handler;
  sigemptyset (&action.sa_mask);
  if (sigaction (SIGSEGV, &action, NULL) || sigaction (SIGBUS, &action, NULL))
    {
      perror ("sigaction");
      return 3;
    }
  long pagesize = sysconf (_SC_PAGESIZE);
  if (pagesize <= 0)
    return 4;
  void *page = mmap (NULL, pagesize, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (page == MAP_FAILED)
    {
      perror ("mmap");
      return 4;
    }
  volatile int failed = 0;
  for (use_function = 0; use_function <= 1; ++use_function)
    for (volatile int iteration = 0; iteration < 4; ++iteration)
      {
        int result = use_function ? (sigsetjmp) (saved.buffer, 1)
				  : sigsetjmp (saved.buffer, 1);
        if (!result)
          {
            volatile unsigned char value = *(volatile unsigned char *) page;
            (void) value;
            fprintf (stderr, "protected-page access did not fault\n");
            failed = 1;
            goto done;
          }
        sigset_t mask;
        if ((result != SIGSEGV && result != SIGBUS)
	    || sigprocmask (SIG_SETMASK, NULL, &mask)
	    || sigismember (&mask, SIGSEGV) != 0
	    || sigismember (&mask, SIGBUS) != 0
	    || !guards_intact (saved.guard))
          {
            fprintf (stderr, "siglongjmp did not restore the saved signal mask\n");
            failed = 1;
            goto done;
          }
      }
done:
  if (munmap (page, pagesize) || handler_count != 8)
    failed = 1;
  return failed;
}
