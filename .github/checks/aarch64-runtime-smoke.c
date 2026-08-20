#include <pthread.h>
#include <signal.h>
#include <errno.h>
#include <stdio.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <time.h>
#include <ucontext.h>
#include <string.h>
#include <unistd.h>

static __thread int tls_value = 17;
static volatile sig_atomic_t signal_seen;
static char ping[] = "ping";
static char pong[] = "pong";

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
  ino_t server_ino;
  ino_t client_ino;
  char buf[8] = {};

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

  mark ("diag: loopback probe start");
  mark ("diag: loopback server socket before");
  server = socket (AF_INET, SOCK_DGRAM, 0);
  mark ("diag: loopback server socket after");
  if (server < 0)
    return fail_socket (18, "loopback server socket");
  struct sockaddr_in server_addr = {};
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = htonl (INADDR_LOOPBACK);
  server_addr.sin_port = 0;
  mark ("diag: loopback server bind before");
  if (bind (server, (struct sockaddr *) &server_addr,
	    sizeof (server_addr)) != 0)
    return fail_socket (19, "loopback server bind");
  mark ("diag: loopback server bind after");
  mark ("diag: loopback server getsockname before");
  socklen_t server_len = sizeof (server_addr);
  if (getsockname (server, (struct sockaddr *) &server_addr, &server_len) != 0)
    return fail_socket (20, "loopback server getsockname");
  mark ("diag: loopback server getsockname after");

  mark ("diag: loopback client socket before");
  client = socket (AF_INET, SOCK_DGRAM, 0);
  mark ("diag: loopback client socket after");
  if (client < 0)
    return fail_socket (21, "loopback client socket");
  struct sockaddr_in client_addr = {};
  client_addr.sin_family = AF_INET;
  client_addr.sin_addr.s_addr = htonl (INADDR_LOOPBACK);
  client_addr.sin_port = 0;
  mark ("diag: loopback client bind before");
  if (bind (client, (struct sockaddr *) &client_addr,
	    sizeof (client_addr)) != 0)
    return fail_socket (22, "loopback client bind");
  mark ("diag: loopback client bind after");
  mark ("diag: loopback client getsockname before");
  socklen_t client_len = sizeof (client_addr);
  if (getsockname (client, (struct sockaddr *) &client_addr, &client_len) != 0)
    return fail_socket (23, "loopback client getsockname");
  mark ("diag: loopback client getsockname after");

  mark ("diag: loopback write ping before");
  if (sendto (client, ping, sizeof (ping), 0,
	      (struct sockaddr *) &server_addr, sizeof (server_addr))
      != (int) sizeof (ping))
    return fail_socket (24, "write ping");
  mark ("diag: loopback write ping after");
  mark ("diag: loopback read ping before");
  struct sockaddr_in peer = {};
  socklen_t peer_len = sizeof (peer);
  if (recvfrom (server, buf, sizeof (ping), 0,
		(struct sockaddr *) &peer, &peer_len) != (int) sizeof (ping))
    return fail_socket (25, "read ping");
  mark ("diag: loopback read ping after");
  if (memcmp (buf, ping, sizeof (ping)) != 0)
    return 26;

  mark ("diag: loopback write pong before");
  if (sendto (server, pong, sizeof (pong), 0,
	      (struct sockaddr *) &client_addr, sizeof (client_addr))
      != (int) sizeof (pong))
    return fail_socket (27, "write pong");
  mark ("diag: loopback write pong after");
  mark ("diag: loopback read pong before");
  peer_len = sizeof (peer);
  if (recvfrom (client, buf, sizeof (pong), 0,
		(struct sockaddr *) &peer, &peer_len) != (int) sizeof (pong))
    return fail_socket (28, "read pong");
  mark ("diag: loopback read pong after");
  if (memcmp (buf, pong, sizeof (pong)) != 0)
    return 29;

  mark ("diag: loopback client close before");
  if (close (client) != 0)
    return fail_socket (30, "loopback client close");
  mark ("diag: loopback client close after");
  mark ("diag: loopback server close before");
  if (close (server) != 0)
    return fail_socket (31, "loopback server close");
  mark ("diag: loopback server close after");

  return 0;
}
