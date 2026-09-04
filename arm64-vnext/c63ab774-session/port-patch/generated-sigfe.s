	.include "tlsoffsets"
	.text

	/* AArch64 signal-interception trampolines for Cygwin/MSYS2.
	 *
	 * TEB access: mov	x16, x18 then ldr from [x16, #8].
	 * This gives the NtTib.StackLimit, which is the TLS base.
	 * x18 is the platform register - READ ONLY, never written.
	 *
	 * All TLS field accesses use register-offset addressing:
	 *   mov xN, _cygtls.field     (load the .equ offset into a reg)
	 *   ldr/str wM, [xbase, xN]   (base + offset)
	 * because the offsets are large negatives (~-7000 to -12000) that
	 * exceed ARM64 immediate-offset ranges.
	 *
	 * Stack-lock: ldaxr/stlxr loops (ARMv8 baseline, no LSE needed).
	 *
	 * ARM64 Windows calling convention:
	 *   x0-x7: args; x8: indirect result; x9-x15: volatile
	 *   x16-x17: IP0/IP1 scratch; x18: platform (TEB) — DO NOT WRITE
	 *   x19-x28: callee-saved; x29: FP; x30: LR
	 *   d0-d7,d16-d31: volatile NEON; d8-d15: callee-saved NEON
	 */

/* Helper macro: compute address of a TLS field into a register.
   tls_base must hold the TLS base pointer.
   Uses xdst as the destination (clobbers it). */
.macro	tls_addr xdst, tls_base, field
	mov	\xdst, \field
	add	\xdst, \tls_base, \xdst
.endm

	.global	_sigfe_maybe
	.seh_proc _sigfe_maybe
_sigfe_maybe:
	.seh_endprologue
	mov	x16, x18
	ldr	x16, [x16, #8]			/* TLS base */
	tls_addr x17, x16, _cygtls.initialized
	cmp	sp, x17				/* sp above TLS? */
	b.hs	0f				/* no TLS, just return */
	ldr	w17, [x17]
	mov	w15, #0x173f
	movk	w15, #0xc763, lsl #16		/* CYGTLS_INITIALIZED */
	cmp	w17, w15
	b.eq	1f
0:	ret
	.seh_endproc

	.global	_sigfe
	.seh_proc _sigfe
_sigfe:
	.seh_endprologue
	mov	x16, x18
	ldr	x16, [x16, #8]			/* TLS base */
1:	/* acquire stacklock */
	tls_addr x17, x16, _cygtls.stacklock
2:	ldaxr	w15, [x17]
	cbnz	w15, 3f
	mov	w14, #1
	stlxr	w13, w14, [x17]
	cbnz	w13, 2b
	b	4f
3:	yield
	b	2b

4:	/* lock acquired — push return addr onto signal stack */
	tls_addr x17, x16, _cygtls.stackptr
	ldr	x15, [x17]			/* old stackptr */
	ldr	x14, [sp, #16]			/* real return addr (from trampoline frame) */
	str	x14, [x15]			/* store on signal stack */
	add	x15, x15, #8
	str	x15, [x17]			/* update stackptr */
	/* replace saved LR with _sigbe */
	adrp	x14, _sigbe
	add	x14, x14, :lo12:_sigbe
	str	x14, [sp, #16]
	/* increment incyg */
	tls_addr x17, x16, _cygtls.incyg
	ldr	w15, [x17]
	add	w15, w15, #1
	str	w15, [x17]
	/* release stacklock */
	tls_addr x17, x16, _cygtls.stacklock
	stlr	wzr, [x17]
	/* pop function address and restored frame, jump to real function */
	ldr	x9, [sp], #16
	ldp	x29, x30, [sp], #16
	br	x9
	.seh_endproc

	.global _sigbe
	.seh_proc _sigbe
_sigbe:
	.seh_endprologue
	mov	x16, x18
	ldr	x16, [x16, #8]
	tls_addr x17, x16, _cygtls.stacklock
1:	ldaxr	w15, [x17]
	cbnz	w15, 2f
	mov	w14, #1
	stlxr	w13, w14, [x17]
	cbnz	w13, 1b
	b	3f
2:	yield
	b	1b
3:	/* lock acquired — pop from signal stack */
	tls_addr x17, x16, _cygtls.stackptr
	ldr	x15, [x17]
	sub	x15, x15, #8
	str	x15, [x17]
	ldr	x15, [x15]			/* real return address */
	/* decrement incyg */
	tls_addr x17, x16, _cygtls.incyg
	ldr	w14, [x17]
	sub	w14, w14, #1
	str	w14, [x17]
	/* release stacklock */
	tls_addr x17, x16, _cygtls.stacklock
	stlr	wzr, [x17]
	br	x15
	.seh_endproc

	.global	sigdelayed
	.seh_proc sigdelayed
sigdelayed:
	/* Save x29/x30 frame and the injected return address (x10). */
	stp	x29, x30, [sp, #-32]!
	.seh_save_regp_x x29, 32
	mov	x29, sp
	str	x10, [sp, #16]
	.seh_save_reg x10, 16

	/* Save ALL volatile + callee-saved registers (except x18).
	 * x0-x17 (18 regs), x19-x28 (10 regs) = 28 * 8 = 224
	 * NZCV + FPCR = 16
	 * NEON q0-q31 = 512
	 * Total = 752, already 16-byte aligned. */
	sub	sp, sp, #752
	.seh_stackalloc 752
	.seh_endprologue

	stp	x0, x1, [sp, #0]
	stp	x2, x3, [sp, #16]
	stp	x4, x5, [sp, #32]
	stp	x6, x7, [sp, #48]
	stp	x8, x9, [sp, #64]
	stp	x10, x11, [sp, #80]
	stp	x12, x13, [sp, #96]
	stp	x14, x15, [sp, #112]
	stp	x16, x17, [sp, #128]
	stp	x19, x20, [sp, #144]
	stp	x21, x22, [sp, #160]
	stp	x23, x24, [sp, #176]
	stp	x25, x26, [sp, #192]
	stp	x27, x28, [sp, #208]
	mrs	x0, nzcv
	mrs	x1, fpcr
	stp	x0, x1, [sp, #224]
	stp	q0, q1, [sp, #240]
	stp	q2, q3, [sp, #272]
	stp	q4, q5, [sp, #304]
	stp	q6, q7, [sp, #336]
	stp	q8, q9, [sp, #368]
	stp	q10, q11, [sp, #400]
	stp	q12, q13, [sp, #432]
	stp	q14, q15, [sp, #464]
	stp	q16, q17, [sp, #496]
	stp	q18, q19, [sp, #528]
	stp	q20, q21, [sp, #560]
	stp	q22, q23, [sp, #592]
	stp	q24, q25, [sp, #624]
	stp	q26, q27, [sp, #656]
	stp	q28, q29, [sp, #688]
	stp	q30, q31, [sp, #720]

	/* Get TLS base into callee-saved x19 */
	mov	x19, x18
	ldr	x19, [x19, #8]
	mov	x17, _cygtls.saved_errno
	ldr	w20, [x19, x17]			/* save saved_errno in w20 */

	/* Call signal handler: x0 = tls + start_offset */
	mov	x0, _cygtls.start_offset
	add	x0, x19, x0
	bl	_ZN7_cygtls19call_signal_handlerEv

	/* Acquire stacklock */
	tls_addr x17, x19, _cygtls.stacklock
1:	ldaxr	w15, [x17]
	cbnz	w15, 2f
	mov	w14, #1
	stlxr	w13, w14, [x17]
	cbnz	w13, 1b
	b	3f
2:	yield
	b	1b
3:	/* Restore errno if saved_errno >= 0 */
	tbnz	w20, #31, 4f
	mov	x17, _cygtls.errno_addr
	ldr	x17, [x19, x17]
	str	w20, [x17]
4:	/* Pop return address from signal stack */
	tls_addr x17, x19, _cygtls.stackptr
	ldr	x15, [x17]
	sub	x14, x15, #8
	str	x14, [x17]
	ldr	x10, [x14]

	/* Clear incyg and release stacklock */
	tls_addr x17, x19, _cygtls.incyg
	str	wzr, [x17]
	tls_addr x17, x19, _cygtls.stacklock
	stlr	wzr, [x17]

	/* Restore NEON */
	ldp	q0, q1, [sp, #240]
	ldp	q2, q3, [sp, #272]
	ldp	q4, q5, [sp, #304]
	ldp	q6, q7, [sp, #336]
	ldp	q8, q9, [sp, #368]
	ldp	q10, q11, [sp, #400]
	ldp	q12, q13, [sp, #432]
	ldp	q14, q15, [sp, #464]
	ldp	q16, q17, [sp, #496]
	ldp	q18, q19, [sp, #528]
	ldp	q20, q21, [sp, #560]
	ldp	q22, q23, [sp, #592]
	ldp	q24, q25, [sp, #624]
	ldp	q26, q27, [sp, #656]
	ldp	q28, q29, [sp, #688]
	ldp	q30, q31, [sp, #720]
	/* Restore NZCV, FPCR */
	ldp	x0, x1, [sp, #224]
	msr	nzcv, x0
	msr	fpcr, x1
	/* Restore GPRs */
	ldp	x0, x1, [sp, #0]
	ldp	x2, x3, [sp, #16]
	ldp	x4, x5, [sp, #32]
	ldp	x6, x7, [sp, #48]
	ldp	x8, x9, [sp, #64]
	ldr	x11, [sp, #88]
	ldp	x12, x13, [sp, #96]
	ldp	x14, x15, [sp, #112]
	ldp	x16, x17, [sp, #128]
	ldp	x19, x20, [sp, #144]
	ldp	x21, x22, [sp, #160]
	ldp	x23, x24, [sp, #176]
	ldp	x25, x26, [sp, #192]
	ldp	x27, x28, [sp, #208]
	add	sp, sp, #752

	ldr	x10, [sp, #16]			/* restore injected return addr */
	ldp	x29, x30, [sp], #32
	br	x10
	.seh_endproc

_sigdelayed_end:
	.global _sigdelayed_end

	.global	stabilize_sig_stack
	.seh_proc stabilize_sig_stack
stabilize_sig_stack:
	stp	x29, x30, [sp, #-32]!
	.seh_save_regp_x x29, 32
	mov	x29, sp
	str	x19, [sp, #16]
	.seh_save_reg x19, 16
	.seh_endprologue

	mov	x19, x18
	ldr	x19, [x19, #8]
	tls_addr x17, x19, _cygtls.stacklock
1:	ldaxr	w15, [x17]
	cbnz	w15, 2f
	mov	w14, #1
	stlxr	w13, w14, [x17]
	cbnz	w13, 1b
	b	3f
2:	yield
	b	1b
3:	/* lock acquired */
	tls_addr x17, x19, _cygtls.incyg
	ldr	w15, [x17]
	add	w15, w15, #1
	str	w15, [x17]
	tls_addr x17, x19, _cygtls.current_sig
	ldr	w15, [x17]
	cbz	w15, 4f
	/* signal pending — release lock, call handler, retry */
	tls_addr x17, x19, _cygtls.stacklock
	stlr	wzr, [x17]
	mov	x0, _cygtls.start_offset
	add	x0, x19, x0
	bl	_ZN7_cygtls19call_signal_handlerEv
	tls_addr x17, x19, _cygtls.incyg
	ldr	w15, [x17]
	sub	w15, w15, #1
	str	w15, [x17]
	tls_addr x17, x19, _cygtls.stacklock
	b	1b
4:	/* no signal */
	tls_addr x17, x19, _cygtls.incyg
	ldr	w15, [x17]
	sub	w15, w15, #1
	str	w15, [x17]
	mov	x11, x19
	ldr	x19, [sp, #16]
	ldp	x29, x30, [sp], #32
	ret
	.seh_endproc

	/* AArch64 jmp_buf layout for Cygwin:
	 *   0x00: tls stackptr (Frame slot)
	 *   0x08-0x50: x19-x28 (callee-saved GPRs)
	 *   0x58: x29 (fp), 0x60: x30 (lr/return addr)
	 *   0x68: sp
	 *   0x70: fpcr
	 *   0x78-0xb7: d8-d15 (callee-saved NEON)
	 *   0x100: savemask (sigsetjmp), 0x108: sigmask
	 */

	.globl	sigsetjmp
	.seh_proc sigsetjmp
sigsetjmp:
	.seh_endprologue
	str	w1, [x0, #0x100]
	cbz	w1, setjmp
	stp	x29, x30, [sp, #-32]!
	mov	x29, sp
	str	x0, [sp, #16]
	add	x2, x0, #0x108
	mov	x1, xzr
	mov	w0, #0
	bl	pthread_sigmask
	ldr	x0, [sp, #16]
	ldp	x29, x30, [sp], #32
	b	setjmp
	.seh_endproc

	.globl	setjmp
	.seh_proc setjmp
setjmp:
	stp	x29, x30, [sp, #-32]!
	.seh_save_regp_x x29, 32
	mov	x29, sp
	str	x19, [sp, #16]
	.seh_save_reg x19, 16
	.seh_endprologue
	/* Save callee-saved GPRs */
	stp	x19, x20, [x0, #0x08]
	stp	x21, x22, [x0, #0x18]
	stp	x23, x24, [x0, #0x28]
	stp	x25, x26, [x0, #0x38]
	stp	x27, x28, [x0, #0x48]
	/* Save caller's fp and lr (from our frame) */
	ldp	x16, x17, [x29]
	stp	x16, x17, [x0, #0x58]
	/* Save caller's sp */
	add	x16, x29, #32
	str	x16, [x0, #0x68]
	mrs	x16, fpcr
	str	x16, [x0, #0x70]
	stp	d8, d9, [x0, #0x78]
	stp	d10, d11, [x0, #0x88]
	stp	d12, d13, [x0, #0x98]
	stp	d14, d15, [x0, #0xa8]

	mov	x19, x0
	bl	stabilize_sig_stack		/* x11 = tls, lock held */
	mov	x17, _cygtls.stackptr
	ldr	x16, [x11, x17]
	str	x16, [x19, #0x00]
	tls_addr x17, x11, _cygtls.stacklock
	stlr	wzr, [x17]
	mov	w0, #0
	ldr	x19, [sp, #16]
	ldp	x29, x30, [sp], #32
	ret
	.seh_endproc

	.globl	siglongjmp
	.seh_proc siglongjmp
siglongjmp:
	stp	x29, x30, [sp, #-48]!
	.seh_save_regp_x x29, 48
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	.seh_save_regp x19, 16
	.seh_endprologue
	mov	x19, x0
	mov	w20, w1
	ldr	w16, [x0, #0x100]
	cbz	w16, .Ldo_longjmp
	mov	x2, xzr
	add	x1, x0, #0x108
	mov	w0, #0
	bl	pthread_sigmask
	b	.Ldo_longjmp
	.seh_endproc

	.globl	longjmp
	.seh_proc longjmp
longjmp:
	stp	x29, x30, [sp, #-48]!
	.seh_save_regp_x x29, 48
	mov	x29, sp
	stp	x19, x20, [sp, #16]
	.seh_save_regp x19, 16
	.seh_endprologue
	mov	x19, x0
	mov	w20, w1
.Ldo_longjmp:
	bl	stabilize_sig_stack		/* x11 = tls, lock held */
	ldr	x16, [x19, #0x00]
	mov	x17, _cygtls.stackptr
	str	x16, [x11, x17]
	tls_addr x17, x11, _cygtls.stacklock
	stlr	wzr, [x17]
	tls_addr x17, x11, _cygtls.incyg
	str	wzr, [x17]
	/* Restore callee-saved */
	ldp	x21, x22, [x19, #0x18]
	ldp	x23, x24, [x19, #0x28]
	ldp	x25, x26, [x19, #0x38]
	ldp	x27, x28, [x19, #0x48]
	ldp	x29, x30, [x19, #0x58]
	ldr	x16, [x19, #0x68]
	ldr	x17, [x19, #0x70]
	msr	fpcr, x17
	ldp	d8, d9, [x19, #0x78]
	ldp	d10, d11, [x19, #0x88]
	ldp	d12, d13, [x19, #0x98]
	ldp	d14, d15, [x19, #0xa8]
	ldp	x19, x20, [x19, #0x08]
	mov	sp, x16
	mov	w0, w20
	cmp	w0, #0
	cinc	w0, w0, eq
	ret
	.seh_endproc
	.extern	_Exit
	.global	_sigfe__Exit
	.seh_proc _sigfe__Exit
_sigfe__Exit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, _Exit
	add	x9, x9, :lo12:_Exit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__chk_fail
	.global	_sigfe___chk_fail
	.seh_proc _sigfe___chk_fail
_sigfe___chk_fail:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __chk_fail
	add	x9, x9, :lo12:__chk_fail
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__cpuset_alloc
	.global	_sigfe___cpuset_alloc
	.seh_proc _sigfe___cpuset_alloc
_sigfe___cpuset_alloc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __cpuset_alloc
	add	x9, x9, :lo12:__cpuset_alloc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__cpuset_free
	.global	_sigfe___cpuset_free
	.seh_proc _sigfe___cpuset_free
_sigfe___cpuset_free:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __cpuset_free
	add	x9, x9, :lo12:__cpuset_free
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__cxa_finalize
	.global	_sigfe___cxa_finalize
	.seh_proc _sigfe___cxa_finalize
_sigfe___cxa_finalize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __cxa_finalize
	add	x9, x9, :lo12:__cxa_finalize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__dn_comp
	.global	_sigfe___dn_comp
	.seh_proc _sigfe___dn_comp
_sigfe___dn_comp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __dn_comp
	add	x9, x9, :lo12:__dn_comp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__dn_expand
	.global	_sigfe___dn_expand
	.seh_proc _sigfe___dn_expand
_sigfe___dn_expand:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __dn_expand
	add	x9, x9, :lo12:__dn_expand
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__dn_skipname
	.global	_sigfe___dn_skipname
	.seh_proc _sigfe___dn_skipname
_sigfe___dn_skipname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __dn_skipname
	add	x9, x9, :lo12:__dn_skipname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__eprintf
	.global	_sigfe___eprintf
	.seh_proc _sigfe___eprintf
_sigfe___eprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __eprintf
	add	x9, x9, :lo12:__eprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__fpurge
	.global	_sigfe___fpurge
	.seh_proc _sigfe___fpurge
_sigfe___fpurge:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __fpurge
	add	x9, x9, :lo12:__fpurge
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__fsetlocking
	.global	_sigfe___fsetlocking
	.seh_proc _sigfe___fsetlocking
_sigfe___fsetlocking:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __fsetlocking
	add	x9, x9, :lo12:__fsetlocking
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__getdelim
	.global	_sigfe___getdelim
	.seh_proc _sigfe___getdelim
_sigfe___getdelim:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __getdelim
	add	x9, x9, :lo12:__getdelim
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__getline
	.global	_sigfe___getline
	.seh_proc _sigfe___getline
_sigfe___getline:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __getline
	add	x9, x9, :lo12:__getline
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__gets_chk
	.global	_sigfe___gets_chk
	.seh_proc _sigfe___gets_chk
_sigfe___gets_chk:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __gets_chk
	add	x9, x9, :lo12:__gets_chk
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__opendir_with_d_ino
	.global	_sigfe___opendir_with_d_ino
	.seh_proc _sigfe___opendir_with_d_ino
_sigfe___opendir_with_d_ino:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __opendir_with_d_ino
	add	x9, x9, :lo12:__opendir_with_d_ino
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_close
	.global	_sigfe___res_close
	.seh_proc _sigfe___res_close
_sigfe___res_close:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_close
	add	x9, x9, :lo12:__res_close
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_init
	.global	_sigfe___res_init
	.seh_proc _sigfe___res_init
_sigfe___res_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_init
	add	x9, x9, :lo12:__res_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_mkquery
	.global	_sigfe___res_mkquery
	.seh_proc _sigfe___res_mkquery
_sigfe___res_mkquery:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_mkquery
	add	x9, x9, :lo12:__res_mkquery
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_nclose
	.global	_sigfe___res_nclose
	.seh_proc _sigfe___res_nclose
_sigfe___res_nclose:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_nclose
	add	x9, x9, :lo12:__res_nclose
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_ninit
	.global	_sigfe___res_ninit
	.seh_proc _sigfe___res_ninit
_sigfe___res_ninit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_ninit
	add	x9, x9, :lo12:__res_ninit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_nmkquery
	.global	_sigfe___res_nmkquery
	.seh_proc _sigfe___res_nmkquery
_sigfe___res_nmkquery:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_nmkquery
	add	x9, x9, :lo12:__res_nmkquery
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_nquery
	.global	_sigfe___res_nquery
	.seh_proc _sigfe___res_nquery
_sigfe___res_nquery:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_nquery
	add	x9, x9, :lo12:__res_nquery
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_nquerydomain
	.global	_sigfe___res_nquerydomain
	.seh_proc _sigfe___res_nquerydomain
_sigfe___res_nquerydomain:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_nquerydomain
	add	x9, x9, :lo12:__res_nquerydomain
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_nsearch
	.global	_sigfe___res_nsearch
	.seh_proc _sigfe___res_nsearch
_sigfe___res_nsearch:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_nsearch
	add	x9, x9, :lo12:__res_nsearch
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_nsend
	.global	_sigfe___res_nsend
	.seh_proc _sigfe___res_nsend
_sigfe___res_nsend:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_nsend
	add	x9, x9, :lo12:__res_nsend
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_query
	.global	_sigfe___res_query
	.seh_proc _sigfe___res_query
_sigfe___res_query:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_query
	add	x9, x9, :lo12:__res_query
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_querydomain
	.global	_sigfe___res_querydomain
	.seh_proc _sigfe___res_querydomain
_sigfe___res_querydomain:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_querydomain
	add	x9, x9, :lo12:__res_querydomain
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_search
	.global	_sigfe___res_search
	.seh_proc _sigfe___res_search
_sigfe___res_search:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_search
	add	x9, x9, :lo12:__res_search
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_send
	.global	_sigfe___res_send
	.seh_proc _sigfe___res_send
_sigfe___res_send:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_send
	add	x9, x9, :lo12:__res_send
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__res_state
	.global	_sigfe___res_state
	.seh_proc _sigfe___res_state
_sigfe___res_state:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __res_state
	add	x9, x9, :lo12:__res_state
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__sched_getaffinity_sys
	.global	_sigfe___sched_getaffinity_sys
	.seh_proc _sigfe___sched_getaffinity_sys
_sigfe___sched_getaffinity_sys:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __sched_getaffinity_sys
	add	x9, x9, :lo12:__sched_getaffinity_sys
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__snprintf_chk
	.global	_sigfe___snprintf_chk
	.seh_proc _sigfe___snprintf_chk
_sigfe___snprintf_chk:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __snprintf_chk
	add	x9, x9, :lo12:__snprintf_chk
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__sprintf_chk
	.global	_sigfe___sprintf_chk
	.seh_proc _sigfe___sprintf_chk
_sigfe___sprintf_chk:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __sprintf_chk
	add	x9, x9, :lo12:__sprintf_chk
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__srget
	.global	_sigfe___srget
	.seh_proc _sigfe___srget
_sigfe___srget:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __srget
	add	x9, x9, :lo12:__srget
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__srget_r
	.global	_sigfe___srget_r
	.seh_proc _sigfe___srget_r
_sigfe___srget_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __srget_r
	add	x9, x9, :lo12:__srget_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__stack_chk_fail
	.global	_sigfe___stack_chk_fail
	.seh_proc _sigfe___stack_chk_fail
_sigfe___stack_chk_fail:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __stack_chk_fail
	add	x9, x9, :lo12:__stack_chk_fail
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__swbuf
	.global	_sigfe___swbuf
	.seh_proc _sigfe___swbuf
_sigfe___swbuf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __swbuf
	add	x9, x9, :lo12:__swbuf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__swbuf_r
	.global	_sigfe___swbuf_r
	.seh_proc _sigfe___swbuf_r
_sigfe___swbuf_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __swbuf_r
	add	x9, x9, :lo12:__swbuf_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__vsnprintf_chk
	.global	_sigfe___vsnprintf_chk
	.seh_proc _sigfe___vsnprintf_chk
_sigfe___vsnprintf_chk:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __vsnprintf_chk
	add	x9, x9, :lo12:__vsnprintf_chk
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__vsprintf_chk
	.global	_sigfe___vsprintf_chk
	.seh_proc _sigfe___vsprintf_chk
_sigfe___vsprintf_chk:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __vsprintf_chk
	add	x9, x9, :lo12:__vsprintf_chk
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__xdrrec_getrec
	.global	_sigfe___xdrrec_getrec
	.seh_proc _sigfe___xdrrec_getrec
_sigfe___xdrrec_getrec:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __xdrrec_getrec
	add	x9, x9, :lo12:__xdrrec_getrec
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__xdrrec_setnonblock
	.global	_sigfe___xdrrec_setnonblock
	.seh_proc _sigfe___xdrrec_setnonblock
_sigfe___xdrrec_setnonblock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __xdrrec_setnonblock
	add	x9, x9, :lo12:__xdrrec_setnonblock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__xpg_sigpause
	.global	_sigfe___xpg_sigpause
	.seh_proc _sigfe___xpg_sigpause
_sigfe___xpg_sigpause:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __xpg_sigpause
	add	x9, x9, :lo12:__xpg_sigpause
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	__xpg_strerror_r
	.global	_sigfe___xpg_strerror_r
	.seh_proc _sigfe___xpg_strerror_r
_sigfe___xpg_strerror_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, __xpg_strerror_r
	add	x9, x9, :lo12:__xpg_strerror_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	_exit
	.global	_sigfe__exit
	.seh_proc _sigfe__exit
_sigfe__exit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, _exit
	add	x9, x9, :lo12:_exit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	_fscanf_r
	.global	_sigfe__fscanf_r
	.seh_proc _sigfe__fscanf_r
_sigfe__fscanf_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, _fscanf_r
	add	x9, x9, :lo12:_fscanf_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	_get_osfhandle
	.global	_sigfe__get_osfhandle
	.seh_proc _sigfe__get_osfhandle
_sigfe__get_osfhandle:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, _get_osfhandle
	add	x9, x9, :lo12:_get_osfhandle
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	_pipe
	.global	_sigfe__pipe
	.seh_proc _sigfe__pipe
_sigfe__pipe:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, _pipe
	add	x9, x9, :lo12:_pipe
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	_pthread_cleanup_pop
	.global	_sigfe__pthread_cleanup_pop
	.seh_proc _sigfe__pthread_cleanup_pop
_sigfe__pthread_cleanup_pop:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, _pthread_cleanup_pop
	add	x9, x9, :lo12:_pthread_cleanup_pop
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	_pthread_cleanup_push
	.global	_sigfe__pthread_cleanup_push
	.seh_proc _sigfe__pthread_cleanup_push
_sigfe__pthread_cleanup_push:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, _pthread_cleanup_push
	add	x9, x9, :lo12:_pthread_cleanup_push
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	accept4
	.global	_sigfe_accept4
	.seh_proc _sigfe_accept4
_sigfe_accept4:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, accept4
	add	x9, x9, :lo12:accept4
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	access
	.global	_sigfe_access
	.seh_proc _sigfe_access
_sigfe_access:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, access
	add	x9, x9, :lo12:access
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl
	.global	_sigfe_acl
	.seh_proc _sigfe_acl
_sigfe_acl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl
	add	x9, x9, :lo12:acl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_calc_mask
	.global	_sigfe_acl_calc_mask
	.seh_proc _sigfe_acl_calc_mask
_sigfe_acl_calc_mask:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_calc_mask
	add	x9, x9, :lo12:acl_calc_mask
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_cmp
	.global	_sigfe_acl_cmp
	.seh_proc _sigfe_acl_cmp
_sigfe_acl_cmp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_cmp
	add	x9, x9, :lo12:acl_cmp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_create_entry
	.global	_sigfe_acl_create_entry
	.seh_proc _sigfe_acl_create_entry
_sigfe_acl_create_entry:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_create_entry
	add	x9, x9, :lo12:acl_create_entry
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_delete_def_file
	.global	_sigfe_acl_delete_def_file
	.seh_proc _sigfe_acl_delete_def_file
_sigfe_acl_delete_def_file:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_delete_def_file
	add	x9, x9, :lo12:acl_delete_def_file
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_dup
	.global	_sigfe_acl_dup
	.seh_proc _sigfe_acl_dup
_sigfe_acl_dup:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_dup
	add	x9, x9, :lo12:acl_dup
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_equiv_mode
	.global	_sigfe_acl_equiv_mode
	.seh_proc _sigfe_acl_equiv_mode
_sigfe_acl_equiv_mode:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_equiv_mode
	add	x9, x9, :lo12:acl_equiv_mode
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_extended_fd
	.global	_sigfe_acl_extended_fd
	.seh_proc _sigfe_acl_extended_fd
_sigfe_acl_extended_fd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_extended_fd
	add	x9, x9, :lo12:acl_extended_fd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_extended_file
	.global	_sigfe_acl_extended_file
	.seh_proc _sigfe_acl_extended_file
_sigfe_acl_extended_file:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_extended_file
	add	x9, x9, :lo12:acl_extended_file
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_extended_file_nofollow
	.global	_sigfe_acl_extended_file_nofollow
	.seh_proc _sigfe_acl_extended_file_nofollow
_sigfe_acl_extended_file_nofollow:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_extended_file_nofollow
	add	x9, x9, :lo12:acl_extended_file_nofollow
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_free
	.global	_sigfe_acl_free
	.seh_proc _sigfe_acl_free
_sigfe_acl_free:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_free
	add	x9, x9, :lo12:acl_free
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_from_text
	.global	_sigfe_acl_from_text
	.seh_proc _sigfe_acl_from_text
_sigfe_acl_from_text:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_from_text
	add	x9, x9, :lo12:acl_from_text
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_get_fd
	.global	_sigfe_acl_get_fd
	.seh_proc _sigfe_acl_get_fd
_sigfe_acl_get_fd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_get_fd
	add	x9, x9, :lo12:acl_get_fd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_get_file
	.global	_sigfe_acl_get_file
	.seh_proc _sigfe_acl_get_file
_sigfe_acl_get_file:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_get_file
	add	x9, x9, :lo12:acl_get_file
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_get_qualifier
	.global	_sigfe_acl_get_qualifier
	.seh_proc _sigfe_acl_get_qualifier
_sigfe_acl_get_qualifier:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_get_qualifier
	add	x9, x9, :lo12:acl_get_qualifier
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_init
	.global	_sigfe_acl_init
	.seh_proc _sigfe_acl_init
_sigfe_acl_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_init
	add	x9, x9, :lo12:acl_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_set_fd
	.global	_sigfe_acl_set_fd
	.seh_proc _sigfe_acl_set_fd
_sigfe_acl_set_fd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_set_fd
	add	x9, x9, :lo12:acl_set_fd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_set_file
	.global	_sigfe_acl_set_file
	.seh_proc _sigfe_acl_set_file
_sigfe_acl_set_file:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_set_file
	add	x9, x9, :lo12:acl_set_file
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_to_any_text
	.global	_sigfe_acl_to_any_text
	.seh_proc _sigfe_acl_to_any_text
_sigfe_acl_to_any_text:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_to_any_text
	add	x9, x9, :lo12:acl_to_any_text
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acl_to_text
	.global	_sigfe_acl_to_text
	.seh_proc _sigfe_acl_to_text
_sigfe_acl_to_text:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acl_to_text
	add	x9, x9, :lo12:acl_to_text
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aclfrommode
	.global	_sigfe_aclfrommode
	.seh_proc _sigfe_aclfrommode
_sigfe_aclfrommode:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aclfrommode
	add	x9, x9, :lo12:aclfrommode
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aclfrompbits
	.global	_sigfe_aclfrompbits
	.seh_proc _sigfe_aclfrompbits
_sigfe_aclfrompbits:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aclfrompbits
	add	x9, x9, :lo12:aclfrompbits
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aclfromtext
	.global	_sigfe_aclfromtext
	.seh_proc _sigfe_aclfromtext
_sigfe_aclfromtext:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aclfromtext
	add	x9, x9, :lo12:aclfromtext
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aclsort
	.global	_sigfe_aclsort
	.seh_proc _sigfe_aclsort
_sigfe_aclsort:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aclsort
	add	x9, x9, :lo12:aclsort
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acltomode
	.global	_sigfe_acltomode
	.seh_proc _sigfe_acltomode
_sigfe_acltomode:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acltomode
	add	x9, x9, :lo12:acltomode
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acltopbits
	.global	_sigfe_acltopbits
	.seh_proc _sigfe_acltopbits
_sigfe_acltopbits:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acltopbits
	add	x9, x9, :lo12:acltopbits
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	acltotext
	.global	_sigfe_acltotext
	.seh_proc _sigfe_acltotext
_sigfe_acltotext:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, acltotext
	add	x9, x9, :lo12:acltotext
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aio_cancel
	.global	_sigfe_aio_cancel
	.seh_proc _sigfe_aio_cancel
_sigfe_aio_cancel:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aio_cancel
	add	x9, x9, :lo12:aio_cancel
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aio_fsync
	.global	_sigfe_aio_fsync
	.seh_proc _sigfe_aio_fsync
_sigfe_aio_fsync:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aio_fsync
	add	x9, x9, :lo12:aio_fsync
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aio_read
	.global	_sigfe_aio_read
	.seh_proc _sigfe_aio_read
_sigfe_aio_read:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aio_read
	add	x9, x9, :lo12:aio_read
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aio_suspend
	.global	_sigfe_aio_suspend
	.seh_proc _sigfe_aio_suspend
_sigfe_aio_suspend:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aio_suspend
	add	x9, x9, :lo12:aio_suspend
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aio_write
	.global	_sigfe_aio_write
	.seh_proc _sigfe_aio_write
_sigfe_aio_write:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aio_write
	add	x9, x9, :lo12:aio_write
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	alarm
	.global	_sigfe_alarm
	.seh_proc _sigfe_alarm
_sigfe_alarm:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, alarm
	add	x9, x9, :lo12:alarm
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	aligned_alloc
	.global	_sigfe_aligned_alloc
	.seh_proc _sigfe_aligned_alloc
_sigfe_aligned_alloc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, aligned_alloc
	add	x9, x9, :lo12:aligned_alloc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	argz_add
	.global	_sigfe_argz_add
	.seh_proc _sigfe_argz_add
_sigfe_argz_add:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, argz_add
	add	x9, x9, :lo12:argz_add
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	argz_add_sep
	.global	_sigfe_argz_add_sep
	.seh_proc _sigfe_argz_add_sep
_sigfe_argz_add_sep:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, argz_add_sep
	add	x9, x9, :lo12:argz_add_sep
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	argz_append
	.global	_sigfe_argz_append
	.seh_proc _sigfe_argz_append
_sigfe_argz_append:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, argz_append
	add	x9, x9, :lo12:argz_append
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	argz_create
	.global	_sigfe_argz_create
	.seh_proc _sigfe_argz_create
_sigfe_argz_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, argz_create
	add	x9, x9, :lo12:argz_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	argz_create_sep
	.global	_sigfe_argz_create_sep
	.seh_proc _sigfe_argz_create_sep
_sigfe_argz_create_sep:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, argz_create_sep
	add	x9, x9, :lo12:argz_create_sep
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	argz_delete
	.global	_sigfe_argz_delete
	.seh_proc _sigfe_argz_delete
_sigfe_argz_delete:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, argz_delete
	add	x9, x9, :lo12:argz_delete
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	argz_insert
	.global	_sigfe_argz_insert
	.seh_proc _sigfe_argz_insert
_sigfe_argz_insert:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, argz_insert
	add	x9, x9, :lo12:argz_insert
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	argz_replace
	.global	_sigfe_argz_replace
	.seh_proc _sigfe_argz_replace
_sigfe_argz_replace:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, argz_replace
	add	x9, x9, :lo12:argz_replace
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	asctime
	.global	_sigfe_asctime
	.seh_proc _sigfe_asctime
_sigfe_asctime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, asctime
	add	x9, x9, :lo12:asctime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	asctime_r
	.global	_sigfe_asctime_r
	.seh_proc _sigfe_asctime_r
_sigfe_asctime_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, asctime_r
	add	x9, x9, :lo12:asctime_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	asnprintf
	.global	_sigfe_asnprintf
	.seh_proc _sigfe_asnprintf
_sigfe_asnprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, asnprintf
	add	x9, x9, :lo12:asnprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	asprintf
	.global	_sigfe_asprintf
	.seh_proc _sigfe_asprintf
_sigfe_asprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, asprintf
	add	x9, x9, :lo12:asprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	at_quick_exit
	.global	_sigfe_at_quick_exit
	.seh_proc _sigfe_at_quick_exit
_sigfe_at_quick_exit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, at_quick_exit
	add	x9, x9, :lo12:at_quick_exit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	atof
	.global	_sigfe_atof
	.seh_proc _sigfe_atof
_sigfe_atof:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, atof
	add	x9, x9, :lo12:atof
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	atoff
	.global	_sigfe_atoff
	.seh_proc _sigfe_atoff
_sigfe_atoff:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, atoff
	add	x9, x9, :lo12:atoff
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	call_once
	.global	_sigfe_call_once
	.seh_proc _sigfe_call_once
_sigfe_call_once:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, call_once
	add	x9, x9, :lo12:call_once
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	calloc
	.global	_sigfe_calloc
	.seh_proc _sigfe_calloc
_sigfe_calloc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, calloc
	add	x9, x9, :lo12:calloc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	canonicalize_file_name
	.global	_sigfe_canonicalize_file_name
	.seh_proc _sigfe_canonicalize_file_name
_sigfe_canonicalize_file_name:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, canonicalize_file_name
	add	x9, x9, :lo12:canonicalize_file_name
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	catclose
	.global	_sigfe_catclose
	.seh_proc _sigfe_catclose
_sigfe_catclose:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, catclose
	add	x9, x9, :lo12:catclose
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	catgets
	.global	_sigfe_catgets
	.seh_proc _sigfe_catgets
_sigfe_catgets:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, catgets
	add	x9, x9, :lo12:catgets
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	catopen
	.global	_sigfe_catopen
	.seh_proc _sigfe_catopen
_sigfe_catopen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, catopen
	add	x9, x9, :lo12:catopen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cfsetispeed
	.global	_sigfe_cfsetispeed
	.seh_proc _sigfe_cfsetispeed
_sigfe_cfsetispeed:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cfsetispeed
	add	x9, x9, :lo12:cfsetispeed
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cfsetospeed
	.global	_sigfe_cfsetospeed
	.seh_proc _sigfe_cfsetospeed
_sigfe_cfsetospeed:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cfsetospeed
	add	x9, x9, :lo12:cfsetospeed
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cfsetspeed
	.global	_sigfe_cfsetspeed
	.seh_proc _sigfe_cfsetspeed
_sigfe_cfsetspeed:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cfsetspeed
	add	x9, x9, :lo12:cfsetspeed
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	chdir
	.global	_sigfe_chdir
	.seh_proc _sigfe_chdir
_sigfe_chdir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, chdir
	add	x9, x9, :lo12:chdir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	chmod
	.global	_sigfe_chmod
	.seh_proc _sigfe_chmod
_sigfe_chmod:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, chmod
	add	x9, x9, :lo12:chmod
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	chown
	.global	_sigfe_chown
	.seh_proc _sigfe_chown
_sigfe_chown:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, chown
	add	x9, x9, :lo12:chown
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	chroot
	.global	_sigfe_chroot
	.seh_proc _sigfe_chroot
_sigfe_chroot:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, chroot
	add	x9, x9, :lo12:chroot
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clearenv
	.global	_sigfe_clearenv
	.seh_proc _sigfe_clearenv
_sigfe_clearenv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clearenv
	add	x9, x9, :lo12:clearenv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clearerr
	.global	_sigfe_clearerr
	.seh_proc _sigfe_clearerr
_sigfe_clearerr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clearerr
	add	x9, x9, :lo12:clearerr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clearerr_unlocked
	.global	_sigfe_clearerr_unlocked
	.seh_proc _sigfe_clearerr_unlocked
_sigfe_clearerr_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clearerr_unlocked
	add	x9, x9, :lo12:clearerr_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clock
	.global	_sigfe_clock
	.seh_proc _sigfe_clock
_sigfe_clock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clock
	add	x9, x9, :lo12:clock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clock_getcpuclockid
	.global	_sigfe_clock_getcpuclockid
	.seh_proc _sigfe_clock_getcpuclockid
_sigfe_clock_getcpuclockid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clock_getcpuclockid
	add	x9, x9, :lo12:clock_getcpuclockid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clock_getres
	.global	_sigfe_clock_getres
	.seh_proc _sigfe_clock_getres
_sigfe_clock_getres:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clock_getres
	add	x9, x9, :lo12:clock_getres
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clock_gettime
	.global	_sigfe_clock_gettime
	.seh_proc _sigfe_clock_gettime
_sigfe_clock_gettime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clock_gettime
	add	x9, x9, :lo12:clock_gettime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clock_nanosleep
	.global	_sigfe_clock_nanosleep
	.seh_proc _sigfe_clock_nanosleep
_sigfe_clock_nanosleep:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clock_nanosleep
	add	x9, x9, :lo12:clock_nanosleep
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clock_setres
	.global	_sigfe_clock_setres
	.seh_proc _sigfe_clock_setres
_sigfe_clock_setres:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clock_setres
	add	x9, x9, :lo12:clock_setres
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	clock_settime
	.global	_sigfe_clock_settime
	.seh_proc _sigfe_clock_settime
_sigfe_clock_settime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, clock_settime
	add	x9, x9, :lo12:clock_settime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	close
	.global	_sigfe_close
	.seh_proc _sigfe_close
_sigfe_close:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, close
	add	x9, x9, :lo12:close
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	close_range
	.global	_sigfe_close_range
	.seh_proc _sigfe_close_range
_sigfe_close_range:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, close_range
	add	x9, x9, :lo12:close_range
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	closedir
	.global	_sigfe_closedir
	.seh_proc _sigfe_closedir
_sigfe_closedir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, closedir
	add	x9, x9, :lo12:closedir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	closelog
	.global	_sigfe_closelog
	.seh_proc _sigfe_closelog
_sigfe_closelog:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, closelog
	add	x9, x9, :lo12:closelog
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cnd_broadcast
	.global	_sigfe_cnd_broadcast
	.seh_proc _sigfe_cnd_broadcast
_sigfe_cnd_broadcast:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cnd_broadcast
	add	x9, x9, :lo12:cnd_broadcast
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cnd_destroy
	.global	_sigfe_cnd_destroy
	.seh_proc _sigfe_cnd_destroy
_sigfe_cnd_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cnd_destroy
	add	x9, x9, :lo12:cnd_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cnd_init
	.global	_sigfe_cnd_init
	.seh_proc _sigfe_cnd_init
_sigfe_cnd_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cnd_init
	add	x9, x9, :lo12:cnd_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cnd_signal
	.global	_sigfe_cnd_signal
	.seh_proc _sigfe_cnd_signal
_sigfe_cnd_signal:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cnd_signal
	add	x9, x9, :lo12:cnd_signal
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cnd_timedwait
	.global	_sigfe_cnd_timedwait
	.seh_proc _sigfe_cnd_timedwait
_sigfe_cnd_timedwait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cnd_timedwait
	add	x9, x9, :lo12:cnd_timedwait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cnd_wait
	.global	_sigfe_cnd_wait
	.seh_proc _sigfe_cnd_wait
_sigfe_cnd_wait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cnd_wait
	add	x9, x9, :lo12:cnd_wait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	creat
	.global	_sigfe_creat
	.seh_proc _sigfe_creat
_sigfe_creat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, creat
	add	x9, x9, :lo12:creat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ctermid
	.global	_sigfe_ctermid
	.seh_proc _sigfe_ctermid
_sigfe_ctermid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ctermid
	add	x9, x9, :lo12:ctermid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ctime
	.global	_sigfe_ctime
	.seh_proc _sigfe_ctime
_sigfe_ctime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ctime
	add	x9, x9, :lo12:ctime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ctime_r
	.global	_sigfe_ctime_r
	.seh_proc _sigfe_ctime_r
_sigfe_ctime_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ctime_r
	add	x9, x9, :lo12:ctime_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cwait
	.global	_sigfe_cwait
	.seh_proc _sigfe_cwait
_sigfe_cwait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cwait
	add	x9, x9, :lo12:cwait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin__cxa_atexit
	.global	_sigfe_cygwin__cxa_atexit
	.seh_proc _sigfe_cygwin__cxa_atexit
_sigfe_cygwin__cxa_atexit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin__cxa_atexit
	add	x9, x9, :lo12:cygwin__cxa_atexit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_accept
	.global	_sigfe_cygwin_accept
	.seh_proc _sigfe_cygwin_accept
_sigfe_cygwin_accept:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_accept
	add	x9, x9, :lo12:cygwin_accept
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_atexit
	.global	_sigfe_cygwin_atexit
	.seh_proc _sigfe_cygwin_atexit
_sigfe_cygwin_atexit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_atexit
	add	x9, x9, :lo12:cygwin_atexit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_attach_handle_to_fd
	.global	_sigfe_cygwin_attach_handle_to_fd
	.seh_proc _sigfe_cygwin_attach_handle_to_fd
_sigfe_cygwin_attach_handle_to_fd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_attach_handle_to_fd
	add	x9, x9, :lo12:cygwin_attach_handle_to_fd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_bind
	.global	_sigfe_cygwin_bind
	.seh_proc _sigfe_cygwin_bind
_sigfe_cygwin_bind:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_bind
	add	x9, x9, :lo12:cygwin_bind
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_bindresvport
	.global	_sigfe_cygwin_bindresvport
	.seh_proc _sigfe_cygwin_bindresvport
_sigfe_cygwin_bindresvport:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_bindresvport
	add	x9, x9, :lo12:cygwin_bindresvport
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_bindresvport_sa
	.global	_sigfe_cygwin_bindresvport_sa
	.seh_proc _sigfe_cygwin_bindresvport_sa
_sigfe_cygwin_bindresvport_sa:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_bindresvport_sa
	add	x9, x9, :lo12:cygwin_bindresvport_sa
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_connect
	.global	_sigfe_cygwin_connect
	.seh_proc _sigfe_cygwin_connect
_sigfe_cygwin_connect:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_connect
	add	x9, x9, :lo12:cygwin_connect
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_conv_path
	.global	_sigfe_cygwin_conv_path
	.seh_proc _sigfe_cygwin_conv_path
_sigfe_cygwin_conv_path:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_conv_path
	add	x9, x9, :lo12:cygwin_conv_path
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_conv_path_list
	.global	_sigfe_cygwin_conv_path_list
	.seh_proc _sigfe_cygwin_conv_path_list
_sigfe_cygwin_conv_path_list:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_conv_path_list
	add	x9, x9, :lo12:cygwin_conv_path_list
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_create_path
	.global	_sigfe_cygwin_create_path
	.seh_proc _sigfe_cygwin_create_path
_sigfe_cygwin_create_path:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_create_path
	add	x9, x9, :lo12:cygwin_create_path
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_endprotoent
	.global	_sigfe_cygwin_endprotoent
	.seh_proc _sigfe_cygwin_endprotoent
_sigfe_cygwin_endprotoent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_endprotoent
	add	x9, x9, :lo12:cygwin_endprotoent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_endservent
	.global	_sigfe_cygwin_endservent
	.seh_proc _sigfe_cygwin_endservent
_sigfe_cygwin_endservent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_endservent
	add	x9, x9, :lo12:cygwin_endservent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_exit
	.global	_sigfe_cygwin_exit
	.seh_proc _sigfe_cygwin_exit
_sigfe_cygwin_exit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_exit
	add	x9, x9, :lo12:cygwin_exit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_freeaddrinfo
	.global	_sigfe_cygwin_freeaddrinfo
	.seh_proc _sigfe_cygwin_freeaddrinfo
_sigfe_cygwin_freeaddrinfo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_freeaddrinfo
	add	x9, x9, :lo12:cygwin_freeaddrinfo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getaddrinfo
	.global	_sigfe_cygwin_getaddrinfo
	.seh_proc _sigfe_cygwin_getaddrinfo
_sigfe_cygwin_getaddrinfo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getaddrinfo
	add	x9, x9, :lo12:cygwin_getaddrinfo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_gethostbyaddr
	.global	_sigfe_cygwin_gethostbyaddr
	.seh_proc _sigfe_cygwin_gethostbyaddr
_sigfe_cygwin_gethostbyaddr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_gethostbyaddr
	add	x9, x9, :lo12:cygwin_gethostbyaddr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_gethostbyname
	.global	_sigfe_cygwin_gethostbyname
	.seh_proc _sigfe_cygwin_gethostbyname
_sigfe_cygwin_gethostbyname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_gethostbyname
	add	x9, x9, :lo12:cygwin_gethostbyname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_gethostname
	.global	_sigfe_cygwin_gethostname
	.seh_proc _sigfe_cygwin_gethostname
_sigfe_cygwin_gethostname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_gethostname
	add	x9, x9, :lo12:cygwin_gethostname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getnameinfo
	.global	_sigfe_cygwin_getnameinfo
	.seh_proc _sigfe_cygwin_getnameinfo
_sigfe_cygwin_getnameinfo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getnameinfo
	add	x9, x9, :lo12:cygwin_getnameinfo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getpeername
	.global	_sigfe_cygwin_getpeername
	.seh_proc _sigfe_cygwin_getpeername
_sigfe_cygwin_getpeername:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getpeername
	add	x9, x9, :lo12:cygwin_getpeername
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getprotobyname
	.global	_sigfe_cygwin_getprotobyname
	.seh_proc _sigfe_cygwin_getprotobyname
_sigfe_cygwin_getprotobyname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getprotobyname
	add	x9, x9, :lo12:cygwin_getprotobyname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getprotobynumber
	.global	_sigfe_cygwin_getprotobynumber
	.seh_proc _sigfe_cygwin_getprotobynumber
_sigfe_cygwin_getprotobynumber:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getprotobynumber
	add	x9, x9, :lo12:cygwin_getprotobynumber
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getprotoent
	.global	_sigfe_cygwin_getprotoent
	.seh_proc _sigfe_cygwin_getprotoent
_sigfe_cygwin_getprotoent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getprotoent
	add	x9, x9, :lo12:cygwin_getprotoent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getservbyname
	.global	_sigfe_cygwin_getservbyname
	.seh_proc _sigfe_cygwin_getservbyname
_sigfe_cygwin_getservbyname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getservbyname
	add	x9, x9, :lo12:cygwin_getservbyname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getservbyport
	.global	_sigfe_cygwin_getservbyport
	.seh_proc _sigfe_cygwin_getservbyport
_sigfe_cygwin_getservbyport:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getservbyport
	add	x9, x9, :lo12:cygwin_getservbyport
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getservent
	.global	_sigfe_cygwin_getservent
	.seh_proc _sigfe_cygwin_getservent
_sigfe_cygwin_getservent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getservent
	add	x9, x9, :lo12:cygwin_getservent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getsockname
	.global	_sigfe_cygwin_getsockname
	.seh_proc _sigfe_cygwin_getsockname
_sigfe_cygwin_getsockname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getsockname
	add	x9, x9, :lo12:cygwin_getsockname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_getsockopt
	.global	_sigfe_cygwin_getsockopt
	.seh_proc _sigfe_cygwin_getsockopt
_sigfe_cygwin_getsockopt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_getsockopt
	add	x9, x9, :lo12:cygwin_getsockopt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_herror
	.global	_sigfe_cygwin_herror
	.seh_proc _sigfe_cygwin_herror
_sigfe_cygwin_herror:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_herror
	add	x9, x9, :lo12:cygwin_herror
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_if_indextoname
	.global	_sigfe_cygwin_if_indextoname
	.seh_proc _sigfe_cygwin_if_indextoname
_sigfe_cygwin_if_indextoname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_if_indextoname
	add	x9, x9, :lo12:cygwin_if_indextoname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_if_nametoindex
	.global	_sigfe_cygwin_if_nametoindex
	.seh_proc _sigfe_cygwin_if_nametoindex
_sigfe_cygwin_if_nametoindex:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_if_nametoindex
	add	x9, x9, :lo12:cygwin_if_nametoindex
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_inet_addr
	.global	_sigfe_cygwin_inet_addr
	.seh_proc _sigfe_cygwin_inet_addr
_sigfe_cygwin_inet_addr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_inet_addr
	add	x9, x9, :lo12:cygwin_inet_addr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_inet_aton
	.global	_sigfe_cygwin_inet_aton
	.seh_proc _sigfe_cygwin_inet_aton
_sigfe_cygwin_inet_aton:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_inet_aton
	add	x9, x9, :lo12:cygwin_inet_aton
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_inet_network
	.global	_sigfe_cygwin_inet_network
	.seh_proc _sigfe_cygwin_inet_network
_sigfe_cygwin_inet_network:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_inet_network
	add	x9, x9, :lo12:cygwin_inet_network
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_inet_ntoa
	.global	_sigfe_cygwin_inet_ntoa
	.seh_proc _sigfe_cygwin_inet_ntoa
_sigfe_cygwin_inet_ntoa:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_inet_ntoa
	add	x9, x9, :lo12:cygwin_inet_ntoa
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_inet_ntop
	.global	_sigfe_cygwin_inet_ntop
	.seh_proc _sigfe_cygwin_inet_ntop
_sigfe_cygwin_inet_ntop:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_inet_ntop
	add	x9, x9, :lo12:cygwin_inet_ntop
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_inet_pton
	.global	_sigfe_cygwin_inet_pton
	.seh_proc _sigfe_cygwin_inet_pton
_sigfe_cygwin_inet_pton:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_inet_pton
	add	x9, x9, :lo12:cygwin_inet_pton
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_listen
	.global	_sigfe_cygwin_listen
	.seh_proc _sigfe_cygwin_listen
_sigfe_cygwin_listen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_listen
	add	x9, x9, :lo12:cygwin_listen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_logon_user
	.global	_sigfe_cygwin_logon_user
	.seh_proc _sigfe_cygwin_logon_user
_sigfe_cygwin_logon_user:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_logon_user
	add	x9, x9, :lo12:cygwin_logon_user
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_rcmd
	.global	_sigfe_cygwin_rcmd
	.seh_proc _sigfe_cygwin_rcmd
_sigfe_cygwin_rcmd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_rcmd
	add	x9, x9, :lo12:cygwin_rcmd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_rcmd_af
	.global	_sigfe_cygwin_rcmd_af
	.seh_proc _sigfe_cygwin_rcmd_af
_sigfe_cygwin_rcmd_af:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_rcmd_af
	add	x9, x9, :lo12:cygwin_rcmd_af
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_recv
	.global	_sigfe_cygwin_recv
	.seh_proc _sigfe_cygwin_recv
_sigfe_cygwin_recv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_recv
	add	x9, x9, :lo12:cygwin_recv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_recvfrom
	.global	_sigfe_cygwin_recvfrom
	.seh_proc _sigfe_cygwin_recvfrom
_sigfe_cygwin_recvfrom:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_recvfrom
	add	x9, x9, :lo12:cygwin_recvfrom
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_recvmsg
	.global	_sigfe_cygwin_recvmsg
	.seh_proc _sigfe_cygwin_recvmsg
_sigfe_cygwin_recvmsg:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_recvmsg
	add	x9, x9, :lo12:cygwin_recvmsg
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_rexec
	.global	_sigfe_cygwin_rexec
	.seh_proc _sigfe_cygwin_rexec
_sigfe_cygwin_rexec:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_rexec
	add	x9, x9, :lo12:cygwin_rexec
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_rresvport
	.global	_sigfe_cygwin_rresvport
	.seh_proc _sigfe_cygwin_rresvport
_sigfe_cygwin_rresvport:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_rresvport
	add	x9, x9, :lo12:cygwin_rresvport
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_rresvport_af
	.global	_sigfe_cygwin_rresvport_af
	.seh_proc _sigfe_cygwin_rresvport_af
_sigfe_cygwin_rresvport_af:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_rresvport_af
	add	x9, x9, :lo12:cygwin_rresvport_af
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_select
	.global	_sigfe_cygwin_select
	.seh_proc _sigfe_cygwin_select
_sigfe_cygwin_select:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_select
	add	x9, x9, :lo12:cygwin_select
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_send
	.global	_sigfe_cygwin_send
	.seh_proc _sigfe_cygwin_send
_sigfe_cygwin_send:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_send
	add	x9, x9, :lo12:cygwin_send
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_sendmsg
	.global	_sigfe_cygwin_sendmsg
	.seh_proc _sigfe_cygwin_sendmsg
_sigfe_cygwin_sendmsg:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_sendmsg
	add	x9, x9, :lo12:cygwin_sendmsg
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_sendto
	.global	_sigfe_cygwin_sendto
	.seh_proc _sigfe_cygwin_sendto
_sigfe_cygwin_sendto:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_sendto
	add	x9, x9, :lo12:cygwin_sendto
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_set_impersonation_token
	.global	_sigfe_cygwin_set_impersonation_token
	.seh_proc _sigfe_cygwin_set_impersonation_token
_sigfe_cygwin_set_impersonation_token:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_set_impersonation_token
	add	x9, x9, :lo12:cygwin_set_impersonation_token
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_setmode
	.global	_sigfe_cygwin_setmode
	.seh_proc _sigfe_cygwin_setmode
_sigfe_cygwin_setmode:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_setmode
	add	x9, x9, :lo12:cygwin_setmode
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_setprotoent
	.global	_sigfe_cygwin_setprotoent
	.seh_proc _sigfe_cygwin_setprotoent
_sigfe_cygwin_setprotoent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_setprotoent
	add	x9, x9, :lo12:cygwin_setprotoent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_setservent
	.global	_sigfe_cygwin_setservent
	.seh_proc _sigfe_cygwin_setservent
_sigfe_cygwin_setservent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_setservent
	add	x9, x9, :lo12:cygwin_setservent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_setsockopt
	.global	_sigfe_cygwin_setsockopt
	.seh_proc _sigfe_cygwin_setsockopt
_sigfe_cygwin_setsockopt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_setsockopt
	add	x9, x9, :lo12:cygwin_setsockopt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_shutdown
	.global	_sigfe_cygwin_shutdown
	.seh_proc _sigfe_cygwin_shutdown
_sigfe_cygwin_shutdown:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_shutdown
	add	x9, x9, :lo12:cygwin_shutdown
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_socket
	.global	_sigfe_cygwin_socket
	.seh_proc _sigfe_cygwin_socket
_sigfe_cygwin_socket:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_socket
	add	x9, x9, :lo12:cygwin_socket
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_stackdump
	.global	_sigfe_cygwin_stackdump
	.seh_proc _sigfe_cygwin_stackdump
_sigfe_cygwin_stackdump:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_stackdump
	add	x9, x9, :lo12:cygwin_stackdump
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_umount
	.global	_sigfe_cygwin_umount
	.seh_proc _sigfe_cygwin_umount
_sigfe_cygwin_umount:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_umount
	add	x9, x9, :lo12:cygwin_umount
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	cygwin_winpid_to_pid
	.global	_sigfe_cygwin_winpid_to_pid
	.seh_proc _sigfe_cygwin_winpid_to_pid
_sigfe_cygwin_winpid_to_pid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, cygwin_winpid_to_pid
	add	x9, x9, :lo12:cygwin_winpid_to_pid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	daemon
	.global	_sigfe_daemon
	.seh_proc _sigfe_daemon
_sigfe_daemon:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, daemon
	add	x9, x9, :lo12:daemon
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_clearerr
	.global	_sigfe_dbm_clearerr
	.seh_proc _sigfe_dbm_clearerr
_sigfe_dbm_clearerr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_clearerr
	add	x9, x9, :lo12:dbm_clearerr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_close
	.global	_sigfe_dbm_close
	.seh_proc _sigfe_dbm_close
_sigfe_dbm_close:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_close
	add	x9, x9, :lo12:dbm_close
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_delete
	.global	_sigfe_dbm_delete
	.seh_proc _sigfe_dbm_delete
_sigfe_dbm_delete:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_delete
	add	x9, x9, :lo12:dbm_delete
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_dirfno
	.global	_sigfe_dbm_dirfno
	.seh_proc _sigfe_dbm_dirfno
_sigfe_dbm_dirfno:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_dirfno
	add	x9, x9, :lo12:dbm_dirfno
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_error
	.global	_sigfe_dbm_error
	.seh_proc _sigfe_dbm_error
_sigfe_dbm_error:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_error
	add	x9, x9, :lo12:dbm_error
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_fetch
	.global	_sigfe_dbm_fetch
	.seh_proc _sigfe_dbm_fetch
_sigfe_dbm_fetch:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_fetch
	add	x9, x9, :lo12:dbm_fetch
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_firstkey
	.global	_sigfe_dbm_firstkey
	.seh_proc _sigfe_dbm_firstkey
_sigfe_dbm_firstkey:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_firstkey
	add	x9, x9, :lo12:dbm_firstkey
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_nextkey
	.global	_sigfe_dbm_nextkey
	.seh_proc _sigfe_dbm_nextkey
_sigfe_dbm_nextkey:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_nextkey
	add	x9, x9, :lo12:dbm_nextkey
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_open
	.global	_sigfe_dbm_open
	.seh_proc _sigfe_dbm_open
_sigfe_dbm_open:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_open
	add	x9, x9, :lo12:dbm_open
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dbm_store
	.global	_sigfe_dbm_store
	.seh_proc _sigfe_dbm_store
_sigfe_dbm_store:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dbm_store
	add	x9, x9, :lo12:dbm_store
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dirfd
	.global	_sigfe_dirfd
	.seh_proc _sigfe_dirfd
_sigfe_dirfd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dirfd
	add	x9, x9, :lo12:dirfd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dladdr
	.global	_sigfe_dladdr
	.seh_proc _sigfe_dladdr
_sigfe_dladdr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dladdr
	add	x9, x9, :lo12:dladdr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dlclose
	.global	_sigfe_dlclose
	.seh_proc _sigfe_dlclose
_sigfe_dlclose:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dlclose
	add	x9, x9, :lo12:dlclose
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dlopen
	.global	_sigfe_dlopen
	.seh_proc _sigfe_dlopen
_sigfe_dlopen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dlopen
	add	x9, x9, :lo12:dlopen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dlsym
	.global	_sigfe_dlsym
	.seh_proc _sigfe_dlsym
_sigfe_dlsym:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dlsym
	add	x9, x9, :lo12:dlsym
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dprintf
	.global	_sigfe_dprintf
	.seh_proc _sigfe_dprintf
_sigfe_dprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dprintf
	add	x9, x9, :lo12:dprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dup
	.global	_sigfe_dup
	.seh_proc _sigfe_dup
_sigfe_dup:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dup
	add	x9, x9, :lo12:dup
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dup2
	.global	_sigfe_dup2
	.seh_proc _sigfe_dup2
_sigfe_dup2:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dup2
	add	x9, x9, :lo12:dup2
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	dup3
	.global	_sigfe_dup3
	.seh_proc _sigfe_dup3
_sigfe_dup3:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, dup3
	add	x9, x9, :lo12:dup3
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	duplocale
	.global	_sigfe_duplocale
	.seh_proc _sigfe_duplocale
_sigfe_duplocale:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, duplocale
	add	x9, x9, :lo12:duplocale
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ecvt
	.global	_sigfe_ecvt
	.seh_proc _sigfe_ecvt
_sigfe_ecvt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ecvt
	add	x9, x9, :lo12:ecvt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ecvtbuf
	.global	_sigfe_ecvtbuf
	.seh_proc _sigfe_ecvtbuf
_sigfe_ecvtbuf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ecvtbuf
	add	x9, x9, :lo12:ecvtbuf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ecvtf
	.global	_sigfe_ecvtf
	.seh_proc _sigfe_ecvtf
_sigfe_ecvtf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ecvtf
	add	x9, x9, :lo12:ecvtf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	endusershell
	.global	_sigfe_endusershell
	.seh_proc _sigfe_endusershell
_sigfe_endusershell:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, endusershell
	add	x9, x9, :lo12:endusershell
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	endutent
	.global	_sigfe_endutent
	.seh_proc _sigfe_endutent
_sigfe_endutent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, endutent
	add	x9, x9, :lo12:endutent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	endutxent
	.global	_sigfe_endutxent
	.seh_proc _sigfe_endutxent
_sigfe_endutxent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, endutxent
	add	x9, x9, :lo12:endutxent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	envz_add
	.global	_sigfe_envz_add
	.seh_proc _sigfe_envz_add
_sigfe_envz_add:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, envz_add
	add	x9, x9, :lo12:envz_add
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	envz_merge
	.global	_sigfe_envz_merge
	.seh_proc _sigfe_envz_merge
_sigfe_envz_merge:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, envz_merge
	add	x9, x9, :lo12:envz_merge
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	envz_remove
	.global	_sigfe_envz_remove
	.seh_proc _sigfe_envz_remove
_sigfe_envz_remove:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, envz_remove
	add	x9, x9, :lo12:envz_remove
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	envz_strip
	.global	_sigfe_envz_strip
	.seh_proc _sigfe_envz_strip
_sigfe_envz_strip:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, envz_strip
	add	x9, x9, :lo12:envz_strip
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	err
	.global	_sigfe_err
	.seh_proc _sigfe_err
_sigfe_err:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, err
	add	x9, x9, :lo12:err
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	error
	.global	_sigfe_error
	.seh_proc _sigfe_error
_sigfe_error:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, error
	add	x9, x9, :lo12:error
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	error_at_line
	.global	_sigfe_error_at_line
	.seh_proc _sigfe_error_at_line
_sigfe_error_at_line:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, error_at_line
	add	x9, x9, :lo12:error_at_line
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	errx
	.global	_sigfe_errx
	.seh_proc _sigfe_errx
_sigfe_errx:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, errx
	add	x9, x9, :lo12:errx
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	euidaccess
	.global	_sigfe_euidaccess
	.seh_proc _sigfe_euidaccess
_sigfe_euidaccess:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, euidaccess
	add	x9, x9, :lo12:euidaccess
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	execl
	.global	_sigfe_execl
	.seh_proc _sigfe_execl
_sigfe_execl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, execl
	add	x9, x9, :lo12:execl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	execle
	.global	_sigfe_execle
	.seh_proc _sigfe_execle
_sigfe_execle:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, execle
	add	x9, x9, :lo12:execle
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	execlp
	.global	_sigfe_execlp
	.seh_proc _sigfe_execlp
_sigfe_execlp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, execlp
	add	x9, x9, :lo12:execlp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	execv
	.global	_sigfe_execv
	.seh_proc _sigfe_execv
_sigfe_execv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, execv
	add	x9, x9, :lo12:execv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	execve
	.global	_sigfe_execve
	.seh_proc _sigfe_execve
_sigfe_execve:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, execve
	add	x9, x9, :lo12:execve
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	execvp
	.global	_sigfe_execvp
	.seh_proc _sigfe_execvp
_sigfe_execvp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, execvp
	add	x9, x9, :lo12:execvp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	execvpe
	.global	_sigfe_execvpe
	.seh_proc _sigfe_execvpe
_sigfe_execvpe:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, execvpe
	add	x9, x9, :lo12:execvpe
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	faccessat
	.global	_sigfe_faccessat
	.seh_proc _sigfe_faccessat
_sigfe_faccessat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, faccessat
	add	x9, x9, :lo12:faccessat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	facl
	.global	_sigfe_facl
	.seh_proc _sigfe_facl
_sigfe_facl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, facl
	add	x9, x9, :lo12:facl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fallocate
	.global	_sigfe_fallocate
	.seh_proc _sigfe_fallocate
_sigfe_fallocate:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fallocate
	add	x9, x9, :lo12:fallocate
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fchdir
	.global	_sigfe_fchdir
	.seh_proc _sigfe_fchdir
_sigfe_fchdir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fchdir
	add	x9, x9, :lo12:fchdir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fchmod
	.global	_sigfe_fchmod
	.seh_proc _sigfe_fchmod
_sigfe_fchmod:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fchmod
	add	x9, x9, :lo12:fchmod
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fchmodat
	.global	_sigfe_fchmodat
	.seh_proc _sigfe_fchmodat
_sigfe_fchmodat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fchmodat
	add	x9, x9, :lo12:fchmodat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fchown
	.global	_sigfe_fchown
	.seh_proc _sigfe_fchown
_sigfe_fchown:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fchown
	add	x9, x9, :lo12:fchown
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fchownat
	.global	_sigfe_fchownat
	.seh_proc _sigfe_fchownat
_sigfe_fchownat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fchownat
	add	x9, x9, :lo12:fchownat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fclose
	.global	_sigfe_fclose
	.seh_proc _sigfe_fclose
_sigfe_fclose:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fclose
	add	x9, x9, :lo12:fclose
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fcloseall
	.global	_sigfe_fcloseall
	.seh_proc _sigfe_fcloseall
_sigfe_fcloseall:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fcloseall
	add	x9, x9, :lo12:fcloseall
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fcntl
	.global	_sigfe_fcntl
	.seh_proc _sigfe_fcntl
_sigfe_fcntl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fcntl
	add	x9, x9, :lo12:fcntl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fcvt
	.global	_sigfe_fcvt
	.seh_proc _sigfe_fcvt
_sigfe_fcvt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fcvt
	add	x9, x9, :lo12:fcvt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fcvtbuf
	.global	_sigfe_fcvtbuf
	.seh_proc _sigfe_fcvtbuf
_sigfe_fcvtbuf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fcvtbuf
	add	x9, x9, :lo12:fcvtbuf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fcvtf
	.global	_sigfe_fcvtf
	.seh_proc _sigfe_fcvtf
_sigfe_fcvtf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fcvtf
	add	x9, x9, :lo12:fcvtf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fdatasync
	.global	_sigfe_fdatasync
	.seh_proc _sigfe_fdatasync
_sigfe_fdatasync:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fdatasync
	add	x9, x9, :lo12:fdatasync
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fdclosedir
	.global	_sigfe_fdclosedir
	.seh_proc _sigfe_fdclosedir
_sigfe_fdclosedir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fdclosedir
	add	x9, x9, :lo12:fdclosedir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fdopen
	.global	_sigfe_fdopen
	.seh_proc _sigfe_fdopen
_sigfe_fdopen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fdopen
	add	x9, x9, :lo12:fdopen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fdopendir
	.global	_sigfe_fdopendir
	.seh_proc _sigfe_fdopendir
_sigfe_fdopendir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fdopendir
	add	x9, x9, :lo12:fdopendir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	feenableexcept
	.global	_sigfe_feenableexcept
	.seh_proc _sigfe_feenableexcept
_sigfe_feenableexcept:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, feenableexcept
	add	x9, x9, :lo12:feenableexcept
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	feholdexcept
	.global	_sigfe_feholdexcept
	.seh_proc _sigfe_feholdexcept
_sigfe_feholdexcept:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, feholdexcept
	add	x9, x9, :lo12:feholdexcept
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	feof
	.global	_sigfe_feof
	.seh_proc _sigfe_feof
_sigfe_feof:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, feof
	add	x9, x9, :lo12:feof
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	feof_unlocked
	.global	_sigfe_feof_unlocked
	.seh_proc _sigfe_feof_unlocked
_sigfe_feof_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, feof_unlocked
	add	x9, x9, :lo12:feof_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ferror
	.global	_sigfe_ferror
	.seh_proc _sigfe_ferror
_sigfe_ferror:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ferror
	add	x9, x9, :lo12:ferror
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ferror_unlocked
	.global	_sigfe_ferror_unlocked
	.seh_proc _sigfe_ferror_unlocked
_sigfe_ferror_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ferror_unlocked
	add	x9, x9, :lo12:ferror_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fesetenv
	.global	_sigfe_fesetenv
	.seh_proc _sigfe_fesetenv
_sigfe_fesetenv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fesetenv
	add	x9, x9, :lo12:fesetenv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fesetexceptflag
	.global	_sigfe_fesetexceptflag
	.seh_proc _sigfe_fesetexceptflag
_sigfe_fesetexceptflag:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fesetexceptflag
	add	x9, x9, :lo12:fesetexceptflag
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	feupdateenv
	.global	_sigfe_feupdateenv
	.seh_proc _sigfe_feupdateenv
_sigfe_feupdateenv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, feupdateenv
	add	x9, x9, :lo12:feupdateenv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fexecve
	.global	_sigfe_fexecve
	.seh_proc _sigfe_fexecve
_sigfe_fexecve:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fexecve
	add	x9, x9, :lo12:fexecve
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fflush
	.global	_sigfe_fflush
	.seh_proc _sigfe_fflush
_sigfe_fflush:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fflush
	add	x9, x9, :lo12:fflush
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fflush_unlocked
	.global	_sigfe_fflush_unlocked
	.seh_proc _sigfe_fflush_unlocked
_sigfe_fflush_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fflush_unlocked
	add	x9, x9, :lo12:fflush_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgetc
	.global	_sigfe_fgetc
	.seh_proc _sigfe_fgetc
_sigfe_fgetc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgetc
	add	x9, x9, :lo12:fgetc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgetc_unlocked
	.global	_sigfe_fgetc_unlocked
	.seh_proc _sigfe_fgetc_unlocked
_sigfe_fgetc_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgetc_unlocked
	add	x9, x9, :lo12:fgetc_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgetpos
	.global	_sigfe_fgetpos
	.seh_proc _sigfe_fgetpos
_sigfe_fgetpos:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgetpos
	add	x9, x9, :lo12:fgetpos
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgets
	.global	_sigfe_fgets
	.seh_proc _sigfe_fgets
_sigfe_fgets:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgets
	add	x9, x9, :lo12:fgets
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgets_unlocked
	.global	_sigfe_fgets_unlocked
	.seh_proc _sigfe_fgets_unlocked
_sigfe_fgets_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgets_unlocked
	add	x9, x9, :lo12:fgets_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgetwc
	.global	_sigfe_fgetwc
	.seh_proc _sigfe_fgetwc
_sigfe_fgetwc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgetwc
	add	x9, x9, :lo12:fgetwc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgetwc_unlocked
	.global	_sigfe_fgetwc_unlocked
	.seh_proc _sigfe_fgetwc_unlocked
_sigfe_fgetwc_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgetwc_unlocked
	add	x9, x9, :lo12:fgetwc_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgetws
	.global	_sigfe_fgetws
	.seh_proc _sigfe_fgetws
_sigfe_fgetws:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgetws
	add	x9, x9, :lo12:fgetws
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgetws_unlocked
	.global	_sigfe_fgetws_unlocked
	.seh_proc _sigfe_fgetws_unlocked
_sigfe_fgetws_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgetws_unlocked
	add	x9, x9, :lo12:fgetws_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fgetxattr
	.global	_sigfe_fgetxattr
	.seh_proc _sigfe_fgetxattr
_sigfe_fgetxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fgetxattr
	add	x9, x9, :lo12:fgetxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fileno
	.global	_sigfe_fileno
	.seh_proc _sigfe_fileno
_sigfe_fileno:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fileno
	add	x9, x9, :lo12:fileno
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fileno_unlocked
	.global	_sigfe_fileno_unlocked
	.seh_proc _sigfe_fileno_unlocked
_sigfe_fileno_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fileno_unlocked
	add	x9, x9, :lo12:fileno_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fiprintf
	.global	_sigfe_fiprintf
	.seh_proc _sigfe_fiprintf
_sigfe_fiprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fiprintf
	add	x9, x9, :lo12:fiprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	flistxattr
	.global	_sigfe_flistxattr
	.seh_proc _sigfe_flistxattr
_sigfe_flistxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, flistxattr
	add	x9, x9, :lo12:flistxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	flock
	.global	_sigfe_flock
	.seh_proc _sigfe_flock
_sigfe_flock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, flock
	add	x9, x9, :lo12:flock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	flockfile
	.global	_sigfe_flockfile
	.seh_proc _sigfe_flockfile
_sigfe_flockfile:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, flockfile
	add	x9, x9, :lo12:flockfile
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fmemopen
	.global	_sigfe_fmemopen
	.seh_proc _sigfe_fmemopen
_sigfe_fmemopen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fmemopen
	add	x9, x9, :lo12:fmemopen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fopen
	.global	_sigfe_fopen
	.seh_proc _sigfe_fopen
_sigfe_fopen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fopen
	add	x9, x9, :lo12:fopen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fopencookie
	.global	_sigfe_fopencookie
	.seh_proc _sigfe_fopencookie
_sigfe_fopencookie:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fopencookie
	add	x9, x9, :lo12:fopencookie
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fork
	.global	_sigfe_fork
	.seh_proc _sigfe_fork
_sigfe_fork:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fork
	add	x9, x9, :lo12:fork
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	forkpty
	.global	_sigfe_forkpty
	.seh_proc _sigfe_forkpty
_sigfe_forkpty:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, forkpty
	add	x9, x9, :lo12:forkpty
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fpathconf
	.global	_sigfe_fpathconf
	.seh_proc _sigfe_fpathconf
_sigfe_fpathconf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fpathconf
	add	x9, x9, :lo12:fpathconf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fprintf
	.global	_sigfe_fprintf
	.seh_proc _sigfe_fprintf
_sigfe_fprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fprintf
	add	x9, x9, :lo12:fprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fpurge
	.global	_sigfe_fpurge
	.seh_proc _sigfe_fpurge
_sigfe_fpurge:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fpurge
	add	x9, x9, :lo12:fpurge
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fputc
	.global	_sigfe_fputc
	.seh_proc _sigfe_fputc
_sigfe_fputc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fputc
	add	x9, x9, :lo12:fputc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fputc_unlocked
	.global	_sigfe_fputc_unlocked
	.seh_proc _sigfe_fputc_unlocked
_sigfe_fputc_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fputc_unlocked
	add	x9, x9, :lo12:fputc_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fputs
	.global	_sigfe_fputs
	.seh_proc _sigfe_fputs
_sigfe_fputs:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fputs
	add	x9, x9, :lo12:fputs
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fputs_unlocked
	.global	_sigfe_fputs_unlocked
	.seh_proc _sigfe_fputs_unlocked
_sigfe_fputs_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fputs_unlocked
	add	x9, x9, :lo12:fputs_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fputwc
	.global	_sigfe_fputwc
	.seh_proc _sigfe_fputwc
_sigfe_fputwc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fputwc
	add	x9, x9, :lo12:fputwc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fputwc_unlocked
	.global	_sigfe_fputwc_unlocked
	.seh_proc _sigfe_fputwc_unlocked
_sigfe_fputwc_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fputwc_unlocked
	add	x9, x9, :lo12:fputwc_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fputws
	.global	_sigfe_fputws
	.seh_proc _sigfe_fputws
_sigfe_fputws:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fputws
	add	x9, x9, :lo12:fputws
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fputws_unlocked
	.global	_sigfe_fputws_unlocked
	.seh_proc _sigfe_fputws_unlocked
_sigfe_fputws_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fputws_unlocked
	add	x9, x9, :lo12:fputws_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fread
	.global	_sigfe_fread
	.seh_proc _sigfe_fread
_sigfe_fread:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fread
	add	x9, x9, :lo12:fread
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fread_unlocked
	.global	_sigfe_fread_unlocked
	.seh_proc _sigfe_fread_unlocked
_sigfe_fread_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fread_unlocked
	add	x9, x9, :lo12:fread_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	free
	.global	_sigfe_free
	.seh_proc _sigfe_free
_sigfe_free:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, free
	add	x9, x9, :lo12:free
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	freeifaddrs
	.global	_sigfe_freeifaddrs
	.seh_proc _sigfe_freeifaddrs
_sigfe_freeifaddrs:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, freeifaddrs
	add	x9, x9, :lo12:freeifaddrs
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	freelocale
	.global	_sigfe_freelocale
	.seh_proc _sigfe_freelocale
_sigfe_freelocale:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, freelocale
	add	x9, x9, :lo12:freelocale
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fremovexattr
	.global	_sigfe_fremovexattr
	.seh_proc _sigfe_fremovexattr
_sigfe_fremovexattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fremovexattr
	add	x9, x9, :lo12:fremovexattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	freopen
	.global	_sigfe_freopen
	.seh_proc _sigfe_freopen
_sigfe_freopen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, freopen
	add	x9, x9, :lo12:freopen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fscanf
	.global	_sigfe_fscanf
	.seh_proc _sigfe_fscanf
_sigfe_fscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fscanf
	add	x9, x9, :lo12:fscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fseek
	.global	_sigfe_fseek
	.seh_proc _sigfe_fseek
_sigfe_fseek:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fseek
	add	x9, x9, :lo12:fseek
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fseeko
	.global	_sigfe_fseeko
	.seh_proc _sigfe_fseeko
_sigfe_fseeko:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fseeko
	add	x9, x9, :lo12:fseeko
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fsetpos
	.global	_sigfe_fsetpos
	.seh_proc _sigfe_fsetpos
_sigfe_fsetpos:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fsetpos
	add	x9, x9, :lo12:fsetpos
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fsetxattr
	.global	_sigfe_fsetxattr
	.seh_proc _sigfe_fsetxattr
_sigfe_fsetxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fsetxattr
	add	x9, x9, :lo12:fsetxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fstat
	.global	_sigfe_fstat
	.seh_proc _sigfe_fstat
_sigfe_fstat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fstat
	add	x9, x9, :lo12:fstat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fstatat
	.global	_sigfe_fstatat
	.seh_proc _sigfe_fstatat
_sigfe_fstatat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fstatat
	add	x9, x9, :lo12:fstatat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fstatfs
	.global	_sigfe_fstatfs
	.seh_proc _sigfe_fstatfs
_sigfe_fstatfs:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fstatfs
	add	x9, x9, :lo12:fstatfs
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fstatvfs
	.global	_sigfe_fstatvfs
	.seh_proc _sigfe_fstatvfs
_sigfe_fstatvfs:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fstatvfs
	add	x9, x9, :lo12:fstatvfs
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fsync
	.global	_sigfe_fsync
	.seh_proc _sigfe_fsync
_sigfe_fsync:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fsync
	add	x9, x9, :lo12:fsync
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ftell
	.global	_sigfe_ftell
	.seh_proc _sigfe_ftell
_sigfe_ftell:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ftell
	add	x9, x9, :lo12:ftell
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ftello
	.global	_sigfe_ftello
	.seh_proc _sigfe_ftello
_sigfe_ftello:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ftello
	add	x9, x9, :lo12:ftello
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ftime
	.global	_sigfe_ftime
	.seh_proc _sigfe_ftime
_sigfe_ftime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ftime
	add	x9, x9, :lo12:ftime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ftok
	.global	_sigfe_ftok
	.seh_proc _sigfe_ftok
_sigfe_ftok:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ftok
	add	x9, x9, :lo12:ftok
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ftruncate
	.global	_sigfe_ftruncate
	.seh_proc _sigfe_ftruncate
_sigfe_ftruncate:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ftruncate
	add	x9, x9, :lo12:ftruncate
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ftrylockfile
	.global	_sigfe_ftrylockfile
	.seh_proc _sigfe_ftrylockfile
_sigfe_ftrylockfile:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ftrylockfile
	add	x9, x9, :lo12:ftrylockfile
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fts_children
	.global	_sigfe_fts_children
	.seh_proc _sigfe_fts_children
_sigfe_fts_children:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fts_children
	add	x9, x9, :lo12:fts_children
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fts_close
	.global	_sigfe_fts_close
	.seh_proc _sigfe_fts_close
_sigfe_fts_close:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fts_close
	add	x9, x9, :lo12:fts_close
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fts_open
	.global	_sigfe_fts_open
	.seh_proc _sigfe_fts_open
_sigfe_fts_open:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fts_open
	add	x9, x9, :lo12:fts_open
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fts_read
	.global	_sigfe_fts_read
	.seh_proc _sigfe_fts_read
_sigfe_fts_read:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fts_read
	add	x9, x9, :lo12:fts_read
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ftw
	.global	_sigfe_ftw
	.seh_proc _sigfe_ftw
_sigfe_ftw:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ftw
	add	x9, x9, :lo12:ftw
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	funlockfile
	.global	_sigfe_funlockfile
	.seh_proc _sigfe_funlockfile
_sigfe_funlockfile:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, funlockfile
	add	x9, x9, :lo12:funlockfile
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	funopen
	.global	_sigfe_funopen
	.seh_proc _sigfe_funopen
_sigfe_funopen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, funopen
	add	x9, x9, :lo12:funopen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	futimens
	.global	_sigfe_futimens
	.seh_proc _sigfe_futimens
_sigfe_futimens:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, futimens
	add	x9, x9, :lo12:futimens
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	futimes
	.global	_sigfe_futimes
	.seh_proc _sigfe_futimes
_sigfe_futimes:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, futimes
	add	x9, x9, :lo12:futimes
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	futimesat
	.global	_sigfe_futimesat
	.seh_proc _sigfe_futimesat
_sigfe_futimesat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, futimesat
	add	x9, x9, :lo12:futimesat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fwide
	.global	_sigfe_fwide
	.seh_proc _sigfe_fwide
_sigfe_fwide:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fwide
	add	x9, x9, :lo12:fwide
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fwprintf
	.global	_sigfe_fwprintf
	.seh_proc _sigfe_fwprintf
_sigfe_fwprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fwprintf
	add	x9, x9, :lo12:fwprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fwrite
	.global	_sigfe_fwrite
	.seh_proc _sigfe_fwrite
_sigfe_fwrite:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fwrite
	add	x9, x9, :lo12:fwrite
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fwrite_unlocked
	.global	_sigfe_fwrite_unlocked
	.seh_proc _sigfe_fwrite_unlocked
_sigfe_fwrite_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fwrite_unlocked
	add	x9, x9, :lo12:fwrite_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	fwscanf
	.global	_sigfe_fwscanf
	.seh_proc _sigfe_fwscanf
_sigfe_fwscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, fwscanf
	add	x9, x9, :lo12:fwscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	gcvt
	.global	_sigfe_gcvt
	.seh_proc _sigfe_gcvt
_sigfe_gcvt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, gcvt
	add	x9, x9, :lo12:gcvt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	gcvtf
	.global	_sigfe_gcvtf
	.seh_proc _sigfe_gcvtf
_sigfe_gcvtf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, gcvtf
	add	x9, x9, :lo12:gcvtf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	get_avphys_pages
	.global	_sigfe_get_avphys_pages
	.seh_proc _sigfe_get_avphys_pages
_sigfe_get_avphys_pages:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, get_avphys_pages
	add	x9, x9, :lo12:get_avphys_pages
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	get_current_dir_name
	.global	_sigfe_get_current_dir_name
	.seh_proc _sigfe_get_current_dir_name
_sigfe_get_current_dir_name:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, get_current_dir_name
	add	x9, x9, :lo12:get_current_dir_name
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	get_nprocs
	.global	_sigfe_get_nprocs
	.seh_proc _sigfe_get_nprocs
_sigfe_get_nprocs:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, get_nprocs
	add	x9, x9, :lo12:get_nprocs
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	get_nprocs_conf
	.global	_sigfe_get_nprocs_conf
	.seh_proc _sigfe_get_nprocs_conf
_sigfe_get_nprocs_conf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, get_nprocs_conf
	add	x9, x9, :lo12:get_nprocs_conf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	get_phys_pages
	.global	_sigfe_get_phys_pages
	.seh_proc _sigfe_get_phys_pages
_sigfe_get_phys_pages:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, get_phys_pages
	add	x9, x9, :lo12:get_phys_pages
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getc
	.global	_sigfe_getc
	.seh_proc _sigfe_getc
_sigfe_getc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getc
	add	x9, x9, :lo12:getc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getc_unlocked
	.global	_sigfe_getc_unlocked
	.seh_proc _sigfe_getc_unlocked
_sigfe_getc_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getc_unlocked
	add	x9, x9, :lo12:getc_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getchar
	.global	_sigfe_getchar
	.seh_proc _sigfe_getchar
_sigfe_getchar:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getchar
	add	x9, x9, :lo12:getchar
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getchar_unlocked
	.global	_sigfe_getchar_unlocked
	.seh_proc _sigfe_getchar_unlocked
_sigfe_getchar_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getchar_unlocked
	add	x9, x9, :lo12:getchar_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getcwd
	.global	_sigfe_getcwd
	.seh_proc _sigfe_getcwd
_sigfe_getcwd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getcwd
	add	x9, x9, :lo12:getcwd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getdomainname
	.global	_sigfe_getdomainname
	.seh_proc _sigfe_getdomainname
_sigfe_getdomainname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getdomainname
	add	x9, x9, :lo12:getdomainname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getentropy
	.global	_sigfe_getentropy
	.seh_proc _sigfe_getentropy
_sigfe_getentropy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getentropy
	add	x9, x9, :lo12:getentropy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getgrent
	.global	_sigfe_getgrent
	.seh_proc _sigfe_getgrent
_sigfe_getgrent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getgrent
	add	x9, x9, :lo12:getgrent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getgrgid
	.global	_sigfe_getgrgid
	.seh_proc _sigfe_getgrgid
_sigfe_getgrgid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getgrgid
	add	x9, x9, :lo12:getgrgid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getgrgid_r
	.global	_sigfe_getgrgid_r
	.seh_proc _sigfe_getgrgid_r
_sigfe_getgrgid_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getgrgid_r
	add	x9, x9, :lo12:getgrgid_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getgrnam
	.global	_sigfe_getgrnam
	.seh_proc _sigfe_getgrnam
_sigfe_getgrnam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getgrnam
	add	x9, x9, :lo12:getgrnam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getgrnam_r
	.global	_sigfe_getgrnam_r
	.seh_proc _sigfe_getgrnam_r
_sigfe_getgrnam_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getgrnam_r
	add	x9, x9, :lo12:getgrnam_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getgrouplist
	.global	_sigfe_getgrouplist
	.seh_proc _sigfe_getgrouplist
_sigfe_getgrouplist:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getgrouplist
	add	x9, x9, :lo12:getgrouplist
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getgroups
	.global	_sigfe_getgroups
	.seh_proc _sigfe_getgroups
_sigfe_getgroups:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getgroups
	add	x9, x9, :lo12:getgroups
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	gethostbyname2
	.global	_sigfe_gethostbyname2
	.seh_proc _sigfe_gethostbyname2
_sigfe_gethostbyname2:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, gethostbyname2
	add	x9, x9, :lo12:gethostbyname2
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	gethostid
	.global	_sigfe_gethostid
	.seh_proc _sigfe_gethostid
_sigfe_gethostid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, gethostid
	add	x9, x9, :lo12:gethostid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getifaddrs
	.global	_sigfe_getifaddrs
	.seh_proc _sigfe_getifaddrs
_sigfe_getifaddrs:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getifaddrs
	add	x9, x9, :lo12:getifaddrs
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getitimer
	.global	_sigfe_getitimer
	.seh_proc _sigfe_getitimer
_sigfe_getitimer:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getitimer
	add	x9, x9, :lo12:getitimer
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getloadavg
	.global	_sigfe_getloadavg
	.seh_proc _sigfe_getloadavg
_sigfe_getloadavg:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getloadavg
	add	x9, x9, :lo12:getloadavg
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getlocalename_l
	.global	_sigfe_getlocalename_l
	.seh_proc _sigfe_getlocalename_l
_sigfe_getlocalename_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getlocalename_l
	add	x9, x9, :lo12:getlocalename_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getmntent
	.global	_sigfe_getmntent
	.seh_proc _sigfe_getmntent
_sigfe_getmntent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getmntent
	add	x9, x9, :lo12:getmntent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getmntent_r
	.global	_sigfe_getmntent_r
	.seh_proc _sigfe_getmntent_r
_sigfe_getmntent_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getmntent_r
	add	x9, x9, :lo12:getmntent_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getmode
	.global	_sigfe_getmode
	.seh_proc _sigfe_getmode
_sigfe_getmode:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getmode
	add	x9, x9, :lo12:getmode
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getopt
	.global	_sigfe_getopt
	.seh_proc _sigfe_getopt
_sigfe_getopt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getopt
	add	x9, x9, :lo12:getopt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getopt_long
	.global	_sigfe_getopt_long
	.seh_proc _sigfe_getopt_long
_sigfe_getopt_long:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getopt_long
	add	x9, x9, :lo12:getopt_long
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getopt_long_only
	.global	_sigfe_getopt_long_only
	.seh_proc _sigfe_getopt_long_only
_sigfe_getopt_long_only:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getopt_long_only
	add	x9, x9, :lo12:getopt_long_only
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpagesize
	.global	_sigfe_getpagesize
	.seh_proc _sigfe_getpagesize
_sigfe_getpagesize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpagesize
	add	x9, x9, :lo12:getpagesize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpass
	.global	_sigfe_getpass
	.seh_proc _sigfe_getpass
_sigfe_getpass:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpass
	add	x9, x9, :lo12:getpass
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpeereid
	.global	_sigfe_getpeereid
	.seh_proc _sigfe_getpeereid
_sigfe_getpeereid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpeereid
	add	x9, x9, :lo12:getpeereid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpgid
	.global	_sigfe_getpgid
	.seh_proc _sigfe_getpgid
_sigfe_getpgid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpgid
	add	x9, x9, :lo12:getpgid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpgrp
	.global	_sigfe_getpgrp
	.seh_proc _sigfe_getpgrp
_sigfe_getpgrp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpgrp
	add	x9, x9, :lo12:getpgrp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpriority
	.global	_sigfe_getpriority
	.seh_proc _sigfe_getpriority
_sigfe_getpriority:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpriority
	add	x9, x9, :lo12:getpriority
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpt
	.global	_sigfe_getpt
	.seh_proc _sigfe_getpt
_sigfe_getpt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpt
	add	x9, x9, :lo12:getpt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpwent
	.global	_sigfe_getpwent
	.seh_proc _sigfe_getpwent
_sigfe_getpwent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpwent
	add	x9, x9, :lo12:getpwent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpwnam
	.global	_sigfe_getpwnam
	.seh_proc _sigfe_getpwnam
_sigfe_getpwnam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpwnam
	add	x9, x9, :lo12:getpwnam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpwnam_r
	.global	_sigfe_getpwnam_r
	.seh_proc _sigfe_getpwnam_r
_sigfe_getpwnam_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpwnam_r
	add	x9, x9, :lo12:getpwnam_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpwuid
	.global	_sigfe_getpwuid
	.seh_proc _sigfe_getpwuid
_sigfe_getpwuid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpwuid
	add	x9, x9, :lo12:getpwuid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getpwuid_r
	.global	_sigfe_getpwuid_r
	.seh_proc _sigfe_getpwuid_r
_sigfe_getpwuid_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getpwuid_r
	add	x9, x9, :lo12:getpwuid_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getrandom
	.global	_sigfe_getrandom
	.seh_proc _sigfe_getrandom
_sigfe_getrandom:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getrandom
	add	x9, x9, :lo12:getrandom
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getrlimit
	.global	_sigfe_getrlimit
	.seh_proc _sigfe_getrlimit
_sigfe_getrlimit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getrlimit
	add	x9, x9, :lo12:getrlimit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getrusage
	.global	_sigfe_getrusage
	.seh_proc _sigfe_getrusage
_sigfe_getrusage:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getrusage
	add	x9, x9, :lo12:getrusage
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	gets
	.global	_sigfe_gets
	.seh_proc _sigfe_gets
_sigfe_gets:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, gets
	add	x9, x9, :lo12:gets
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getsid
	.global	_sigfe_getsid
	.seh_proc _sigfe_getsid
_sigfe_getsid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getsid
	add	x9, x9, :lo12:getsid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	gettimeofday
	.global	_sigfe_gettimeofday
	.seh_proc _sigfe_gettimeofday
_sigfe_gettimeofday:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, gettimeofday
	add	x9, x9, :lo12:gettimeofday
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getusershell
	.global	_sigfe_getusershell
	.seh_proc _sigfe_getusershell
_sigfe_getusershell:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getusershell
	add	x9, x9, :lo12:getusershell
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getutent
	.global	_sigfe_getutent
	.seh_proc _sigfe_getutent
_sigfe_getutent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getutent
	add	x9, x9, :lo12:getutent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getutid
	.global	_sigfe_getutid
	.seh_proc _sigfe_getutid
_sigfe_getutid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getutid
	add	x9, x9, :lo12:getutid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getutline
	.global	_sigfe_getutline
	.seh_proc _sigfe_getutline
_sigfe_getutline:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getutline
	add	x9, x9, :lo12:getutline
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getutxent
	.global	_sigfe_getutxent
	.seh_proc _sigfe_getutxent
_sigfe_getutxent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getutxent
	add	x9, x9, :lo12:getutxent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getutxid
	.global	_sigfe_getutxid
	.seh_proc _sigfe_getutxid
_sigfe_getutxid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getutxid
	add	x9, x9, :lo12:getutxid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getutxline
	.global	_sigfe_getutxline
	.seh_proc _sigfe_getutxline
_sigfe_getutxline:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getutxline
	add	x9, x9, :lo12:getutxline
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getw
	.global	_sigfe_getw
	.seh_proc _sigfe_getw
_sigfe_getw:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getw
	add	x9, x9, :lo12:getw
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getwc
	.global	_sigfe_getwc
	.seh_proc _sigfe_getwc
_sigfe_getwc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getwc
	add	x9, x9, :lo12:getwc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getwc_unlocked
	.global	_sigfe_getwc_unlocked
	.seh_proc _sigfe_getwc_unlocked
_sigfe_getwc_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getwc_unlocked
	add	x9, x9, :lo12:getwc_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getwchar
	.global	_sigfe_getwchar
	.seh_proc _sigfe_getwchar
_sigfe_getwchar:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getwchar
	add	x9, x9, :lo12:getwchar
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getwchar_unlocked
	.global	_sigfe_getwchar_unlocked
	.seh_proc _sigfe_getwchar_unlocked
_sigfe_getwchar_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getwchar_unlocked
	add	x9, x9, :lo12:getwchar_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getwd
	.global	_sigfe_getwd
	.seh_proc _sigfe_getwd
_sigfe_getwd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getwd
	add	x9, x9, :lo12:getwd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	getxattr
	.global	_sigfe_getxattr
	.seh_proc _sigfe_getxattr
_sigfe_getxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, getxattr
	add	x9, x9, :lo12:getxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	glob
	.global	_sigfe_glob
	.seh_proc _sigfe_glob
_sigfe_glob:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, glob
	add	x9, x9, :lo12:glob
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	glob_pattern_p
	.global	_sigfe_glob_pattern_p
	.seh_proc _sigfe_glob_pattern_p
_sigfe_glob_pattern_p:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, glob_pattern_p
	add	x9, x9, :lo12:glob_pattern_p
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	globfree
	.global	_sigfe_globfree
	.seh_proc _sigfe_globfree
_sigfe_globfree:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, globfree
	add	x9, x9, :lo12:globfree
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	gmtime
	.global	_sigfe_gmtime
	.seh_proc _sigfe_gmtime
_sigfe_gmtime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, gmtime
	add	x9, x9, :lo12:gmtime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	gmtime_r
	.global	_sigfe_gmtime_r
	.seh_proc _sigfe_gmtime_r
_sigfe_gmtime_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, gmtime_r
	add	x9, x9, :lo12:gmtime_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	hcreate
	.global	_sigfe_hcreate
	.seh_proc _sigfe_hcreate
_sigfe_hcreate:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, hcreate
	add	x9, x9, :lo12:hcreate
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	hcreate_r
	.global	_sigfe_hcreate_r
	.seh_proc _sigfe_hcreate_r
_sigfe_hcreate_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, hcreate_r
	add	x9, x9, :lo12:hcreate_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	hdestroy
	.global	_sigfe_hdestroy
	.seh_proc _sigfe_hdestroy
_sigfe_hdestroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, hdestroy
	add	x9, x9, :lo12:hdestroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	hdestroy_r
	.global	_sigfe_hdestroy_r
	.seh_proc _sigfe_hdestroy_r
_sigfe_hdestroy_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, hdestroy_r
	add	x9, x9, :lo12:hdestroy_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	hsearch
	.global	_sigfe_hsearch
	.seh_proc _sigfe_hsearch
_sigfe_hsearch:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, hsearch
	add	x9, x9, :lo12:hsearch
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	hsearch_r
	.global	_sigfe_hsearch_r
	.seh_proc _sigfe_hsearch_r
_sigfe_hsearch_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, hsearch_r
	add	x9, x9, :lo12:hsearch_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	if_freenameindex
	.global	_sigfe_if_freenameindex
	.seh_proc _sigfe_if_freenameindex
_sigfe_if_freenameindex:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, if_freenameindex
	add	x9, x9, :lo12:if_freenameindex
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	if_nameindex
	.global	_sigfe_if_nameindex
	.seh_proc _sigfe_if_nameindex
_sigfe_if_nameindex:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, if_nameindex
	add	x9, x9, :lo12:if_nameindex
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	initgroups
	.global	_sigfe_initgroups
	.seh_proc _sigfe_initgroups
_sigfe_initgroups:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, initgroups
	add	x9, x9, :lo12:initgroups
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ioctl
	.global	_sigfe_ioctl
	.seh_proc _sigfe_ioctl
_sigfe_ioctl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ioctl
	add	x9, x9, :lo12:ioctl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	iprintf
	.global	_sigfe_iprintf
	.seh_proc _sigfe_iprintf
_sigfe_iprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, iprintf
	add	x9, x9, :lo12:iprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	iruserok
	.global	_sigfe_iruserok
	.seh_proc _sigfe_iruserok
_sigfe_iruserok:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, iruserok
	add	x9, x9, :lo12:iruserok
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	iruserok_sa
	.global	_sigfe_iruserok_sa
	.seh_proc _sigfe_iruserok_sa
_sigfe_iruserok_sa:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, iruserok_sa
	add	x9, x9, :lo12:iruserok_sa
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	isatty
	.global	_sigfe_isatty
	.seh_proc _sigfe_isatty
_sigfe_isatty:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, isatty
	add	x9, x9, :lo12:isatty
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	kill
	.global	_sigfe_kill
	.seh_proc _sigfe_kill
_sigfe_kill:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, kill
	add	x9, x9, :lo12:kill
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	killpg
	.global	_sigfe_killpg
	.seh_proc _sigfe_killpg
_sigfe_killpg:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, killpg
	add	x9, x9, :lo12:killpg
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lchown
	.global	_sigfe_lchown
	.seh_proc _sigfe_lchown
_sigfe_lchown:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lchown
	add	x9, x9, :lo12:lchown
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lgetxattr
	.global	_sigfe_lgetxattr
	.seh_proc _sigfe_lgetxattr
_sigfe_lgetxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lgetxattr
	add	x9, x9, :lo12:lgetxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	link
	.global	_sigfe_link
	.seh_proc _sigfe_link
_sigfe_link:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, link
	add	x9, x9, :lo12:link
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	linkat
	.global	_sigfe_linkat
	.seh_proc _sigfe_linkat
_sigfe_linkat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, linkat
	add	x9, x9, :lo12:linkat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lio_listio
	.global	_sigfe_lio_listio
	.seh_proc _sigfe_lio_listio
_sigfe_lio_listio:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lio_listio
	add	x9, x9, :lo12:lio_listio
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	listxattr
	.global	_sigfe_listxattr
	.seh_proc _sigfe_listxattr
_sigfe_listxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, listxattr
	add	x9, x9, :lo12:listxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	llistxattr
	.global	_sigfe_llistxattr
	.seh_proc _sigfe_llistxattr
_sigfe_llistxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, llistxattr
	add	x9, x9, :lo12:llistxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	localtime
	.global	_sigfe_localtime
	.seh_proc _sigfe_localtime
_sigfe_localtime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, localtime
	add	x9, x9, :lo12:localtime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	localtime_r
	.global	_sigfe_localtime_r
	.seh_proc _sigfe_localtime_r
_sigfe_localtime_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, localtime_r
	add	x9, x9, :lo12:localtime_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lockf
	.global	_sigfe_lockf
	.seh_proc _sigfe_lockf
_sigfe_lockf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lockf
	add	x9, x9, :lo12:lockf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	login
	.global	_sigfe_login
	.seh_proc _sigfe_login
_sigfe_login:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, login
	add	x9, x9, :lo12:login
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	login_tty
	.global	_sigfe_login_tty
	.seh_proc _sigfe_login_tty
_sigfe_login_tty:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, login_tty
	add	x9, x9, :lo12:login_tty
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	logout
	.global	_sigfe_logout
	.seh_proc _sigfe_logout
_sigfe_logout:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, logout
	add	x9, x9, :lo12:logout
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	logwtmp
	.global	_sigfe_logwtmp
	.seh_proc _sigfe_logwtmp
_sigfe_logwtmp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, logwtmp
	add	x9, x9, :lo12:logwtmp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lremovexattr
	.global	_sigfe_lremovexattr
	.seh_proc _sigfe_lremovexattr
_sigfe_lremovexattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lremovexattr
	add	x9, x9, :lo12:lremovexattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lseek
	.global	_sigfe_lseek
	.seh_proc _sigfe_lseek
_sigfe_lseek:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lseek
	add	x9, x9, :lo12:lseek
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lsetxattr
	.global	_sigfe_lsetxattr
	.seh_proc _sigfe_lsetxattr
_sigfe_lsetxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lsetxattr
	add	x9, x9, :lo12:lsetxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lstat
	.global	_sigfe_lstat
	.seh_proc _sigfe_lstat
_sigfe_lstat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lstat
	add	x9, x9, :lo12:lstat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	lutimes
	.global	_sigfe_lutimes
	.seh_proc _sigfe_lutimes
_sigfe_lutimes:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, lutimes
	add	x9, x9, :lo12:lutimes
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mallinfo
	.global	_sigfe_mallinfo
	.seh_proc _sigfe_mallinfo
_sigfe_mallinfo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mallinfo
	add	x9, x9, :lo12:mallinfo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	malloc
	.global	_sigfe_malloc
	.seh_proc _sigfe_malloc
_sigfe_malloc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, malloc
	add	x9, x9, :lo12:malloc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	malloc_stats
	.global	_sigfe_malloc_stats
	.seh_proc _sigfe_malloc_stats
_sigfe_malloc_stats:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, malloc_stats
	add	x9, x9, :lo12:malloc_stats
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	malloc_trim
	.global	_sigfe_malloc_trim
	.seh_proc _sigfe_malloc_trim
_sigfe_malloc_trim:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, malloc_trim
	add	x9, x9, :lo12:malloc_trim
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	malloc_usable_size
	.global	_sigfe_malloc_usable_size
	.seh_proc _sigfe_malloc_usable_size
_sigfe_malloc_usable_size:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, malloc_usable_size
	add	x9, x9, :lo12:malloc_usable_size
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mallopt
	.global	_sigfe_mallopt
	.seh_proc _sigfe_mallopt
_sigfe_mallopt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mallopt
	add	x9, x9, :lo12:mallopt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	memalign
	.global	_sigfe_memalign
	.seh_proc _sigfe_memalign
_sigfe_memalign:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, memalign
	add	x9, x9, :lo12:memalign
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkdir
	.global	_sigfe_mkdir
	.seh_proc _sigfe_mkdir
_sigfe_mkdir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkdir
	add	x9, x9, :lo12:mkdir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkdirat
	.global	_sigfe_mkdirat
	.seh_proc _sigfe_mkdirat
_sigfe_mkdirat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkdirat
	add	x9, x9, :lo12:mkdirat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkdtemp
	.global	_sigfe_mkdtemp
	.seh_proc _sigfe_mkdtemp
_sigfe_mkdtemp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkdtemp
	add	x9, x9, :lo12:mkdtemp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkfifo
	.global	_sigfe_mkfifo
	.seh_proc _sigfe_mkfifo
_sigfe_mkfifo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkfifo
	add	x9, x9, :lo12:mkfifo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkfifoat
	.global	_sigfe_mkfifoat
	.seh_proc _sigfe_mkfifoat
_sigfe_mkfifoat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkfifoat
	add	x9, x9, :lo12:mkfifoat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mknod
	.global	_sigfe_mknod
	.seh_proc _sigfe_mknod
_sigfe_mknod:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mknod
	add	x9, x9, :lo12:mknod
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mknodat
	.global	_sigfe_mknodat
	.seh_proc _sigfe_mknodat
_sigfe_mknodat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mknodat
	add	x9, x9, :lo12:mknodat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkostemp
	.global	_sigfe_mkostemp
	.seh_proc _sigfe_mkostemp
_sigfe_mkostemp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkostemp
	add	x9, x9, :lo12:mkostemp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkostemps
	.global	_sigfe_mkostemps
	.seh_proc _sigfe_mkostemps
_sigfe_mkostemps:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkostemps
	add	x9, x9, :lo12:mkostemps
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkstemp
	.global	_sigfe_mkstemp
	.seh_proc _sigfe_mkstemp
_sigfe_mkstemp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkstemp
	add	x9, x9, :lo12:mkstemp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mkstemps
	.global	_sigfe_mkstemps
	.seh_proc _sigfe_mkstemps
_sigfe_mkstemps:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mkstemps
	add	x9, x9, :lo12:mkstemps
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mktemp
	.global	_sigfe_mktemp
	.seh_proc _sigfe_mktemp
_sigfe_mktemp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mktemp
	add	x9, x9, :lo12:mktemp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mktime
	.global	_sigfe_mktime
	.seh_proc _sigfe_mktime
_sigfe_mktime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mktime
	add	x9, x9, :lo12:mktime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mlock
	.global	_sigfe_mlock
	.seh_proc _sigfe_mlock
_sigfe_mlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mlock
	add	x9, x9, :lo12:mlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mmap
	.global	_sigfe_mmap
	.seh_proc _sigfe_mmap
_sigfe_mmap:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mmap
	add	x9, x9, :lo12:mmap
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mount
	.global	_sigfe_mount
	.seh_proc _sigfe_mount
_sigfe_mount:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mount
	add	x9, x9, :lo12:mount
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mprotect
	.global	_sigfe_mprotect
	.seh_proc _sigfe_mprotect
_sigfe_mprotect:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mprotect
	add	x9, x9, :lo12:mprotect
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_close
	.global	_sigfe_mq_close
	.seh_proc _sigfe_mq_close
_sigfe_mq_close:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_close
	add	x9, x9, :lo12:mq_close
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_getattr
	.global	_sigfe_mq_getattr
	.seh_proc _sigfe_mq_getattr
_sigfe_mq_getattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_getattr
	add	x9, x9, :lo12:mq_getattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_notify
	.global	_sigfe_mq_notify
	.seh_proc _sigfe_mq_notify
_sigfe_mq_notify:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_notify
	add	x9, x9, :lo12:mq_notify
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_open
	.global	_sigfe_mq_open
	.seh_proc _sigfe_mq_open
_sigfe_mq_open:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_open
	add	x9, x9, :lo12:mq_open
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_receive
	.global	_sigfe_mq_receive
	.seh_proc _sigfe_mq_receive
_sigfe_mq_receive:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_receive
	add	x9, x9, :lo12:mq_receive
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_send
	.global	_sigfe_mq_send
	.seh_proc _sigfe_mq_send
_sigfe_mq_send:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_send
	add	x9, x9, :lo12:mq_send
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_setattr
	.global	_sigfe_mq_setattr
	.seh_proc _sigfe_mq_setattr
_sigfe_mq_setattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_setattr
	add	x9, x9, :lo12:mq_setattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_timedreceive
	.global	_sigfe_mq_timedreceive
	.seh_proc _sigfe_mq_timedreceive
_sigfe_mq_timedreceive:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_timedreceive
	add	x9, x9, :lo12:mq_timedreceive
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_timedsend
	.global	_sigfe_mq_timedsend
	.seh_proc _sigfe_mq_timedsend
_sigfe_mq_timedsend:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_timedsend
	add	x9, x9, :lo12:mq_timedsend
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mq_unlink
	.global	_sigfe_mq_unlink
	.seh_proc _sigfe_mq_unlink
_sigfe_mq_unlink:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mq_unlink
	add	x9, x9, :lo12:mq_unlink
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	msgctl
	.global	_sigfe_msgctl
	.seh_proc _sigfe_msgctl
_sigfe_msgctl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, msgctl
	add	x9, x9, :lo12:msgctl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	msgget
	.global	_sigfe_msgget
	.seh_proc _sigfe_msgget
_sigfe_msgget:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, msgget
	add	x9, x9, :lo12:msgget
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	msgrcv
	.global	_sigfe_msgrcv
	.seh_proc _sigfe_msgrcv
_sigfe_msgrcv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, msgrcv
	add	x9, x9, :lo12:msgrcv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	msgsnd
	.global	_sigfe_msgsnd
	.seh_proc _sigfe_msgsnd
_sigfe_msgsnd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, msgsnd
	add	x9, x9, :lo12:msgsnd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	msync
	.global	_sigfe_msync
	.seh_proc _sigfe_msync
_sigfe_msync:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, msync
	add	x9, x9, :lo12:msync
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	msys_detach_dll
	.global	_sigfe_maybe_msys_detach_dll
	.seh_proc _sigfe_maybe_msys_detach_dll
_sigfe_maybe_msys_detach_dll:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, msys_detach_dll
	add	x9, x9, :lo12:msys_detach_dll
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe_maybe
	.seh_endproc

	.extern	mtx_destroy
	.global	_sigfe_mtx_destroy
	.seh_proc _sigfe_mtx_destroy
_sigfe_mtx_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mtx_destroy
	add	x9, x9, :lo12:mtx_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mtx_init
	.global	_sigfe_mtx_init
	.seh_proc _sigfe_mtx_init
_sigfe_mtx_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mtx_init
	add	x9, x9, :lo12:mtx_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mtx_lock
	.global	_sigfe_mtx_lock
	.seh_proc _sigfe_mtx_lock
_sigfe_mtx_lock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mtx_lock
	add	x9, x9, :lo12:mtx_lock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mtx_timedlock
	.global	_sigfe_mtx_timedlock
	.seh_proc _sigfe_mtx_timedlock
_sigfe_mtx_timedlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mtx_timedlock
	add	x9, x9, :lo12:mtx_timedlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mtx_trylock
	.global	_sigfe_mtx_trylock
	.seh_proc _sigfe_mtx_trylock
_sigfe_mtx_trylock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mtx_trylock
	add	x9, x9, :lo12:mtx_trylock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	mtx_unlock
	.global	_sigfe_mtx_unlock
	.seh_proc _sigfe_mtx_unlock
_sigfe_mtx_unlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, mtx_unlock
	add	x9, x9, :lo12:mtx_unlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	munlock
	.global	_sigfe_munlock
	.seh_proc _sigfe_munlock
_sigfe_munlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, munlock
	add	x9, x9, :lo12:munlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	munmap
	.global	_sigfe_munmap
	.seh_proc _sigfe_munmap
_sigfe_munmap:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, munmap
	add	x9, x9, :lo12:munmap
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	nanosleep
	.global	_sigfe_nanosleep
	.seh_proc _sigfe_nanosleep
_sigfe_nanosleep:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, nanosleep
	add	x9, x9, :lo12:nanosleep
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	newlocale
	.global	_sigfe_newlocale
	.seh_proc _sigfe_newlocale
_sigfe_newlocale:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, newlocale
	add	x9, x9, :lo12:newlocale
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	nftw
	.global	_sigfe_nftw
	.seh_proc _sigfe_nftw
_sigfe_nftw:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, nftw
	add	x9, x9, :lo12:nftw
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	nice
	.global	_sigfe_nice
	.seh_proc _sigfe_nice
_sigfe_nice:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, nice
	add	x9, x9, :lo12:nice
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	nl_langinfo
	.global	_sigfe_nl_langinfo
	.seh_proc _sigfe_nl_langinfo
_sigfe_nl_langinfo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, nl_langinfo
	add	x9, x9, :lo12:nl_langinfo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	nl_langinfo_l
	.global	_sigfe_nl_langinfo_l
	.seh_proc _sigfe_nl_langinfo_l
_sigfe_nl_langinfo_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, nl_langinfo_l
	add	x9, x9, :lo12:nl_langinfo_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	on_exit
	.global	_sigfe_on_exit
	.seh_proc _sigfe_on_exit
_sigfe_on_exit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, on_exit
	add	x9, x9, :lo12:on_exit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	open
	.global	_sigfe_open
	.seh_proc _sigfe_open
_sigfe_open:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, open
	add	x9, x9, :lo12:open
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	open_memstream
	.global	_sigfe_open_memstream
	.seh_proc _sigfe_open_memstream
_sigfe_open_memstream:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, open_memstream
	add	x9, x9, :lo12:open_memstream
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	open_wmemstream
	.global	_sigfe_open_wmemstream
	.seh_proc _sigfe_open_wmemstream
_sigfe_open_wmemstream:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, open_wmemstream
	add	x9, x9, :lo12:open_wmemstream
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	openat
	.global	_sigfe_openat
	.seh_proc _sigfe_openat
_sigfe_openat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, openat
	add	x9, x9, :lo12:openat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	opendir
	.global	_sigfe_opendir
	.seh_proc _sigfe_opendir
_sigfe_opendir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, opendir
	add	x9, x9, :lo12:opendir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	openlog
	.global	_sigfe_openlog
	.seh_proc _sigfe_openlog
_sigfe_openlog:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, openlog
	add	x9, x9, :lo12:openlog
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	openpty
	.global	_sigfe_openpty
	.seh_proc _sigfe_openpty
_sigfe_openpty:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, openpty
	add	x9, x9, :lo12:openpty
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pathconf
	.global	_sigfe_pathconf
	.seh_proc _sigfe_pathconf
_sigfe_pathconf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pathconf
	add	x9, x9, :lo12:pathconf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pause
	.global	_sigfe_pause
	.seh_proc _sigfe_pause
_sigfe_pause:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pause
	add	x9, x9, :lo12:pause
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pclose
	.global	_sigfe_pclose
	.seh_proc _sigfe_pclose
_sigfe_pclose:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pclose
	add	x9, x9, :lo12:pclose
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	perror
	.global	_sigfe_perror
	.seh_proc _sigfe_perror
_sigfe_perror:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, perror
	add	x9, x9, :lo12:perror
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pipe
	.global	_sigfe_pipe
	.seh_proc _sigfe_pipe
_sigfe_pipe:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pipe
	add	x9, x9, :lo12:pipe
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pipe2
	.global	_sigfe_pipe2
	.seh_proc _sigfe_pipe2
_sigfe_pipe2:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pipe2
	add	x9, x9, :lo12:pipe2
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	poll
	.global	_sigfe_poll
	.seh_proc _sigfe_poll
_sigfe_poll:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, poll
	add	x9, x9, :lo12:poll
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	popen
	.global	_sigfe_popen
	.seh_proc _sigfe_popen
_sigfe_popen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, popen
	add	x9, x9, :lo12:popen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_close
	.global	_sigfe_posix_close
	.seh_proc _sigfe_posix_close
_sigfe_posix_close:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_close
	add	x9, x9, :lo12:posix_close
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_fadvise
	.global	_sigfe_posix_fadvise
	.seh_proc _sigfe_posix_fadvise
_sigfe_posix_fadvise:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_fadvise
	add	x9, x9, :lo12:posix_fadvise
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_fallocate
	.global	_sigfe_posix_fallocate
	.seh_proc _sigfe_posix_fallocate
_sigfe_posix_fallocate:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_fallocate
	add	x9, x9, :lo12:posix_fallocate
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_getdents
	.global	_sigfe_posix_getdents
	.seh_proc _sigfe_posix_getdents
_sigfe_posix_getdents:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_getdents
	add	x9, x9, :lo12:posix_getdents
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_madvise
	.global	_sigfe_posix_madvise
	.seh_proc _sigfe_posix_madvise
_sigfe_posix_madvise:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_madvise
	add	x9, x9, :lo12:posix_madvise
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_memalign
	.global	_sigfe_posix_memalign
	.seh_proc _sigfe_posix_memalign
_sigfe_posix_memalign:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_memalign
	add	x9, x9, :lo12:posix_memalign
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_openpt
	.global	_sigfe_posix_openpt
	.seh_proc _sigfe_posix_openpt
_sigfe_posix_openpt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_openpt
	add	x9, x9, :lo12:posix_openpt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawn
	.global	_sigfe_posix_spawn
	.seh_proc _sigfe_posix_spawn
_sigfe_posix_spawn:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawn
	add	x9, x9, :lo12:posix_spawn
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawn_file_actions_addchdir_np
	.global	_sigfe_posix_spawn_file_actions_addchdir_np
	.seh_proc _sigfe_posix_spawn_file_actions_addchdir_np
_sigfe_posix_spawn_file_actions_addchdir_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawn_file_actions_addchdir_np
	add	x9, x9, :lo12:posix_spawn_file_actions_addchdir_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawn_file_actions_addclose
	.global	_sigfe_posix_spawn_file_actions_addclose
	.seh_proc _sigfe_posix_spawn_file_actions_addclose
_sigfe_posix_spawn_file_actions_addclose:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawn_file_actions_addclose
	add	x9, x9, :lo12:posix_spawn_file_actions_addclose
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawn_file_actions_adddup2
	.global	_sigfe_posix_spawn_file_actions_adddup2
	.seh_proc _sigfe_posix_spawn_file_actions_adddup2
_sigfe_posix_spawn_file_actions_adddup2:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawn_file_actions_adddup2
	add	x9, x9, :lo12:posix_spawn_file_actions_adddup2
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawn_file_actions_addfchdir_np
	.global	_sigfe_posix_spawn_file_actions_addfchdir_np
	.seh_proc _sigfe_posix_spawn_file_actions_addfchdir_np
_sigfe_posix_spawn_file_actions_addfchdir_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawn_file_actions_addfchdir_np
	add	x9, x9, :lo12:posix_spawn_file_actions_addfchdir_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawn_file_actions_addopen
	.global	_sigfe_posix_spawn_file_actions_addopen
	.seh_proc _sigfe_posix_spawn_file_actions_addopen
_sigfe_posix_spawn_file_actions_addopen:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawn_file_actions_addopen
	add	x9, x9, :lo12:posix_spawn_file_actions_addopen
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawn_file_actions_destroy
	.global	_sigfe_posix_spawn_file_actions_destroy
	.seh_proc _sigfe_posix_spawn_file_actions_destroy
_sigfe_posix_spawn_file_actions_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawn_file_actions_destroy
	add	x9, x9, :lo12:posix_spawn_file_actions_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawn_file_actions_init
	.global	_sigfe_posix_spawn_file_actions_init
	.seh_proc _sigfe_posix_spawn_file_actions_init
_sigfe_posix_spawn_file_actions_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawn_file_actions_init
	add	x9, x9, :lo12:posix_spawn_file_actions_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawnattr_destroy
	.global	_sigfe_posix_spawnattr_destroy
	.seh_proc _sigfe_posix_spawnattr_destroy
_sigfe_posix_spawnattr_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawnattr_destroy
	add	x9, x9, :lo12:posix_spawnattr_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawnattr_init
	.global	_sigfe_posix_spawnattr_init
	.seh_proc _sigfe_posix_spawnattr_init
_sigfe_posix_spawnattr_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawnattr_init
	add	x9, x9, :lo12:posix_spawnattr_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	posix_spawnp
	.global	_sigfe_posix_spawnp
	.seh_proc _sigfe_posix_spawnp
_sigfe_posix_spawnp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, posix_spawnp
	add	x9, x9, :lo12:posix_spawnp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ppoll
	.global	_sigfe_ppoll
	.seh_proc _sigfe_ppoll
_sigfe_ppoll:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ppoll
	add	x9, x9, :lo12:ppoll
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pread
	.global	_sigfe_pread
	.seh_proc _sigfe_pread
_sigfe_pread:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pread
	add	x9, x9, :lo12:pread
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	printf
	.global	_sigfe_printf
	.seh_proc _sigfe_printf
_sigfe_printf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, printf
	add	x9, x9, :lo12:printf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pselect
	.global	_sigfe_pselect
	.seh_proc _sigfe_pselect
_sigfe_pselect:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pselect
	add	x9, x9, :lo12:pselect
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	psiginfo
	.global	_sigfe_psiginfo
	.seh_proc _sigfe_psiginfo
_sigfe_psiginfo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, psiginfo
	add	x9, x9, :lo12:psiginfo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	psignal
	.global	_sigfe_psignal
	.seh_proc _sigfe_psignal
_sigfe_psignal:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, psignal
	add	x9, x9, :lo12:psignal
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_atfork
	.global	_sigfe_pthread_atfork
	.seh_proc _sigfe_pthread_atfork
_sigfe_pthread_atfork:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_atfork
	add	x9, x9, :lo12:pthread_atfork
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_destroy
	.global	_sigfe_pthread_attr_destroy
	.seh_proc _sigfe_pthread_attr_destroy
_sigfe_pthread_attr_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_destroy
	add	x9, x9, :lo12:pthread_attr_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getdetachstate
	.global	_sigfe_pthread_attr_getdetachstate
	.seh_proc _sigfe_pthread_attr_getdetachstate
_sigfe_pthread_attr_getdetachstate:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getdetachstate
	add	x9, x9, :lo12:pthread_attr_getdetachstate
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getguardsize
	.global	_sigfe_pthread_attr_getguardsize
	.seh_proc _sigfe_pthread_attr_getguardsize
_sigfe_pthread_attr_getguardsize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getguardsize
	add	x9, x9, :lo12:pthread_attr_getguardsize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getinheritsched
	.global	_sigfe_pthread_attr_getinheritsched
	.seh_proc _sigfe_pthread_attr_getinheritsched
_sigfe_pthread_attr_getinheritsched:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getinheritsched
	add	x9, x9, :lo12:pthread_attr_getinheritsched
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getschedparam
	.global	_sigfe_pthread_attr_getschedparam
	.seh_proc _sigfe_pthread_attr_getschedparam
_sigfe_pthread_attr_getschedparam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getschedparam
	add	x9, x9, :lo12:pthread_attr_getschedparam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getschedpolicy
	.global	_sigfe_pthread_attr_getschedpolicy
	.seh_proc _sigfe_pthread_attr_getschedpolicy
_sigfe_pthread_attr_getschedpolicy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getschedpolicy
	add	x9, x9, :lo12:pthread_attr_getschedpolicy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getscope
	.global	_sigfe_pthread_attr_getscope
	.seh_proc _sigfe_pthread_attr_getscope
_sigfe_pthread_attr_getscope:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getscope
	add	x9, x9, :lo12:pthread_attr_getscope
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getstack
	.global	_sigfe_pthread_attr_getstack
	.seh_proc _sigfe_pthread_attr_getstack
_sigfe_pthread_attr_getstack:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getstack
	add	x9, x9, :lo12:pthread_attr_getstack
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getstackaddr
	.global	_sigfe_pthread_attr_getstackaddr
	.seh_proc _sigfe_pthread_attr_getstackaddr
_sigfe_pthread_attr_getstackaddr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getstackaddr
	add	x9, x9, :lo12:pthread_attr_getstackaddr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_getstacksize
	.global	_sigfe_pthread_attr_getstacksize
	.seh_proc _sigfe_pthread_attr_getstacksize
_sigfe_pthread_attr_getstacksize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_getstacksize
	add	x9, x9, :lo12:pthread_attr_getstacksize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_init
	.global	_sigfe_pthread_attr_init
	.seh_proc _sigfe_pthread_attr_init
_sigfe_pthread_attr_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_init
	add	x9, x9, :lo12:pthread_attr_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setdetachstate
	.global	_sigfe_pthread_attr_setdetachstate
	.seh_proc _sigfe_pthread_attr_setdetachstate
_sigfe_pthread_attr_setdetachstate:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setdetachstate
	add	x9, x9, :lo12:pthread_attr_setdetachstate
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setguardsize
	.global	_sigfe_pthread_attr_setguardsize
	.seh_proc _sigfe_pthread_attr_setguardsize
_sigfe_pthread_attr_setguardsize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setguardsize
	add	x9, x9, :lo12:pthread_attr_setguardsize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setinheritsched
	.global	_sigfe_pthread_attr_setinheritsched
	.seh_proc _sigfe_pthread_attr_setinheritsched
_sigfe_pthread_attr_setinheritsched:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setinheritsched
	add	x9, x9, :lo12:pthread_attr_setinheritsched
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setschedparam
	.global	_sigfe_pthread_attr_setschedparam
	.seh_proc _sigfe_pthread_attr_setschedparam
_sigfe_pthread_attr_setschedparam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setschedparam
	add	x9, x9, :lo12:pthread_attr_setschedparam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setschedpolicy
	.global	_sigfe_pthread_attr_setschedpolicy
	.seh_proc _sigfe_pthread_attr_setschedpolicy
_sigfe_pthread_attr_setschedpolicy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setschedpolicy
	add	x9, x9, :lo12:pthread_attr_setschedpolicy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setscope
	.global	_sigfe_pthread_attr_setscope
	.seh_proc _sigfe_pthread_attr_setscope
_sigfe_pthread_attr_setscope:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setscope
	add	x9, x9, :lo12:pthread_attr_setscope
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setstack
	.global	_sigfe_pthread_attr_setstack
	.seh_proc _sigfe_pthread_attr_setstack
_sigfe_pthread_attr_setstack:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setstack
	add	x9, x9, :lo12:pthread_attr_setstack
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setstackaddr
	.global	_sigfe_pthread_attr_setstackaddr
	.seh_proc _sigfe_pthread_attr_setstackaddr
_sigfe_pthread_attr_setstackaddr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setstackaddr
	add	x9, x9, :lo12:pthread_attr_setstackaddr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_attr_setstacksize
	.global	_sigfe_pthread_attr_setstacksize
	.seh_proc _sigfe_pthread_attr_setstacksize
_sigfe_pthread_attr_setstacksize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_attr_setstacksize
	add	x9, x9, :lo12:pthread_attr_setstacksize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_barrier_destroy
	.global	_sigfe_pthread_barrier_destroy
	.seh_proc _sigfe_pthread_barrier_destroy
_sigfe_pthread_barrier_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_barrier_destroy
	add	x9, x9, :lo12:pthread_barrier_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_barrier_init
	.global	_sigfe_pthread_barrier_init
	.seh_proc _sigfe_pthread_barrier_init
_sigfe_pthread_barrier_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_barrier_init
	add	x9, x9, :lo12:pthread_barrier_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_barrier_wait
	.global	_sigfe_pthread_barrier_wait
	.seh_proc _sigfe_pthread_barrier_wait
_sigfe_pthread_barrier_wait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_barrier_wait
	add	x9, x9, :lo12:pthread_barrier_wait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_barrierattr_destroy
	.global	_sigfe_pthread_barrierattr_destroy
	.seh_proc _sigfe_pthread_barrierattr_destroy
_sigfe_pthread_barrierattr_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_barrierattr_destroy
	add	x9, x9, :lo12:pthread_barrierattr_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_barrierattr_getpshared
	.global	_sigfe_pthread_barrierattr_getpshared
	.seh_proc _sigfe_pthread_barrierattr_getpshared
_sigfe_pthread_barrierattr_getpshared:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_barrierattr_getpshared
	add	x9, x9, :lo12:pthread_barrierattr_getpshared
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_barrierattr_init
	.global	_sigfe_pthread_barrierattr_init
	.seh_proc _sigfe_pthread_barrierattr_init
_sigfe_pthread_barrierattr_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_barrierattr_init
	add	x9, x9, :lo12:pthread_barrierattr_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_barrierattr_setpshared
	.global	_sigfe_pthread_barrierattr_setpshared
	.seh_proc _sigfe_pthread_barrierattr_setpshared
_sigfe_pthread_barrierattr_setpshared:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_barrierattr_setpshared
	add	x9, x9, :lo12:pthread_barrierattr_setpshared
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_cancel
	.global	_sigfe_pthread_cancel
	.seh_proc _sigfe_pthread_cancel
_sigfe_pthread_cancel:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_cancel
	add	x9, x9, :lo12:pthread_cancel
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_cond_broadcast
	.global	_sigfe_pthread_cond_broadcast
	.seh_proc _sigfe_pthread_cond_broadcast
_sigfe_pthread_cond_broadcast:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_cond_broadcast
	add	x9, x9, :lo12:pthread_cond_broadcast
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_cond_clockwait
	.global	_sigfe_pthread_cond_clockwait
	.seh_proc _sigfe_pthread_cond_clockwait
_sigfe_pthread_cond_clockwait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_cond_clockwait
	add	x9, x9, :lo12:pthread_cond_clockwait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_cond_destroy
	.global	_sigfe_pthread_cond_destroy
	.seh_proc _sigfe_pthread_cond_destroy
_sigfe_pthread_cond_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_cond_destroy
	add	x9, x9, :lo12:pthread_cond_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_cond_init
	.global	_sigfe_pthread_cond_init
	.seh_proc _sigfe_pthread_cond_init
_sigfe_pthread_cond_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_cond_init
	add	x9, x9, :lo12:pthread_cond_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_cond_signal
	.global	_sigfe_pthread_cond_signal
	.seh_proc _sigfe_pthread_cond_signal
_sigfe_pthread_cond_signal:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_cond_signal
	add	x9, x9, :lo12:pthread_cond_signal
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_cond_timedwait
	.global	_sigfe_pthread_cond_timedwait
	.seh_proc _sigfe_pthread_cond_timedwait
_sigfe_pthread_cond_timedwait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_cond_timedwait
	add	x9, x9, :lo12:pthread_cond_timedwait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_cond_wait
	.global	_sigfe_pthread_cond_wait
	.seh_proc _sigfe_pthread_cond_wait
_sigfe_pthread_cond_wait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_cond_wait
	add	x9, x9, :lo12:pthread_cond_wait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_condattr_destroy
	.global	_sigfe_pthread_condattr_destroy
	.seh_proc _sigfe_pthread_condattr_destroy
_sigfe_pthread_condattr_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_condattr_destroy
	add	x9, x9, :lo12:pthread_condattr_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_condattr_getclock
	.global	_sigfe_pthread_condattr_getclock
	.seh_proc _sigfe_pthread_condattr_getclock
_sigfe_pthread_condattr_getclock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_condattr_getclock
	add	x9, x9, :lo12:pthread_condattr_getclock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_condattr_getpshared
	.global	_sigfe_pthread_condattr_getpshared
	.seh_proc _sigfe_pthread_condattr_getpshared
_sigfe_pthread_condattr_getpshared:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_condattr_getpshared
	add	x9, x9, :lo12:pthread_condattr_getpshared
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_condattr_init
	.global	_sigfe_pthread_condattr_init
	.seh_proc _sigfe_pthread_condattr_init
_sigfe_pthread_condattr_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_condattr_init
	add	x9, x9, :lo12:pthread_condattr_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_condattr_setclock
	.global	_sigfe_pthread_condattr_setclock
	.seh_proc _sigfe_pthread_condattr_setclock
_sigfe_pthread_condattr_setclock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_condattr_setclock
	add	x9, x9, :lo12:pthread_condattr_setclock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_condattr_setpshared
	.global	_sigfe_pthread_condattr_setpshared
	.seh_proc _sigfe_pthread_condattr_setpshared
_sigfe_pthread_condattr_setpshared:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_condattr_setpshared
	add	x9, x9, :lo12:pthread_condattr_setpshared
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_continue
	.global	_sigfe_pthread_continue
	.seh_proc _sigfe_pthread_continue
_sigfe_pthread_continue:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_continue
	add	x9, x9, :lo12:pthread_continue
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_create
	.global	_sigfe_pthread_create
	.seh_proc _sigfe_pthread_create
_sigfe_pthread_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_create
	add	x9, x9, :lo12:pthread_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_detach
	.global	_sigfe_pthread_detach
	.seh_proc _sigfe_pthread_detach
_sigfe_pthread_detach:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_detach
	add	x9, x9, :lo12:pthread_detach
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_equal
	.global	_sigfe_pthread_equal
	.seh_proc _sigfe_pthread_equal
_sigfe_pthread_equal:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_equal
	add	x9, x9, :lo12:pthread_equal
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_exit
	.global	_sigfe_pthread_exit
	.seh_proc _sigfe_pthread_exit
_sigfe_pthread_exit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_exit
	add	x9, x9, :lo12:pthread_exit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_getaffinity_np
	.global	_sigfe_pthread_getaffinity_np
	.seh_proc _sigfe_pthread_getaffinity_np
_sigfe_pthread_getaffinity_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_getaffinity_np
	add	x9, x9, :lo12:pthread_getaffinity_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_getattr_np
	.global	_sigfe_pthread_getattr_np
	.seh_proc _sigfe_pthread_getattr_np
_sigfe_pthread_getattr_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_getattr_np
	add	x9, x9, :lo12:pthread_getattr_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_getconcurrency
	.global	_sigfe_pthread_getconcurrency
	.seh_proc _sigfe_pthread_getconcurrency
_sigfe_pthread_getconcurrency:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_getconcurrency
	add	x9, x9, :lo12:pthread_getconcurrency
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_getcpuclockid
	.global	_sigfe_pthread_getcpuclockid
	.seh_proc _sigfe_pthread_getcpuclockid
_sigfe_pthread_getcpuclockid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_getcpuclockid
	add	x9, x9, :lo12:pthread_getcpuclockid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_getname_np
	.global	_sigfe_pthread_getname_np
	.seh_proc _sigfe_pthread_getname_np
_sigfe_pthread_getname_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_getname_np
	add	x9, x9, :lo12:pthread_getname_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_getschedparam
	.global	_sigfe_pthread_getschedparam
	.seh_proc _sigfe_pthread_getschedparam
_sigfe_pthread_getschedparam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_getschedparam
	add	x9, x9, :lo12:pthread_getschedparam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_getsequence_np
	.global	_sigfe_pthread_getsequence_np
	.seh_proc _sigfe_pthread_getsequence_np
_sigfe_pthread_getsequence_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_getsequence_np
	add	x9, x9, :lo12:pthread_getsequence_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_getspecific
	.global	_sigfe_pthread_getspecific
	.seh_proc _sigfe_pthread_getspecific
_sigfe_pthread_getspecific:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_getspecific
	add	x9, x9, :lo12:pthread_getspecific
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_join
	.global	_sigfe_pthread_join
	.seh_proc _sigfe_pthread_join
_sigfe_pthread_join:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_join
	add	x9, x9, :lo12:pthread_join
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_key_create
	.global	_sigfe_pthread_key_create
	.seh_proc _sigfe_pthread_key_create
_sigfe_pthread_key_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_key_create
	add	x9, x9, :lo12:pthread_key_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_key_delete
	.global	_sigfe_pthread_key_delete
	.seh_proc _sigfe_pthread_key_delete
_sigfe_pthread_key_delete:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_key_delete
	add	x9, x9, :lo12:pthread_key_delete
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_kill
	.global	_sigfe_pthread_kill
	.seh_proc _sigfe_pthread_kill
_sigfe_pthread_kill:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_kill
	add	x9, x9, :lo12:pthread_kill
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_clocklock
	.global	_sigfe_pthread_mutex_clocklock
	.seh_proc _sigfe_pthread_mutex_clocklock
_sigfe_pthread_mutex_clocklock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_clocklock
	add	x9, x9, :lo12:pthread_mutex_clocklock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_destroy
	.global	_sigfe_pthread_mutex_destroy
	.seh_proc _sigfe_pthread_mutex_destroy
_sigfe_pthread_mutex_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_destroy
	add	x9, x9, :lo12:pthread_mutex_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_getprioceiling
	.global	_sigfe_pthread_mutex_getprioceiling
	.seh_proc _sigfe_pthread_mutex_getprioceiling
_sigfe_pthread_mutex_getprioceiling:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_getprioceiling
	add	x9, x9, :lo12:pthread_mutex_getprioceiling
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_init
	.global	_sigfe_pthread_mutex_init
	.seh_proc _sigfe_pthread_mutex_init
_sigfe_pthread_mutex_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_init
	add	x9, x9, :lo12:pthread_mutex_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_lock
	.global	_sigfe_pthread_mutex_lock
	.seh_proc _sigfe_pthread_mutex_lock
_sigfe_pthread_mutex_lock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_lock
	add	x9, x9, :lo12:pthread_mutex_lock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_setprioceiling
	.global	_sigfe_pthread_mutex_setprioceiling
	.seh_proc _sigfe_pthread_mutex_setprioceiling
_sigfe_pthread_mutex_setprioceiling:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_setprioceiling
	add	x9, x9, :lo12:pthread_mutex_setprioceiling
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_timedlock
	.global	_sigfe_pthread_mutex_timedlock
	.seh_proc _sigfe_pthread_mutex_timedlock
_sigfe_pthread_mutex_timedlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_timedlock
	add	x9, x9, :lo12:pthread_mutex_timedlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_trylock
	.global	_sigfe_pthread_mutex_trylock
	.seh_proc _sigfe_pthread_mutex_trylock
_sigfe_pthread_mutex_trylock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_trylock
	add	x9, x9, :lo12:pthread_mutex_trylock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutex_unlock
	.global	_sigfe_pthread_mutex_unlock
	.seh_proc _sigfe_pthread_mutex_unlock
_sigfe_pthread_mutex_unlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutex_unlock
	add	x9, x9, :lo12:pthread_mutex_unlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_destroy
	.global	_sigfe_pthread_mutexattr_destroy
	.seh_proc _sigfe_pthread_mutexattr_destroy
_sigfe_pthread_mutexattr_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_destroy
	add	x9, x9, :lo12:pthread_mutexattr_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_getprioceiling
	.global	_sigfe_pthread_mutexattr_getprioceiling
	.seh_proc _sigfe_pthread_mutexattr_getprioceiling
_sigfe_pthread_mutexattr_getprioceiling:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_getprioceiling
	add	x9, x9, :lo12:pthread_mutexattr_getprioceiling
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_getprotocol
	.global	_sigfe_pthread_mutexattr_getprotocol
	.seh_proc _sigfe_pthread_mutexattr_getprotocol
_sigfe_pthread_mutexattr_getprotocol:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_getprotocol
	add	x9, x9, :lo12:pthread_mutexattr_getprotocol
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_getpshared
	.global	_sigfe_pthread_mutexattr_getpshared
	.seh_proc _sigfe_pthread_mutexattr_getpshared
_sigfe_pthread_mutexattr_getpshared:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_getpshared
	add	x9, x9, :lo12:pthread_mutexattr_getpshared
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_gettype
	.global	_sigfe_pthread_mutexattr_gettype
	.seh_proc _sigfe_pthread_mutexattr_gettype
_sigfe_pthread_mutexattr_gettype:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_gettype
	add	x9, x9, :lo12:pthread_mutexattr_gettype
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_init
	.global	_sigfe_pthread_mutexattr_init
	.seh_proc _sigfe_pthread_mutexattr_init
_sigfe_pthread_mutexattr_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_init
	add	x9, x9, :lo12:pthread_mutexattr_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_setprioceiling
	.global	_sigfe_pthread_mutexattr_setprioceiling
	.seh_proc _sigfe_pthread_mutexattr_setprioceiling
_sigfe_pthread_mutexattr_setprioceiling:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_setprioceiling
	add	x9, x9, :lo12:pthread_mutexattr_setprioceiling
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_setprotocol
	.global	_sigfe_pthread_mutexattr_setprotocol
	.seh_proc _sigfe_pthread_mutexattr_setprotocol
_sigfe_pthread_mutexattr_setprotocol:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_setprotocol
	add	x9, x9, :lo12:pthread_mutexattr_setprotocol
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_setpshared
	.global	_sigfe_pthread_mutexattr_setpshared
	.seh_proc _sigfe_pthread_mutexattr_setpshared
_sigfe_pthread_mutexattr_setpshared:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_setpshared
	add	x9, x9, :lo12:pthread_mutexattr_setpshared
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_mutexattr_settype
	.global	_sigfe_pthread_mutexattr_settype
	.seh_proc _sigfe_pthread_mutexattr_settype
_sigfe_pthread_mutexattr_settype:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_mutexattr_settype
	add	x9, x9, :lo12:pthread_mutexattr_settype
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_once
	.global	_sigfe_pthread_once
	.seh_proc _sigfe_pthread_once
_sigfe_pthread_once:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_once
	add	x9, x9, :lo12:pthread_once
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_clockrdlock
	.global	_sigfe_pthread_rwlock_clockrdlock
	.seh_proc _sigfe_pthread_rwlock_clockrdlock
_sigfe_pthread_rwlock_clockrdlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_clockrdlock
	add	x9, x9, :lo12:pthread_rwlock_clockrdlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_clockwrlock
	.global	_sigfe_pthread_rwlock_clockwrlock
	.seh_proc _sigfe_pthread_rwlock_clockwrlock
_sigfe_pthread_rwlock_clockwrlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_clockwrlock
	add	x9, x9, :lo12:pthread_rwlock_clockwrlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_destroy
	.global	_sigfe_pthread_rwlock_destroy
	.seh_proc _sigfe_pthread_rwlock_destroy
_sigfe_pthread_rwlock_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_destroy
	add	x9, x9, :lo12:pthread_rwlock_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_init
	.global	_sigfe_pthread_rwlock_init
	.seh_proc _sigfe_pthread_rwlock_init
_sigfe_pthread_rwlock_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_init
	add	x9, x9, :lo12:pthread_rwlock_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_rdlock
	.global	_sigfe_pthread_rwlock_rdlock
	.seh_proc _sigfe_pthread_rwlock_rdlock
_sigfe_pthread_rwlock_rdlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_rdlock
	add	x9, x9, :lo12:pthread_rwlock_rdlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_timedrdlock
	.global	_sigfe_pthread_rwlock_timedrdlock
	.seh_proc _sigfe_pthread_rwlock_timedrdlock
_sigfe_pthread_rwlock_timedrdlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_timedrdlock
	add	x9, x9, :lo12:pthread_rwlock_timedrdlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_timedwrlock
	.global	_sigfe_pthread_rwlock_timedwrlock
	.seh_proc _sigfe_pthread_rwlock_timedwrlock
_sigfe_pthread_rwlock_timedwrlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_timedwrlock
	add	x9, x9, :lo12:pthread_rwlock_timedwrlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_tryrdlock
	.global	_sigfe_pthread_rwlock_tryrdlock
	.seh_proc _sigfe_pthread_rwlock_tryrdlock
_sigfe_pthread_rwlock_tryrdlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_tryrdlock
	add	x9, x9, :lo12:pthread_rwlock_tryrdlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_trywrlock
	.global	_sigfe_pthread_rwlock_trywrlock
	.seh_proc _sigfe_pthread_rwlock_trywrlock
_sigfe_pthread_rwlock_trywrlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_trywrlock
	add	x9, x9, :lo12:pthread_rwlock_trywrlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_unlock
	.global	_sigfe_pthread_rwlock_unlock
	.seh_proc _sigfe_pthread_rwlock_unlock
_sigfe_pthread_rwlock_unlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_unlock
	add	x9, x9, :lo12:pthread_rwlock_unlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlock_wrlock
	.global	_sigfe_pthread_rwlock_wrlock
	.seh_proc _sigfe_pthread_rwlock_wrlock
_sigfe_pthread_rwlock_wrlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlock_wrlock
	add	x9, x9, :lo12:pthread_rwlock_wrlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlockattr_destroy
	.global	_sigfe_pthread_rwlockattr_destroy
	.seh_proc _sigfe_pthread_rwlockattr_destroy
_sigfe_pthread_rwlockattr_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlockattr_destroy
	add	x9, x9, :lo12:pthread_rwlockattr_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlockattr_getpshared
	.global	_sigfe_pthread_rwlockattr_getpshared
	.seh_proc _sigfe_pthread_rwlockattr_getpshared
_sigfe_pthread_rwlockattr_getpshared:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlockattr_getpshared
	add	x9, x9, :lo12:pthread_rwlockattr_getpshared
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlockattr_init
	.global	_sigfe_pthread_rwlockattr_init
	.seh_proc _sigfe_pthread_rwlockattr_init
_sigfe_pthread_rwlockattr_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlockattr_init
	add	x9, x9, :lo12:pthread_rwlockattr_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_rwlockattr_setpshared
	.global	_sigfe_pthread_rwlockattr_setpshared
	.seh_proc _sigfe_pthread_rwlockattr_setpshared
_sigfe_pthread_rwlockattr_setpshared:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_rwlockattr_setpshared
	add	x9, x9, :lo12:pthread_rwlockattr_setpshared
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_self
	.global	_sigfe_pthread_self
	.seh_proc _sigfe_pthread_self
_sigfe_pthread_self:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_self
	add	x9, x9, :lo12:pthread_self
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_setaffinity_np
	.global	_sigfe_pthread_setaffinity_np
	.seh_proc _sigfe_pthread_setaffinity_np
_sigfe_pthread_setaffinity_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_setaffinity_np
	add	x9, x9, :lo12:pthread_setaffinity_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_setcancelstate
	.global	_sigfe_pthread_setcancelstate
	.seh_proc _sigfe_pthread_setcancelstate
_sigfe_pthread_setcancelstate:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_setcancelstate
	add	x9, x9, :lo12:pthread_setcancelstate
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_setcanceltype
	.global	_sigfe_pthread_setcanceltype
	.seh_proc _sigfe_pthread_setcanceltype
_sigfe_pthread_setcanceltype:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_setcanceltype
	add	x9, x9, :lo12:pthread_setcanceltype
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_setconcurrency
	.global	_sigfe_pthread_setconcurrency
	.seh_proc _sigfe_pthread_setconcurrency
_sigfe_pthread_setconcurrency:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_setconcurrency
	add	x9, x9, :lo12:pthread_setconcurrency
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_setname_np
	.global	_sigfe_pthread_setname_np
	.seh_proc _sigfe_pthread_setname_np
_sigfe_pthread_setname_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_setname_np
	add	x9, x9, :lo12:pthread_setname_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_setschedparam
	.global	_sigfe_pthread_setschedparam
	.seh_proc _sigfe_pthread_setschedparam
_sigfe_pthread_setschedparam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_setschedparam
	add	x9, x9, :lo12:pthread_setschedparam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_setschedprio
	.global	_sigfe_pthread_setschedprio
	.seh_proc _sigfe_pthread_setschedprio
_sigfe_pthread_setschedprio:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_setschedprio
	add	x9, x9, :lo12:pthread_setschedprio
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_setspecific
	.global	_sigfe_pthread_setspecific
	.seh_proc _sigfe_pthread_setspecific
_sigfe_pthread_setspecific:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_setspecific
	add	x9, x9, :lo12:pthread_setspecific
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_sigmask
	.global	_sigfe_pthread_sigmask
	.seh_proc _sigfe_pthread_sigmask
_sigfe_pthread_sigmask:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_sigmask
	add	x9, x9, :lo12:pthread_sigmask
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_sigqueue
	.global	_sigfe_pthread_sigqueue
	.seh_proc _sigfe_pthread_sigqueue
_sigfe_pthread_sigqueue:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_sigqueue
	add	x9, x9, :lo12:pthread_sigqueue
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_spin_destroy
	.global	_sigfe_pthread_spin_destroy
	.seh_proc _sigfe_pthread_spin_destroy
_sigfe_pthread_spin_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_spin_destroy
	add	x9, x9, :lo12:pthread_spin_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_spin_init
	.global	_sigfe_pthread_spin_init
	.seh_proc _sigfe_pthread_spin_init
_sigfe_pthread_spin_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_spin_init
	add	x9, x9, :lo12:pthread_spin_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_spin_lock
	.global	_sigfe_pthread_spin_lock
	.seh_proc _sigfe_pthread_spin_lock
_sigfe_pthread_spin_lock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_spin_lock
	add	x9, x9, :lo12:pthread_spin_lock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_spin_trylock
	.global	_sigfe_pthread_spin_trylock
	.seh_proc _sigfe_pthread_spin_trylock
_sigfe_pthread_spin_trylock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_spin_trylock
	add	x9, x9, :lo12:pthread_spin_trylock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_spin_unlock
	.global	_sigfe_pthread_spin_unlock
	.seh_proc _sigfe_pthread_spin_unlock
_sigfe_pthread_spin_unlock:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_spin_unlock
	add	x9, x9, :lo12:pthread_spin_unlock
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_suspend
	.global	_sigfe_pthread_suspend
	.seh_proc _sigfe_pthread_suspend
_sigfe_pthread_suspend:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_suspend
	add	x9, x9, :lo12:pthread_suspend
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_testcancel
	.global	_sigfe_pthread_testcancel
	.seh_proc _sigfe_pthread_testcancel
_sigfe_pthread_testcancel:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_testcancel
	add	x9, x9, :lo12:pthread_testcancel
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_timedjoin_np
	.global	_sigfe_pthread_timedjoin_np
	.seh_proc _sigfe_pthread_timedjoin_np
_sigfe_pthread_timedjoin_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_timedjoin_np
	add	x9, x9, :lo12:pthread_timedjoin_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_tryjoin_np
	.global	_sigfe_pthread_tryjoin_np
	.seh_proc _sigfe_pthread_tryjoin_np
_sigfe_pthread_tryjoin_np:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_tryjoin_np
	add	x9, x9, :lo12:pthread_tryjoin_np
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pthread_yield
	.global	_sigfe_pthread_yield
	.seh_proc _sigfe_pthread_yield
_sigfe_pthread_yield:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pthread_yield
	add	x9, x9, :lo12:pthread_yield
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ptsname
	.global	_sigfe_ptsname
	.seh_proc _sigfe_ptsname
_sigfe_ptsname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ptsname
	add	x9, x9, :lo12:ptsname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ptsname_r
	.global	_sigfe_ptsname_r
	.seh_proc _sigfe_ptsname_r
_sigfe_ptsname_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ptsname_r
	add	x9, x9, :lo12:ptsname_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putc
	.global	_sigfe_putc
	.seh_proc _sigfe_putc
_sigfe_putc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putc
	add	x9, x9, :lo12:putc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putc_unlocked
	.global	_sigfe_putc_unlocked
	.seh_proc _sigfe_putc_unlocked
_sigfe_putc_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putc_unlocked
	add	x9, x9, :lo12:putc_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putchar
	.global	_sigfe_putchar
	.seh_proc _sigfe_putchar
_sigfe_putchar:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putchar
	add	x9, x9, :lo12:putchar
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putchar_unlocked
	.global	_sigfe_putchar_unlocked
	.seh_proc _sigfe_putchar_unlocked
_sigfe_putchar_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putchar_unlocked
	add	x9, x9, :lo12:putchar_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putenv
	.global	_sigfe_putenv
	.seh_proc _sigfe_putenv
_sigfe_putenv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putenv
	add	x9, x9, :lo12:putenv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	puts
	.global	_sigfe_puts
	.seh_proc _sigfe_puts
_sigfe_puts:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, puts
	add	x9, x9, :lo12:puts
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pututline
	.global	_sigfe_pututline
	.seh_proc _sigfe_pututline
_sigfe_pututline:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pututline
	add	x9, x9, :lo12:pututline
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pututxline
	.global	_sigfe_pututxline
	.seh_proc _sigfe_pututxline
_sigfe_pututxline:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pututxline
	add	x9, x9, :lo12:pututxline
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putw
	.global	_sigfe_putw
	.seh_proc _sigfe_putw
_sigfe_putw:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putw
	add	x9, x9, :lo12:putw
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putwc
	.global	_sigfe_putwc
	.seh_proc _sigfe_putwc
_sigfe_putwc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putwc
	add	x9, x9, :lo12:putwc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putwc_unlocked
	.global	_sigfe_putwc_unlocked
	.seh_proc _sigfe_putwc_unlocked
_sigfe_putwc_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putwc_unlocked
	add	x9, x9, :lo12:putwc_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putwchar
	.global	_sigfe_putwchar
	.seh_proc _sigfe_putwchar
_sigfe_putwchar:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putwchar
	add	x9, x9, :lo12:putwchar
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	putwchar_unlocked
	.global	_sigfe_putwchar_unlocked
	.seh_proc _sigfe_putwchar_unlocked
_sigfe_putwchar_unlocked:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, putwchar_unlocked
	add	x9, x9, :lo12:putwchar_unlocked
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	pwrite
	.global	_sigfe_pwrite
	.seh_proc _sigfe_pwrite
_sigfe_pwrite:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, pwrite
	add	x9, x9, :lo12:pwrite
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	quick_exit
	.global	_sigfe_quick_exit
	.seh_proc _sigfe_quick_exit
_sigfe_quick_exit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, quick_exit
	add	x9, x9, :lo12:quick_exit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	quotactl
	.global	_sigfe_quotactl
	.seh_proc _sigfe_quotactl
_sigfe_quotactl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, quotactl
	add	x9, x9, :lo12:quotactl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	raise
	.global	_sigfe_raise
	.seh_proc _sigfe_raise
_sigfe_raise:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, raise
	add	x9, x9, :lo12:raise
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	read
	.global	_sigfe_read
	.seh_proc _sigfe_read
_sigfe_read:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, read
	add	x9, x9, :lo12:read
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	readdir
	.global	_sigfe_readdir
	.seh_proc _sigfe_readdir
_sigfe_readdir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, readdir
	add	x9, x9, :lo12:readdir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	readdir_r
	.global	_sigfe_readdir_r
	.seh_proc _sigfe_readdir_r
_sigfe_readdir_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, readdir_r
	add	x9, x9, :lo12:readdir_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	readlink
	.global	_sigfe_readlink
	.seh_proc _sigfe_readlink
_sigfe_readlink:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, readlink
	add	x9, x9, :lo12:readlink
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	readlinkat
	.global	_sigfe_readlinkat
	.seh_proc _sigfe_readlinkat
_sigfe_readlinkat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, readlinkat
	add	x9, x9, :lo12:readlinkat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	readv
	.global	_sigfe_readv
	.seh_proc _sigfe_readv
_sigfe_readv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, readv
	add	x9, x9, :lo12:readv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	realloc
	.global	_sigfe_realloc
	.seh_proc _sigfe_realloc
_sigfe_realloc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, realloc
	add	x9, x9, :lo12:realloc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	reallocarray
	.global	_sigfe_reallocarray
	.seh_proc _sigfe_reallocarray
_sigfe_reallocarray:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, reallocarray
	add	x9, x9, :lo12:reallocarray
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	reallocf
	.global	_sigfe_reallocf
	.seh_proc _sigfe_reallocf
_sigfe_reallocf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, reallocf
	add	x9, x9, :lo12:reallocf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	realpath
	.global	_sigfe_realpath
	.seh_proc _sigfe_realpath
_sigfe_realpath:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, realpath
	add	x9, x9, :lo12:realpath
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	regcomp
	.global	_sigfe_regcomp
	.seh_proc _sigfe_regcomp
_sigfe_regcomp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, regcomp
	add	x9, x9, :lo12:regcomp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	regerror
	.global	_sigfe_regerror
	.seh_proc _sigfe_regerror
_sigfe_regerror:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, regerror
	add	x9, x9, :lo12:regerror
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	regexec
	.global	_sigfe_regexec
	.seh_proc _sigfe_regexec
_sigfe_regexec:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, regexec
	add	x9, x9, :lo12:regexec
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	regfree
	.global	_sigfe_regfree
	.seh_proc _sigfe_regfree
_sigfe_regfree:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, regfree
	add	x9, x9, :lo12:regfree
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	remove
	.global	_sigfe_remove
	.seh_proc _sigfe_remove
_sigfe_remove:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, remove
	add	x9, x9, :lo12:remove
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	removexattr
	.global	_sigfe_removexattr
	.seh_proc _sigfe_removexattr
_sigfe_removexattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, removexattr
	add	x9, x9, :lo12:removexattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	rename
	.global	_sigfe_rename
	.seh_proc _sigfe_rename
_sigfe_rename:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, rename
	add	x9, x9, :lo12:rename
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	renameat
	.global	_sigfe_renameat
	.seh_proc _sigfe_renameat
_sigfe_renameat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, renameat
	add	x9, x9, :lo12:renameat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	renameat2
	.global	_sigfe_renameat2
	.seh_proc _sigfe_renameat2
_sigfe_renameat2:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, renameat2
	add	x9, x9, :lo12:renameat2
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	revoke
	.global	_sigfe_revoke
	.seh_proc _sigfe_revoke
_sigfe_revoke:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, revoke
	add	x9, x9, :lo12:revoke
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	rewind
	.global	_sigfe_rewind
	.seh_proc _sigfe_rewind
_sigfe_rewind:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, rewind
	add	x9, x9, :lo12:rewind
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	rewinddir
	.global	_sigfe_rewinddir
	.seh_proc _sigfe_rewinddir
_sigfe_rewinddir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, rewinddir
	add	x9, x9, :lo12:rewinddir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	rmdir
	.global	_sigfe_rmdir
	.seh_proc _sigfe_rmdir
_sigfe_rmdir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, rmdir
	add	x9, x9, :lo12:rmdir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	rpmatch
	.global	_sigfe_rpmatch
	.seh_proc _sigfe_rpmatch
_sigfe_rpmatch:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, rpmatch
	add	x9, x9, :lo12:rpmatch
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ruserok
	.global	_sigfe_ruserok
	.seh_proc _sigfe_ruserok
_sigfe_ruserok:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ruserok
	add	x9, x9, :lo12:ruserok
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sbrk
	.global	_sigfe_sbrk
	.seh_proc _sigfe_sbrk
_sigfe_sbrk:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sbrk
	add	x9, x9, :lo12:sbrk
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	scandir
	.global	_sigfe_scandir
	.seh_proc _sigfe_scandir
_sigfe_scandir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, scandir
	add	x9, x9, :lo12:scandir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	scandirat
	.global	_sigfe_scandirat
	.seh_proc _sigfe_scandirat
_sigfe_scandirat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, scandirat
	add	x9, x9, :lo12:scandirat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	scanf
	.global	_sigfe_scanf
	.seh_proc _sigfe_scanf
_sigfe_scanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, scanf
	add	x9, x9, :lo12:scanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_get_priority_max
	.global	_sigfe_sched_get_priority_max
	.seh_proc _sigfe_sched_get_priority_max
_sigfe_sched_get_priority_max:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_get_priority_max
	add	x9, x9, :lo12:sched_get_priority_max
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_get_priority_min
	.global	_sigfe_sched_get_priority_min
	.seh_proc _sigfe_sched_get_priority_min
_sigfe_sched_get_priority_min:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_get_priority_min
	add	x9, x9, :lo12:sched_get_priority_min
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_getaffinity
	.global	_sigfe_sched_getaffinity
	.seh_proc _sigfe_sched_getaffinity
_sigfe_sched_getaffinity:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_getaffinity
	add	x9, x9, :lo12:sched_getaffinity
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_getcpu
	.global	_sigfe_sched_getcpu
	.seh_proc _sigfe_sched_getcpu
_sigfe_sched_getcpu:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_getcpu
	add	x9, x9, :lo12:sched_getcpu
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_getparam
	.global	_sigfe_sched_getparam
	.seh_proc _sigfe_sched_getparam
_sigfe_sched_getparam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_getparam
	add	x9, x9, :lo12:sched_getparam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_rr_get_interval
	.global	_sigfe_sched_rr_get_interval
	.seh_proc _sigfe_sched_rr_get_interval
_sigfe_sched_rr_get_interval:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_rr_get_interval
	add	x9, x9, :lo12:sched_rr_get_interval
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_setaffinity
	.global	_sigfe_sched_setaffinity
	.seh_proc _sigfe_sched_setaffinity
_sigfe_sched_setaffinity:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_setaffinity
	add	x9, x9, :lo12:sched_setaffinity
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_setparam
	.global	_sigfe_sched_setparam
	.seh_proc _sigfe_sched_setparam
_sigfe_sched_setparam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_setparam
	add	x9, x9, :lo12:sched_setparam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_setscheduler
	.global	_sigfe_sched_setscheduler
	.seh_proc _sigfe_sched_setscheduler
_sigfe_sched_setscheduler:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_setscheduler
	add	x9, x9, :lo12:sched_setscheduler
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sched_yield
	.global	_sigfe_sched_yield
	.seh_proc _sigfe_sched_yield
_sigfe_sched_yield:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sched_yield
	add	x9, x9, :lo12:sched_yield
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	seekdir
	.global	_sigfe_seekdir
	.seh_proc _sigfe_seekdir
_sigfe_seekdir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, seekdir
	add	x9, x9, :lo12:seekdir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_clockwait
	.global	_sigfe_sem_clockwait
	.seh_proc _sigfe_sem_clockwait
_sigfe_sem_clockwait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_clockwait
	add	x9, x9, :lo12:sem_clockwait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_close
	.global	_sigfe_sem_close
	.seh_proc _sigfe_sem_close
_sigfe_sem_close:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_close
	add	x9, x9, :lo12:sem_close
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_destroy
	.global	_sigfe_sem_destroy
	.seh_proc _sigfe_sem_destroy
_sigfe_sem_destroy:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_destroy
	add	x9, x9, :lo12:sem_destroy
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_getvalue
	.global	_sigfe_sem_getvalue
	.seh_proc _sigfe_sem_getvalue
_sigfe_sem_getvalue:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_getvalue
	add	x9, x9, :lo12:sem_getvalue
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_init
	.global	_sigfe_sem_init
	.seh_proc _sigfe_sem_init
_sigfe_sem_init:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_init
	add	x9, x9, :lo12:sem_init
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_open
	.global	_sigfe_sem_open
	.seh_proc _sigfe_sem_open
_sigfe_sem_open:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_open
	add	x9, x9, :lo12:sem_open
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_post
	.global	_sigfe_sem_post
	.seh_proc _sigfe_sem_post
_sigfe_sem_post:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_post
	add	x9, x9, :lo12:sem_post
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_timedwait
	.global	_sigfe_sem_timedwait
	.seh_proc _sigfe_sem_timedwait
_sigfe_sem_timedwait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_timedwait
	add	x9, x9, :lo12:sem_timedwait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_trywait
	.global	_sigfe_sem_trywait
	.seh_proc _sigfe_sem_trywait
_sigfe_sem_trywait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_trywait
	add	x9, x9, :lo12:sem_trywait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_unlink
	.global	_sigfe_sem_unlink
	.seh_proc _sigfe_sem_unlink
_sigfe_sem_unlink:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_unlink
	add	x9, x9, :lo12:sem_unlink
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sem_wait
	.global	_sigfe_sem_wait
	.seh_proc _sigfe_sem_wait
_sigfe_sem_wait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sem_wait
	add	x9, x9, :lo12:sem_wait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	semctl
	.global	_sigfe_semctl
	.seh_proc _sigfe_semctl
_sigfe_semctl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, semctl
	add	x9, x9, :lo12:semctl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	semget
	.global	_sigfe_semget
	.seh_proc _sigfe_semget
_sigfe_semget:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, semget
	add	x9, x9, :lo12:semget
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	semop
	.global	_sigfe_semop
	.seh_proc _sigfe_semop
_sigfe_semop:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, semop
	add	x9, x9, :lo12:semop
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setbuf
	.global	_sigfe_setbuf
	.seh_proc _sigfe_setbuf
_sigfe_setbuf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setbuf
	add	x9, x9, :lo12:setbuf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setbuffer
	.global	_sigfe_setbuffer
	.seh_proc _sigfe_setbuffer
_sigfe_setbuffer:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setbuffer
	add	x9, x9, :lo12:setbuffer
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setdtablesize
	.global	_sigfe_setdtablesize
	.seh_proc _sigfe_setdtablesize
_sigfe_setdtablesize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setdtablesize
	add	x9, x9, :lo12:setdtablesize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setegid
	.global	_sigfe_setegid
	.seh_proc _sigfe_setegid
_sigfe_setegid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setegid
	add	x9, x9, :lo12:setegid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setenv
	.global	_sigfe_setenv
	.seh_proc _sigfe_setenv
_sigfe_setenv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setenv
	add	x9, x9, :lo12:setenv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	seteuid
	.global	_sigfe_seteuid
	.seh_proc _sigfe_seteuid
_sigfe_seteuid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, seteuid
	add	x9, x9, :lo12:seteuid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setgid
	.global	_sigfe_setgid
	.seh_proc _sigfe_setgid
_sigfe_setgid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setgid
	add	x9, x9, :lo12:setgid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setgroups
	.global	_sigfe_setgroups
	.seh_proc _sigfe_setgroups
_sigfe_setgroups:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setgroups
	add	x9, x9, :lo12:setgroups
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sethostname
	.global	_sigfe_sethostname
	.seh_proc _sigfe_sethostname
_sigfe_sethostname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sethostname
	add	x9, x9, :lo12:sethostname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setitimer
	.global	_sigfe_setitimer
	.seh_proc _sigfe_setitimer
_sigfe_setitimer:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setitimer
	add	x9, x9, :lo12:setitimer
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setlinebuf
	.global	_sigfe_setlinebuf
	.seh_proc _sigfe_setlinebuf
_sigfe_setlinebuf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setlinebuf
	add	x9, x9, :lo12:setlinebuf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setmntent
	.global	_sigfe_setmntent
	.seh_proc _sigfe_setmntent
_sigfe_setmntent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setmntent
	add	x9, x9, :lo12:setmntent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setpgid
	.global	_sigfe_setpgid
	.seh_proc _sigfe_setpgid
_sigfe_setpgid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setpgid
	add	x9, x9, :lo12:setpgid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setpgrp
	.global	_sigfe_setpgrp
	.seh_proc _sigfe_setpgrp
_sigfe_setpgrp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setpgrp
	add	x9, x9, :lo12:setpgrp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setpriority
	.global	_sigfe_setpriority
	.seh_proc _sigfe_setpriority
_sigfe_setpriority:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setpriority
	add	x9, x9, :lo12:setpriority
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setproctitle
	.global	_sigfe_setproctitle
	.seh_proc _sigfe_setproctitle
_sigfe_setproctitle:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setproctitle
	add	x9, x9, :lo12:setproctitle
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setregid
	.global	_sigfe_setregid
	.seh_proc _sigfe_setregid
_sigfe_setregid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setregid
	add	x9, x9, :lo12:setregid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setreuid
	.global	_sigfe_setreuid
	.seh_proc _sigfe_setreuid
_sigfe_setreuid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setreuid
	add	x9, x9, :lo12:setreuid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setrlimit
	.global	_sigfe_setrlimit
	.seh_proc _sigfe_setrlimit
_sigfe_setrlimit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setrlimit
	add	x9, x9, :lo12:setrlimit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setsid
	.global	_sigfe_setsid
	.seh_proc _sigfe_setsid
_sigfe_setsid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setsid
	add	x9, x9, :lo12:setsid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	settimeofday
	.global	_sigfe_settimeofday
	.seh_proc _sigfe_settimeofday
_sigfe_settimeofday:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, settimeofday
	add	x9, x9, :lo12:settimeofday
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setuid
	.global	_sigfe_setuid
	.seh_proc _sigfe_setuid
_sigfe_setuid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setuid
	add	x9, x9, :lo12:setuid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setusershell
	.global	_sigfe_setusershell
	.seh_proc _sigfe_setusershell
_sigfe_setusershell:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setusershell
	add	x9, x9, :lo12:setusershell
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setutent
	.global	_sigfe_setutent
	.seh_proc _sigfe_setutent
_sigfe_setutent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setutent
	add	x9, x9, :lo12:setutent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setutxent
	.global	_sigfe_setutxent
	.seh_proc _sigfe_setutxent
_sigfe_setutxent:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setutxent
	add	x9, x9, :lo12:setutxent
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setvbuf
	.global	_sigfe_setvbuf
	.seh_proc _sigfe_setvbuf
_sigfe_setvbuf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setvbuf
	add	x9, x9, :lo12:setvbuf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	setxattr
	.global	_sigfe_setxattr
	.seh_proc _sigfe_setxattr
_sigfe_setxattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, setxattr
	add	x9, x9, :lo12:setxattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	shm_open
	.global	_sigfe_shm_open
	.seh_proc _sigfe_shm_open
_sigfe_shm_open:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, shm_open
	add	x9, x9, :lo12:shm_open
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	shm_unlink
	.global	_sigfe_shm_unlink
	.seh_proc _sigfe_shm_unlink
_sigfe_shm_unlink:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, shm_unlink
	add	x9, x9, :lo12:shm_unlink
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	shmat
	.global	_sigfe_shmat
	.seh_proc _sigfe_shmat
_sigfe_shmat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, shmat
	add	x9, x9, :lo12:shmat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	shmctl
	.global	_sigfe_shmctl
	.seh_proc _sigfe_shmctl
_sigfe_shmctl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, shmctl
	add	x9, x9, :lo12:shmctl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	shmdt
	.global	_sigfe_shmdt
	.seh_proc _sigfe_shmdt
_sigfe_shmdt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, shmdt
	add	x9, x9, :lo12:shmdt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	shmget
	.global	_sigfe_shmget
	.seh_proc _sigfe_shmget
_sigfe_shmget:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, shmget
	add	x9, x9, :lo12:shmget
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sig2str
	.global	_sigfe_sig2str
	.seh_proc _sigfe_sig2str
_sigfe_sig2str:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sig2str
	add	x9, x9, :lo12:sig2str
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigaction
	.global	_sigfe_sigaction
	.seh_proc _sigfe_sigaction
_sigfe_sigaction:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigaction
	add	x9, x9, :lo12:sigaction
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigaddset
	.global	_sigfe_sigaddset
	.seh_proc _sigfe_sigaddset
_sigfe_sigaddset:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigaddset
	add	x9, x9, :lo12:sigaddset
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigaltstack
	.global	_sigfe_sigaltstack
	.seh_proc _sigfe_sigaltstack
_sigfe_sigaltstack:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigaltstack
	add	x9, x9, :lo12:sigaltstack
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigdelset
	.global	_sigfe_sigdelset
	.seh_proc _sigfe_sigdelset
_sigfe_sigdelset:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigdelset
	add	x9, x9, :lo12:sigdelset
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sighold
	.global	_sigfe_sighold
	.seh_proc _sigfe_sighold
_sigfe_sighold:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sighold
	add	x9, x9, :lo12:sighold
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigignore
	.global	_sigfe_sigignore
	.seh_proc _sigfe_sigignore
_sigfe_sigignore:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigignore
	add	x9, x9, :lo12:sigignore
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	siginterrupt
	.global	_sigfe_siginterrupt
	.seh_proc _sigfe_siginterrupt
_sigfe_siginterrupt:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, siginterrupt
	add	x9, x9, :lo12:siginterrupt
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigismember
	.global	_sigfe_sigismember
	.seh_proc _sigfe_sigismember
_sigfe_sigismember:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigismember
	add	x9, x9, :lo12:sigismember
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	signal
	.global	_sigfe_signal
	.seh_proc _sigfe_signal
_sigfe_signal:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, signal
	add	x9, x9, :lo12:signal
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	signalfd
	.global	_sigfe_signalfd
	.seh_proc _sigfe_signalfd
_sigfe_signalfd:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, signalfd
	add	x9, x9, :lo12:signalfd
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigpause
	.global	_sigfe_sigpause
	.seh_proc _sigfe_sigpause
_sigfe_sigpause:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigpause
	add	x9, x9, :lo12:sigpause
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigpending
	.global	_sigfe_sigpending
	.seh_proc _sigfe_sigpending
_sigfe_sigpending:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigpending
	add	x9, x9, :lo12:sigpending
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigprocmask
	.global	_sigfe_sigprocmask
	.seh_proc _sigfe_sigprocmask
_sigfe_sigprocmask:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigprocmask
	add	x9, x9, :lo12:sigprocmask
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigqueue
	.global	_sigfe_sigqueue
	.seh_proc _sigfe_sigqueue
_sigfe_sigqueue:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigqueue
	add	x9, x9, :lo12:sigqueue
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigrelse
	.global	_sigfe_sigrelse
	.seh_proc _sigfe_sigrelse
_sigfe_sigrelse:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigrelse
	add	x9, x9, :lo12:sigrelse
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigset
	.global	_sigfe_sigset
	.seh_proc _sigfe_sigset
_sigfe_sigset:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigset
	add	x9, x9, :lo12:sigset
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigsuspend
	.global	_sigfe_sigsuspend
	.seh_proc _sigfe_sigsuspend
_sigfe_sigsuspend:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigsuspend
	add	x9, x9, :lo12:sigsuspend
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigtimedwait
	.global	_sigfe_sigtimedwait
	.seh_proc _sigfe_sigtimedwait
_sigfe_sigtimedwait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigtimedwait
	add	x9, x9, :lo12:sigtimedwait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigwait
	.global	_sigfe_sigwait
	.seh_proc _sigfe_sigwait
_sigfe_sigwait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigwait
	add	x9, x9, :lo12:sigwait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sigwaitinfo
	.global	_sigfe_sigwaitinfo
	.seh_proc _sigfe_sigwaitinfo
_sigfe_sigwaitinfo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sigwaitinfo
	add	x9, x9, :lo12:sigwaitinfo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	siprintf
	.global	_sigfe_siprintf
	.seh_proc _sigfe_siprintf
_sigfe_siprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, siprintf
	add	x9, x9, :lo12:siprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sleep
	.global	_sigfe_sleep
	.seh_proc _sigfe_sleep
_sigfe_sleep:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sleep
	add	x9, x9, :lo12:sleep
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	snprintf
	.global	_sigfe_snprintf
	.seh_proc _sigfe_snprintf
_sigfe_snprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, snprintf
	add	x9, x9, :lo12:snprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sockatmark
	.global	_sigfe_sockatmark
	.seh_proc _sigfe_sockatmark
_sigfe_sockatmark:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sockatmark
	add	x9, x9, :lo12:sockatmark
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	socketpair
	.global	_sigfe_socketpair
	.seh_proc _sigfe_socketpair
_sigfe_socketpair:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, socketpair
	add	x9, x9, :lo12:socketpair
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	spawnl
	.global	_sigfe_spawnl
	.seh_proc _sigfe_spawnl
_sigfe_spawnl:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, spawnl
	add	x9, x9, :lo12:spawnl
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	spawnle
	.global	_sigfe_spawnle
	.seh_proc _sigfe_spawnle
_sigfe_spawnle:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, spawnle
	add	x9, x9, :lo12:spawnle
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	spawnlp
	.global	_sigfe_spawnlp
	.seh_proc _sigfe_spawnlp
_sigfe_spawnlp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, spawnlp
	add	x9, x9, :lo12:spawnlp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	spawnlpe
	.global	_sigfe_spawnlpe
	.seh_proc _sigfe_spawnlpe
_sigfe_spawnlpe:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, spawnlpe
	add	x9, x9, :lo12:spawnlpe
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	spawnv
	.global	_sigfe_spawnv
	.seh_proc _sigfe_spawnv
_sigfe_spawnv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, spawnv
	add	x9, x9, :lo12:spawnv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	spawnve
	.global	_sigfe_spawnve
	.seh_proc _sigfe_spawnve
_sigfe_spawnve:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, spawnve
	add	x9, x9, :lo12:spawnve
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	spawnvp
	.global	_sigfe_spawnvp
	.seh_proc _sigfe_spawnvp
_sigfe_spawnvp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, spawnvp
	add	x9, x9, :lo12:spawnvp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	spawnvpe
	.global	_sigfe_spawnvpe
	.seh_proc _sigfe_spawnvpe
_sigfe_spawnvpe:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, spawnvpe
	add	x9, x9, :lo12:spawnvpe
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sprintf
	.global	_sigfe_sprintf
	.seh_proc _sigfe_sprintf
_sigfe_sprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sprintf
	add	x9, x9, :lo12:sprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sscanf
	.global	_sigfe_sscanf
	.seh_proc _sigfe_sscanf
_sigfe_sscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sscanf
	add	x9, x9, :lo12:sscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	stat
	.global	_sigfe_stat
	.seh_proc _sigfe_stat
_sigfe_stat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, stat
	add	x9, x9, :lo12:stat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	statfs
	.global	_sigfe_statfs
	.seh_proc _sigfe_statfs
_sigfe_statfs:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, statfs
	add	x9, x9, :lo12:statfs
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	statvfs
	.global	_sigfe_statvfs
	.seh_proc _sigfe_statvfs
_sigfe_statvfs:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, statvfs
	add	x9, x9, :lo12:statvfs
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	stime
	.global	_sigfe_stime
	.seh_proc _sigfe_stime
_sigfe_stime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, stime
	add	x9, x9, :lo12:stime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	str2sig
	.global	_sigfe_str2sig
	.seh_proc _sigfe_str2sig
_sigfe_str2sig:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, str2sig
	add	x9, x9, :lo12:str2sig
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strdup
	.global	_sigfe_strdup
	.seh_proc _sigfe_strdup
_sigfe_strdup:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strdup
	add	x9, x9, :lo12:strdup
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strerror
	.global	_sigfe_strerror
	.seh_proc _sigfe_strerror
_sigfe_strerror:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strerror
	add	x9, x9, :lo12:strerror
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strerror_l
	.global	_sigfe_strerror_l
	.seh_proc _sigfe_strerror_l
_sigfe_strerror_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strerror_l
	add	x9, x9, :lo12:strerror_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strerror_r
	.global	_sigfe_strerror_r
	.seh_proc _sigfe_strerror_r
_sigfe_strerror_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strerror_r
	add	x9, x9, :lo12:strerror_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strfmon
	.global	_sigfe_strfmon
	.seh_proc _sigfe_strfmon
_sigfe_strfmon:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strfmon
	add	x9, x9, :lo12:strfmon
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strfmon_l
	.global	_sigfe_strfmon_l
	.seh_proc _sigfe_strfmon_l
_sigfe_strfmon_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strfmon_l
	add	x9, x9, :lo12:strfmon_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strftime
	.global	_sigfe_strftime
	.seh_proc _sigfe_strftime
_sigfe_strftime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strftime
	add	x9, x9, :lo12:strftime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strftime_l
	.global	_sigfe_strftime_l
	.seh_proc _sigfe_strftime_l
_sigfe_strftime_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strftime_l
	add	x9, x9, :lo12:strftime_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strndup
	.global	_sigfe_strndup
	.seh_proc _sigfe_strndup
_sigfe_strndup:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strndup
	add	x9, x9, :lo12:strndup
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strptime
	.global	_sigfe_strptime
	.seh_proc _sigfe_strptime
_sigfe_strptime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strptime
	add	x9, x9, :lo12:strptime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strptime_l
	.global	_sigfe_strptime_l
	.seh_proc _sigfe_strptime_l
_sigfe_strptime_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strptime_l
	add	x9, x9, :lo12:strptime_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strsignal
	.global	_sigfe_strsignal
	.seh_proc _sigfe_strsignal
_sigfe_strsignal:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strsignal
	add	x9, x9, :lo12:strsignal
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strtod
	.global	_sigfe_strtod
	.seh_proc _sigfe_strtod
_sigfe_strtod:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strtod
	add	x9, x9, :lo12:strtod
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strtod_l
	.global	_sigfe_strtod_l
	.seh_proc _sigfe_strtod_l
_sigfe_strtod_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strtod_l
	add	x9, x9, :lo12:strtod_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strtof
	.global	_sigfe_strtof
	.seh_proc _sigfe_strtof
_sigfe_strtof:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strtof
	add	x9, x9, :lo12:strtof
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strtof_l
	.global	_sigfe_strtof_l
	.seh_proc _sigfe_strtof_l
_sigfe_strtof_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strtof_l
	add	x9, x9, :lo12:strtof_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strtold
	.global	_sigfe_strtold
	.seh_proc _sigfe_strtold
_sigfe_strtold:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strtold
	add	x9, x9, :lo12:strtold
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	strtold_l
	.global	_sigfe_strtold_l
	.seh_proc _sigfe_strtold_l
_sigfe_strtold_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, strtold_l
	add	x9, x9, :lo12:strtold_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	swprintf
	.global	_sigfe_swprintf
	.seh_proc _sigfe_swprintf
_sigfe_swprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, swprintf
	add	x9, x9, :lo12:swprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	swscanf
	.global	_sigfe_swscanf
	.seh_proc _sigfe_swscanf
_sigfe_swscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, swscanf
	add	x9, x9, :lo12:swscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	symlink
	.global	_sigfe_symlink
	.seh_proc _sigfe_symlink
_sigfe_symlink:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, symlink
	add	x9, x9, :lo12:symlink
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	symlinkat
	.global	_sigfe_symlinkat
	.seh_proc _sigfe_symlinkat
_sigfe_symlinkat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, symlinkat
	add	x9, x9, :lo12:symlinkat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sync
	.global	_sigfe_sync
	.seh_proc _sigfe_sync
_sigfe_sync:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sync
	add	x9, x9, :lo12:sync
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sysconf
	.global	_sigfe_sysconf
	.seh_proc _sigfe_sysconf
_sigfe_sysconf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sysconf
	add	x9, x9, :lo12:sysconf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	sysinfo
	.global	_sigfe_sysinfo
	.seh_proc _sigfe_sysinfo
_sigfe_sysinfo:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, sysinfo
	add	x9, x9, :lo12:sysinfo
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	syslog
	.global	_sigfe_syslog
	.seh_proc _sigfe_syslog
_sigfe_syslog:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, syslog
	add	x9, x9, :lo12:syslog
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	system
	.global	_sigfe_system
	.seh_proc _sigfe_system
_sigfe_system:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, system
	add	x9, x9, :lo12:system
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcdrain
	.global	_sigfe_tcdrain
	.seh_proc _sigfe_tcdrain
_sigfe_tcdrain:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcdrain
	add	x9, x9, :lo12:tcdrain
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcflow
	.global	_sigfe_tcflow
	.seh_proc _sigfe_tcflow
_sigfe_tcflow:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcflow
	add	x9, x9, :lo12:tcflow
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcflush
	.global	_sigfe_tcflush
	.seh_proc _sigfe_tcflush
_sigfe_tcflush:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcflush
	add	x9, x9, :lo12:tcflush
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcgetattr
	.global	_sigfe_tcgetattr
	.seh_proc _sigfe_tcgetattr
_sigfe_tcgetattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcgetattr
	add	x9, x9, :lo12:tcgetattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcgetpgrp
	.global	_sigfe_tcgetpgrp
	.seh_proc _sigfe_tcgetpgrp
_sigfe_tcgetpgrp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcgetpgrp
	add	x9, x9, :lo12:tcgetpgrp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcgetsid
	.global	_sigfe_tcgetsid
	.seh_proc _sigfe_tcgetsid
_sigfe_tcgetsid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcgetsid
	add	x9, x9, :lo12:tcgetsid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcgetwinsize
	.global	_sigfe_tcgetwinsize
	.seh_proc _sigfe_tcgetwinsize
_sigfe_tcgetwinsize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcgetwinsize
	add	x9, x9, :lo12:tcgetwinsize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcsendbreak
	.global	_sigfe_tcsendbreak
	.seh_proc _sigfe_tcsendbreak
_sigfe_tcsendbreak:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcsendbreak
	add	x9, x9, :lo12:tcsendbreak
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcsetattr
	.global	_sigfe_tcsetattr
	.seh_proc _sigfe_tcsetattr
_sigfe_tcsetattr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcsetattr
	add	x9, x9, :lo12:tcsetattr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcsetpgrp
	.global	_sigfe_tcsetpgrp
	.seh_proc _sigfe_tcsetpgrp
_sigfe_tcsetpgrp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcsetpgrp
	add	x9, x9, :lo12:tcsetpgrp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tcsetwinsize
	.global	_sigfe_tcsetwinsize
	.seh_proc _sigfe_tcsetwinsize
_sigfe_tcsetwinsize:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tcsetwinsize
	add	x9, x9, :lo12:tcsetwinsize
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tdelete
	.global	_sigfe_tdelete
	.seh_proc _sigfe_tdelete
_sigfe_tdelete:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tdelete
	add	x9, x9, :lo12:tdelete
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	telldir
	.global	_sigfe_telldir
	.seh_proc _sigfe_telldir
_sigfe_telldir:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, telldir
	add	x9, x9, :lo12:telldir
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tempnam
	.global	_sigfe_tempnam
	.seh_proc _sigfe_tempnam
_sigfe_tempnam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tempnam
	add	x9, x9, :lo12:tempnam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	thrd_create
	.global	_sigfe_thrd_create
	.seh_proc _sigfe_thrd_create
_sigfe_thrd_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, thrd_create
	add	x9, x9, :lo12:thrd_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	thrd_current
	.global	_sigfe_thrd_current
	.seh_proc _sigfe_thrd_current
_sigfe_thrd_current:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, thrd_current
	add	x9, x9, :lo12:thrd_current
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	thrd_detach
	.global	_sigfe_thrd_detach
	.seh_proc _sigfe_thrd_detach
_sigfe_thrd_detach:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, thrd_detach
	add	x9, x9, :lo12:thrd_detach
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	thrd_equal
	.global	_sigfe_thrd_equal
	.seh_proc _sigfe_thrd_equal
_sigfe_thrd_equal:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, thrd_equal
	add	x9, x9, :lo12:thrd_equal
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	thrd_exit
	.global	_sigfe_thrd_exit
	.seh_proc _sigfe_thrd_exit
_sigfe_thrd_exit:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, thrd_exit
	add	x9, x9, :lo12:thrd_exit
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	thrd_join
	.global	_sigfe_thrd_join
	.seh_proc _sigfe_thrd_join
_sigfe_thrd_join:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, thrd_join
	add	x9, x9, :lo12:thrd_join
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	thrd_sleep
	.global	_sigfe_thrd_sleep
	.seh_proc _sigfe_thrd_sleep
_sigfe_thrd_sleep:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, thrd_sleep
	add	x9, x9, :lo12:thrd_sleep
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	thrd_yield
	.global	_sigfe_thrd_yield
	.seh_proc _sigfe_thrd_yield
_sigfe_thrd_yield:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, thrd_yield
	add	x9, x9, :lo12:thrd_yield
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	time
	.global	_sigfe_time
	.seh_proc _sigfe_time
_sigfe_time:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, time
	add	x9, x9, :lo12:time
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timelocal
	.global	_sigfe_timelocal
	.seh_proc _sigfe_timelocal
_sigfe_timelocal:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timelocal
	add	x9, x9, :lo12:timelocal
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timer_create
	.global	_sigfe_timer_create
	.seh_proc _sigfe_timer_create
_sigfe_timer_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timer_create
	add	x9, x9, :lo12:timer_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timer_delete
	.global	_sigfe_timer_delete
	.seh_proc _sigfe_timer_delete
_sigfe_timer_delete:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timer_delete
	add	x9, x9, :lo12:timer_delete
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timer_getoverrun
	.global	_sigfe_timer_getoverrun
	.seh_proc _sigfe_timer_getoverrun
_sigfe_timer_getoverrun:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timer_getoverrun
	add	x9, x9, :lo12:timer_getoverrun
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timer_gettime
	.global	_sigfe_timer_gettime
	.seh_proc _sigfe_timer_gettime
_sigfe_timer_gettime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timer_gettime
	add	x9, x9, :lo12:timer_gettime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timer_settime
	.global	_sigfe_timer_settime
	.seh_proc _sigfe_timer_settime
_sigfe_timer_settime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timer_settime
	add	x9, x9, :lo12:timer_settime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timerfd_create
	.global	_sigfe_timerfd_create
	.seh_proc _sigfe_timerfd_create
_sigfe_timerfd_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timerfd_create
	add	x9, x9, :lo12:timerfd_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timerfd_gettime
	.global	_sigfe_timerfd_gettime
	.seh_proc _sigfe_timerfd_gettime
_sigfe_timerfd_gettime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timerfd_gettime
	add	x9, x9, :lo12:timerfd_gettime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timerfd_settime
	.global	_sigfe_timerfd_settime
	.seh_proc _sigfe_timerfd_settime
_sigfe_timerfd_settime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timerfd_settime
	add	x9, x9, :lo12:timerfd_settime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	times
	.global	_sigfe_times
	.seh_proc _sigfe_times
_sigfe_times:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, times
	add	x9, x9, :lo12:times
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timespec_get
	.global	_sigfe_timespec_get
	.seh_proc _sigfe_timespec_get
_sigfe_timespec_get:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timespec_get
	add	x9, x9, :lo12:timespec_get
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	timezone
	.global	_sigfe_timezone
	.seh_proc _sigfe_timezone
_sigfe_timezone:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, timezone
	add	x9, x9, :lo12:timezone
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tmpfile
	.global	_sigfe_tmpfile
	.seh_proc _sigfe_tmpfile
_sigfe_tmpfile:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tmpfile
	add	x9, x9, :lo12:tmpfile
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tmpnam
	.global	_sigfe_tmpnam
	.seh_proc _sigfe_tmpnam
_sigfe_tmpnam:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tmpnam
	add	x9, x9, :lo12:tmpnam
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	truncate
	.global	_sigfe_truncate
	.seh_proc _sigfe_truncate
_sigfe_truncate:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, truncate
	add	x9, x9, :lo12:truncate
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tsearch
	.global	_sigfe_tsearch
	.seh_proc _sigfe_tsearch
_sigfe_tsearch:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tsearch
	add	x9, x9, :lo12:tsearch
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tss_create
	.global	_sigfe_tss_create
	.seh_proc _sigfe_tss_create
_sigfe_tss_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tss_create
	add	x9, x9, :lo12:tss_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tss_delete
	.global	_sigfe_tss_delete
	.seh_proc _sigfe_tss_delete
_sigfe_tss_delete:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tss_delete
	add	x9, x9, :lo12:tss_delete
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tss_get
	.global	_sigfe_tss_get
	.seh_proc _sigfe_tss_get
_sigfe_tss_get:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tss_get
	add	x9, x9, :lo12:tss_get
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tss_set
	.global	_sigfe_tss_set
	.seh_proc _sigfe_tss_set
_sigfe_tss_set:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tss_set
	add	x9, x9, :lo12:tss_set
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ttyname
	.global	_sigfe_ttyname
	.seh_proc _sigfe_ttyname
_sigfe_ttyname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ttyname
	add	x9, x9, :lo12:ttyname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ttyname_r
	.global	_sigfe_ttyname_r
	.seh_proc _sigfe_ttyname_r
_sigfe_ttyname_r:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ttyname_r
	add	x9, x9, :lo12:ttyname_r
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	tzset
	.global	_sigfe_tzset
	.seh_proc _sigfe_tzset
_sigfe_tzset:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, tzset
	add	x9, x9, :lo12:tzset
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ualarm
	.global	_sigfe_ualarm
	.seh_proc _sigfe_ualarm
_sigfe_ualarm:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ualarm
	add	x9, x9, :lo12:ualarm
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	umount
	.global	_sigfe_umount
	.seh_proc _sigfe_umount
_sigfe_umount:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, umount
	add	x9, x9, :lo12:umount
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	uname
	.global	_sigfe_uname
	.seh_proc _sigfe_uname
_sigfe_uname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, uname
	add	x9, x9, :lo12:uname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	uname_x
	.global	_sigfe_uname_x
	.seh_proc _sigfe_uname_x
_sigfe_uname_x:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, uname_x
	add	x9, x9, :lo12:uname_x
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ungetc
	.global	_sigfe_ungetc
	.seh_proc _sigfe_ungetc
_sigfe_ungetc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ungetc
	add	x9, x9, :lo12:ungetc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	ungetwc
	.global	_sigfe_ungetwc
	.seh_proc _sigfe_ungetwc
_sigfe_ungetwc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, ungetwc
	add	x9, x9, :lo12:ungetwc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	unlink
	.global	_sigfe_unlink
	.seh_proc _sigfe_unlink
_sigfe_unlink:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, unlink
	add	x9, x9, :lo12:unlink
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	unlinkat
	.global	_sigfe_unlinkat
	.seh_proc _sigfe_unlinkat
_sigfe_unlinkat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, unlinkat
	add	x9, x9, :lo12:unlinkat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	unsetenv
	.global	_sigfe_unsetenv
	.seh_proc _sigfe_unsetenv
_sigfe_unsetenv:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, unsetenv
	add	x9, x9, :lo12:unsetenv
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	updwtmp
	.global	_sigfe_updwtmp
	.seh_proc _sigfe_updwtmp
_sigfe_updwtmp:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, updwtmp
	add	x9, x9, :lo12:updwtmp
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	updwtmpx
	.global	_sigfe_updwtmpx
	.seh_proc _sigfe_updwtmpx
_sigfe_updwtmpx:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, updwtmpx
	add	x9, x9, :lo12:updwtmpx
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	uselocale
	.global	_sigfe_uselocale
	.seh_proc _sigfe_uselocale
_sigfe_uselocale:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, uselocale
	add	x9, x9, :lo12:uselocale
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	usleep
	.global	_sigfe_usleep
	.seh_proc _sigfe_usleep
_sigfe_usleep:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, usleep
	add	x9, x9, :lo12:usleep
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	utime
	.global	_sigfe_utime
	.seh_proc _sigfe_utime
_sigfe_utime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, utime
	add	x9, x9, :lo12:utime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	utimensat
	.global	_sigfe_utimensat
	.seh_proc _sigfe_utimensat
_sigfe_utimensat:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, utimensat
	add	x9, x9, :lo12:utimensat
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	utimes
	.global	_sigfe_utimes
	.seh_proc _sigfe_utimes
_sigfe_utimes:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, utimes
	add	x9, x9, :lo12:utimes
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	utmpname
	.global	_sigfe_utmpname
	.seh_proc _sigfe_utmpname
_sigfe_utmpname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, utmpname
	add	x9, x9, :lo12:utmpname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	utmpxname
	.global	_sigfe_utmpxname
	.seh_proc _sigfe_utmpxname
_sigfe_utmpxname:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, utmpxname
	add	x9, x9, :lo12:utmpxname
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	valloc
	.global	_sigfe_valloc
	.seh_proc _sigfe_valloc
_sigfe_valloc:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, valloc
	add	x9, x9, :lo12:valloc
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vasnprintf
	.global	_sigfe_vasnprintf
	.seh_proc _sigfe_vasnprintf
_sigfe_vasnprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vasnprintf
	add	x9, x9, :lo12:vasnprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vasprintf
	.global	_sigfe_vasprintf
	.seh_proc _sigfe_vasprintf
_sigfe_vasprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vasprintf
	add	x9, x9, :lo12:vasprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vdprintf
	.global	_sigfe_vdprintf
	.seh_proc _sigfe_vdprintf
_sigfe_vdprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vdprintf
	add	x9, x9, :lo12:vdprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	verr
	.global	_sigfe_verr
	.seh_proc _sigfe_verr
_sigfe_verr:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, verr
	add	x9, x9, :lo12:verr
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	verrx
	.global	_sigfe_verrx
	.seh_proc _sigfe_verrx
_sigfe_verrx:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, verrx
	add	x9, x9, :lo12:verrx
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vfiprintf
	.global	_sigfe_vfiprintf
	.seh_proc _sigfe_vfiprintf
_sigfe_vfiprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vfiprintf
	add	x9, x9, :lo12:vfiprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vfork
	.global	_sigfe_vfork
	.seh_proc _sigfe_vfork
_sigfe_vfork:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vfork
	add	x9, x9, :lo12:vfork
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vfprintf
	.global	_sigfe_vfprintf
	.seh_proc _sigfe_vfprintf
_sigfe_vfprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vfprintf
	add	x9, x9, :lo12:vfprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vfscanf
	.global	_sigfe_vfscanf
	.seh_proc _sigfe_vfscanf
_sigfe_vfscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vfscanf
	add	x9, x9, :lo12:vfscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vfwprintf
	.global	_sigfe_vfwprintf
	.seh_proc _sigfe_vfwprintf
_sigfe_vfwprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vfwprintf
	add	x9, x9, :lo12:vfwprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vfwscanf
	.global	_sigfe_vfwscanf
	.seh_proc _sigfe_vfwscanf
_sigfe_vfwscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vfwscanf
	add	x9, x9, :lo12:vfwscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vhangup
	.global	_sigfe_vhangup
	.seh_proc _sigfe_vhangup
_sigfe_vhangup:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vhangup
	add	x9, x9, :lo12:vhangup
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vprintf
	.global	_sigfe_vprintf
	.seh_proc _sigfe_vprintf
_sigfe_vprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vprintf
	add	x9, x9, :lo12:vprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vscanf
	.global	_sigfe_vscanf
	.seh_proc _sigfe_vscanf
_sigfe_vscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vscanf
	add	x9, x9, :lo12:vscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vsnprintf
	.global	_sigfe_vsnprintf
	.seh_proc _sigfe_vsnprintf
_sigfe_vsnprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vsnprintf
	add	x9, x9, :lo12:vsnprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vsprintf
	.global	_sigfe_vsprintf
	.seh_proc _sigfe_vsprintf
_sigfe_vsprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vsprintf
	add	x9, x9, :lo12:vsprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vsscanf
	.global	_sigfe_vsscanf
	.seh_proc _sigfe_vsscanf
_sigfe_vsscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vsscanf
	add	x9, x9, :lo12:vsscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vswprintf
	.global	_sigfe_vswprintf
	.seh_proc _sigfe_vswprintf
_sigfe_vswprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vswprintf
	add	x9, x9, :lo12:vswprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vswscanf
	.global	_sigfe_vswscanf
	.seh_proc _sigfe_vswscanf
_sigfe_vswscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vswscanf
	add	x9, x9, :lo12:vswscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vsyslog
	.global	_sigfe_vsyslog
	.seh_proc _sigfe_vsyslog
_sigfe_vsyslog:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vsyslog
	add	x9, x9, :lo12:vsyslog
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vwarn
	.global	_sigfe_vwarn
	.seh_proc _sigfe_vwarn
_sigfe_vwarn:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vwarn
	add	x9, x9, :lo12:vwarn
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vwarnx
	.global	_sigfe_vwarnx
	.seh_proc _sigfe_vwarnx
_sigfe_vwarnx:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vwarnx
	add	x9, x9, :lo12:vwarnx
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vwprintf
	.global	_sigfe_vwprintf
	.seh_proc _sigfe_vwprintf
_sigfe_vwprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vwprintf
	add	x9, x9, :lo12:vwprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	vwscanf
	.global	_sigfe_vwscanf
	.seh_proc _sigfe_vwscanf
_sigfe_vwscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, vwscanf
	add	x9, x9, :lo12:vwscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	wait
	.global	_sigfe_wait
	.seh_proc _sigfe_wait
_sigfe_wait:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, wait
	add	x9, x9, :lo12:wait
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	wait3
	.global	_sigfe_wait3
	.seh_proc _sigfe_wait3
_sigfe_wait3:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, wait3
	add	x9, x9, :lo12:wait3
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	wait4
	.global	_sigfe_wait4
	.seh_proc _sigfe_wait4
_sigfe_wait4:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, wait4
	add	x9, x9, :lo12:wait4
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	waitpid
	.global	_sigfe_waitpid
	.seh_proc _sigfe_waitpid
_sigfe_waitpid:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, waitpid
	add	x9, x9, :lo12:waitpid
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	warn
	.global	_sigfe_warn
	.seh_proc _sigfe_warn
_sigfe_warn:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, warn
	add	x9, x9, :lo12:warn
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	warnx
	.global	_sigfe_warnx
	.seh_proc _sigfe_warnx
_sigfe_warnx:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, warnx
	add	x9, x9, :lo12:warnx
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	wcsftime
	.global	_sigfe_wcsftime
	.seh_proc _sigfe_wcsftime
_sigfe_wcsftime:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, wcsftime
	add	x9, x9, :lo12:wcsftime
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	wcsftime_l
	.global	_sigfe_wcsftime_l
	.seh_proc _sigfe_wcsftime_l
_sigfe_wcsftime_l:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, wcsftime_l
	add	x9, x9, :lo12:wcsftime_l
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	wprintf
	.global	_sigfe_wprintf
	.seh_proc _sigfe_wprintf
_sigfe_wprintf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, wprintf
	add	x9, x9, :lo12:wprintf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	write
	.global	_sigfe_write
	.seh_proc _sigfe_write
_sigfe_write:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, write
	add	x9, x9, :lo12:write
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	writev
	.global	_sigfe_writev
	.seh_proc _sigfe_writev
_sigfe_writev:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, writev
	add	x9, x9, :lo12:writev
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	wscanf
	.global	_sigfe_wscanf
	.seh_proc _sigfe_wscanf
_sigfe_wscanf:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, wscanf
	add	x9, x9, :lo12:wscanf
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_array
	.global	_sigfe_xdr_array
	.seh_proc _sigfe_xdr_array
_sigfe_xdr_array:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_array
	add	x9, x9, :lo12:xdr_array
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_bool
	.global	_sigfe_xdr_bool
	.seh_proc _sigfe_xdr_bool
_sigfe_xdr_bool:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_bool
	add	x9, x9, :lo12:xdr_bool
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_bytes
	.global	_sigfe_xdr_bytes
	.seh_proc _sigfe_xdr_bytes
_sigfe_xdr_bytes:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_bytes
	add	x9, x9, :lo12:xdr_bytes
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_char
	.global	_sigfe_xdr_char
	.seh_proc _sigfe_xdr_char
_sigfe_xdr_char:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_char
	add	x9, x9, :lo12:xdr_char
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_double
	.global	_sigfe_xdr_double
	.seh_proc _sigfe_xdr_double
_sigfe_xdr_double:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_double
	add	x9, x9, :lo12:xdr_double
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_enum
	.global	_sigfe_xdr_enum
	.seh_proc _sigfe_xdr_enum
_sigfe_xdr_enum:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_enum
	add	x9, x9, :lo12:xdr_enum
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_float
	.global	_sigfe_xdr_float
	.seh_proc _sigfe_xdr_float
_sigfe_xdr_float:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_float
	add	x9, x9, :lo12:xdr_float
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_free
	.global	_sigfe_xdr_free
	.seh_proc _sigfe_xdr_free
_sigfe_xdr_free:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_free
	add	x9, x9, :lo12:xdr_free
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_hyper
	.global	_sigfe_xdr_hyper
	.seh_proc _sigfe_xdr_hyper
_sigfe_xdr_hyper:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_hyper
	add	x9, x9, :lo12:xdr_hyper
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_int
	.global	_sigfe_xdr_int
	.seh_proc _sigfe_xdr_int
_sigfe_xdr_int:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_int
	add	x9, x9, :lo12:xdr_int
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_int16_t
	.global	_sigfe_xdr_int16_t
	.seh_proc _sigfe_xdr_int16_t
_sigfe_xdr_int16_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_int16_t
	add	x9, x9, :lo12:xdr_int16_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_int32_t
	.global	_sigfe_xdr_int32_t
	.seh_proc _sigfe_xdr_int32_t
_sigfe_xdr_int32_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_int32_t
	add	x9, x9, :lo12:xdr_int32_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_int64_t
	.global	_sigfe_xdr_int64_t
	.seh_proc _sigfe_xdr_int64_t
_sigfe_xdr_int64_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_int64_t
	add	x9, x9, :lo12:xdr_int64_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_int8_t
	.global	_sigfe_xdr_int8_t
	.seh_proc _sigfe_xdr_int8_t
_sigfe_xdr_int8_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_int8_t
	add	x9, x9, :lo12:xdr_int8_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_long
	.global	_sigfe_xdr_long
	.seh_proc _sigfe_xdr_long
_sigfe_xdr_long:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_long
	add	x9, x9, :lo12:xdr_long
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_longlong_t
	.global	_sigfe_xdr_longlong_t
	.seh_proc _sigfe_xdr_longlong_t
_sigfe_xdr_longlong_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_longlong_t
	add	x9, x9, :lo12:xdr_longlong_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_netobj
	.global	_sigfe_xdr_netobj
	.seh_proc _sigfe_xdr_netobj
_sigfe_xdr_netobj:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_netobj
	add	x9, x9, :lo12:xdr_netobj
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_opaque
	.global	_sigfe_xdr_opaque
	.seh_proc _sigfe_xdr_opaque
_sigfe_xdr_opaque:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_opaque
	add	x9, x9, :lo12:xdr_opaque
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_pointer
	.global	_sigfe_xdr_pointer
	.seh_proc _sigfe_xdr_pointer
_sigfe_xdr_pointer:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_pointer
	add	x9, x9, :lo12:xdr_pointer
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_reference
	.global	_sigfe_xdr_reference
	.seh_proc _sigfe_xdr_reference
_sigfe_xdr_reference:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_reference
	add	x9, x9, :lo12:xdr_reference
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_short
	.global	_sigfe_xdr_short
	.seh_proc _sigfe_xdr_short
_sigfe_xdr_short:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_short
	add	x9, x9, :lo12:xdr_short
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_sizeof
	.global	_sigfe_xdr_sizeof
	.seh_proc _sigfe_xdr_sizeof
_sigfe_xdr_sizeof:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_sizeof
	add	x9, x9, :lo12:xdr_sizeof
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_string
	.global	_sigfe_xdr_string
	.seh_proc _sigfe_xdr_string
_sigfe_xdr_string:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_string
	add	x9, x9, :lo12:xdr_string
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_char
	.global	_sigfe_xdr_u_char
	.seh_proc _sigfe_xdr_u_char
_sigfe_xdr_u_char:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_char
	add	x9, x9, :lo12:xdr_u_char
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_hyper
	.global	_sigfe_xdr_u_hyper
	.seh_proc _sigfe_xdr_u_hyper
_sigfe_xdr_u_hyper:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_hyper
	add	x9, x9, :lo12:xdr_u_hyper
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_int
	.global	_sigfe_xdr_u_int
	.seh_proc _sigfe_xdr_u_int
_sigfe_xdr_u_int:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_int
	add	x9, x9, :lo12:xdr_u_int
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_int16_t
	.global	_sigfe_xdr_u_int16_t
	.seh_proc _sigfe_xdr_u_int16_t
_sigfe_xdr_u_int16_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_int16_t
	add	x9, x9, :lo12:xdr_u_int16_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_int32_t
	.global	_sigfe_xdr_u_int32_t
	.seh_proc _sigfe_xdr_u_int32_t
_sigfe_xdr_u_int32_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_int32_t
	add	x9, x9, :lo12:xdr_u_int32_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_int64_t
	.global	_sigfe_xdr_u_int64_t
	.seh_proc _sigfe_xdr_u_int64_t
_sigfe_xdr_u_int64_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_int64_t
	add	x9, x9, :lo12:xdr_u_int64_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_int8_t
	.global	_sigfe_xdr_u_int8_t
	.seh_proc _sigfe_xdr_u_int8_t
_sigfe_xdr_u_int8_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_int8_t
	add	x9, x9, :lo12:xdr_u_int8_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_long
	.global	_sigfe_xdr_u_long
	.seh_proc _sigfe_xdr_u_long
_sigfe_xdr_u_long:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_long
	add	x9, x9, :lo12:xdr_u_long
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_longlong_t
	.global	_sigfe_xdr_u_longlong_t
	.seh_proc _sigfe_xdr_u_longlong_t
_sigfe_xdr_u_longlong_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_longlong_t
	add	x9, x9, :lo12:xdr_u_longlong_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_u_short
	.global	_sigfe_xdr_u_short
	.seh_proc _sigfe_xdr_u_short
_sigfe_xdr_u_short:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_u_short
	add	x9, x9, :lo12:xdr_u_short
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_uint16_t
	.global	_sigfe_xdr_uint16_t
	.seh_proc _sigfe_xdr_uint16_t
_sigfe_xdr_uint16_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_uint16_t
	add	x9, x9, :lo12:xdr_uint16_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_uint32_t
	.global	_sigfe_xdr_uint32_t
	.seh_proc _sigfe_xdr_uint32_t
_sigfe_xdr_uint32_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_uint32_t
	add	x9, x9, :lo12:xdr_uint32_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_uint64_t
	.global	_sigfe_xdr_uint64_t
	.seh_proc _sigfe_xdr_uint64_t
_sigfe_xdr_uint64_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_uint64_t
	add	x9, x9, :lo12:xdr_uint64_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_uint8_t
	.global	_sigfe_xdr_uint8_t
	.seh_proc _sigfe_xdr_uint8_t
_sigfe_xdr_uint8_t:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_uint8_t
	add	x9, x9, :lo12:xdr_uint8_t
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_union
	.global	_sigfe_xdr_union
	.seh_proc _sigfe_xdr_union
_sigfe_xdr_union:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_union
	add	x9, x9, :lo12:xdr_union
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_vector
	.global	_sigfe_xdr_vector
	.seh_proc _sigfe_xdr_vector
_sigfe_xdr_vector:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_vector
	add	x9, x9, :lo12:xdr_vector
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_void
	.global	_sigfe_xdr_void
	.seh_proc _sigfe_xdr_void
_sigfe_xdr_void:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_void
	add	x9, x9, :lo12:xdr_void
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdr_wrapstring
	.global	_sigfe_xdr_wrapstring
	.seh_proc _sigfe_xdr_wrapstring
_sigfe_xdr_wrapstring:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdr_wrapstring
	add	x9, x9, :lo12:xdr_wrapstring
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdrmem_create
	.global	_sigfe_xdrmem_create
	.seh_proc _sigfe_xdrmem_create
_sigfe_xdrmem_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdrmem_create
	add	x9, x9, :lo12:xdrmem_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdrrec_create
	.global	_sigfe_xdrrec_create
	.seh_proc _sigfe_xdrrec_create
_sigfe_xdrrec_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdrrec_create
	add	x9, x9, :lo12:xdrrec_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdrrec_endofrecord
	.global	_sigfe_xdrrec_endofrecord
	.seh_proc _sigfe_xdrrec_endofrecord
_sigfe_xdrrec_endofrecord:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdrrec_endofrecord
	add	x9, x9, :lo12:xdrrec_endofrecord
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdrrec_eof
	.global	_sigfe_xdrrec_eof
	.seh_proc _sigfe_xdrrec_eof
_sigfe_xdrrec_eof:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdrrec_eof
	add	x9, x9, :lo12:xdrrec_eof
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdrrec_skiprecord
	.global	_sigfe_xdrrec_skiprecord
	.seh_proc _sigfe_xdrrec_skiprecord
_sigfe_xdrrec_skiprecord:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdrrec_skiprecord
	add	x9, x9, :lo12:xdrrec_skiprecord
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

	.extern	xdrstdio_create
	.global	_sigfe_xdrstdio_create
	.seh_proc _sigfe_xdrstdio_create
_sigfe_xdrstdio_create:
	stp	x29, x30, [sp, #-16]!
	.seh_save_regp_x x29, 16
	adrp	x9, xdrstdio_create
	add	x9, x9, :lo12:xdrstdio_create
	str	x9, [sp, #-16]!
	.seh_stackalloc 16
	.seh_endprologue
	b	_sigfe
	.seh_endproc

