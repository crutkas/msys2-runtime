  .section	.foo_autoload_text,"wx"
  .global	testfn
  .align	16
testfn:
  movq		3f(%rip),%rax
  jmp		*%rax
1:
  nop
2:.quad		.foo_info
3:.quad		1b
  .section	.data_cygwin_nocopy,"w"
.foo_info:
  .quad		0
