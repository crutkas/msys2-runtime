	.text
	.p2align 2
	.global layer3_autoload_call
layer3_autoload_call:
	adrp	x16, layer3_autoload_slot
	add	x16, x16, :lo12:layer3_autoload_slot
	ldr	x17, [x16]
	br	x17

	.global layer3_autoload_patch
layer3_autoload_patch:
	stur	x1, [x0, #12]
	ldur	x0, [x0, #12]
	ret
