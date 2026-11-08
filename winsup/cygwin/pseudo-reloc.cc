/* pseudo-reloc.cc

   Contributed by Egor Duda  <deo@logos-m.ru>
   Modified by addition of runtime_pseudo_reloc version 2
   by Kai Tietz  <kai.tietz@onevision.com>

   THIS SOFTWARE IS NOT COPYRIGHTED

   This source code is offered for use in the public domain. You may
   use, modify or distribute it freely.

   This code is distributed in the hope that it will be useful but
   WITHOUT ANY WARRANTY. ALL WARRENTIES, EXPRESS OR IMPLIED ARE HEREBY
   DISCLAMED. This includes but is not limited to warrenties of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
*/

#ifndef __CYGWIN__
# include "windows.h"
# define NO_COPY
#else
# include "winsup.h"
# include <sys/cygwin.h>
# if defined (__aarch64__)
#  include "aarch64_pseudo_reloc.h"
# endif
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <memory.h>

#ifdef __GNUC__
#define ATTRIBUTE_NORETURN __attribute__ ((noreturn))
#else
#define ATTRIBUTE_NORETURN
#endif

#ifndef __MINGW_LSYMBOL
#define __MINGW_LSYMBOL(sym) sym
#endif

extern char __RUNTIME_PSEUDO_RELOC_LIST__;
extern char __RUNTIME_PSEUDO_RELOC_LIST_END__;
extern char __MINGW_LSYMBOL(_image_base__);

/* v1 relocation is basically:
 *   *(base + .target) += .addend
 * where (base + .target) is always assumed to point
 * to a DWORD (4 bytes).
 */
typedef struct {
  DWORD addend;
  DWORD target;
} runtime_pseudo_reloc_item_v1;

/* v2 relocation is more complex. In effect, it is
 *    *(base + .target) += *(base + .sym) - (base + .sym)
 * with care taken in both reading, sign extension, and writing
 * because .flags may indicate that (base + .target) may point
 * to a BYTE, WORD, DWORD, or QWORD (w64).
 */
typedef struct {
  DWORD sym;
  DWORD target;
  DWORD flags;
} runtime_pseudo_reloc_item_v2;

typedef struct {
  DWORD magic1;
  DWORD magic2;
  DWORD version;
} runtime_pseudo_reloc_v2;

static void ATTRIBUTE_NORETURN
__report_error (const char *msg, ...)
{
#ifdef __CYGWIN__
  /* This function is used to print short error messages
   * to stderr, which may occur during DLL initialization
   * while fixing up 'pseudo' relocations. This early, we
   * may not be able to use cygwin stdio functions, so we
   * use the win32 WriteFile api. This should work with both
   * normal win32 console IO handles, redirected ones, and
   * cygwin ptys.
   */
  char buf[128];
  char *posix_module = NULL;
  static const char UNKNOWN_MODULE[] = "<unknown module>: ";
  static const char CYGWIN_FAILURE_MSG[] = "Cygwin runtime failure: ";
  HANDLE errh = GetStdHandle (STD_ERROR_HANDLE);
  va_list args;

  /* FIXME: cleanup further to avoid old use of cygwin_internal */
  if (errh == INVALID_HANDLE_VALUE)
    cygwin_internal (CW_EXIT_PROCESS, STATUS_ILLEGAL_DLL_PSEUDO_RELOCATION, 1);

  posix_module = (char *) cygwin_create_path (CCP_WIN_W_TO_POSIX,
					      global_progname);

  va_start (args, msg);
  vsnprintf (buf, sizeof (buf), msg, args);
  va_end (args);
  buf[sizeof (buf) - 1] = '\0'; /* paranoia */

  small_printf ("%s%s: %s\n", CYGWIN_FAILURE_MSG, posix_module ?: UNKNOWN_MODULE, buf);
  if (posix_module)
    free (posix_module);

  cygwin_internal (CW_EXIT_PROCESS, STATUS_ILLEGAL_DLL_PSEUDO_RELOCATION, 1);
  /* not reached, but silences noreturn warning */
  abort ();
#else
  va_list argp;
  va_start (argp, msg);
# ifdef __MINGW64_VERSION_MAJOR
  fprintf (stderr, "Mingw-w64 runtime failure:\n");
# else
  fprintf (stderr, "Mingw runtime failure:\n");
# endif
  vfprintf (stderr, msg, argp);
  va_end (argp);
  abort ();
#endif
}

/*
 * This function automatically sets addr as PAGE_EXECUTE_READWRITE
 * by deciding whether VirtualQuery for the addr is actually needed.
 * And it assumes that it is called in LdrpCallInitRoutine.
 * Hence not thread safe.
 */
static bool
is_writable_protection (DWORD protection)
{
  DWORD access = protection & 0xff;
  return !(protection & PAGE_GUARD)
	 && (access == PAGE_EXECUTE_READWRITE || access == PAGE_READWRITE
	     || access == PAGE_EXECUTE_WRITECOPY || access == PAGE_WRITECOPY);
}

static void
auto_protect_for (void* addr)
{
  static MEMORY_BASIC_INFORMATION mbi;
  static bool state = false;
  static DWORD oldprot;

  if (!addr)
    {
      /* Restore original protection. */
      if (state && !is_writable_protection (mbi.Protect)
	  && !VirtualProtect (mbi.BaseAddress, mbi.RegionSize, oldprot,
			      &oldprot))
	__report_error ("VirtualProtect restore failed with error %lu",
			GetLastError ());
      state = false;
      return;
    }
  if (state)
    {
      /* We have valid region information.  Are we still within this region?
         If so, just leave. */
      uintptr_t offset = (uintptr_t) addr - (uintptr_t) mbi.BaseAddress;
      if ((uintptr_t) addr >= (uintptr_t) mbi.BaseAddress
	  && offset < mbi.RegionSize)
	return;
      /* Otherwise, restore original protection and fall through to querying
         and potentially changing next region. */
      if (!is_writable_protection (mbi.Protect)
	  && !VirtualProtect (mbi.BaseAddress, mbi.RegionSize, oldprot,
			      &oldprot))
	__report_error ("VirtualProtect restore failed with error %lu",
			GetLastError ());
    }
  else
    state = true;
  /* Query region and temporarily allow write access to read-only protected
     memory.  */
  if (!VirtualQuery (addr, &mbi, sizeof mbi))
    __report_error ("VirtualQuery failed with error %lu", GetLastError ());
  if (!is_writable_protection (mbi.Protect)
      && !VirtualProtect (mbi.BaseAddress, mbi.RegionSize,
			  PAGE_EXECUTE_READWRITE, &oldprot))
    __report_error ("VirtualProtect failed with error %lu", GetLastError ());
}

/* This function temporarily marks the page containing addr
 * writable, before copying len bytes from *src to *addr, and
 * then restores the original protection settings to the page.
 *
 * Using this function eliminates the requirement with older
 * pseudo-reloc implementations, that sections containing
 * pseudo-relocs (such as .text and .rdata) be permanently
 * marked writable. This older behavior sabotaged any memory
 * savings achieved by shared libraries on win32 -- and was
 * slower, too.  However, on cygwin as of binutils 2.20 the
 * .text section is still marked writable, and the .rdata section
 * is folded into the (writable) .data when --enable-auto-import.
 */
static void
__write_memory (void *addr, const void *src, size_t len)
{
  if (!len)
    return;
  /* Fix page protection for writing. */
  auto_protect_for (addr);
  /* write the data. */
  memcpy (addr, src, len);
}

#define RP_VERSION_V1 0
#define RP_VERSION_V2 1

#if defined (__aarch64__)
static size_t
aarch64_validate_image_and_table (void *start, void *end, void *base)
{
  IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *) base;
  if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0)
    __report_error ("Invalid AArch64 image header");

  IMAGE_NT_HEADERS64 *nt
    = (IMAGE_NT_HEADERS64 *) ((uintptr_t) base + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE
      || nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC
      || nt->OptionalHeader.SizeOfImage < sizeof (IMAGE_DOS_HEADER))
    __report_error ("Invalid AArch64 PE header");

  size_t image_size = nt->OptionalHeader.SizeOfImage;
  uintptr_t image = (uintptr_t) base;
  if (image > UINTPTR_MAX - image_size)
    __report_error ("AArch64 image address overflow");
  uintptr_t table_start = (uintptr_t) start;
  uintptr_t table_end = (uintptr_t) end;
  if (table_start < image || table_end < table_start
      || table_end - image > image_size || (table_start - image) & 3)
    __report_error ("AArch64 pseudo-relocation table is outside the image");
  return image_size;
}

static unsigned int
aarch64_reloc_bits (const runtime_pseudo_reloc_item_v2 *item)
{
  return item->flags & 0xff;
}

static uintptr_t
aarch64_reloc_address (void *base,
		       const runtime_pseudo_reloc_item_v2 *item)
{
  return (uintptr_t) base + item->target;
}

static const runtime_pseudo_reloc_item_v2 *
aarch64_find_low_reloc (const runtime_pseudo_reloc_item_v2 *page,
			const runtime_pseudo_reloc_item_v2 *end,
			void *base)
{
  if (page + 1 >= end)
    return NULL;

  unsigned int page_reg
    = aarch64_page_register (*((uint32_t *) aarch64_reloc_address (base,
								   page)));
  const runtime_pseudo_reloc_item_v2 *item = page + 1;
  if (item->sym != page->sym || aarch64_reloc_bits (item) != 12
      || item->target & 3)
    return NULL;

  uint32_t instruction
    = *((uint32_t *) aarch64_reloc_address (base, item));
  if (aarch64_page_offset_kind (instruction) == AARCH64_PSEUDO_RELOC_NONE
      || aarch64_page_offset_base_register (instruction) != page_reg)
    return NULL;
  return item;
}

static const runtime_pseudo_reloc_item_v2 *
aarch64_find_page_reloc (const runtime_pseudo_reloc_item_v2 *first,
			 const runtime_pseudo_reloc_item_v2 *low,
			 void *base)
{
  if (low == first)
    return NULL;

  uint32_t low_instruction
    = *((uint32_t *) aarch64_reloc_address (base, low));
  unsigned int base_reg
    = aarch64_page_offset_base_register (low_instruction);
  const runtime_pseudo_reloc_item_v2 *item = low - 1;
  if (item->sym != low->sym || aarch64_reloc_bits (item) != 21
      || item->target & 3)
    return NULL;

  uint32_t instruction
    = *((uint32_t *) aarch64_reloc_address (base, item));
  if (!aarch64_is_adrp (instruction)
      || aarch64_page_register (instruction) != base_reg)
    return NULL;
  return item;
}

static size_t
aarch64_reloc_width (unsigned int bits)
{
  switch (bits)
    {
    case 8:
      return 1;
    case 16:
      return 2;
    case 12:
    case 21:
    case 32:
      return 4;
    case 64:
      return 8;
    default:
      return 0;
    }
}

static bool
aarch64_ranges_overlap (uintptr_t left, size_t left_size,
			uintptr_t right, size_t right_size)
{
  return left < right + right_size && right < left + left_size;
}

static void ATTRIBUTE_NORETURN
report_aarch64_reloc_error (aarch64_pseudo_reloc_status status,
			    uintptr_t page_address,
			    uintptr_t low_address)
{
  switch (status)
    {
    case AARCH64_PSEUDO_RELOC_INVALID_PAGE_INSTRUCTION:
      __report_error ("Invalid AArch64 PAGEBASE instruction at %p",
		      (void *) page_address);
    case AARCH64_PSEUDO_RELOC_INVALID_PAGE_OFFSET_INSTRUCTION:
      __report_error ("Invalid AArch64 PAGEOFFSET instruction at %p",
		      (void *) low_address);
    case AARCH64_PSEUDO_RELOC_REGISTER_MISMATCH:
      __report_error ("Mismatched AArch64 pseudo-relocation pair at %p/%p",
		      (void *) page_address, (void *) low_address);
    case AARCH64_PSEUDO_RELOC_ADDRESS_OVERFLOW:
      __report_error ("AArch64 pseudo-relocation address overflow at %p/%p",
		      (void *) page_address, (void *) low_address);
    case AARCH64_PSEUDO_RELOC_OUT_OF_RANGE:
      __report_error ("AArch64 PAGEBASE target is outside +/-4GiB at %p",
		      (void *) page_address);
    case AARCH64_PSEUDO_RELOC_MISALIGNED_PAGE_OFFSET:
      __report_error ("Misaligned AArch64 PAGEOFFSET target at %p",
		      (void *) low_address);
    default:
      __report_error ("Unknown AArch64 pseudo-relocation failure at %p/%p",
		      (void *) page_address, (void *) low_address);
    }
}

static void
validate_aarch64_pseudo_relocs (runtime_pseudo_reloc_item_v2 *first,
				runtime_pseudo_reloc_item_v2 *end,
				void *base, size_t image_size,
				uintptr_t table_start, uintptr_t table_end)
{
  uintptr_t image = (uintptr_t) base;

  for (runtime_pseudo_reloc_item_v2 *item = first; item < end; ++item)
    {
      unsigned int bits = aarch64_reloc_bits (item);
      size_t width = aarch64_reloc_width (bits);
      if (!width)
	__report_error ("Unknown pseudo relocation bit size %u", bits);
      if (item->sym > image_size - sizeof (ptrdiff_t)
	  || item->sym & (sizeof (ptrdiff_t) - 1))
	__report_error ("Invalid AArch64 import slot RVA 0x%x",
			(unsigned int) item->sym);
      if (item->target > image_size - width)
	__report_error ("Invalid AArch64 relocation target RVA 0x%x",
			(unsigned int) item->target);

      uintptr_t target = image + item->target;
      if (aarch64_ranges_overlap (target, width, table_start,
				  table_end - table_start))
	__report_error ("AArch64 relocation target overlaps its table at %p",
			(void *) target);

      for (runtime_pseudo_reloc_item_v2 *other = item + 1;
	   other < end; ++other)
	{
	  size_t other_width = aarch64_reloc_width (
				aarch64_reloc_bits (other));
	  if (!other_width)
	    continue;
	  uintptr_t other_target = image + other->target;
	  if (other->target <= image_size - other_width
	      && aarch64_ranges_overlap (target, width, other_target,
					 other_width))
	    __report_error ("Overlapping AArch64 pseudo-relocations at %p",
			    (void *) target);
	}
    }

  for (runtime_pseudo_reloc_item_v2 *item = first; item < end; ++item)
    {
      unsigned int bits = aarch64_reloc_bits (item);
      if (bits != 12 && bits != 21)
	continue;

      uintptr_t address = aarch64_reloc_address (base, item);
      if (item->target & 3)
	__report_error ("Unaligned AArch64 pseudo-relocation target %p",
			(void *) address);

      if (bits == 12)
	{
	  uint32_t instruction = *((uint32_t *) address);
	  if (aarch64_page_offset_kind (instruction)
	      == AARCH64_PSEUDO_RELOC_NONE)
	    report_aarch64_reloc_error (
	      AARCH64_PSEUDO_RELOC_INVALID_PAGE_OFFSET_INSTRUCTION, 0,
	      address);

	  const runtime_pseudo_reloc_item_v2 *page
	    = aarch64_find_page_reloc (first, item, base);
	  if (!page || aarch64_find_low_reloc (page, end, base) != item)
	    __report_error ("Unpaired AArch64 PAGEOFFSET relocation at %p",
			    (void *) address);
	  continue;
	}

      uint32_t page_instruction = *((uint32_t *) address);
      if (!aarch64_is_adrp (page_instruction))
	report_aarch64_reloc_error (
	  AARCH64_PSEUDO_RELOC_INVALID_PAGE_INSTRUCTION, address, 0);

      const runtime_pseudo_reloc_item_v2 *low
	= aarch64_find_low_reloc (item, end, base);
      if (!low || aarch64_find_page_reloc (first, low, base) != item)
	__report_error ("Unpaired AArch64 PAGEBASE relocation at %p",
			(void *) address);
      if (low->target - item->target != 4
	  && low->target - item->target != 8)
	__report_error ("Non-local AArch64 pseudo-relocation pair at %p/%p",
			(void *) address,
			(void *) aarch64_reloc_address (base, low));

      uintptr_t import_slot = (uintptr_t) base + item->sym;

      uint32_t low_instruction
	= *((uint32_t *) aarch64_reloc_address (base, low));
      aarch64_pseudo_reloc_result result;
      aarch64_pseudo_reloc_status status
	= aarch64_relocate_pseudo_pair (
	    &result, page_instruction, low_instruction, address, import_slot,
	    *((uintptr_t *) import_slot));
      if (status != AARCH64_PSEUDO_RELOC_OK)
	report_aarch64_reloc_error (
	  status, address, aarch64_reloc_address (base, low));
    }
}

static void ATTRIBUTE_NORETURN
rollback_aarch64_pair (uintptr_t page_address, uintptr_t low_address,
		       uint32_t original_page, uint32_t original_low,
		       MEMORY_BASIC_INFORMATION *mbi, bool changed,
		       DWORD old_protection, const char *operation,
		       DWORD operation_error)
{
  memcpy ((void *) page_address, &original_page, sizeof original_page);
  memcpy ((void *) low_address, &original_low, sizeof original_low);

  uintptr_t flush_start
    = page_address < low_address ? page_address : low_address;
  uintptr_t flush_end
    = page_address > low_address ? page_address : low_address;
  bool flushed = FlushInstructionCache (
		   GetCurrentProcess (), (void *) flush_start,
		   flush_end + sizeof (uint32_t) - flush_start);

  bool restored = true;
  if (changed)
    {
      DWORD unused;
      restored = VirtualProtect (mbi->BaseAddress, mbi->RegionSize,
				 old_protection, &unused);
    }

  if (!flushed || !restored)
    __report_error ("%s failed with error %lu; rollback cleanup failed",
		    operation, operation_error);
  __report_error ("%s failed with error %lu; instructions rolled back",
		  operation, operation_error);
}

static void
write_aarch64_pair (uintptr_t page_address, uintptr_t low_address,
		    uint32_t relocated_page, uint32_t relocated_low)
{
  MEMORY_BASIC_INFORMATION page_mbi;
  MEMORY_BASIC_INFORMATION low_mbi;
  if (!VirtualQuery ((void *) page_address, &page_mbi, sizeof page_mbi)
      || !VirtualQuery ((void *) low_address, &low_mbi, sizeof low_mbi))
    __report_error ("VirtualQuery failed for AArch64 instruction pair");
  if (page_mbi.BaseAddress != low_mbi.BaseAddress
      || page_mbi.RegionSize != low_mbi.RegionSize
      || page_mbi.Protect != low_mbi.Protect)
    __report_error ("AArch64 instruction pair crosses memory regions");

  uint32_t original_page = *((uint32_t *) page_address);
  uint32_t original_low = *((uint32_t *) low_address);
  DWORD old_protection = page_mbi.Protect;
  bool changed = !is_writable_protection (page_mbi.Protect);
  if (changed
      && !VirtualProtect (page_mbi.BaseAddress, page_mbi.RegionSize,
			  PAGE_EXECUTE_READWRITE, &old_protection))
    __report_error ("VirtualProtect failed for AArch64 instruction pair "
		    "with error %lu", GetLastError ());

  memcpy ((void *) page_address, &relocated_page, sizeof relocated_page);
  memcpy ((void *) low_address, &relocated_low, sizeof relocated_low);

  uintptr_t flush_start
    = page_address < low_address ? page_address : low_address;
  uintptr_t flush_end
    = page_address > low_address ? page_address : low_address;
  if (!FlushInstructionCache (
	GetCurrentProcess (), (void *) flush_start,
	flush_end + sizeof (uint32_t) - flush_start))
    {
      DWORD error = GetLastError ();
      rollback_aarch64_pair (page_address, low_address, original_page,
			     original_low, &page_mbi, changed,
			     old_protection, "FlushInstructionCache", error);
    }

  if (changed)
    {
      DWORD unused;
      if (!VirtualProtect (page_mbi.BaseAddress, page_mbi.RegionSize,
			   old_protection, &unused))
	{
	  DWORD error = GetLastError ();
	  rollback_aarch64_pair (page_address, low_address, original_page,
				 original_low, &page_mbi, changed,
				 old_protection, "VirtualProtect restore",
				 error);
	}
    }
}

static void
apply_aarch64_pseudo_reloc (runtime_pseudo_reloc_item_v2 *page,
			    runtime_pseudo_reloc_item_v2 *first,
			    runtime_pseudo_reloc_item_v2 *end,
			    void *base)
{
  const runtime_pseudo_reloc_item_v2 *low
    = aarch64_find_low_reloc (page, end, base);
  uintptr_t page_address = aarch64_reloc_address (base, page);
  uintptr_t low_address = aarch64_reloc_address (base, low);
  uintptr_t import_slot = (uintptr_t) base + page->sym;
  aarch64_pseudo_reloc_result result;
  aarch64_pseudo_reloc_status status
    = aarch64_relocate_pseudo_pair (
	&result, *((uint32_t *) page_address), *((uint32_t *) low_address),
	page_address, import_slot, *((uintptr_t *) import_slot));

  if (status != AARCH64_PSEUDO_RELOC_OK
      || aarch64_find_page_reloc (first, low, base) != page)
    report_aarch64_reloc_error (status, page_address, low_address);

  write_aarch64_pair (page_address, low_address, result.page_instruction,
		      result.page_offset_instruction);
}
#endif

static void
do_pseudo_reloc (void * start, void * end, void * base)
{
  ptrdiff_t addr_imp, reldata;
  ptrdiff_t reloc_target = (ptrdiff_t) ((char *)end - (char*)start);
  runtime_pseudo_reloc_v2 *v2_hdr = (runtime_pseudo_reloc_v2 *) start;
  runtime_pseudo_reloc_item_v2 *r;
#if defined (__aarch64__)
  size_t image_size = aarch64_validate_image_and_table (start, end, base);
#endif

  /* A valid relocation list will contain at least one entry, and
   * one v1 data structure (the smallest one) requires two DWORDs.
   * So, if the relocation list is smaller than 8 bytes, bail.
   */
  if (reloc_target < 8)
    return;

  /* Check if this is the old pseudo relocation version.  */
  /* There are two kinds of v1 relocation lists:
   *   1) With a (v2-style) version header. In this case, the
   *      first entry in the list is a 3-DWORD structure, with
   *      value:
   *	  { 0, 0, RP_VERSION_V1 }
   *      In this case, we skip to the next entry in the list,
   *      knowing that all elements after the head item can
   *      be cast to runtime_pseudo_reloc_item_v1.
   *   2) Without a (v2-style) version header. In this case, the
   *      first element in the list IS an actual v1 relocation
   *      record, which is two DWORDs.  Because there will never
   *      be a case where a v1 relocation record has both
   *      addend == 0 and target == 0, this case will not be
   *      confused with the prior one.
   * All current binutils, when generating a v1 relocation list,
   * use the second (e.g. original) form -- that is, without the
   * v2-style version header.
   */
  if (reloc_target >= 12
      && v2_hdr->magic1 == 0 && v2_hdr->magic2 == 0
      && v2_hdr->version == RP_VERSION_V1)
    {
      /* We have a list header item indicating that the rest
       * of the list contains v1 entries.  Move the pointer to
       * the first true v1 relocation record.  By definition,
       * that v1 element will not have both addend == 0 and
       * target == 0 (and thus, when interpreted as a
       * runtime_pseudo_reloc_v2, it will not have both
       * magic1 == 0 and magic2 == 0).
       */
      v2_hdr++;
    }

  if (v2_hdr->magic1 != 0 || v2_hdr->magic2 != 0)
    {
      /*************************
       * Handle v1 relocations *
       *************************/
      runtime_pseudo_reloc_item_v1 * o;
      for (o = (runtime_pseudo_reloc_item_v1 *) v2_hdr;
	   o < (runtime_pseudo_reloc_item_v1 *)end;
	   o++)
	{
	  DWORD newval;
	  reloc_target = (ptrdiff_t) base + o->target;
	  newval = (*((DWORD*) reloc_target)) + o->addend;
	  __write_memory ((void *) reloc_target, &newval, sizeof (DWORD));
	}
      /* Restore original protection. */
      auto_protect_for (NULL);
      return;
    }

  /* If we got this far, then we have relocations of version 2 or newer */

  /* Check if this is a known version.  */
  if (v2_hdr->version != RP_VERSION_V2)
    {
      __report_error ("  Unknown pseudo relocation protocol version %d.\n",
		      (int) v2_hdr->version);
      return;
    }

  /*************************
   * Handle v2 relocations *
   *************************/

  /* Walk over header. */
  r = (runtime_pseudo_reloc_item_v2 *) &v2_hdr[1];

  ptrdiff_t v2_size = (char *) end - (char *) r;
  if (v2_size < 0
      || v2_size % (ptrdiff_t) sizeof (runtime_pseudo_reloc_item_v2))
    __report_error ("Malformed pseudo relocation table size %ld",
		    (long) v2_size);

#if defined (__aarch64__)
  validate_aarch64_pseudo_relocs (
    r, (runtime_pseudo_reloc_item_v2 *) end, base, image_size,
    (uintptr_t) start, (uintptr_t) end);
  for (runtime_pseudo_reloc_item_v2 *item = r;
       item < (runtime_pseudo_reloc_item_v2 *) end; ++item)
    if (aarch64_reloc_bits (item) == 21)
      apply_aarch64_pseudo_reloc (
	item, r, (runtime_pseudo_reloc_item_v2 *) end, base);
#endif

  for (; r < (runtime_pseudo_reloc_item_v2 *) end; r++)
    {
      /* location where new address will be written */
      reloc_target = (ptrdiff_t) base + r->target;

#if defined (__aarch64__)
      unsigned int bits = aarch64_reloc_bits (r);
      if (bits == 12 || bits == 21)
	continue;
#endif

      /* get sym pointer. It points either to the iat entry
       * of the referenced element, or to the stub function.
       */
      addr_imp = (ptrdiff_t) base + r->sym;
      addr_imp = *((ptrdiff_t *) addr_imp);

      /* read existing relocation value from image, casting to the
       * bitsize indicated by the 8 LSBs of flags. If the value is
       * negative, manually sign-extend to ptrdiff_t width. Raise an
       * error if the bitsize indicated by the 8 LSBs of flags is not
       * supported.
       */
      switch ((r->flags & 0xff))
	{
	case 8:
	  reldata = (ptrdiff_t) (*((unsigned char *)reloc_target));
	  if ((reldata & 0x80) != 0)
	    reldata |= ~((ptrdiff_t) 0xff);
	  break;
	case 16:
	  reldata = (ptrdiff_t) (*((unsigned short *)reloc_target));
	  if ((reldata & 0x8000) != 0)
	    reldata |= ~((ptrdiff_t) 0xffff);
	  break;
	case 32:
	  reldata = (ptrdiff_t) (*((unsigned int *)reloc_target));
#if defined (__x86_64__) || defined (_WIN64)
	  if ((reldata & 0x80000000) != 0)
	    reldata |= ~((ptrdiff_t) 0xffffffff);
#endif
	  break;
#if defined (__x86_64__) || defined (_WIN64)
	case 64:
	  reldata = (ptrdiff_t) (*((unsigned long long *)reloc_target));
	  break;
#endif
	default:
	  reldata=0;
	  __report_error ("  Unknown pseudo relocation bit size %d.\n",
		  (int) (r->flags & 0xff));
	  break;
	}

      /* Adjust the relocation value */
      reldata -= ((ptrdiff_t) base + r->sym);
      reldata += addr_imp;

      /* Write the new relocation value back to *reloc_target */
      switch ((r->flags & 0xff))
	{
	case 8:
	  __write_memory ((void *) reloc_target, &reldata, 1);
	  break;
	case 16:
	  __write_memory ((void *) reloc_target, &reldata, 2);
	  break;
	case 32:
#if defined (__CYGWIN__) && defined (__x86_64__)
	  if (reldata > (ptrdiff_t) __INT32_MAX__
	      || reldata < -((ptrdiff_t) __INT32_MAX__) - 1)
	    __report_error ("Invalid relocation.  Offset %p at address %p "
			    "doesn't fit into 32 bits", reldata, reloc_target);
#endif
	  __write_memory ((void *) reloc_target, &reldata, 4);
	  break;
#if defined (__x86_64__) || defined (_WIN64)
	case 64:
	  __write_memory ((void *) reloc_target, &reldata, 8);
	  break;
#endif
	}
    }
  /* Restore original protection. */
  auto_protect_for (NULL);
}

#ifdef __CYGWIN__
extern "C" void
_pei386_runtime_relocator (per_process *u)
{
  if (u)
    do_pseudo_reloc (u->pseudo_reloc_start, u->pseudo_reloc_end, u->image_base);
}
#else
extern "C" void
_pei386_runtime_relocator (void)
{
  static NO_COPY int was_init = 0;
  if (was_init)
    return;
  ++was_init;
  do_pseudo_reloc (&__RUNTIME_PSEUDO_RELOC_LIST__,
		   &__RUNTIME_PSEUDO_RELOC_LIST_END__,
		   &__MINGW_LSYMBOL(_image_base__));
}
#endif
