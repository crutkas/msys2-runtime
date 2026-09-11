/* cpuid.h: Define cpuid instruction

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#ifndef CPUID_H
#define CPUID_H

#ifdef __x86_64__
static inline void __attribute ((always_inline))
cpuid (uint32_t *a, uint32_t *b, uint32_t *c, uint32_t *d, uint32_t ain,
       uint32_t cin = 0)
{
  asm volatile ("cpuid"
		: "=a" (*a), "=b" (*b), "=c" (*c), "=d" (*d)
		: "a" (ain), "c" (cin));
}

static inline bool __attribute ((always_inline))
can_set_flag (uint32_t long flag)
{
  uint32_t long r1, r2;

  asm volatile ("pushfq\n"
		"popq %0\n"
		"movq %0, %1\n"
		"xorq %2, %0\n"
		"pushq %0\n"
		"popfq\n"
		"pushfq\n"
		"popq %0\n"
		"pushq %1\n"
		"popfq\n"
		: "=&r" (r1), "=&r" (r2)
		: "ir" (flag)
  );
  return ((r1 ^ r2) & flag) != 0;
}
#elif defined (__aarch64__)
/* AArch64 has neither a CPUID instruction nor an EFLAGS register, so
   neither of these x86 primitives has an ARM64 analogue.  Feature and
   topology discovery on Windows ARM64 goes through
   IsProcessorFeaturePresent() and the ID_AA64* system registers instead.

   These are deliberately NON-FUNCTIONAL stubs.  They exist only so that
   the x86-oriented callers in fhandler/proc.cc and sysconf.cc keep
   compiling; they report nothing.  Consequently /proc/cpuinfo and the
   sysconf() CPU cache/topology queries return no CPU detail on ARM64.
   Porting those callers is separate, still-unfinished work and must not
   be mistaken for a working implementation. */
static inline void __attribute ((always_inline))
cpuid (uint32_t *a, uint32_t *b, uint32_t *c, uint32_t *d, uint32_t ain,
       uint32_t cin = 0)
{
  (void) ain;
  (void) cin;
  *a = *b = *c = *d = 0;
}

static inline bool __attribute ((always_inline))
can_set_flag (uint32_t flag)
{
  (void) flag;
  return false;
}
#else
#error unimplemented for this target
#endif

#endif // !CPUID_H
