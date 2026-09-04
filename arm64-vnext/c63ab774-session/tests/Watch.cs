// Hardware watchpoint on cygheap+8 (the chain head), to catch the writer
// directly instead of searching for it.
//
// ARM64 CONTEXT (912 bytes): X[0..30] @0x008, Sp @0x100, Pc @0x108,
//   V[32] @0x110, Fpcr @0x310, Fpsr @0x314, Bcr[8] @0x318, Bvr[8] @0x338,
//   Wcr[2] @0x378, Wvr[2] @0x380.
// DBGWCR: E bit0 | PAC bits2:1 (0b10 = EL0) | LSC bits4:3 (0b10 = store)
//         | BAS bits12:5 (0xFF = all 8 bytes)  => 1|0x4|0x10|0x1FE0 = 0x1FF5
//
// HONEST FAILURE MODE: if SetThreadContext will not take the debug registers,
// or no watchpoint exception ever arrives, this reports that plainly rather
// than producing a result.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Watch {
  [StructLayout(LayoutKind.Sequential)]
  struct STARTUPINFO { public int cb; public IntPtr r1,r2,r3;
    public int dwX,dwY,dwXSize,dwYSize,dwXCount,dwYCount,dwFillAttribute,dwFlags;
    public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
  [StructLayout(LayoutKind.Sequential)]
  struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
  [StructLayout(LayoutKind.Sequential)]
  struct MBI { public IntPtr BaseAddress, AllocationBase; public uint AllocationProtect; public int pad;
    public IntPtr RegionSize; public uint State, Protect, Type; }

  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inh,
    uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32")] static extern bool WaitForDebugEvent(byte[] ev, uint ms);
  [DllImport("kernel32")] static extern bool ContinueDebugEvent(int pid, int tid, uint status);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenThread(uint acc, bool inh, int tid);
  [DllImport("kernel32", SetLastError=true)] static extern bool GetThreadContext(IntPtr t, IntPtr ctx);
  [DllImport("kernel32", SetLastError=true)] static extern bool SetThreadContext(IntPtr t, IntPtr ctx);
  [DllImport("kernel32")] static extern IntPtr VirtualQueryEx(IntPtr p, IntPtr a, out MBI b, IntPtr len);
  [DllImport("kernel32", SetLastError=true)]
  static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] buf, IntPtr n, out IntPtr got);
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern uint GetModuleFileNameExW(IntPtr p, IntPtr m, StringBuilder n, uint sz);
  [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32")] static extern bool TerminateProcess(IntPtr h, uint c);

  const long CHAIN = 0x800000008L, LOW = 0x800000000L, HIGH = 0xa00000000L;
  const int CTXSZ = 912;
  const uint FLAGS_ALL   = 0x0040000F;  // ARM64|CONTROL|INTEGER|FP|DEBUG_REGISTERS
  const uint FLAGS_DEBUG = 0x00400008;  // ARM64|DEBUG_REGISTERS

  static IntPtr proc;
  static string Where(long a) {
    if (a == 0) return "(null)";
    MBI m;
    if (VirtualQueryEx(proc, (IntPtr)a, out m, (IntPtr)Marshal.SizeOf(typeof(MBI))) == IntPtr.Zero) return "UNMAPPED";
    var sb = new StringBuilder(260);
    string n = GetModuleFileNameExW(proc, m.AllocationBase, sb, 260) > 0
             ? System.IO.Path.GetFileName(sb.ToString()) : "(anon)";
    return string.Format("{0}+0x{1:X}", n, a - m.AllocationBase.ToInt64());
  }
  static bool R64(long a, out long v) {
    byte[] b = new byte[8]; IntPtr g; v = 0;
    if (!ReadProcessMemory(proc, (IntPtr)a, b, (IntPtr)8, out g) || g.ToInt64() != 8) return false;
    v = BitConverter.ToInt64(b,0); return true;
  }
  static IntPtr Ctx(IntPtr raw) {   // 16-byte align
    long v = raw.ToInt64(); return (IntPtr)((v + 15) & ~15L);
  }

  static bool Arm(int tid, StringBuilder log, IntPtr ctx) {
    return SetWp(tid, ctx, true, log);
  }

  // Arm or disarm the watchpoint, optionally toggling the AArch64 software
  // single-step bit (Cpsr bit 21, offset 0x004) so we can advance PAST the
  // watched store instead of re-faulting on it forever.
  static bool SetWp(int tid, IntPtr ctx, bool arm, StringBuilder log, bool step = false) {
    IntPtr th = OpenThread(0x001F03FF, false, tid);
    if (th == IntPtr.Zero) return false;
    for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
    Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS_ALL));
    if (!GetThreadContext(th, ctx)) { CloseHandle(th); return false; }
    Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS_ALL));
    Marshal.WriteInt32(ctx, 0x378, arm ? 0x1FF5 : 0);
    Marshal.WriteInt64(ctx, 0x380, arm ? CHAIN : 0);
    int cpsr = Marshal.ReadInt32(ctx, 0x004);
    cpsr = step ? (cpsr | (1 << 21)) : (cpsr & ~(1 << 21));
    Marshal.WriteInt32(ctx, 0x004, cpsr);
    bool ok = SetThreadContext(th, ctx);
    if (log != null) {
      for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
      Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS_ALL));
      if (GetThreadContext(th, ctx)) {
        int wcr = Marshal.ReadInt32(ctx, 0x378);
        long wvr = Marshal.ReadInt64(ctx, 0x380);
        log.AppendLine(string.Format("  armed tid={0}: readback Wcr[0]=0x{1:X} Wvr[0]=0x{2:X}{3}",
          tid, wcr, wvr, (wcr == 0 || wvr != CHAIN) ? "   <<< PLATFORM DID NOT KEEP IT" : "   OK"));
        if (wcr == 0 || wvr != CHAIN) ok = false;
      }
    }
    CloseHandle(th);
    return ok;
  }

  static bool ArmQuiet(int tid, IntPtr ctx) { return SetWp(tid, ctx, true, null); }

  // Disarm the watchpoint and place a hardware breakpoint on the next
  // instruction, so resumption is guaranteed to trap and we can re-arm.
  static bool DisarmAndBreakAt(int tid, IntPtr ctx, long nextPc) {
    IntPtr th = OpenThread(0x001F03FF, false, tid);
    if (th == IntPtr.Zero) return false;
    for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
    Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS_ALL));
    if (!GetThreadContext(th, ctx)) { CloseHandle(th); return false; }
    Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS_ALL));
    Marshal.WriteInt32(ctx, 0x378, 0);            // Wcr[0] off
    Marshal.WriteInt64(ctx, 0x380, 0);            // Wvr[0]
    Marshal.WriteInt32(ctx, 0x318, 0x1E5);        // Bcr[0] on
    Marshal.WriteInt64(ctx, 0x338, nextPc);       // Bvr[0]
    bool ok = SetThreadContext(th, ctx);
    CloseHandle(th);
    return ok;
  }
  static bool ClearBreakAndArm(int tid, IntPtr ctx) {
    IntPtr th = OpenThread(0x001F03FF, false, tid);
    if (th == IntPtr.Zero) return false;
    for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
    Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS_ALL));
    if (!GetThreadContext(th, ctx)) { CloseHandle(th); return false; }
    Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS_ALL));
    Marshal.WriteInt32(ctx, 0x318, 0);            // Bcr[0] off
    Marshal.WriteInt64(ctx, 0x338, 0);
    Marshal.WriteInt32(ctx, 0x378, 0x1FF5);       // Wcr[0] back on
    Marshal.WriteInt64(ctx, 0x380, CHAIN);
    bool ok = SetThreadContext(th, ctx);
    CloseHandle(th);
    return ok;
  }
  static bool DisarmAndStep(int tid, IntPtr ctx) { return SetWp(tid, ctx, false, null, true); }

  public static string Run(string exe, string cwd) {
    var sb = new StringBuilder();
    var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si);
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(exe, null, IntPtr.Zero, IntPtr.Zero, false, 1, IntPtr.Zero, cwd, ref si, out pi))
      return "CreateProcess failed err=" + Marshal.GetLastWin32Error();
    proc = pi.hProcess;
    int rootPid = pi.dwProcessId;
    IntPtr rawCtx = Marshal.AllocHGlobal(CTXSZ + 32);
    IntPtr ctx = Ctx(rawCtx);
    byte[] ev = new byte[256];
    bool armed = false; int hits = 0; bool everFired = false;
    var stepTids = new HashSet<int>();
    var threads = new List<int>();

    while (WaitForDebugEvent(ev, 30000)) {
      int code = BitConverter.ToInt32(ev,0), pid = BitConverter.ToInt32(ev,4), tid = BitConverter.ToInt32(ev,8);
      uint cont = 0x00010002;
      if (code == 6) { long db = BitConverter.ToInt64(ev,24); var nb = new StringBuilder(260);
         string dn = GetModuleFileNameExW(proc,(IntPtr)db,nb,260) > 0 ? System.IO.Path.GetFileName(nb.ToString()) : "?";
         sb.AppendLine("   [DLL] base=0x" + db.ToString("X") + "  " + dn); }
      if (armed) sb.AppendLine("   [ev] code=" + code + " tid=" + tid + (code==1 ? " ec=0x" + BitConverter.ToUInt32(ev,16).ToString("X8") + (BitConverter.ToInt32(ev,168)!=0?" first":" second") : "") + (stepTids.Contains(tid) ? " (mid-advance)" : ""));
      if (armed && !stepTids.Contains(tid)) { if (!ArmQuiet(tid, ctx)) sb.AppendLine("   [ev] RE-ARM FAILED tid=" + tid); }

      if (code == 3) { threads.Add(tid); }        // CREATE_PROCESS
      else if (code == 2) { threads.Add(tid); /* deliberately NOT arming new threads */ }
      else if (code == 1) {
        uint ec = BitConverter.ToUInt32(ev,16);
        long addr = BitConverter.ToInt64(ev,32);
        bool first = BitConverter.ToInt32(ev,168) != 0;

        if (ec == 0x80000003 && !armed) {
          // initial loader breakpoint: earliest reliable point to arm.
          sb.AppendLine("initial breakpoint - arming write-watchpoint on 0x" + CHAIN.ToString("X"));
          armed = Arm(tid, sb, ctx);
          if (!armed) {
            sb.AppendLine(">>> COULD NOT ARM A HARDWARE WATCHPOINT ON THIS PLATFORM.");
            sb.AppendLine(">>> Reporting that rather than a result. Use the polling bisect instead.");
            TerminateProcess(pi.hProcess, 1);
            break;
          }
        }
        else if (ec == 0x80000004 || ec == 0x4000001E || ec == 0x80000003) {
          everFired = true;
          if (stepTids.Contains(tid)) {
            // we just advanced one instruction past the watched store; re-arm
            stepTids.Remove(tid);
            if (!ClearBreakAndArm(tid, ctx)) sb.AppendLine("   [ev] ClearBreakAndArm FAILED");
            cont = 0x00010002;
          } else {
            hits++;
            for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
            Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS_ALL));
            IntPtr th = OpenThread(0x001F03FF, false, tid);
            long pc = 0, lr = 0;
            if (th != IntPtr.Zero && GetThreadContext(th, ctx)) {
              pc = Marshal.ReadInt64(ctx, 0x108);
              lr = Marshal.ReadInt64(ctx, 0x008 + 30*8);
              CloseHandle(th);
            }
            long val; bool ok = R64(CHAIN, out val);
            bool wild = ok && val != 0 && (val < LOW || val >= HIGH);
            bool known = (Where(pc).EndsWith("+0xA9000"));
            if (wild || !known || hits <= 400)
              sb.AppendLine(string.Format("[{0,4}] chain=0x{1:X16} {2} PC={3} LR={4}",
                hits, ok ? val : -1, wild ? " *** WILD ***" : "", Where(pc), Where(lr)));
            if (wild) {
              sb.AppendLine();
              sb.AppendLine(">>> WRITER FOUND");
              sb.AppendLine(">>>   PC = 0x" + pc.ToString("X16") + "   " + Where(pc));
              sb.AppendLine(">>>   LR = 0x" + lr.ToString("X16") + "   " + Where(lr));
              TerminateProcess(pi.hProcess, 1); break;
            }
            if (hits > 20000) { sb.AppendLine("(20000 hits, stopping)"); TerminateProcess(pi.hProcess,1); break; }
            // disarm + single-step so the store can complete and we move on
            bool st = DisarmAndBreakAt(tid, ctx, pc + 4); if (st) stepTids.Add(tid); else sb.AppendLine("   [ev] DisarmAndBreakAt FAILED err=" + Marshal.GetLastWin32Error());
            if (!st) {
              sb.AppendLine(">>> could not set single-step; cannot advance past the store.");
              TerminateProcess(pi.hProcess, 1); break;
            }
            cont = 0x00010002;
          }
        }
        else if (!first) { sb.AppendLine("unhandled 0x" + ec.ToString("X8") + " at " + Where(addr)); cont = 0x00010002; }
        else cont = 0x80010001;
      }
      else if (code == 5 && pid == rootPid) {
        sb.AppendLine("process exited, code=" + BitConverter.ToUInt32(ev,16));
        ContinueDebugEvent(pid, tid, cont); break;
      }
      ContinueDebugEvent(pid, tid, cont);
    }
    if (armed && !everFired)
      sb.AppendLine(">>> WATCHPOINT ARMED AND VERIFIED BUT NEVER FIRED. Inconclusive - "
                    + "the platform may accept the registers without honouring them.");
    Marshal.FreeHGlobal(rawCtx);
    return sb.ToString();
  }
}











