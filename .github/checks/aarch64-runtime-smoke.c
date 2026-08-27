#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/utsname.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>

/* Exercise Cygwin's own pthread-key TLS implementation rather than
   compiler-emitted __thread storage: the latter requires the
   toolchain's libgcc to provide __emutls_get_address (or native PE
   TLS relocations), which is a cross-compiler/libgcc concern outside
   this runtime, not something Cygwin itself implements. Per-thread
   isolation via pthread_key_t/pthread_setspecific/pthread_getspecific
   is implemented directly by this runtime and is what this probe
   means to validate.  */
static pthread_key_t tls_key;
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
  static int child_slot = 29;

  pthread_setspecific (tls_key, &child_slot);
  *result = *(int *) pthread_getspecific (tls_key);
  return NULL;
}

int
main (void)
{
  struct sigaction action = {};
  struct timespec now;
  struct utsname name;
  ucontext_t context;
  pthread_t thread;
  int main_slot = 17;
  int thread_value = 0;
  int sock;

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

  if (pthread_key_create (&tls_key, NULL) != 0)
    return 6;
  if (pthread_setspecific (tls_key, &main_slot) != 0)
    return 6;
  if (pthread_create (&thread, NULL, thread_main, &thread_value) != 0)
    return 6;
  if (pthread_join (thread, NULL) != 0)
    return 7;
  if (thread_value != 29 || *(int *) pthread_getspecific (tls_key) != 17)
    return 8;

  action.sa_handler = signal_handler;
  sigemptyset (&action.sa_mask);
  if (sigaction (SIGUSR1, &action, NULL) != 0)
    return 9;
  if (raise (SIGUSR1) != 0 || signal_seen != SIGUSR1)
    return 10;

  sock = socket (AF_INET, SOCK_STREAM, 0);
  if (sock < 0)
    return 11;
  if (close (sock) != 0)
    return 12;

  return 0;
}
