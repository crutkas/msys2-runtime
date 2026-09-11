/* signal-frame-arm64.h

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

/* Saved by the AArch64 sigdelayed entry in scripts/gendef. */
#pragma once

struct alignas (16) arm64_signal_frame
{
  uint64_t x0_x17[18];
  uint64_t x19_x28[10];
  uint64_t nzcv;
  uint64_t fpcr;
  decltype (CONTEXT::V) v;
  uint64_t fp;
  uint64_t lr;
  uint64_t platform;
  uint64_t fpsr;
};

static_assert (sizeof (arm64_signal_frame) == 784);
static_assert (offsetof (arm64_signal_frame, nzcv) == 224);
static_assert (offsetof (arm64_signal_frame, v) == 240);
static_assert (offsetof (arm64_signal_frame, fp) == 752);
static_assert (offsetof (arm64_signal_frame, platform) == 768);
static_assert (offsetof (arm64_signal_frame, fpsr) == 776);

static inline void
arm64_signal_context (CONTEXT &ctx, const arm64_signal_frame &frame,
		      uintptr_t pc)
{
  /* Older w32api headers omit floating-point state from CONTEXT_FULL. */
  ctx.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_FLOATING_POINT;
  ctx.Cpsr = frame.nzcv;
  for (unsigned i = 0; i < 18; ++i)
    ctx.X[i] = frame.x0_x17[i];
  ctx.X[18] = frame.platform;
  for (unsigned i = 0; i < 10; ++i)
    ctx.X[19 + i] = frame.x19_x28[i];
  ctx.Fp = frame.fp;
  ctx.Lr = frame.lr;
  ctx.Sp = reinterpret_cast<uintptr_t> (&frame + 1);
  ctx.Pc = pc;
  for (unsigned i = 0; i < 32; ++i)
    ctx.V[i] = frame.v[i];
  ctx.Fpcr = frame.fpcr;
  ctx.Fpsr = frame.fpsr;
}
