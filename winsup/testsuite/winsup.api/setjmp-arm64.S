	.text
	.globl setjmp_arm64_check
	.seh_proc setjmp_arm64_check
setjmp_arm64_check:
	stp x29, x30, [sp, #-384]!
	.seh_save_fplr_x 384
	stp x19, x20, [sp, #16]
	.seh_save_regp x19, 16
	stp x21, x22, [sp, #32]
	.seh_save_regp x21, 32
	.seh_endprologue
	mov w19, w0
	mov w21, w1
	mov w20, #0x1234
	add x0, sp, #64
	cmp w21, #0
	b.ge .Lsigsetjmp
	bl setjmp
	b .Lreturned
.Lsigsetjmp:
	mov w1, w21
	bl sigsetjmp
.Lreturned:
	cbnz w0, .Lverify
	add x0, sp, #64
	mov w1, w19
	cmp w21, #0
	b.lt .Llongjmp
	bl siglongjmp
	brk #0
.Llongjmp:
	bl longjmp
	brk #0
.Lverify:
	mov w22, #0x1234
	cmp w20, w22
	b.ne .Lfailed
	mov w22, w19
	cmp w22, #0
	cinc w22, w22, eq
	cmp w0, w22
	b.ne .Lfailed
	mov w0, #0
	b .Ldone
.Lfailed:
	mov w0, #1
.Ldone:
	.seh_startepilogue
	ldp x21, x22, [sp, #32]
	.seh_save_regp x21, 32
	ldp x19, x20, [sp, #16]
	.seh_save_regp x19, 16
	ldp x29, x30, [sp], #384
	.seh_save_fplr_x 384
	.seh_endepilogue
	ret
	.seh_endproc
