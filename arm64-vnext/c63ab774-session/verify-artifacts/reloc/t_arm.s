  .section	.foo_autoload_text,"wx"
  .global	testfn
  .balign	16
testfn:
  ldr		x16, 3f
  br		x16
1:
  nop
2:.quad		.foo_info
3:.quad		1b
  .balign	8
  .section	.data_cygwin_nocopy,"w"
.foo_info:
  .quad		0
