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
