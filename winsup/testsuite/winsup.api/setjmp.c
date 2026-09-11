/* Check jump return values independently of saved nonvolatile registers. */
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>

#ifdef __aarch64__
_Static_assert (sizeof (jmp_buf) == 0x100, "runtime register area layout");
_Static_assert (sizeof (sigjmp_buf) == 0x110, "runtime signal mask layout");
extern int setjmp_arm64_check (int, int);
#endif

static int
check_jump (int value, int save_mask)
{
#ifdef __aarch64__
  int failed = setjmp_arm64_check (value, save_mask);
  if (failed)
    fprintf (stderr, "jump(%d, savemask=%d) corrupted return value or x20\n",
	     value, save_mask);
  return failed;
#else
  sigjmp_buf env;
  volatile int requested = value;
  int result;

  if (save_mask < 0)
    result = setjmp (env);
  else
    result = sigsetjmp (env, save_mask);
  if (result == 0)
    {
      if (save_mask < 0)
	longjmp (env, requested);
      siglongjmp (env, requested);
    }
  if (result != (requested ? requested : 1))
    {
      fprintf (stderr, "jump(%d, savemask=%d) returned %d\n",
	       requested, save_mask, result);
      return 1;
    }
  return 0;
#endif
}

int
main (void)
{
  static const int values[] = { 0, 1, 7, 55, -3 };
  int failures = 0;
  for (int mode = -1; mode <= 1; ++mode)
    for (unsigned i = 0; i < sizeof values / sizeof values[0]; ++i)
      failures += check_jump (values[i], mode);
  return failures != 0;
}
