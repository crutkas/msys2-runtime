/**
 * This file has no copyright assigned and is placed in the Public Domain.
 * This file is part of the mingw-w64 runtime package.
 * No warranty is given; refer to the file DISCLAIMER.PD within this package.
 */
#include <_mingw_mac.h>

	.file	"scalbl.S"
	.text
#if defined(__x86_64__)
	.align 8
#elif defined(__i386__)
	.align 4
#endif
.globl __MINGW_USYMBOL(scalbl)
	.def	__MINGW_USYMBOL(scalbl);	.scl	2;	.type	32;	.endef
__MINGW_USYMBOL(scalbl):
#if defined(__x86_64__)
	subq  $24, %rsp
	fldt	(%r8)
	fldt	(%rdx)
	fscale
	fstp	%st(1)
	movq	%rcx,%rax
	movq	$0,8(%rcx)
	fstpt	(%rcx)
	addq $24, %rsp
	ret
#elif defined(__i386__)
	fildl	16(%esp)
	fldt	4(%esp)
	fscale
	fstp	%st(1)
	ret
#elif __SIZEOF_LONG_DOUBLE__ == __SIZEOF_DOUBLE__
	fcmp	d1, d1
	b.vs	2f
	fmov	x1, d1
	ubfx	x2, x1, #52, #11
	cmp	x2, #0x7ff
	b.eq	1f
	frintz	d2, d1
	fcmp	d2, d1
	b.ne	3f
	fcvtzs	w0, d1
	b	scalbn
1:
	tbnz	x1, #63, 4f
2:
	fmul	d0, d0, d1
	ret
3:
	fsub	d1, d1, d1
	fdiv	d0, d1, d1
	ret
4:
	fneg	d1, d1
	fdiv	d0, d0, d1
	ret
#else
	.error "unimplemented for this target yet"
#endif
