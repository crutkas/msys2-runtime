/* Exercise fork/exec argument bytes, inherited signals and pthread TLS. */
#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile sig_atomic_t handled;
static __thread int local_value;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned counter;

static void
handler (int sig)
{
  handled = sig == SIGUSR1;
}

static int
wait_for (pid_t child, int expected)
{
  int status;
  pid_t result;
  do
    result = waitpid (child, &status, 0);
  while (result < 0 && errno == EINTR);
  if (result != child)
    {
      perror ("waitpid");
      return 1;
    }
  if (!WIFEXITED (status))
    {
      fprintf (stderr, "child %ld abnormal status %#x\n", (long) child, status);
      return 1;
    }
  if (WEXITSTATUS (status) != expected)
    {
      fprintf (stderr, "child %ld exit %d, expected %d\n",
	       (long) child, WEXITSTATUS (status), expected);
      return 1;
    }
  return 0;
}

static void
make_argument (char *out, int length)
{
  static const char pattern[] = "a B\"\\cD";
  for (int i = 0; i < length; ++i)
    out[i] = pattern[i % (sizeof pattern - 1)];
  out[length] = 0;
}

static int
exec_child (int argc, char **argv)
{
  char expected[41];
  if (argc != 4)
    return 91;
  int length = atoi (argv[2]);
  if (length < 1 || length > 40)
    return 92;
  make_argument (expected, length);
  if (strlen (argv[3]) != (size_t) length
      || memcmp (argv[3], expected, (size_t) length + 1))
    return 93;
  if (signal (SIGUSR1, handler) == SIG_ERR || raise (SIGUSR1))
    return 94;
  return handled ? 55 : 95;
}

static int
fork_probe (void)
{
  int pipefd[2];
  unsigned char *data = malloc (4096);
  if (!data || pipe (pipefd))
    {
      perror ("fork setup");
      free (data);
      return 1;
    }
  memset (data, 0x5a, 4096);
  pid_t child = fork ();
  if (child < 0)
    {
      perror ("fork");
      close (pipefd[0]);
      close (pipefd[1]);
      free (data);
      return 1;
    }
  if (child == 0)
    {
      close (pipefd[0]);
      for (int i = 0; i < 4096; ++i)
	if (data[i] != 0x5a)
	  _exit (80);
      memset (data, 0xa5, 4096);
      handled = 0;
      if (raise (SIGUSR1) || !handled)
	_exit (84);
      pid_t nested = fork ();
      if (nested < 0)
	_exit (81);
      if (nested == 0)
	_exit (17);
      if (wait_for (nested, 17))
	_exit (82);
      uint32_t value = 0x12345678;
      if (write (pipefd[1], &value, sizeof value) != sizeof value)
	_exit (83);
      free (data);
      _exit (41);
    }
  close (pipefd[1]);
  uint32_t value = 0;
  ssize_t bytes;
  do
    bytes = read (pipefd[0], &value, sizeof value);
  while (bytes < 0 && errno == EINTR);
  close (pipefd[0]);
  int failed = wait_for (child, 41)
	       || bytes != sizeof value || value != 0x12345678;
  for (int i = 0; i < 4096; ++i)
    if (data[i] != 0x5a)
      failed = 1;
  free (data);
  return failed;
}

static void *
thread_probe (void *argument)
{
  int expected = (int) (intptr_t) argument;
  local_value = expected;
  for (int i = 0; i < 200; ++i)
    {
      if (pthread_mutex_lock (&lock))
	return (void *) 1;
      ++counter;
      if (pthread_mutex_unlock (&lock))
	return (void *) 2;
      if (local_value != expected)
	return (void *) 3;
      sched_yield ();
    }
  return NULL;
}

int
main (int argc, char **argv)
{
  if (argc > 1 && !strcmp (argv[1], "--exec-child"))
    return exec_child (argc, argv);
  if (argc > 1 && !strcmp (argv[1], "--direct-exec"))
    {
      char argument[41];
      make_argument (argument, 40);
      execl (argv[0], argv[0], "--exec-child", "40", argument, (char *) NULL);
      perror ("direct exec");
      return 99;
    }
  if (argc == 3 && !strcmp (argv[1], "--native-exec"))
    {
      pid_t child = fork ();
      if (child < 0)
	return 1;
      if (child == 0)
	{
	  char *args[] = { argv[2], NULL };
	  execv (argv[2], args);
	  _exit (99);
	}
      return wait_for (child, 73);
    }
  if (signal (SIGUSR1, handler) == SIG_ERR || raise (SIGUSR1) || !handled)
    return 1;
  for (int i = 0; i < 5; ++i)
    if (fork_probe ())
      return 2;
  for (int length = 1; length <= 40; ++length)
    {
      char argument[41], number[8];
      make_argument (argument, length);
      snprintf (number, sizeof number, "%d", length);
      pid_t child = fork ();
      if (child < 0)
	{
	  perror ("fork exec");
	  return 3;
	}
      if (child == 0)
	{
	  execl (argv[0], argv[0], "--exec-child", number, argument, (char *) NULL);
	  perror ("exec");
	  _exit (99);
	}
      if (wait_for (child, 55))
	return 4;
    }
  pthread_t threads[4];
  for (int i = 0; i < 4; ++i)
    if (pthread_create (&threads[i], NULL, thread_probe,
			(void *) (intptr_t) (i + 1)))
      return 5;
  for (int i = 0; i < 4; ++i)
    {
      void *result;
      if (pthread_join (threads[i], &result) || result)
	return 6;
    }
  return counter == 800 ? 0 : 7;
}
