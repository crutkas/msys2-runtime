/* Copyright (C) 2026 Cygwin Authors

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#include <ctype.h>
#include <stdio.h>
#include <string.h>

int
main (int argc, char **argv)
{
  if (argc != 3)
    {
      fprintf (stderr, "expected 2 arguments, received %d\n", argc - 1);
      return 1;
    }

  if (!((isalpha ((unsigned char) argv[1][0]) && argv[1][1] == ':')
	|| ((argv[1][0] == '\\' || argv[1][0] == '/')
	    && argv[1][1] == argv[1][0]))
      || !strstr (argv[1], "argv-personality-marker"))
    {
      fprintf (stderr, "POSIX path was not converted: %s\n", argv[1]);
      return 1;
    }

  if (strcmp (argv[2], "if=/Device/Null") != 0)
    {
      fprintf (stderr, "device operand was not converted: %s\n", argv[2]);
      return 1;
    }

  return 0;
}
