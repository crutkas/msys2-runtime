// DECISIVE EMPIRICAL TEST, all logic inside C# to avoid PowerShell type coercion.
// Question: on Windows on Arm, does the TEB live in x18 or in tpidr_el0?
using System;
using System.Runtime.InteropServices;

public static class TebProbe {
  [DllImport("kernel32")] static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr sz, uint t, uint p);
  [DllImport("kernel32")] static extern bool VirtualProtect(IntPtr a, UIntPtr sz, uint p, out uint o);
  [DllImport("kernel32")] static extern bool FlushInstructionCache(IntPtr h, IntPtr a, UIntPtr sz);
  [DllImport("kernel32")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32")] static extern void GetCurrentThreadStackLimits(out IntPtr low, out IntPtr high);

  delegate IntPtr Thunk();

  static IntPtr Run(uint[] insns) {
    int n = insns.Length * 4;
    IntPtr m = VirtualAlloc(IntPtr.Zero, (UIntPtr)n, 0x3000, 0x04);
    byte[] b = new byte[n];
    Buffer.BlockCopy(insns, 0, b, 0, n);
    Marshal.Copy(b, 0, m, n);
    uint old;
    VirtualProtect(m, (UIntPtr)n, 0x20, out old);
    FlushInstructionCache(GetCurrentProcess(), m, (UIntPtr)n);
    Thunk t = (Thunk)Marshal.GetDelegateForFunctionPointer(m, typeof(Thunk));
    return t();
  }

  public static string Go() {
    string s = "";
    const uint MRS_TPIDR = 0xD53BD040u;  // mrs x0, tpidr_el0
    const uint MOV_X18   = 0xAA1203E0u;  // mov x0, x18   (orr x0, xzr, x18)
    const uint RET       = 0xD65F03C0u;  // ret

    IntPtr tpidr = IntPtr.Zero, x18 = IntPtr.Zero;
    string terr = null, xerr = null;
    try { tpidr = Run(new uint[]{ MRS_TPIDR, RET }); } catch (Exception e) { terr = e.GetType().Name; }
    try { x18   = Run(new uint[]{ MOV_X18,   RET }); } catch (Exception e) { xerr = e.GetType().Name; }

    s += "mrs x0, tpidr_el0 -> " + (terr ?? ("0x" + tpidr.ToInt64().ToString("X16"))) + "\n";
    s += "mov x0, x18       -> " + (xerr ?? ("0x" + x18.ToInt64().ToString("X16"))) + "\n";

    IntPtr lo, hi;
    GetCurrentThreadStackLimits(out lo, out hi);
    s += "GetCurrentThreadStackLimits: low=0x" + lo.ToInt64().ToString("X16")
       + " high=0x" + hi.ToInt64().ToString("X16") + "\n\n";

    // NT_TIB: +0x08 StackBase (== high), +0x10 StackLimit (== low)
    s += "--- interpret x18 as TEB ---\n";
    if (x18 != IntPtr.Zero) {
      long sb = Marshal.ReadInt64(x18, 8);
      long sl = Marshal.ReadInt64(x18, 16);
      s += "  [x18+0x08] StackBase  = 0x" + sb.ToString("X16")
         + (sb == hi.ToInt64() ? "   MATCHES stack high  <<<" : "   (no match)") + "\n";
      s += "  [x18+0x10] StackLimit = 0x" + sl.ToString("X16")
         + (sl == lo.ToInt64() ? "   MATCHES stack low   <<<" : "   (no match)") + "\n";
    } else s += "  x18 is ZERO\n";

    s += "\n--- interpret tpidr_el0 as TEB ---\n";
    if (tpidr != IntPtr.Zero) {
      try {
        long sb = Marshal.ReadInt64(tpidr, 8);
        s += "  [tpidr+0x08] = 0x" + sb.ToString("X16")
           + (sb == hi.ToInt64() ? "   MATCHES stack high" : "   (no match)") + "\n";
      } catch (Exception e) { s += "  dereference FAILED: " + e.GetType().Name + "\n"; }
    } else {
      s += "  tpidr_el0 is ZERO -> `ldr xN,[xN,#8]` would READ ADDRESS 0x8\n";
      s += "  which is EXACTLY the captured fault: AV READ target 0x0000000000000008\n";
    }

    s += "\nVERDICT: ";
    if (x18 != IntPtr.Zero && Marshal.ReadInt64(x18, 8) == hi.ToInt64()) {
      s += "x18 IS the TEB on this machine";
      s += (tpidr == IntPtr.Zero) ? " and tpidr_el0 is ZERO.\n" : " ; tpidr_el0 is non-zero but is NOT the TEB.\n";
    } else s += "inconclusive - inspect values above.\n";
    return s;
  }
}
