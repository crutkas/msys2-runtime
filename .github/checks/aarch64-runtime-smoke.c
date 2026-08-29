#include <errno.h>
#include <fcntl.h>
#include <locale.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/cygwin.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static pthread_key_t tls_key;
static volatile sig_atomic_t signal_seen;

static void
fail (const char *operation)
{
  fprintf (stderr, "runtime-smoke: %s: %s\n", operation, strerror (errno));
  exit (1);
}

static void
on_signal (int signal_number)
{
  signal_seen = signal_number;
}

static void *
thread_main (void *argument)
{
  if (pthread_setspecific (tls_key, argument) != 0)
    return NULL;
  return pthread_getspecific (tls_key);
}

static void
expect_child_ok (pid_t pid, const char *operation)
{
  int status;
  if (waitpid (pid, &status, 0) != pid || !WIFEXITED (status)
      || WEXITSTATUS (status) != 0)
    {
      errno = ECHILD;
      fail (operation);
    }
}

int
main (int argc, char **argv)
{
  char cwd[1024];
  char buffer[32] = { 0 };
  char converted_path[1024];
  int pipe_fds[2];
  int socket_fds[2];
  pthread_t thread;
  void *thread_result = NULL;
  pid_t child;
  pid_t spawned;
  struct stat first;
  struct stat second;
  char *spawn_argv[] = { "/cmd/git.exe", "--version", NULL };

  if (argc != 2)
    {
      fprintf (stderr, "usage: runtime-smoke WINDOWS-PATH\n");
      return 2;
    }
  if (!getcwd (cwd, sizeof cwd))
    fail ("getcwd");
  if (strncmp (cwd, "/usr/bin", 8) != 0)
    {
      fprintf (stderr, "runtime-smoke: unexpected cwd %s\n", cwd);
      return 1;
    }
  if (cygwin_conv_path (CCP_WIN_A_TO_POSIX, argv[1], converted_path,
                        sizeof converted_path) != 0
      || strncmp (converted_path, "/tmp/", 5) != 0)
    {
      fprintf (stderr, "runtime-smoke: path conversion failed: %s -> %s\n",
               argv[1], converted_path);
      return 1;
    }
  if (!setlocale (LC_ALL, "C") || strcmp (setlocale (LC_ALL, NULL), "C") != 0)
    {
      fprintf (stderr, "runtime-smoke: C locale baseline failed\n");
      return 1;
    }

  if (pthread_key_create (&tls_key, NULL) != 0
      || pthread_create (&thread, NULL, thread_main, (void *) 42) != 0
      || pthread_join (thread, &thread_result) != 0
      || thread_result != (void *) 42)
    fail ("pthread TLS");
  pthread_key_delete (tls_key);

  if (pipe (pipe_fds) != 0)
    fail ("pipe");
  child = fork ();
  if (child < 0)
    fail ("fork");
  if (child == 0)
    {
      close (pipe_fds[0]);
      if (write (pipe_fds[1], "fork", 4) != 4)
        _exit (1);
      _exit (0);
    }
  close (pipe_fds[1]);
  if (read (pipe_fds[0], buffer, sizeof buffer) != 4 || strcmp (buffer, "fork"))
    fail ("pipe read");
  expect_child_ok (child, "fork wait");

  if (signal (SIGUSR1, on_signal) == SIG_ERR || raise (SIGUSR1) != 0
      || signal_seen != SIGUSR1)
    fail ("signal");

  if (socketpair (AF_UNIX, SOCK_STREAM, 0, socket_fds) != 0)
    fail ("socketpair");
  if (write (socket_fds[0], "socket", 6) != 6
      || read (socket_fds[1], buffer, sizeof buffer) != 6
      || strncmp (buffer, "socket", 6))
    fail ("socketpair I/O");

  unlink ("/tmp/runtime-smoke-hardlink");
  unlink ("/tmp/runtime-smoke-symlink");
  unlink ("/tmp/runtime-smoke-file");
  int fd = open ("/tmp/runtime-smoke-file", O_CREAT | O_WRONLY | O_TRUNC, 0600);
  if (fd < 0 || write (fd, "data", 4) != 4 || close (fd) != 0)
    fail ("file I/O");
  if (link ("/tmp/runtime-smoke-file", "/tmp/runtime-smoke-hardlink") != 0
      || stat ("/tmp/runtime-smoke-file", &first) != 0
      || stat ("/tmp/runtime-smoke-hardlink", &second) != 0
      || first.st_ino != second.st_ino)
    fail ("hardlink");
  if (symlink ("runtime-smoke-file", "/tmp/runtime-smoke-symlink") != 0
      || lstat ("/tmp/runtime-smoke-symlink", &second) != 0
      || !S_ISLNK (second.st_mode))
    fail ("symlink");

  if (posix_spawn (&spawned, spawn_argv[0], NULL, NULL, spawn_argv, environ) != 0)
    fail ("posix_spawn");
  expect_child_ok (spawned, "spawn wait");

  child = fork ();
  if (child < 0)
    fail ("SEH fork");
  if (child == 0)
    {
      volatile int *bad = NULL;
      *bad = 1;
      _exit (1);
    }
  int seh_status;
  if (waitpid (child, &seh_status, 0) != child || !WIFSIGNALED (seh_status)
      || WTERMSIG (seh_status) != SIGSEGV)
    {
      fprintf (stderr, "runtime-smoke: SEH did not map to SIGSEGV\n");
      return 1;
    }

  printf ("runtime-smoke: cwd=%s pthread=42 fork=fork signal=%d socket=socket "
          "files=ok spawn=ok seh=SIGSEGV locale=C path=%s\n",
          cwd, signal_seen, converted_path);
  return 0;
}
