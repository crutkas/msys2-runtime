__declspec(dllimport) void ExitProcess (unsigned long);

static int resolver_calls;

static long
layer3_autoload_target (long value)
{
  return value + 1;
}

static long layer3_autoload_resolver (long);
void *layer3_autoload_slot = (void *) layer3_autoload_resolver;

static long
layer3_autoload_resolver (long value)
{
  ++resolver_calls;
  layer3_autoload_slot = (void *) layer3_autoload_target;
  return layer3_autoload_target (value);
}

long layer3_autoload_call (long);
void *layer3_autoload_patch (unsigned char *, void *);

void
mainCRTStartup (void)
{
  unsigned char slot[24] = { 0 };
  long first = layer3_autoload_call (40);
  long second = layer3_autoload_call (41);
  void *patched = layer3_autoload_patch (slot, (void *) layer3_autoload_target);
  ExitProcess (first == 41 && second == 42 && resolver_calls == 1
	       && patched == (void *) layer3_autoload_target
	       ? 0 : 1);
}

void *layer3_autoload_reloc_anchor = (void *) mainCRTStartup;
