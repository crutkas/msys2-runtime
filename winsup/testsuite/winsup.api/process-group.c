/* Check stopped-child status and process-group continuation. */
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static pid_t
wait_child (pid_t child, int *status, int options)
{
  pid_t result;
  do
    result = waitpid (child, status, options);
  while (result < 0 && errno == EINTR);
  return result;
}

static int
abort_child (pid_t child, int error)
{
  int status;
  kill (child, SIGKILL);
  wait_child (child, &status, 0);
  return error;
}

int
main (void)
{
  int pipefd[2], status;
  char ready;
  if (pipe (pipefd))
    return 1;
  pid_t child = fork ();
  if (child < 0)
    return 2;
  if (child == 0)
    {
      close (pipefd[0]);
      if (setpgid (0, 0) || getpgrp () != getpid ())
	_exit (91);
      if (write (pipefd[1], "R", 1) != 1)
	_exit (92);
      close (pipefd[1]);
      if (raise (SIGSTOP))
	_exit (93);
      _exit (42);
    }
  close (pipefd[1]);
  ssize_t count;
  do
    count = read (pipefd[0], &ready, 1);
  while (count < 0 && errno == EINTR);
  close (pipefd[0]);
  if (count != 1 || ready != 'R')
    return abort_child (child, 3);
  if (wait_child (child, &status, WUNTRACED) != child)
    return 4;
  if (WIFEXITED (status) || WIFSIGNALED (status))
    return 4;
  if (!WIFSTOPPED (status) || WSTOPSIG (status) != SIGSTOP)
    return abort_child (child, 4);
  if (getpgid (child) != child || child == getpgrp ())
    return abort_child (child, 5);
  if (kill (-child, SIGCONT))
    return abort_child (child, 6);
  if (wait_child (child, &status, 0) != child || !WIFEXITED (status)
      || WEXITSTATUS (status) != 42)
    return 7;
  return 0;
}
