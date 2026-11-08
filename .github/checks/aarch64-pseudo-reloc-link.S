	.text

	.macro import_address name, addend
	.global \name
\name:
	adrp	x0, abi_imported_data+\addend
	add	x0, x0, :lo12:abi_imported_data+\addend
	ret
	.endm

	import_address abi_import_zero, 0
	import_address abi_import_plus_one, 1
	import_address abi_import_plus_page, 0x1000
	import_address abi_import_minus_one, -1
	import_address abi_import_minus_page, -0x1000

	.macro import_load name, mnemonic, destination, addend
	.global \name
\name:
	adrp	x1, abi_imported_data+\addend
	\mnemonic \destination, [x1, :lo12:abi_imported_data+\addend]
	ret
	.endm

	import_load abi_load_byte, ldrb, w0, 0
	import_load abi_load_half, ldrh, w0, 2
	import_load abi_load_word, ldr, w0, 4
	import_load abi_load_double, ldr, x0, 8
	import_load abi_load_quad, ldr, q0, 16
	import_load abi_store_byte, strb, w0, 0
	import_load abi_store_half, strh, w0, 2
	import_load abi_store_word, str, w0, 4
	import_load abi_store_double, str, x0, 8
	import_load abi_store_quad, str, q0, 16
