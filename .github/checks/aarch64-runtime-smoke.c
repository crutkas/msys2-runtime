#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <netinet/in.h>
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
wait_readable (int sock)
{
  fd_set rfds;
  struct timeval tv = { 5, 0 };

  FD_ZERO (&rfds);
  FD_SET (sock, &rfds);
  return select (sock + 1, &rfds, NULL, NULL, &tv);
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
  int pair[2];
  int rc;
  ino_t server_ino;
  ino_t client_ino;
  ino_t pair0_ino;
  ino_t pair1_ino;
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

  server = socket (AF_INET, SOCK_STREAM, 0);
  client = socket (AF_INET, SOCK_STREAM, 0);
  if (server < 0 || client < 0)
    return 11;

  if (!socket_ino (server, &server_ino)
      || !socket_ino (client, &client_ino)
      || server_ino == client_ino)
    return 12;

  if (socketpair (AF_UNIX, SOCK_STREAM, 0, pair) != 0)
    return fail_socket (13, "socketpair");
  if (!socket_ino (pair[0], &pair0_ino)
      || !socket_ino (pair[1], &pair1_ino)
      || pair0_ino == pair1_ino)
    return 14;
  if (!socket_ino (server, &server_ino)
      || !socket_ino (client, &client_ino)
      || server_ino == pair0_ino
      || server_ino == pair1_ino
      || client_ino == pair0_ino
      || client_ino == pair1_ino)
    return 15;

  if (send (pair[0], ping, sizeof (ping), 0) != (int) sizeof (ping))
    return fail_socket (16, "send ping");
  rc = wait_readable (pair[1]);
  if (rc != 1)
    return fail_socket (17, "select pair1");
  if (recv (pair[1], buf, sizeof (ping), 0) != (int) sizeof (ping))
    return fail_socket (18, "recv ping");
  if (memcmp (buf, ping, sizeof (ping)) != 0)
    return 19;

  if (send (pair[1], pong, sizeof (pong), 0) != (int) sizeof (pong))
    return fail_socket (20, "send pong");
  rc = wait_readable (pair[0]);
  if (rc != 1)
    return fail_socket (21, "select pair0");
  if (recv (pair[0], buf, sizeof (pong), 0) != (int) sizeof (pong))
    return fail_socket (22, "recv pong");
  if (memcmp (buf, pong, sizeof (pong)) != 0)
    return 23;

  if (close (pair[1]) != 0)
    return 24;
  if (close (pair[0]) != 0)
    return 25;
  if (close (client) != 0)
    return 26;
  if (close (server) != 0)
    return 27;

  return 0;
}
