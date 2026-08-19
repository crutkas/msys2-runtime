#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <time.h>
#include <ucontext.h>
#include <string.h>
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

static int
socket_ino (int sock, ino_t *ino)
{
  struct stat st;

  if (fstat (sock, &st) != 0)
    return 0;
  *ino = st.st_ino;
  return st.st_ino != 0;
}

static int
fail_socket (int code, const char *stage)
{
  fprintf (stderr, "%s failed: errno %d\n", stage, errno);
  return code;
}

int
main (void)
{
  struct sigaction action = {};
  struct timespec now;
  struct utsname name;
  ucontext_t context;
  pthread_t thread;
  int thread_value = 0;
  int server;
  int client;
  int fds[2];
  ino_t server_ino;
  ino_t client_ino;
  char buf[8] = {};
  const char ping[] = "ping";
  const char pong[] = "pong";

  if (getpid () <= 0)
    return 1;
  if (sysconf (_SC_PAGESIZE) <= 0 || sysconf (_SC_NPROCESSORS_ONLN) <= 0)
    return 2;
  if (uname (&name) != 0 || !name.machine[0])
    return 3;
  if (clock_gettime (CLOCK_MONOTONIC, &now) != 0)
    return 4;
  if (getcontext (&context) != 0)
    return 5;

  if (pthread_create (&thread, NULL, thread_main, &thread_value) != 0)
    return 6;
  if (pthread_join (thread, NULL) != 0)
    return 7;
  if (thread_value != 29 || tls_value != 17)
    return 8;

  action.sa_handler = signal_handler;
  sigemptyset (&action.sa_mask);
  if (sigaction (SIGUSR1, &action, NULL) != 0)
    return 9;
  if (raise (SIGUSR1) != 0 || signal_seen != SIGUSR1)
    return 10;

  if (socketpair (AF_UNIX, SOCK_STREAM, 0, fds) != 0)
    return fail_socket (11, "socketpair");
  server = fds[0];
  client = fds[1];

  if (!socket_ino (server, &server_ino)
      || !socket_ino (client, &client_ino)
      || server_ino == client_ino)
    return 12;

  if (send (client, ping, sizeof (ping), 0) != (int) sizeof (ping))
    return fail_socket (13, "send ping");
  if (recv (server, buf, sizeof (ping), 0) != (int) sizeof (ping))
    return fail_socket (14, "recv ping");
  if (memcmp (buf, ping, sizeof (ping)) != 0)
    return 15;

  if (send (server, pong, sizeof (pong), 0) != (int) sizeof (pong))
    return fail_socket (16, "send pong");
  if (recv (client, buf, sizeof (pong), 0) != (int) sizeof (pong))
    return fail_socket (17, "recv pong");
  if (memcmp (buf, pong, sizeof (pong)) != 0)
    return 18;

  if (close (client) != 0)
    return 19;
  if (close (server) != 0)
    return 20;

  return 0;
}
