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

static void
mark (const char *label)
{
  fprintf (stderr, "%s\n", label);
  fflush (stderr);
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

  mark ("diag: inode probe start");
  mark ("diag: inode server socket before");
  server = socket (AF_INET, SOCK_STREAM, 0);
  mark ("diag: inode server socket after");
  if (server < 0)
    return fail_socket (11, "inode server socket");
  mark ("diag: inode server fstat before");
  if (!socket_ino (server, &server_ino))
    return fail_socket (12, "inode server fstat");
  mark ("diag: inode server fstat after");
  mark ("diag: inode client socket before");
  client = socket (AF_INET, SOCK_STREAM, 0);
  mark ("diag: inode client socket after");
  if (client < 0)
    return fail_socket (13, "inode client socket");
  mark ("diag: inode client fstat before");
  if (!socket_ino (client, &client_ino))
    return fail_socket (14, "inode client fstat");
  mark ("diag: inode client fstat after");
  if (server_ino == client_ino)
    return 15;
  mark ("diag: inode client close before");
  if (close (client) != 0)
    return fail_socket (16, "inode client close");
  mark ("diag: inode client close after");
  mark ("diag: inode server close before");
  if (close (server) != 0)
    return fail_socket (17, "inode server close");
  mark ("diag: inode server close after");

  mark ("diag: socketpair probe start");
  mark ("diag: socketpair before");
  if (socketpair (AF_UNIX, SOCK_STREAM, 0, fds) != 0)
    return fail_socket (18, "socketpair");
  mark ("diag: socketpair after");
  server = fds[0];
  client = fds[1];

  mark ("diag: socketpair send ping before");
  if (send (client, ping, sizeof (ping), 0) != (int) sizeof (ping))
    return fail_socket (19, "send ping");
  mark ("diag: socketpair send ping after");
  mark ("diag: socketpair recv ping before");
  if (recv (server, buf, sizeof (ping), 0) != (int) sizeof (ping))
    return fail_socket (20, "recv ping");
  mark ("diag: socketpair recv ping after");
  if (memcmp (buf, ping, sizeof (ping)) != 0)
    return 21;

  mark ("diag: socketpair send pong before");
  if (send (server, pong, sizeof (pong), 0) != (int) sizeof (pong))
    return fail_socket (22, "send pong");
  mark ("diag: socketpair send pong after");
  mark ("diag: socketpair recv pong before");
  if (recv (client, buf, sizeof (pong), 0) != (int) sizeof (pong))
    return fail_socket (23, "recv pong");
  mark ("diag: socketpair recv pong after");
  if (memcmp (buf, pong, sizeof (pong)) != 0)
    return 24;

  mark ("diag: socketpair client close before");
  if (close (client) != 0)
    return fail_socket (25, "socketpair client close");
  mark ("diag: socketpair client close after");
  mark ("diag: socketpair server close before");
  if (close (server) != 0)
    return fail_socket (26, "socketpair server close");
  mark ("diag: socketpair server close after");

  return 0;
}
