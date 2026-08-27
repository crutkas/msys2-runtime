#include <errno.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static const char child_text[] = "ISO-8859-1|LATIN1|--to-code=UTF-8\n";

static int
write_all (int fd, const char *data, size_t size)
{
  while (size)
    {
      ssize_t written = write (fd, data, size);
      if (written < 0)
	{
	  if (errno == EINTR)
	    continue;
	  return -1;
	}
      data += written;
      size -= written;
    }
  return 0;
}

static int
child_mode (int argc, char **argv, int exit_code)
{
  if (argc != 5
      || strcmp (argv[2], "ISO-8859-1") != 0
      || strcmp (argv[3], "LATIN1") != 0
      || strcmp (argv[4], "--to-code=UTF-8") != 0
      || write_all (STDOUT_FILENO, child_text, sizeof (child_text) - 1) != 0)
    return 100;
  return exit_code;
}

static int
read_and_wait (int fd, pid_t pid, int expected_exit)
{
  char buffer[sizeof (child_text)] = {};
  size_t used = 0;
  int status;

  while (used < sizeof (child_text) - 1)
    {
      ssize_t count = read (fd, buffer + used,
			    sizeof (child_text) - 1 - used);
      if (count < 0 && errno == EINTR)
	continue;
      if (count <= 0)
	break;
      used += count;
    }
  close (fd);
  if (waitpid (pid, &status, 0) != pid
      || !WIFEXITED (status)
      || WEXITSTATUS (status) != expected_exit)
    return -1;
  return used == sizeof (child_text) - 1
	 && memcmp (buffer, child_text, sizeof (child_text) - 1) == 0 ? 0 : -1;
}

static int
test_fork (void)
{
  int pipefd[2];
  pid_t pid;

  if (pipe (pipefd) != 0)
    return 1;
  pid = fork ();
  if (pid < 0)
    return 2;
  if (pid == 0)
    {
      close (pipefd[0]);
      if (dup2 (pipefd[1], STDOUT_FILENO) < 0)
	_exit (101);
      close (pipefd[1]);
      _exit (write_all (STDOUT_FILENO, child_text,
			sizeof (child_text) - 1) == 0 ? 37 : 102);
    }
  close (pipefd[1]);
  return read_and_wait (pipefd[0], pid, 37) == 0 ? 0 : 3;
}

static int
test_spawn (const char *self)
{
  char *argv[] = {(char *) self, (char *) "--spawn-child",
		  (char *) "ISO-8859-1", (char *) "LATIN1",
		  (char *) "--to-code=UTF-8", NULL};
  posix_spawn_file_actions_t actions;
  int pipefd[2];
  pid_t pid;

  if (pipe (pipefd) != 0)
    return 1;
  if (posix_spawn_file_actions_init (&actions) != 0
      || posix_spawn_file_actions_adddup2 (&actions, pipefd[1],
					   STDOUT_FILENO) != 0
      || posix_spawn_file_actions_addclose (&actions, pipefd[0]) != 0
      || posix_spawn_file_actions_addclose (&actions, pipefd[1]) != 0)
    return 2;
  int result = posix_spawn (&pid, self, &actions, NULL, argv, environ);
  posix_spawn_file_actions_destroy (&actions);
  close (pipefd[1]);
  if (result != 0)
    {
      close (pipefd[0]);
      return 3;
    }
  return read_and_wait (pipefd[0], pid, 41) == 0 ? 0 : 4;
}

static int
test_exec (const char *self)
{
  int pipefd[2];
  pid_t pid;

  if (pipe (pipefd) != 0)
    return 1;
  pid = fork ();
  if (pid < 0)
    return 2;
  if (pid == 0)
    {
      close (pipefd[0]);
      if (dup2 (pipefd[1], STDOUT_FILENO) < 0)
	_exit (101);
      close (pipefd[1]);
      execl (self, self, "--exec-child", "ISO-8859-1", "LATIN1",
	     "--to-code=UTF-8", (char *) NULL);
      _exit (103);
    }
  close (pipefd[1]);
  return read_and_wait (pipefd[0], pid, 43) == 0 ? 0 : 3;
}

int
main (int argc, char **argv)
{
  if (argc > 1 && strcmp (argv[1], "--spawn-child") == 0)
    return child_mode (argc, argv, 41);
  if (argc > 1 && strcmp (argv[1], "--exec-child") == 0)
    return child_mode (argc, argv, 43);
  if (test_fork () != 0)
    return 10;
  if (test_spawn (argv[0]) != 0)
    return 20;
  if (test_exec (argv[0]) != 0)
    return 30;
  return 0;
}
