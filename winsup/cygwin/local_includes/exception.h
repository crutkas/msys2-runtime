/* exception.h

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#pragma once

#define exception_list void
#ifdef __x86_64__
typedef struct _DISPATCHER_CONTEXT *PDISPATCHER_CONTEXT;
#elif defined (__aarch64__)
/* w32api (v12.0.0) already provides
     typedef struct _DISPATCHER_CONTEXT *PDISPATCHER_CONTEXT;
   for ARM64 too, so redeclaring it here would conflict.  Note the struct is
   plain _DISPATCHER_CONTEXT on every architecture -- there is no
   _DISPATCHER_CONTEXT_ARM64 -- hence the mangled handler name below uses
   P19_DISPATCHER_CONTEXT, identical to x86_64. */
#else
#error unimplemented for this target
#endif

class exception
{
  static EXCEPTION_DISPOSITION myfault (EXCEPTION_RECORD *, exception_list *,
					CONTEXT *, PDISPATCHER_CONTEXT);
  static EXCEPTION_DISPOSITION handle (EXCEPTION_RECORD *, exception_list *,
				       CONTEXT *, PDISPATCHER_CONTEXT);
public:
  exception () __attribute__ ((always_inline))
  {
    /* Install SEH handler.  The .seh_handler directive needs the mangled
       name of exception::handle, which embeds its parameter type and so
       differs between targets (verified with llvm-nm). */
#ifdef __x86_64__
    asm volatile ("\n"
      "  1:								\n"
      "    .seh_handler _ZN9exception6handleEP17_EXCEPTION_RECORDPvP8_CONTEXT"
      "P19_DISPATCHER_CONTEXT, @except					\n"
      "    .seh_handlerdata						\n"
      "    .long 1							\n"
      "    .rva 1b, 2f, 2f, 2f					\n"
      "    .seh_code							\n");
#else
    asm volatile ("\n"
      "  1:								\n"
      "    .seh_handler _ZN9exception6handleEP17_EXCEPTION_RECORDPvP8_CONTEXT"
      "P19_DISPATCHER_CONTEXT, @except				\n"
      "    .seh_handlerdata						\n"
      "    .long 1							\n"
      /* The AArch64 assembler accepts named symbols but not numeric local
	 labels (1b/2f) as .rva operands, so alias them first.  %= keeps
	 the alias names unique per instantiation, and 2f still resolves
	 to this object's matching destructor label exactly as before. */
      "    .set Lcygseh%=_beg, 1b					\n"
      "    .set Lcygseh%=_end, 2f					\n"
      "    .rva Lcygseh%=_beg, Lcygseh%=_end, Lcygseh%=_end, Lcygseh%=_end \n"
      "    .text							\n"
      /* A clobber list makes this extended asm, which is required for %=
	 to be substituted; basic asm does no operand substitution. */
      ::: "memory");
#endif
  };
  ~exception () __attribute__ ((always_inline))
  {
    asm volatile ("\n\
      nop								\n\
    2:									\n\
      nop								\n");
  }
};

LONG CALLBACK myfault_altstack_handler (EXCEPTION_POINTERS *);

class cygwin_exception
{
  PUINT_PTR framep;
  PCONTEXT ctx;
  EXCEPTION_RECORD *e;
  HANDLE h;
  void dump_exception ();
  void open_stackdumpfile ();
public:
  cygwin_exception (PUINT_PTR in_framep, PCONTEXT in_ctx = NULL, EXCEPTION_RECORD *in_e = NULL):
    framep (in_framep), ctx (in_ctx), e (in_e), h (NULL) {}
  void dumpstack ();
  PCONTEXT context () const {return ctx;}
  EXCEPTION_RECORD *exception_record () const {return e;}
};
