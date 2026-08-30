/* io.h

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#ifndef _IO_H_
#define _IO_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

/*
 * Function to return a Win32 HANDLE from a fd.
 */
#if defined(__aarch64__) && defined(_WIN64)
extern intptr_t _get_osfhandle(int);
#else
extern long _get_osfhandle(int);
#endif
#define get_osfhandle(i) _get_osfhandle(i)
extern int _setmode (int __fd, int __mode);
#define setmode(f,m) _setmode((f),(m))

#ifdef __cplusplus
};
#endif /* __cplusplus */

#endif /* _IO_H_ */
