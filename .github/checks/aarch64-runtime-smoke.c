#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <netdb.h>
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
  int accepted;
  int rc;
  ino_t server_ino;
  ino_t client_ino;
  ino_t accepted_ino;
  struct sockaddr_storage server_storage = {};
  struct sockaddr_storage peer = {};
  struct addrinfo hints = {};
  struct addrinfo *resolved = NULL;
  struct addrinfo *ai = NULL;
  socklen_t server_addrlen;
  socklen_t addrlen = sizeof (peer);
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

  hints.ai_family = AF_INET6;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;
  if (getaddrinfo ("::1", "0", &hints, &resolved) != 0)
    return 11;
  for (ai = resolved; ai; ai = ai->ai_next)
    if (ai->ai_family == AF_INET6
        && ai->ai_socktype == SOCK_STREAM
        && ai->ai_addrlen <= sizeof (server_storage))
      break;
  if (!ai)
    {
      freeaddrinfo (resolved);
      return 12;
    }

  server = socket (AF_INET6, SOCK_STREAM, 0);
  client = socket (AF_INET6, SOCK_STREAM, 0);
  if (server < 0 || client < 0)
    {
      freeaddrinfo (resolved);
      return 13;
    }

  if (!socket_ino (server, &server_ino)
      || !socket_ino (client, &client_ino)
      || server_ino == client_ino)
    {
      freeaddrinfo (resolved);
      return 14;
    }

  {
    int on = 1;
    if (setsockopt (server, SOL_SOCKET, SO_REUSEADDR,
                    &on, sizeof (on)) != 0)
      {
        freeaddrinfo (resolved);
        return fail_socket (15, "setsockopt SO_REUSEADDR");
      }
  }
  if (bind (server, ai->ai_addr, (socklen_t) ai->ai_addrlen) != 0)
    {
      freeaddrinfo (resolved);
      return fail_socket (16, "bind");
    }
  server_addrlen = sizeof (server_storage);
  if (getsockname (server, (struct sockaddr *) &server_storage, &server_addrlen) != 0)
    {
      freeaddrinfo (resolved);
      return fail_socket (17, "getsockname");
    }
  if (server_addrlen != ai->ai_addrlen)
    {
      freeaddrinfo (resolved);
      return 18;
    }
  if (listen (server, 1) != 0)
    {
      freeaddrinfo (resolved);
      return fail_socket (19, "listen");
    }
  if (connect (client, ai->ai_addr, (socklen_t) ai->ai_addrlen) != 0)
    {
      freeaddrinfo (resolved);
      return fail_socket (20, "connect");
    }
  accepted = accept (server, (struct sockaddr *) &peer, &addrlen);
  if (accepted < 0)
    {
      freeaddrinfo (resolved);
      return fail_socket (21, "accept");
    }
  if (!socket_ino (accepted, &accepted_ino)
      || !socket_ino (server, &server_ino)
      || !socket_ino (client, &client_ino)
      || server_ino == client_ino
      || server_ino == accepted_ino
      || client_ino == accepted_ino)
    {
      freeaddrinfo (resolved);
      return 22;
    }

  if (send (client, ping, sizeof (ping), 0) != (int) sizeof (ping))
    {
      freeaddrinfo (resolved);
      return fail_socket (23, "send ping");
    }
  rc = wait_readable (accepted);
  if (rc != 1)
    {
      freeaddrinfo (resolved);
      return fail_socket (24, "select accepted");
    }
  if (recv (accepted, buf, sizeof (ping), 0) != (int) sizeof (ping))
    {
      freeaddrinfo (resolved);
      return fail_socket (25, "recv ping");
    }
  if (memcmp (buf, ping, sizeof (ping)) != 0)
    {
      freeaddrinfo (resolved);
      return 26;
    }

  if (send (accepted, pong, sizeof (pong), 0) != (int) sizeof (pong))
    {
      freeaddrinfo (resolved);
      return fail_socket (27, "send pong");
    }
  rc = wait_readable (client);
  if (rc != 1)
    {
      freeaddrinfo (resolved);
      return fail_socket (28, "select client");
    }
  if (recv (client, buf, sizeof (pong), 0) != (int) sizeof (pong))
    {
      freeaddrinfo (resolved);
      return fail_socket (29, "recv pong");
    }
  if (memcmp (buf, pong, sizeof (pong)) != 0)
    {
      freeaddrinfo (resolved);
      return 30;
    }

  if (close (accepted) != 0)
    {
      freeaddrinfo (resolved);
      return 31;
    }
  if (close (client) != 0)
    {
      freeaddrinfo (resolved);
      return 32;
    }
  if (close (server) != 0)
    {
      freeaddrinfo (resolved);
      return 33;
    }
  freeaddrinfo (resolved);

  return 0;
}
