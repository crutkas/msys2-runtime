#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <netinet/in.h>
#include <netdb.h>
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
  int accepted;
  int rc;
  ino_t server_ino;
  ino_t client_ino;
  ino_t accepted_ino;
  struct sockaddr_in peer = {};
  struct sockaddr_in bound = {};
  struct addrinfo hints = {};
  struct addrinfo *bindinfo = NULL;
  struct addrinfo *connectinfo = NULL;
  socklen_t addrlen = sizeof (peer);
  char port[16];
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

  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  hints.ai_flags = AI_PASSIVE;
  if (getaddrinfo (NULL, "0", &hints, &bindinfo) != 0 || !bindinfo)
    return 13;
  if (bind (server, bindinfo->ai_addr, (int) bindinfo->ai_addrlen) != 0)
    {
      freeaddrinfo (bindinfo);
      return fail_socket (13, "bind");
    }
  freeaddrinfo (bindinfo);
  if (listen (server, 1) != 0)
    return fail_socket (14, "listen");
  if (getsockname (server, (struct sockaddr *) &bound, &addrlen) != 0)
    return 15;
  snprintf (port, sizeof (port), "%u", ntohs (bound.sin_port));
  if (getaddrinfo ("127.0.0.1", port, &hints, &connectinfo) != 0
      || !connectinfo)
    return fail_socket (16, "connect addrinfo");
  if (connect (client, connectinfo->ai_addr, (int) connectinfo->ai_addrlen) != 0)
    {
      freeaddrinfo (connectinfo);
      return fail_socket (16, "connect");
    }
  freeaddrinfo (connectinfo);
  addrlen = sizeof (peer);
  accepted = accept (server, (struct sockaddr *) &peer, &addrlen);
  if (accepted < 0)
    return fail_socket (17, "accept");
  if (!socket_ino (server, &server_ino)
      || !socket_ino (client, &client_ino)
      || !socket_ino (accepted, &accepted_ino)
      || server_ino == client_ino
      || server_ino == accepted_ino
      || client_ino == accepted_ino)
    return 18;

  if (send (client, ping, sizeof (ping), 0) != (int) sizeof (ping))
    return fail_socket (19, "send ping");
  rc = wait_readable (accepted);
  if (rc != 1)
    return fail_socket (20, "select accepted");
  if (recv (accepted, buf, sizeof (ping), 0) != (int) sizeof (ping))
    return fail_socket (21, "recv ping");
  if (memcmp (buf, ping, sizeof (ping)) != 0)
    return 22;

  if (send (accepted, pong, sizeof (pong), 0) != (int) sizeof (pong))
    return fail_socket (23, "send pong");
  rc = wait_readable (client);
  if (rc != 1)
    return fail_socket (24, "select client");
  if (recv (client, buf, sizeof (pong), 0) != (int) sizeof (pong))
    return fail_socket (25, "recv pong");
  if (memcmp (buf, pong, sizeof (pong)) != 0)
    return 26;

  if (close (accepted) != 0)
    return 27;
  if (close (client) != 0)
    return 28;
  if (close (server) != 0)
    return 29;

  return 0;
}
