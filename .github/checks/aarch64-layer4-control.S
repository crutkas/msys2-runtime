	.include "tlsoffsets"

	.text
	.global mainCRTStartup
mainCRTStartup:
	stp	x29, x30, [sp, #-16]!
	bl	init_tls
	bl	test_sigfe
	bl	test_setjmp
	bl	test_sigsetjmp
	mov	w0, wzr
	b	ExitProcess

	.global delayed_mainCRTStartup
delayed_mainCRTStartup:
	mov	x0, #0x1234
	mov	x16, #0x1616
	mov	x17, #0x1717
	bl	sigdelayed
	mov	w0, #90
	b	ExitProcess

fail:
	b	ExitProcess

tls_address:
	ldr	x9, [x18, #8]
	add	x0, x9, x0
	ret

init_tls:
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.current_sig
	str	wzr, [x9, x10]
	ldr	x10, =_cygtls.incyg
	str	wzr, [x9, x10]
	ldr	x10, =_cygtls.stacklock
	str	wzr, [x9, x10]
	adrp	x11, signal_slots
	add	x11, x11, :lo12:signal_slots
	ldr	x10, =_cygtls.stackptr
	str	x11, [x9, x10]
	ldr	x10, =_cygtls.initialized
	movz	w11, #0x173f
	movk	w11, #0xc763, lsl #16
	str	w11, [x9, x10]
	ldp	x29, x30, [sp], #16
	ret

test_sigfe:
	stp	x29, x30, [sp, #-16]!
	mov	x29, sp
	bl	init_tls
	bl	_sigfe_layer4_target
	cmp	x0, #42
	b.ne	.Lsigfe_result
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.stackptr
	ldr	x11, [x9, x10]
	adrp	x12, signal_slots
	add	x12, x12, :lo12:signal_slots
	cmp	x11, x12
	b.ne	.Lsigfe_stack
	ldr	x10, =_cygtls.incyg
	ldr	w11, [x9, x10]
	cbnz	w11, .Lsigfe_incyg
	ldr	x10, =_cygtls.stacklock
	ldr	w11, [x9, x10]
	cbnz	w11, .Lsigfe_lock

	// A corrupt initialization magic must bypass all TLS stack mutation.
	ldr	x10, =_cygtls.initialized
	str	wzr, [x9, x10]
	bl	_sigfe_layer4_target
	cmp	x0, #42
	b.ne	.Lsigfe_corrupt_result
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.stackptr
	ldr	x11, [x9, x10]
	adrp	x12, signal_slots
	add	x12, x12, :lo12:signal_slots
	cmp	x11, x12
	b.ne	.Lsigfe_corrupt_stack
	bl	init_tls
	ldp	x29, x30, [sp], #16
	ret
.Lsigfe_result:
	mov	w0, #11
	b	fail
.Lsigfe_stack:
	mov	w0, #12
	b	fail
.Lsigfe_incyg:
	mov	w0, #13
	b	fail
.Lsigfe_lock:
	mov	w0, #14
	b	fail
.Lsigfe_corrupt_result:
	mov	w0, #15
	b	fail
.Lsigfe_corrupt_stack:
	mov	w0, #16
	b	fail

	.global layer4_target
layer4_target:
	mov	x9, sp
	tst	x9, #15
	b.ne	.Ltarget_alignment
	mov	x0, #42
	ret
.Ltarget_alignment:
	mov	w0, #17
	b	fail

test_setjmp:
	sub	sp, sp, #16
	str	x30, [sp]
	bl	init_tls
	adrp	x9, handler_calls
	add	x9, x9, :lo12:handler_calls
	str	wzr, [x9]
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.current_sig
	mov	w11, #1
	str	w11, [x9, x10]
	adrp	x9, expected_sp
	add	x9, x9, :lo12:expected_sp
	mov	x10, sp
	str	x10, [x9]

	mov	x19, #19
	mov	x20, #20
	mov	x21, #21
	mov	x22, #22
	mov	x23, #23
	mov	x24, #24
	mov	x25, #25
	mov	x26, #26
	mov	x27, #27
	mov	x28, #28
	mov	x29, #29
	mov	x9, #81
	fmov	d8, x9
	mov	x9, #91
	fmov	d9, x9
	mov	x9, #101
	fmov	d10, x9
	mov	x9, #111
	fmov	d11, x9
	mov	x9, #121
	fmov	d12, x9
	mov	x9, #131
	fmov	d13, x9
	mov	x9, #141
	fmov	d14, x9
	mov	x9, #151
	fmov	d15, x9
	msr	fpcr, xzr
	mov	x9, #1
	msr	fpsr, x9

	adrp	x0, jump_buffer
	add	x0, x0, :lo12:jump_buffer
	bl	setjmp
	cbnz	x0, .Lsetjmp_resumed

	mov	x19, xzr
	mov	x20, xzr
	mov	x21, xzr
	mov	x22, xzr
	mov	x23, xzr
	mov	x24, xzr
	mov	x25, xzr
	mov	x26, xzr
	mov	x27, xzr
	mov	x28, xzr
	mov	x29, xzr
	fmov	d8, xzr
	fmov	d9, xzr
	fmov	d10, xzr
	fmov	d11, xzr
	fmov	d12, xzr
	fmov	d13, xzr
	fmov	d14, xzr
	fmov	d15, xzr
	mov	x9, #0x400000
	msr	fpcr, x9
	msr	fpsr, xzr
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.stackptr
	adrp	x11, signal_slots
	add	x11, x11, :lo12:signal_slots
	add	x11, x11, #16
	str	x11, [x9, x10]
	adrp	x0, jump_buffer
	add	x0, x0, :lo12:jump_buffer
	mov	x1, #7
	bl	longjmp
	mov	w0, #20
	b	fail

.Lsetjmp_resumed:
	cmp	x0, #7
	b.ne	.Lsetjmp_value
	cmp	x19, #19
	b.ne	.Lsetjmp_gpr
	cmp	x20, #20
	b.ne	.Lsetjmp_gpr
	cmp	x21, #21
	b.ne	.Lsetjmp_gpr
	cmp	x22, #22
	b.ne	.Lsetjmp_gpr
	cmp	x23, #23
	b.ne	.Lsetjmp_gpr
	cmp	x24, #24
	b.ne	.Lsetjmp_gpr
	cmp	x25, #25
	b.ne	.Lsetjmp_gpr
	cmp	x26, #26
	b.ne	.Lsetjmp_gpr
	cmp	x27, #27
	b.ne	.Lsetjmp_gpr
	cmp	x28, #28
	b.ne	.Lsetjmp_gpr
	cmp	x29, #29
	b.ne	.Lsetjmp_gpr
	adrp	x9, expected_sp
	add	x9, x9, :lo12:expected_sp
	ldr	x9, [x9]
	cmp	sp, x9
	b.ne	.Lsetjmp_sp
	mrs	x9, fpcr
	cbnz	x9, .Lsetjmp_fpcr
	mrs	x9, fpsr
	cmp	x9, #1
	b.ne	.Lsetjmp_fpsr
	mov	x10, #81
	fmov	x9, d8
	cmp	x9, x10
	b.ne	.Lsetjmp_fpr
	mov	x10, #91
	fmov	x9, d9
	cmp	x9, x10
	b.ne	.Lsetjmp_fpr
	mov	x10, #101
	fmov	x9, d10
	cmp	x9, x10
	b.ne	.Lsetjmp_fpr
	mov	x10, #111
	fmov	x9, d11
	cmp	x9, x10
	b.ne	.Lsetjmp_fpr
	mov	x10, #121
	fmov	x9, d12
	cmp	x9, x10
	b.ne	.Lsetjmp_fpr
	mov	x10, #131
	fmov	x9, d13
	cmp	x9, x10
	b.ne	.Lsetjmp_fpr
	mov	x10, #141
	fmov	x9, d14
	cmp	x9, x10
	b.ne	.Lsetjmp_fpr
	mov	x10, #151
	fmov	x9, d15
	cmp	x9, x10
	b.ne	.Lsetjmp_fpr
	adrp	x9, jump_guard_before
	add	x9, x9, :lo12:jump_guard_before
	ldr	x10, [x9]
	ldr	x11, =0x1122334455667788
	cmp	x10, x11
	b.ne	.Lsetjmp_guard
	adrp	x9, jump_guard_after
	add	x9, x9, :lo12:jump_guard_after
	ldr	x10, [x9]
	ldr	x11, =0x8877665544332211
	cmp	x10, x11
	b.ne	.Lsetjmp_guard
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.stackptr
	ldr	x11, [x9, x10]
	adrp	x12, signal_slots
	add	x12, x12, :lo12:signal_slots
	cmp	x11, x12
	b.ne	.Lsetjmp_tls
	adrp	x9, handler_calls
	add	x9, x9, :lo12:handler_calls
	ldr	w10, [x9]
	cmp	w10, #1
	b.ne	.Lsetjmp_handler
	ldr	x30, [sp]
	add	sp, sp, #16
	ret
.Lsetjmp_value:
	mov	w0, #21
	b	fail
.Lsetjmp_gpr:
	mov	w0, #22
	b	fail
.Lsetjmp_sp:
	mov	w0, #23
	b	fail
.Lsetjmp_fpcr:
	mov	w0, #24
	b	fail
.Lsetjmp_fpsr:
	mov	w0, #25
	b	fail
.Lsetjmp_fpr:
	mov	w0, #26
	b	fail
.Lsetjmp_guard:
	mov	w0, #27
	b	fail
.Lsetjmp_tls:
	mov	w0, #28
	b	fail
.Lsetjmp_handler:
	mov	w0, #29
	b	fail

test_sigsetjmp:
	sub	sp, sp, #16
	str	x30, [sp]
	bl	init_tls
	adrp	x9, mask_calls
	add	x9, x9, :lo12:mask_calls
	str	wzr, [x9]
	adrp	x0, sigjump_buffer
	add	x0, x0, :lo12:sigjump_buffer
	mov	w1, #1
	bl	sigsetjmp
	cbnz	x0, .Lsigjmp_resumed
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.stackptr
	adrp	x11, signal_slots
	add	x11, x11, :lo12:signal_slots
	add	x11, x11, #24
	str	x11, [x9, x10]
	adrp	x0, sigjump_buffer
	add	x0, x0, :lo12:sigjump_buffer
	mov	x1, #9
	bl	siglongjmp
	mov	w0, #30
	b	fail
.Lsigjmp_resumed:
	cmp	x0, #9
	b.ne	.Lsigjmp_value
	adrp	x9, mask_calls
	add	x9, x9, :lo12:mask_calls
	ldr	w10, [x9]
	cmp	w10, #2
	b.ne	.Lsigjmp_calls
	adrp	x9, sigjump_buffer
	add	x9, x9, :lo12:sigjump_buffer
	ldr	w10, [x9, #0xc8]
	cmp	w10, #1
	b.ne	.Lsigjmp_savemask
	ldr	x10, [x9, #0xd0]
	ldr	x11, =0x55aa55aa55aa55aa
	cmp	x10, x11
	b.ne	.Lsigjmp_mask
	adrp	x9, sigjump_guard_after
	add	x9, x9, :lo12:sigjump_guard_after
	ldr	x10, [x9]
	ldr	x11, =0xabcdef0123456789
	cmp	x10, x11
	b.ne	.Lsigjmp_guard
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.stackptr
	ldr	x11, [x9, x10]
	adrp	x12, signal_slots
	add	x12, x12, :lo12:signal_slots
	cmp	x11, x12
	b.ne	.Lsigjmp_tls
	ldr	x30, [sp]
	add	sp, sp, #16
	ret
.Lsigjmp_value:
	mov	w0, #31
	b	fail
.Lsigjmp_calls:
	mov	w0, #32
	b	fail
.Lsigjmp_savemask:
	mov	w0, #33
	b	fail
.Lsigjmp_mask:
	mov	w0, #34
	b	fail
.Lsigjmp_guard:
	mov	w0, #35
	b	fail
.Lsigjmp_tls:
	mov	w0, #36
	b	fail

	.global pthread_sigmask
pthread_sigmask:
	adrp	x9, mask_calls
	add	x9, x9, :lo12:mask_calls
	ldr	w10, [x9]
	add	w10, w10, #1
	str	w10, [x9]
	cbnz	x1, .Lmask_restore
	cbz	x2, .Lmask_args
	ldr	x10, =0x55aa55aa55aa55aa
	str	x10, [x2]
	mov	w0, wzr
	ret
.Lmask_restore:
	cbnz	x2, .Lmask_args
	ldr	x10, [x1]
	ldr	x11, =0x55aa55aa55aa55aa
	cmp	x10, x11
	b.ne	.Lmask_data
	mov	w0, wzr
	ret
.Lmask_args:
	mov	w0, #37
	b	fail
.Lmask_data:
	mov	w0, #38
	b	fail

	.global _ZN7_cygtls19call_signal_handlerEv
_ZN7_cygtls19call_signal_handlerEv:
	ldr	x9, [x18, #8]
	ldr	x10, =_cygtls.start_offset
	add	x10, x9, x10
	cmp	x0, x10
	b.ne	.Lhandler_arg
	ldr	x10, =_cygtls.current_sig
	str	wzr, [x9, x10]
	adrp	x9, handler_calls
	add	x9, x9, :lo12:handler_calls
	ldr	w10, [x9]
	add	w10, w10, #1
	str	w10, [x9]
	mov	w0, wzr
	ret
.Lhandler_arg:
	mov	w0, #39
	b	fail

	.data
	.p2align 3
jump_guard_before:
	.quad	0x1122334455667788
jump_buffer:
	.space	200
jump_guard_after:
	.quad	0x8877665544332211
sigjump_guard_before:
	.quad	0x123456789abcdef0
sigjump_buffer:
	.space	216
sigjump_guard_after:
	.quad	0xabcdef0123456789
signal_slots:
	.space	64
expected_sp:
	.quad	0
mask_calls:
	.long	0
handler_calls:
	.long	0
