#include <errno.h>
#include <pthread.h>
#include <stdint.h>

#if !defined(__aarch64__)
#error This check must be compiled for AArch64
#endif

#define EXPORT __attribute__ ((dllexport))

#ifdef __cplusplus
#define CONSTINIT constinit
extern "C"
{
#else
#define CONSTINIT
#endif

EXPORT CONSTINIT pthread_mutex_t abi_default_mutex = PTHREAD_MUTEX_INITIALIZER;
EXPORT CONSTINIT pthread_mutex_t abi_recursive_mutex =
  PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
EXPORT CONSTINIT pthread_mutex_t abi_normal_mutex =
  PTHREAD_NORMAL_MUTEX_INITIALIZER_NP;
EXPORT CONSTINIT pthread_mutex_t abi_errorcheck_mutex =
  PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP;
EXPORT CONSTINIT pthread_cond_t abi_condition = PTHREAD_COND_INITIALIZER;
EXPORT CONSTINIT pthread_rwlock_t abi_rwlock = PTHREAD_RWLOCK_INITIALIZER;
EXPORT CONSTINIT pthread_once_t abi_once = PTHREAD_ONCE_INIT;

EXPORT pthread_mutex_t
abi_default_mutex_value (void)
{
  return PTHREAD_MUTEX_INITIALIZER;
}

EXPORT pthread_mutex_t
abi_recursive_mutex_value (void)
{
  return PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
}

EXPORT pthread_mutex_t
abi_normal_mutex_value (void)
{
  return PTHREAD_NORMAL_MUTEX_INITIALIZER_NP;
}

EXPORT pthread_mutex_t
abi_errorcheck_mutex_value (void)
{
  return PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP;
}

EXPORT pthread_cond_t
abi_condition_value (void)
{
  return PTHREAD_COND_INITIALIZER;
}

EXPORT pthread_rwlock_t
abi_rwlock_value (void)
{
  return PTHREAD_RWLOCK_INITIALIZER;
}

EXPORT const char *
abi_normal_mutex_plus_one (void)
{
  return (const char *)
    ((uintptr_t) PTHREAD_NORMAL_MUTEX_INITIALIZER_NP + 1);
}

EXPORT const char *
abi_normal_mutex_plus_page (void)
{
  return (const char *)
    ((uintptr_t) PTHREAD_NORMAL_MUTEX_INITIALIZER_NP + 0x1000);
}

EXPORT const char *
abi_normal_mutex_minus_one (void)
{
  return (const char *)
    ((uintptr_t) PTHREAD_NORMAL_MUTEX_INITIALIZER_NP - 1);
}

EXPORT const char *
abi_normal_mutex_minus_page (void)
{
  return (const char *)
    ((uintptr_t) PTHREAD_NORMAL_MUTEX_INITIALIZER_NP - 0x1000);
}

EXPORT int
abi_default_mutex_round_trip (void)
{
  int ret = pthread_mutex_lock (&abi_default_mutex);

  return ret ? ret : pthread_mutex_unlock (&abi_default_mutex);
}

#ifdef ABI_RUNTIME_TEST

static int once_calls;

static void
once_callback (void)
{
  ++once_calls;
}

static int
exercise_initializers (pthread_mutex_t *default_mutex,
		       pthread_mutex_t *normal_mutex,
		       pthread_mutex_t *recursive_mutex,
		       pthread_mutex_t *errorcheck_mutex,
		       pthread_cond_t *condition,
		       pthread_rwlock_t *rwlock,
		       pthread_once_t *once)
{
  const struct timespec expired = { 0, 0 };

  if (pthread_mutex_lock (default_mutex) != 0)
    return 1;
  if (pthread_cond_timedwait (condition, default_mutex, &expired) != ETIMEDOUT)
    return 2;
  if (pthread_mutex_unlock (default_mutex) != 0)
    return 3;
  if (pthread_cond_destroy (condition) != 0)
    return 4;
  if (pthread_mutex_destroy (default_mutex) != 0)
    return 5;

  if (pthread_mutex_lock (normal_mutex) != 0
      || pthread_mutex_unlock (normal_mutex) != 0
      || pthread_mutex_destroy (normal_mutex) != 0)
    return 6;

  if (pthread_mutex_lock (recursive_mutex) != 0
      || pthread_mutex_lock (recursive_mutex) != 0
      || pthread_mutex_unlock (recursive_mutex) != 0
      || pthread_mutex_unlock (recursive_mutex) != 0
      || pthread_mutex_destroy (recursive_mutex) != 0)
    return 7;

  if (pthread_mutex_lock (errorcheck_mutex) != 0
      || pthread_mutex_lock (errorcheck_mutex) != EDEADLK
      || pthread_mutex_unlock (errorcheck_mutex) != 0
      || pthread_mutex_destroy (errorcheck_mutex) != 0)
    return 8;

  if (pthread_rwlock_rdlock (rwlock) != 0
      || pthread_rwlock_unlock (rwlock) != 0
      || pthread_rwlock_wrlock (rwlock) != 0
      || pthread_rwlock_unlock (rwlock) != 0
      || pthread_rwlock_destroy (rwlock) != 0)
    return 9;

  once_calls = 0;
  if (pthread_once (once, once_callback) != 0
      || pthread_once (once, once_callback) != 0
      || once_calls != 1)
    return 10;

  return 0;
}

int
main (void)
{
  const uintptr_t initializers[] = {
    (uintptr_t) abi_recursive_mutex,
    (uintptr_t) abi_normal_mutex,
    (uintptr_t) abi_errorcheck_mutex,
    (uintptr_t) abi_condition,
    (uintptr_t) abi_rwlock
  };

  if (abi_default_mutex != abi_normal_mutex
      || abi_once.mutex != abi_normal_mutex
      || abi_once.state != 0)
    return 1;
  for (size_t i = 0; i < sizeof initializers / sizeof initializers[0]; ++i)
    {
      if (initializers[i] == 0)
	return 1;
      for (size_t j = i + 1;
	   j < sizeof initializers / sizeof initializers[0]; ++j)
	if (initializers[i] == initializers[j])
	  return 1;
    }
  if (abi_default_mutex_value () != abi_default_mutex
      || abi_recursive_mutex_value () != abi_recursive_mutex
      || abi_normal_mutex_value () != abi_normal_mutex
      || abi_errorcheck_mutex_value () != abi_errorcheck_mutex
      || abi_condition_value () != abi_condition
      || abi_rwlock_value () != abi_rwlock
      || abi_normal_mutex_plus_one ()
	 != (const char *) ((uintptr_t) abi_normal_mutex + 1)
      || abi_normal_mutex_plus_page ()
	 != (const char *) ((uintptr_t) abi_normal_mutex + 0x1000)
      || abi_normal_mutex_minus_one ()
	 != (const char *) ((uintptr_t) abi_normal_mutex - 1)
      || abi_normal_mutex_minus_page ()
	 != (const char *) ((uintptr_t) abi_normal_mutex - 0x1000))
    return 1;

  int ret = exercise_initializers (&abi_default_mutex, &abi_normal_mutex,
				   &abi_recursive_mutex,
				   &abi_errorcheck_mutex, &abi_condition,
				   &abi_rwlock, &abi_once);
  if (ret)
    return 10 + ret;

  pthread_mutex_t legacy_default_mutex = (pthread_mutex_t) (uintptr_t) 19;
  pthread_mutex_t legacy_normal_mutex = (pthread_mutex_t) (uintptr_t) 19;
  pthread_mutex_t legacy_recursive_mutex = (pthread_mutex_t) (uintptr_t) 18;
  pthread_mutex_t legacy_errorcheck_mutex = (pthread_mutex_t) (uintptr_t) 20;
  pthread_cond_t legacy_condition = (pthread_cond_t) (uintptr_t) 21;
  pthread_rwlock_t legacy_rwlock = (pthread_rwlock_t) (uintptr_t) 22;
  pthread_once_t legacy_once = {
    (pthread_mutex_t) (uintptr_t) 19,
    0
  };

  ret = exercise_initializers (&legacy_default_mutex, &legacy_normal_mutex,
			       &legacy_recursive_mutex,
			       &legacy_errorcheck_mutex, &legacy_condition,
			       &legacy_rwlock, &legacy_once);
  if (ret)
    return 30 + ret;

  return 0;
}

#endif

#ifdef __cplusplus
}
#endif
