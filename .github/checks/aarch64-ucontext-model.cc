#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(__aarch64__)
#error This check must run on AArch64
#endif

static constexpr size_t min_sig_stack = 8192;
static constexpr size_t context_size = 0x3d0;

static void
check (bool condition, const char *message)
{
  if (!condition)
    {
      fprintf (stderr, "AArch64 ucontext model failure: %s\n", message);
      abort ();
    }
}

static uintptr_t
read_sp ()
{
  uintptr_t value;
  __asm__ __volatile__ ("mov %0, sp" : "=r" (value));
  return value;
}

static uintptr_t
read_x18 ()
{
  uintptr_t value;
  __asm__ __volatile__ ("mov %0, x18" : "=r" (value));
  return value;
}

struct altstack_layout
{
  uintptr_t begin;
  uintptr_t end;
  uintptr_t context;
};

static altstack_layout
layout_altstack (void *base, size_t size)
{
  uintptr_t begin = (uintptr_t) base;
  uintptr_t end = begin + size;
  uintptr_t aligned_top = end & ~(uintptr_t) 15;
  uintptr_t context = (aligned_top - context_size) & ~(uintptr_t) 15;
  return {begin, end, context};
}

using altstack_handler = void (*) (void *);

struct altstack_call
{
  uintptr_t sp;
  uintptr_t arg;
  uintptr_t handler;
};

__attribute__ ((noinline)) static void
run_on_altstack (uintptr_t sp, altstack_handler handler, void *arg)
{
  altstack_call call = {sp, (uintptr_t) arg, (uintptr_t) handler};

  __asm__ __volatile__ ("\n\
	mov	x17, %[ARGS]		\n\
	mov	x19, sp			\n\
	ldp	x9, x0, [x17]		\n\
	ldr	x16, [x17, #16]		\n\
	mov	sp, x9			\n\
	blr	x16			\n\
	mov	sp, x19			\n"
	: : [ARGS] "r" (&call)
	: "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7",
	  "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15",
	  "x16", "x17", "x19", "x30",
	  "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7",
	  "v8", "v9", "v10", "v11", "v12", "v13", "v14", "v15",
	  "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23",
	  "v24", "v25", "v26", "v27", "v28", "v29", "v30", "v31",
	  "cc", "memory");
}

struct signal_context_model
{
  uint64_t mask;
  uint64_t pc;
  uint64_t marker;
};

struct altstack_probe
{
  altstack_layout layout;
  signal_context_model *context;
  uintptr_t nested_sp;
  altstack_probe *nested;
  bool entered;
};

static void
probe_altstack (void *opaque)
{
  altstack_probe *probe = (altstack_probe *) opaque;
  uintptr_t sp = read_sp ();
  char marker;

  check ((sp & 15) == 0, "handler SP is not 16-byte aligned");
  check ((uintptr_t) &marker >= probe->layout.begin,
	 "handler stack escaped below its reservation");
  check ((uintptr_t) &marker < probe->layout.context,
	 "handler stack overlaps the saved signal context");
  probe->context->mask ^= UINT64_C (0x55aa55aa55aa55aa);
  probe->entered = true;

  if (probe->nested)
    {
      uintptr_t before = read_sp ();
      run_on_altstack (probe->nested_sp, probe_altstack, probe->nested);
      uintptr_t after = read_sp ();
      check (before == after, "nested alternate stack did not restore SP");
    }
}

static void
check_altstack_switch ()
{
  alignas (16) unsigned char outer_stack[min_sig_stack];
  alignas (16) unsigned char inner_stack[min_sig_stack + 31];
  altstack_layout outer = layout_altstack (outer_stack, sizeof outer_stack);
  altstack_layout inner
    = layout_altstack (inner_stack + 7, sizeof inner_stack - 7);

  check ((outer.context & 15) == 0, "outer context is misaligned");
  check ((inner.context & 15) == 0, "unaligned stack context is misaligned");
  check (outer.context >= outer.begin, "outer context is below reservation");
  check (inner.context >= inner.begin, "inner context is below reservation");
  check (outer.context + context_size <= outer.end,
	 "outer context exceeds reservation");
  check (inner.context + context_size <= inner.end,
	 "inner context exceeds reservation");

  signal_context_model outer_source =
    {UINT64_C (0x0123456789abcdef), UINT64_C (0x1000200030004000), 1};
  signal_context_model inner_source =
    {UINT64_C (0xfedcba9876543210), UINT64_C (0x5000600070008000), 2};
  auto *outer_context
    = (signal_context_model *) (outer.context + context_size
				- sizeof (signal_context_model));
  auto *inner_context
    = (signal_context_model *) (inner.context + context_size
				- sizeof (signal_context_model));
  memcpy (outer_context, &outer_source, sizeof outer_source);
  memcpy (inner_context, &inner_source, sizeof inner_source);

  altstack_probe inner_probe = {inner, inner_context, 0, nullptr, false};
  altstack_probe outer_probe =
    {outer, outer_context, inner.context, &inner_probe, false};
  uintptr_t original_sp = read_sp ();
  uintptr_t original_x18 = read_x18 ();
  run_on_altstack (outer.context, probe_altstack, &outer_probe);

  check (read_sp () == original_sp, "outer alternate stack did not restore SP");
  check (read_x18 () == original_x18, "alternate stack changed reserved x18");
  check (outer_probe.entered && inner_probe.entered,
	 "nested alternate stack handler did not run");
  check (outer_context->mask
	 == (outer_source.mask ^ UINT64_C (0x55aa55aa55aa55aa)),
	 "outer context changes were not retained");
  check (inner_context->mask
	 == (inner_source.mask ^ UINT64_C (0x55aa55aa55aa55aa)),
	 "inner context changes were not retained");
  check (outer_context->pc == outer_source.pc
	 && inner_context->pc == inner_source.pc,
	 "alternate stack changed unrelated context state");
}

struct context_model
{
  uint64_t x[31] = {};
  uint64_t sp = 0;
  uint64_t pc = 0;
  uint64_t lr = 0;
};

static void
make_context_model (context_model &context, void *stack, size_t stack_size,
		    uintptr_t function, uintptr_t trampoline,
		    context_model *link, const uintptr_t *args, int argc)
{
  constexpr int register_arg_count = 8;
  size_t stack_arg_count = argc > register_arg_count
			   ? argc - register_arg_count : 0;
  size_t stack_arg_size
    = (stack_arg_count * sizeof (uintptr_t) + 15) & ~(size_t) 15;
  uintptr_t stack_top = ((uintptr_t) stack + stack_size) & ~(uintptr_t) 15;
  uintptr_t *uclink = (uintptr_t *) (stack_top - 16);
  uintptr_t *sp = (uintptr_t *) ((uintptr_t) uclink - stack_arg_size);

  *uclink = (uintptr_t) link;
  for (int i = 0; i < argc; ++i)
    if (i < register_arg_count)
      context.x[i] = args[i];
    else
      sp[i - register_arg_count] = args[i];

  context.pc = function;
  context.sp = (uintptr_t) sp;
  context.x[19] = (uintptr_t) uclink;
  context.lr = trampoline;
}

static context_model *
continue_context_model (const context_model &context)
{
  return *(context_model **) context.x[19];
}

static void
check_context_case (int argc)
{
  alignas (16) unsigned char stack[32768];
  memset (stack, 0xa5, sizeof stack);
  uintptr_t args[20];
  for (int i = 0; i < 20; ++i)
    args[i] = UINT64_C (0x1234567800000000) + (uint32_t) i;
  args[0] = UINT64_C (0xffffffffffffffff);
  args[7] = UINT64_C (0x00000000ffffffff);
  args[8] = UINT64_C (0x8765432112345678);

  context_model link;
  context_model context;
  uintptr_t function = UINT64_C (0x0000000180010000);
  uintptr_t trampoline = UINT64_C (0x0000000180020000);
  make_context_model (context, stack + 3, sizeof stack - 3,
		      function, trampoline, &link, args, argc);

  check ((context.sp & 15) == 0, "makecontext SP is not aligned");
  check ((context.x[19] & 15) == 0, "uc_link slot is not aligned");
  check (context.pc == function, "target PC is incorrect");
  check (context.lr == trampoline, "continuation LR is incorrect");
  check (continue_context_model (context) == &link,
	 "continuation did not recover uc_link");

  int register_args = argc < 8 ? argc : 8;
  for (int i = 0; i < register_args; ++i)
    check (context.x[i] == args[i], "register argument width/order is wrong");
  for (int i = 8; i < argc; ++i)
    check (((uintptr_t *) context.sp)[i - 8] == args[i],
	   "stack argument width/order is wrong");

  size_t stack_arg_count = argc > 8 ? argc - 8 : 0;
  size_t expected_stack_size
    = (stack_arg_count * sizeof (uintptr_t) + 15) & ~(size_t) 15;
  check (context.x[19] - context.sp == expected_stack_size,
	 "stack argument area has the wrong size");
}

static void
check_makecontext_layout ()
{
  check_context_case (0);
  check_context_case (8);
  check_context_case (9);
  check_context_case (12);
  check_context_case (15);
  check_context_case (20);

  alignas (16) unsigned char first_stack[32768];
  alignas (16) unsigned char second_stack[32768];
  context_model second;
  context_model first;
  make_context_model (second, second_stack, sizeof second_stack, 2, 20,
		      nullptr, nullptr, 0);
  make_context_model (first, first_stack, sizeof first_stack, 1, 10,
		      &second, nullptr, 0);
  check (continue_context_model (first) == &second,
	 "nested context did not continue to uc_link");
  check (continue_context_model (second) == nullptr,
	 "null uc_link did not select process exit");
}

int
main ()
{
  static_assert (sizeof (uintptr_t) == 8);
  static_assert (sizeof (void *) == 8);
  check_altstack_switch ();
  check_makecontext_layout ();
  return 0;
}
