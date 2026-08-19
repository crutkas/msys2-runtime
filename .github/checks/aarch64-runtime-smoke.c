#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <sys/socket.h>
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
fail_socket (int code, const char *stage)
{
  fprintf (stderr, "%s failed: errno %d\n", stage, errno);
  return code;
}

static int
fail_gai (int code, const char *host, int rc)
{
  fprintf (stderr, "getaddrinfo %s failed: %s\n", host, gai_strerror (rc));
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
  ino_t server_ino;
  ino_t client_ino;
  struct sockaddr_storage server_storage = {};
  struct sockaddr_storage peer = {};
  struct addrinfo hints = {};
  struct addrinfo *resolved = NULL;
  struct addrinfo *ai = NULL;
  socklen_t server_addrlen;
  socklen_t addrlen = sizeof (peer);
  struct timeval timeout = { 5, 0 };
  char buf[8] = {};
  const char ping[] = "ping";
  const char pong[] = "pong";
  const char *loopback_hosts[] = { "::1", "127.0.0.1" };
  const int loopback_families[] = { AF_INET6, AF_INET };
  const size_t loopback_count = sizeof (loopback_hosts) / sizeof (loopback_hosts[0]);

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

  hints.ai_socktype = SOCK_DGRAM;
  hints.ai_flags = AI_NUMERICHOST;
  for (size_t i = 0; i < loopback_count; ++i)
    {
      int gai_rc;

      hints.ai_family = loopback_families[i];
      gai_rc = getaddrinfo (loopback_hosts[i], "0", &hints, &resolved);
      if (gai_rc != 0)
        {
          if (i + 1 == loopback_count)
            return fail_gai (11, loopback_hosts[i], gai_rc);
          continue;
        }
      for (ai = resolved; ai; ai = ai->ai_next)
        if (ai->ai_family == loopback_families[i]
            && ai->ai_socktype == SOCK_DGRAM
            && ai->ai_addrlen <= sizeof (server_storage))
          break;
      if (ai)
        break;
      if (i + 1 == loopback_count)
        return 11;
      freeaddrinfo (resolved);
      resolved = NULL;
    }
  if (!ai)
    return 11;

  server = socket (ai->ai_family, SOCK_DGRAM, ai->ai_protocol);
  client = socket (ai->ai_family, SOCK_DGRAM, ai->ai_protocol);
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

  if (setsockopt (server, SOL_SOCKET, SO_RCVTIMEO,
                  &timeout, sizeof (timeout)) != 0
      || setsockopt (client, SOL_SOCKET, SO_RCVTIMEO,
                     &timeout, sizeof (timeout)) != 0)
    {
      freeaddrinfo (resolved);
      return fail_socket (15, "setsockopt SO_RCVTIMEO");
    }

  {
    int on = 1;
    if (setsockopt (server, SOL_SOCKET, SO_REUSEADDR,
                    &on, sizeof (on)) != 0)
      {
        freeaddrinfo (resolved);
        return fail_socket (16, "setsockopt SO_REUSEADDR");
      }
  }
  if (bind (server, ai->ai_addr, (socklen_t) ai->ai_addrlen) != 0)
    {
      freeaddrinfo (resolved);
      return fail_socket (17, "bind");
    }
  server_addrlen = sizeof (server_storage);
  if (getsockname (server, (struct sockaddr *) &server_storage, &server_addrlen) != 0)
    {
      freeaddrinfo (resolved);
      return fail_socket (18, "getsockname");
    }
  if (server_addrlen != ai->ai_addrlen)
    {
      freeaddrinfo (resolved);
      return 19;
    }
  if (!socket_ino (client, &client_ino)
      || server_ino == client_ino)
    {
      freeaddrinfo (resolved);
      return 20;
    }

  if (sendto (client, ping, sizeof (ping), 0,
              (struct sockaddr *) &server_storage,
              (socklen_t) server_addrlen) != (int) sizeof (ping))
    {
      freeaddrinfo (resolved);
      return fail_socket (21, "sendto ping");
    }
  addrlen = sizeof (peer);
  if (recvfrom (server, buf, sizeof (ping), 0,
                (struct sockaddr *) &peer, &addrlen) != (int) sizeof (ping))
    {
      freeaddrinfo (resolved);
      return fail_socket (22, "recvfrom ping");
    }
  if (memcmp (buf, ping, sizeof (ping)) != 0)
    {
      freeaddrinfo (resolved);
      return 23;
    }

  if (sendto (server, pong, sizeof (pong), 0,
              (struct sockaddr *) &peer, addrlen) != (int) sizeof (pong))
    {
      freeaddrinfo (resolved);
      return fail_socket (24, "sendto pong");
    }
  addrlen = sizeof (server_storage);
  if (recvfrom (client, buf, sizeof (pong), 0,
                (struct sockaddr *) &server_storage, &addrlen) != (int) sizeof (pong))
    {
      freeaddrinfo (resolved);
      return fail_socket (25, "recvfrom pong");
    }
  if (memcmp (buf, pong, sizeof (pong)) != 0)
    {
      freeaddrinfo (resolved);
      return 26;
    }

  if (close (client) != 0)
    {
      freeaddrinfo (resolved);
      return 27;
    }
  if (close (server) != 0)
    {
      freeaddrinfo (resolved);
      return 28;
    }
  freeaddrinfo (resolved);

  return 0;
}
