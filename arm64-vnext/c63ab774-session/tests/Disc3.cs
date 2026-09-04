// (a)/(b) DISCRIMINATOR by READ-AT-KNOWN-POINTS.
//
// At msys-2.0.dll RVA 0xA8FF8 the instruction is:
//     str x0, [x5, #8]        ; rvc->prev = cygheap->chain
// so at that PC:  x5 = the entry being born, x0 = the value about to become
// its prev. Reading registers at a CODE breakpoint answers the question
// directly and never tries to capture a write, so it is immune to the
// DLL-load limitation that defeated the data watchpoint.
//
//   entry 0x8000068F0 with x0 WILD        -> (a) head already wild at birth
//   entry 0x8000068F0 with x0 = 0x68C0    -> (b) slot overwritten after birth
//
// Uses Bcr[0]/Bvr[0] for the probe and Bcr[1]/Bvr[1] for the PC+4 advance,
// so the two never contend.
//   Bcr[0]@0x318  Bcr[1]@0x31C   Bvr[0]@0x338  Bvr[1]@0x340
//   DBGBCR = E|PAC(EL0)|BAS(0xF) = 1|0x4|0x1E0 = 0x1E5
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class Disc3 {
  [StructLayout(LayoutKind.Sequential)]
  struct STARTUPINFO { public int cb; public IntPtr r1,r2,r3;
    public int dwX,dwY,dwXSize,dwYSize,dwXCount,dwYCount,dwFillAttribute,dwFlags;
    public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
  [StructLayout(LayoutKind.Sequential)]
  struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

  [DllImport("kernel32", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta, bool inh,
    uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32")] static extern bool WaitForDebugEvent(byte[] ev, uint ms);
  [DllImport("kernel32")] static extern bool ContinueDebugEvent(int pid, int tid, uint status);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr OpenThread(uint a, bool i, int t);
  [DllImport("kernel32", SetLastError=true)] static extern bool GetThreadContext(IntPtr t, IntPtr c);
  [DllImport("kernel32", SetLastError=true)] static extern bool SetThreadContext(IntPtr t, IntPtr c);
  [DllImport("kernel32", SetLastError=true)]
  static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, IntPtr n, out IntPtr g);
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern bool EnumProcessModulesEx(IntPtr p, [Out] IntPtr[] m, uint cb, out uint need, uint f);
  [DllImport("psapi", CharSet=CharSet.Unicode)]
  static extern uint GetModuleBaseNameW(IntPtr p, IntPtr m, StringBuilder n, uint sz);
  [DllImport("kernel32")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32")] static extern bool TerminateProcess(IntPtr h, uint c);

  const int CTXSZ = 912;
  const uint FLAGS = 0x0040000F;
  const long PREV_STORE_RVA = 0xA8FF8L;
  const long FETCH_RVA      = 0xA9F94L;   // cstrdup entry -- LR here IS the caller
  const long LOW = 0x800000000L, HIGH = 0xa00000000L;
  static IntPtr proc;

  static long fetchPc = 0;
  static bool sampling = false; static long lastChain = 0;
  static bool verified = false; static int vBcr2, vBcr0; static long vBvr2, vBvr0;
  static bool SetBps(int tid, IntPtr ctx, long probe, long advance) {
    IntPtr th = OpenThread(0x001F03FF, false, tid);
    if (th == IntPtr.Zero) return false;
    for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
    Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS));
    if (!GetThreadContext(th, ctx)) { CloseHandle(th); return false; }
    Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS));
    Marshal.WriteInt32(ctx, 0x318, probe   != 0 ? 0x1E5 : 0);
    Marshal.WriteInt64(ctx, 0x338, probe);
        Marshal.WriteInt32(ctx, 0x31C, advance != 0 ? 0x1E5 : 0);
    Marshal.WriteInt64(ctx, 0x340, advance);
    Marshal.WriteInt32(ctx, 0x320, fetchPc != 0 ? 0x1E5 : 0);   // Bcr[2]
    Marshal.WriteInt64(ctx, 0x348, fetchPc);                     // Bvr[2]
    bool ok = SetThreadContext(th, ctx);
    if (ok && fetchPc != 0 && !verified) {
      for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
      Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS));
      if (GetThreadContext(th, ctx)) {
        vBcr2 = Marshal.ReadInt32(ctx, 0x320);
        vBvr2 = Marshal.ReadInt64(ctx, 0x348);
        vBcr0 = Marshal.ReadInt32(ctx, 0x318);
        vBvr0 = Marshal.ReadInt64(ctx, 0x338);
        verified = true;
      }
    }
    CloseHandle(th);
    return ok;
  }

  public static string Run(string exe, string cwd) {
    var sb = new StringBuilder();
    var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(si);
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(exe, null, IntPtr.Zero, IntPtr.Zero, false, 1, IntPtr.Zero, cwd, ref si, out pi))
      return "CreateProcess failed";
    proc = pi.hProcess;
    int rootPid = pi.dwProcessId;
    IntPtr rawCtx = Marshal.AllocHGlobal(CTXSZ + 32);
    IntPtr ctx = (IntPtr)((rawCtx.ToInt64() + 15) & ~15L);
    byte[] ev = new byte[256];
    long probePc = 0; bool armed = false; int hits = 0;
    var advancing = new HashSet<int>();
    var seen = new List<int>();

    while (WaitForDebugEvent(ev, 30000)) {
      int code = BitConverter.ToInt32(ev,0), pid = BitConverter.ToInt32(ev,4), tid = BitConverter.ToInt32(ev,8);
      uint cont = 0x00010002;

      if (!seen.Contains(tid)) seen.Add(tid);

      if (sampling) {
        long cv = 0; byte[] sb8 = new byte[8]; IntPtr sg; long ca = 0x800000008L;
        if (ReadProcessMemory(proc,(IntPtr)ca,sb8,(IntPtr)8,out sg)) cv = BitConverter.ToInt64(sb8,0);
        if (cv != lastChain) {
          bool w = cv != 0 && (cv < LOW || cv >= HIGH);
          sb.AppendLine("   [sample] after ev code=" + code + " tid=" + tid
                        + "  cygheap+8 = 0x" + cv.ToString("X") + (w ? "   *** WILD - STORE HAPPENED IN THE PRECEDING INTERVAL ***" : ""));
          lastChain = cv;
          if (w) { TerminateProcess(pi.hProcess, 1); break; }
        } else {
          sb.AppendLine("   [sample] after ev code=" + code + " tid=" + tid + "  cygheap+8 unchanged");
        }
      }

      if (code == 6 || code == 2 || code == 3) {
        // (re)locate the DLL and arm as soon as it is present
        if (!armed) {
          IntPtr[] mods = new IntPtr[512]; uint need;
          if (EnumProcessModulesEx(proc, mods, (uint)(mods.Length*IntPtr.Size), out need, 3)) {
            int n = (int)(need / IntPtr.Size);
            for (int i = 0; i < n; i++) {
              var nm = new StringBuilder(260);
              if (GetModuleBaseNameW(proc, mods[i], nm, 260) > 0 &&
                  nm.ToString().ToLower().Contains("msys-2.0")) {
                probePc = mods[i].ToInt64() + PREV_STORE_RVA; fetchPc = mods[i].ToInt64() + FETCH_RVA;
                sb.AppendLine("probe PC = 0x" + probePc.ToString("X") + "  (RVA 0x" + PREV_STORE_RVA.ToString("X") + ")");
                armed = true; break;
              }
            }
          }
        }
        if (armed) foreach (int t in seen) if (!advancing.Contains(t)) SetBps(t, ctx, probePc, 0);
      }
      else if (code == 1) {
        uint ec = BitConverter.ToUInt32(ev,16);
        if (armed && ec == 0x80000003) {
          IntPtr th = OpenThread(0x001F03FF, false, tid);
          for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
          Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS));
          long pc = 0, x0 = 0, x5 = 0;
          if (th != IntPtr.Zero && GetThreadContext(th, ctx)) {
            pc = Marshal.ReadInt64(ctx, 0x108);
            x0 = Marshal.ReadInt64(ctx, 0x008 + 0*8);
            x5 = Marshal.ReadInt64(ctx, 0x008 + 5*8);
            CloseHandle(th);
          }
          if (pc == fetchPc && !advancing.Contains(tid)) {
            {
              long lr = 0, a0 = 0;
              IntPtr th3 = OpenThread(0x001F03FF, false, tid);
              if (th3 != IntPtr.Zero) {
                for (int i = 0; i < CTXSZ; i++) Marshal.WriteByte(ctx, i, 0);
                Marshal.WriteInt32(ctx, 0, unchecked((int)FLAGS));
                if (GetThreadContext(th3, ctx)) { lr = Marshal.ReadInt64(ctx, 0x008+30*8); a0 = Marshal.ReadInt64(ctx, 0x008); }
                CloseHandle(th3);
              }
              long imgBase = probePc - PREV_STORE_RVA;
              sb.AppendLine("   ---- cstrdup() called: caller LR = 0x" + lr.ToString("X")
                            + "  (RVA 0x" + (lr - imgBase).ToString("X") + ")  arg0=0x" + a0.ToString("X"));
            }
            if (SetBps(tid, ctx, 0, pc + 4)) advancing.Add(tid);
            ContinueDebugEvent(pid, tid, cont); continue;
          }
          if (advancing.Contains(tid)) {
            advancing.Remove(tid);
            SetBps(tid, ctx, probePc, 0);
          } else if (pc == probePc) {
            hits++;
            bool wild = x0 != 0 && (x0 < LOW || x0 >= HIGH);
            bool target = (x5 == 0x8000068F0L);
            sb.AppendLine(string.Format("[{0,3}] tid={1} entry(x5)=0x{2:X}  prev-to-store(x0)=0x{3:X}{4}{5}",
              hits, tid, x5, x0, wild ? "  *** WILD ***" : "", target ? "   <<<< THE TARGET ENTRY" : ""));
            if (x5 == 0x8000068C0L) { sampling = true; lastChain = 0x8000068C0L;
              sb.AppendLine("   >>> now sampling cygheap+8 at every debug event"); }
            if (target) {
              sb.AppendLine();
              sb.AppendLine(">>> VERDICT for entry 0x8000068F0:");
              if (wild) sb.AppendLine(">>>   x0 IS WILD AT BIRTH  =>  CASE (a): cygheap->chain was already"
                                    + " clobbered; _cmalloc faithfully copied it.");
              else if (x5 != 0) sb.AppendLine(">>>   x0 = 0x" + x0.ToString("X") + " (valid) AT BIRTH  =>  CASE (b):"
                                    + " the prev slot was overwritten AFTER birth.");
              TerminateProcess(pi.hProcess, 1);
              break;
            }
            if (hits > 2000) { sb.AppendLine("(cap reached)"); TerminateProcess(pi.hProcess,1); break; }
            if (SetBps(tid, ctx, 0, pc + 4)) advancing.Add(tid);
          }
        }
        else if (ec != 0x80000003 && ec != 0x406D1388 && BitConverter.ToInt32(ev,168) != 0) cont = 0x80010001;
      }
      else if (code == 5 && pid == rootPid) { sb.AppendLine("process exited"); ContinueDebugEvent(pid,tid,cont); break; }
      ContinueDebugEvent(pid, tid, cont);
    }
    Marshal.FreeHGlobal(rawCtx);
    sb.AppendLine("READBACK  Bcr[0]=0x" + vBcr0.ToString("X") + " Bvr[0]=0x" + vBvr0.ToString("X")
                  + "   Bcr[2]=0x" + vBcr2.ToString("X") + " Bvr[2]=0x" + vBvr2.ToString("X"));
    sb.AppendLine("Bcr[2] HONOURED? " + ((vBcr2 != 0 && vBvr2 != 0) ? "YES - the negative is real" : "NO - negative is VOID"));
    if (hits == 0) sb.AppendLine(">>> probe never fired - inconclusive, do not read as evidence.");
    return sb.ToString();
  }
}







