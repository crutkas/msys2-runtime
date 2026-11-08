	.text
	.global DllMainCRTStartup
DllMainCRTStartup:
	mov	w0, 1
	ret

	.data
	.balign 16
	.global aarch64_near_value
aarch64_near_value:
	.quad	0x1122334455667788

	.balign 16
	.global aarch64_far_object
aarch64_far_object:
	.quad	0x8877665544332211
