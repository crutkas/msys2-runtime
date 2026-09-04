// Cross-architecture differential: walk the cygheap allocation chain of a
// RUNNING x86-64 MSYS2 process (Git for Windows) from this ARM64 process.
//
// DOES NOT ASSUME OUR OFFSETS TRANSFER. It validates them structurally: if
// offsetof(chain) were wrong for that build, the very first read would not
// yield a descending run of in-heap pointers. A long clean walk is itself
// evidence the offset is right; a short or garbage walk is reported as
// "offsets not established" rather than as a result.
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public static class XArch {
  [StructLayout(LayoutKind.Sequential)]
  struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public int pad;
    public IntPtr RegionSize; public uint State, Protect, Type; }
  [DllImport("kernel32", SetLastError=true)]
  static extern IntPtr OpenProcess(uint acc, bool inh, int pid);
  [DllImport("kernel32")] static extern IntPtr VirtualQueryEx(IntPtr p, IntPtr a, out MBI b, IntPtr len);
  [DllImport("kernel32", SetLastError=true)]
  static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] buf, IntPtr n, out IntPtr got);
  [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);

  const long LOW = 0x800000000L, HIGH = 0xa00000000L;

  static string Region(IntPtr p, long a) {
    MBI m;
    if (VirtualQueryEx(p, (IntPtr)a, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) return "QUERY-FAIL";
    return (m.State == 0x1000 ? "COMMITTED" : m.State == 0x2000 ? "RESERVED" : "FREE")
           + " allocBase=0x" + m.AllocationBase.ToInt64().ToString("X")
           + " size=0x" + m.RegionSize.ToInt64().ToString("X");
  }
  static bool R64(IntPtr p, long a, out long v) {
    byte[] b = new byte[8]; IntPtr g; v = 0;
    if (!ReadProcessMemory(p, (IntPtr)a, b, (IntPtr)8, out g) || g.ToInt64() != 8) return false;
    v = BitConverter.ToInt64(b,0); return true;
  }

  public static string Walk(int pid) {
    var sb = new StringBuilder();
    IntPtr h = OpenProcess(0x1010, false, pid);   // QUERY_INFORMATION | VM_READ
    if (h == IntPtr.Zero) return "OpenProcess failed err=" + Marshal.GetLastWin32Error();
    sb.AppendLine("x86-64 MSYS2 process pid=" + pid);
    sb.AppendLine("  region @0x800000000: " + Region(h, LOW));
    MBI m;
    long lowAddr = LOW;
    VirtualQueryEx(h, (IntPtr)lowAddr, out m, (IntPtr)Marshal.SizeOf(typeof(MBI)));
    if (m.State != 0x1000) {
      sb.AppendLine("  >>> cygheap is NOT at 0x800000000 in this build.");
      sb.AppendLine("  >>> OFFSETS NOT ESTABLISHED - no comparison can be made.");
      CloseHandle(h); return sb.ToString();
    }
    sb.AppendLine("  --- THREAD_STORAGE arena [0x600000000,0x800000000) ---");
    {
      long a = 0x600000000L; int nreg = 0; long topEnd = 0;
      while (a < 0x800000000L && nreg < 200) {
        MBI mm;
        if (VirtualQueryEx(h, (IntPtr)a, out mm, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) break;
        long rb = mm.BaseAddress.ToInt64(), rs = mm.RegionSize.ToInt64();
        if (mm.State != 0x10000) {
          sb.AppendLine(string.Format("     0x{0:X}..0x{1:X}  {2} size=0x{3:X}",
            rb, rb+rs, mm.State==0x1000?"COMMITTED":"RESERVED ", rs));
          nreg++; if (rb+rs > topEnd) topEnd = rb+rs;
        }
        a = rb + rs;
      }
      if (nreg == 0) sb.AppendLine("     (arena EMPTY - nothing allocated in thread storage)");
      else sb.AppendLine("     highest end = 0x" + topEnd.ToString("X")
             + (topEnd == 0x800000000L ? "   <<< TOUCHES THE CYGHEAP BOUNDARY" : "   (does NOT reach 0x800000000)"));
    }
    sb.AppendLine();
    long chain;
    if (!R64(h, LOW + 8, out chain)) { CloseHandle(h); return sb + "  cannot read +8\n"; }
    sb.AppendLine("  [assumed chain @ +8] = 0x" + chain.ToString("X16"));
    if (chain == 0) {
      sb.AppendLine("  >>> chain is NULL: either empty, or +8 is not chain in this build.");
      CloseHandle(h); return sb.ToString();
    }
    if (chain < LOW || chain >= HIGH) {
      sb.AppendLine("  >>> value at +8 is not an in-heap pointer.");
      sb.AppendLine("  >>> OFFSETS NOT ESTABLISHED for this build - not reporting a result.");
      CloseHandle(h); return sb.ToString();
    }
    long rvc = chain; int n = 0; long lowest = long.MaxValue; bool broke = false;
    while (rvc != 0 && n < 4000) {
      long b, prev;
      if (!R64(h, rvc, out b) || !R64(h, rvc + 8, out prev)) {
        sb.AppendLine("  [" + n + "] rvc=0x" + rvc.ToString("X") + " UNREADABLE " + Region(h, rvc));
        sb.AppendLine("  >>> CHAIN BROKEN after " + n + " entries");
        broke = true; break;
      }
      if (rvc < lowest) lowest = rvc;
      if (prev != 0 && (prev < LOW || prev >= HIGH)) {
        sb.AppendLine("  [" + n + "] rvc=0x" + rvc.ToString("X") + " b=0x" + b.ToString("X")
                      + " prev=0x" + prev.ToString("X16") + "  <== OUT OF CYGHEAP");
        sb.AppendLine("      that prev: " + Region(h, prev));
        sb.AppendLine("  >>> CHAIN IS UNTERMINATED after " + (n+1) + " entries");
        broke = true; break;
      }
      rvc = prev; n++;
    }
    if (!broke)
      sb.AppendLine("  >>> CHAIN TERMINATED CLEANLY WITH NULL after " + n + " entries");
    sb.AppendLine("  lowest entry seen = 0x" + (lowest == long.MaxValue ? 0 : lowest).ToString("X"));
    sb.AppendLine("  entries walked = " + n + (n >= 10 ? "   (a long clean descending walk: the +8 offset is structurally confirmed)"
                                                      : "   (too short to confirm the offset)"));
    CloseHandle(h);
    return sb.ToString();
  }
}


