	.text
	.global main
main:
	adrp	x0, aarch64_far_object+1
	add	x0, x0, :lo12:aarch64_far_object+1
	mov	w0, 0
	ret
