/* aarch64_pthread_wrapper.h

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#if !defined(__aarch64__)
#error unimplemented for this target
#endif

static_assert (__builtin_offsetof (pthread_wrapper_arg, func) == 0);
static_assert (__builtin_offsetof (pthread_wrapper_arg, arg) == 8);
static_assert (__builtin_offsetof (pthread_wrapper_arg, stackaddr) == 16);
static_assert (__builtin_offsetof (pthread_wrapper_arg, stackbase) == 24);
static_assert ((__CYGTLS_PADSIZE__ & 15) == 0);

/* Preserve the entry point and argument before releasing the OS stack. */
__asm__ __volatile__ ("\n\
	ldp	x20, x21, [%[WRAPPER_ARG]]	// x20 = func, x21 = arg	\n\
	ldp	x0, x1, [%[WRAPPER_ARG], #16]	// x0 = stackaddr, x1 = stackbase\n\
	sub	sp, x1, %[CYGTLS]		// switch to the Cygwin stack	\n\
	mov	fp, xzr				// clear frame pointer (x29)	\n\
	mov	x1, xzr				// dwSize = 0			\n\
	mov	x2, #0x8000			// dwFreeType = MEM_RELEASE	\n\
	bl	VirtualFree			// free the original OS stack	\n\
	mov	x0, x21				// thread argument		\n\
	blr	x20				// call the thread function	\n"
	: : [WRAPPER_ARG] "r" (&wrapper_arg),
	    [CYGTLS] "r" (__CYGTLS_PADSIZE__)
	: "x0", "x1", "x2", "x20", "x21", "x29", "memory");
