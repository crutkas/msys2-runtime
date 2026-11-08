#if !defined(__aarch64__)
#error A native AArch64 compiler is required
#endif

__declspec (dllexport) int
unload_probe_value (void)
{
  return 42;
}
