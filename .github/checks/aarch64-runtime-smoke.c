#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/utsname.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>

static __thread int tls_value = 17;
static volatile sig_atomic_t signal_seen;

static void
signal_handler (int sig)
{
  signal_seen = sig;
}

static void *
thread_main (void *arg)
{
  int *result = (int *) arg;

  tls_value = 29;
  *result = tls_value;
  return NULL;
}

int
main (int argc, char **argv)
{
  struct sigaction action = {};
  struct timespec now;
  struct utsname name;
  ucontext_t context;
  pthread_t thread;
  pid_t child;
  int thread_value = 0;
  int status;
  int sock;

  if (argc != 3 || strcmp (argv[1], "plain-argument") != 0
      || strcmp (argv[2], "argument with spaces") != 0)
    return 1;
  if (getpid () <= 0)
    return 2;
  if (sysconf (_SC_PAGESIZE) <= 0 || sysconf (_SC_NPROCESSORS_ONLN) <= 0)
    return 3;
  if (uname (&name) != 0 || !name.machine[0])
    return 4;
  if (clock_gettime (CLOCK_MONOTONIC, &now) != 0)
    return 5;
  if (getcontext (&context) != 0)
    return 6;

  if (pthread_create (&thread, NULL, thread_main, &thread_value) != 0)
    return 7;
  if (pthread_join (thread, NULL) != 0)
    return 8;
  if (thread_value != 29 || tls_value != 17)
    return 9;

  action.sa_handler = signal_handler;
  sigemptyset (&action.sa_mask);
  if (sigaction (SIGUSR1, &action, NULL) != 0)
    return 10;
  if (raise (SIGUSR1) != 0 || signal_seen != SIGUSR1)
    return 11;

  sock = socket (AF_INET, SOCK_STREAM, 0);
  if (sock < 0)
    return 12;
  if (close (sock) != 0)
    return 13;

  child = fork ();
  if (child < 0)
    return 14;
  if (child == 0)
    _exit (argc == 3 && strcmp (argv[2], "argument with spaces") == 0 ? 0 : 15);
  if (waitpid (child, &status, 0) != child)
    return 16;
  if (!WIFEXITED (status) || WEXITSTATUS (status) != 0)
    return 17;

  puts ("aarch64-runtime-smoke=pass");
  return 0;
}
