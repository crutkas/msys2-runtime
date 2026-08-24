#if defined(__i386__)
#  define SYM(x) _##x
#else
#  define SYM(x) x
#endif

#if defined(__aarch64__)

/* AArch64 page-relative relocations cannot encode the low absolute sentinel
   values.  Use unique DLL-owned objects so public initializers remain address
   constant expressions. */
.data
.p2align 3
.globl SYM(__pthread_recursive_mutex_initializer_np)
SYM(__pthread_recursive_mutex_initializer_np):
	.quad 0
.globl SYM(__pthread_normal_mutex_initializer_np)
SYM(__pthread_normal_mutex_initializer_np):
	.quad 0
.globl SYM(__pthread_errorcheck_mutex_initializer_np)
SYM(__pthread_errorcheck_mutex_initializer_np):
	.quad 0
.globl SYM(__pthread_cond_initializer)
SYM(__pthread_cond_initializer):
	.quad 0
.globl SYM(__pthread_rwlock_initializer)
SYM(__pthread_rwlock_initializer):
	.quad 0

#else

/* these should all be too low to ever be valid addresses */
.globl SYM(__pthread_recursive_mutex_initializer_np)
.set __pthread_recursive_mutex_initializer_np, 18
.globl SYM(__pthread_normal_mutex_initializer_np)
.set __pthread_normal_mutex_initializer_np, 19
.globl SYM(__pthread_errorcheck_mutex_initializer_np)
.set __pthread_errorcheck_mutex_initializer_np, 20
.globl SYM(__pthread_cond_initializer)
.set __pthread_cond_initializer, 21
.globl SYM(__pthread_rwlock_initializer)
.set __pthread_rwlock_initializer, 22

#endif
