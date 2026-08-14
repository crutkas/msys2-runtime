typedef unsigned int DWORD;
typedef int NTSTATUS;

__attribute__ ((dllimport)) DWORD GetLastError (void);
__attribute__ ((dllimport)) NTSTATUS NtYieldExecution (void);

int probe_entry (void);

__attribute__ ((section (".data")))
volatile DWORD probe_data = 1;

__attribute__ ((section (".bss")))
volatile DWORD probe_bss;

__attribute__ ((section (".rdata")))
int (*const volatile probe_reloc) (void) = probe_entry;

__attribute__ ((section (".tls")))
volatile DWORD probe_tls = 2;

__attribute__ ((section (".data_cygwin_nocopy")))
volatile DWORD probe_nocopy_data = 3;

__attribute__ ((section (".rdata_cygwin_nocopy")))
const volatile DWORD probe_nocopy_rdata = 4;

__attribute__ ((section (".cygwin_dll_common")))
volatile DWORD probe_dll_common = 5;

__attribute__ ((noinline, section (".probe_autoload_text")))
static DWORD
probe_autoload (void)
{
  return probe_nocopy_rdata;
}

__attribute__ ((constructor))
static void
probe_ctor (void)
{
  ++probe_data;
}

__attribute__ ((destructor))
static void
probe_dtor (void)
{
  --probe_data;
}

__declspec (dllexport) int
probe_entry (void)
{
  probe_bss = GetLastError ();
  return (NtYieldExecution ()
	  + probe_bss
	  + probe_data
	  + probe_tls
	  + probe_nocopy_data
	  + probe_dll_common
	  + probe_autoload ()
	  + (probe_reloc == probe_entry));
}
