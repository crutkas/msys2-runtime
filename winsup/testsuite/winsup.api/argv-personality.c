/* Copyright (C) 2026 Cygwin Authors

This file is part of Cygwin.

This software is a copyrighted work licensed under the terms of the
Cygwin license.  Please consult the file "CYGWIN_LICENSE" for
details. */

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

/* The foreign parent is an optional negative fixture.  The same-cohort
   and Windows-personality controls are always required. */

static int
child_succeeded (int status)
{
  return status >= 0 && WIFEXITED (status) && WEXITSTATUS (status) == 0;
}

static int
check_random_read (void)
{
  unsigned char buf[4096];
  size_t total = 0;
  int fd = open ("/dev/urandom", O_RDONLY | O_NONBLOCK);

  if (fd < 0)
    {
      perror ("open /dev/urandom");
      return 1;
    }

  while (total < sizeof buf)
    {
      ssize_t count = read (fd, buf + total, sizeof buf - total);
      if (count < 0)
	{
	  if (errno == EINTR)
	    continue;
	  perror ("read /dev/urandom");
	  close (fd);
	  return 1;
	}
      if (count == 0)
	{
	  fprintf (stderr, "short read from /dev/urandom\n");
	  close (fd);
	  return 1;
	}
      total += count;
    }

  return close (fd) != 0;
}

static int
check_native_dd (void)
{
  const char *dd = getenv ("MSYS_TEST_DD");
  char output[] = "argv-personality-dd.XXXXXX";
  char of_arg[sizeof output + 4];
  int fd;
  int status;
  struct stat st;

  if (!dd || !*dd)
    dd = "dd";

  fd = mkstemp (output);
  if (fd < 0)
    {
      perror ("mkstemp");
      return 1;
    }
  close (fd);
  unlink (output);

  snprintf (of_arg, sizeof of_arg, "of=%s", output);
  const char *const argv[] = {
    "dd", "if=/dev/urandom", of_arg, "bs=4096", "count=1",
    "iflag=fullblock,nonblock", "status=none", NULL
  };
  if (strpbrk (dd, "/\\"))
    status = spawnv (_P_WAIT, dd, argv);
  else
    status = spawnvp (_P_WAIT, dd, argv);

  if (!child_succeeded (status))
    {
      fprintf (stderr, "native dd failed with status %d\n", status);
      unlink (output);
      return 1;
    }
  if (stat (output, &st) != 0 || st.st_size != 4096)
    {
      fprintf (stderr, "native dd wrote %lld bytes instead of 4096\n",
	       stat (output, &st) == 0 ? (long long) st.st_size : -1LL);
      unlink (output);
      return 1;
    }

  return unlink (output) != 0;
}

static int
check_same_cohort (const char *self)
{
  char path_arg[PATH_MAX];
  char cwd[PATH_MAX];
  int status;

  if (!getcwd (cwd, sizeof cwd)
      || snprintf (path_arg, sizeof path_arg,
		   "%s/argv-personality-marker", cwd) >= (int) sizeof path_arg)
    {
      perror ("getcwd");
      return 1;
    }

  const char *const argv[] = {
    self, "--msys-child", path_arg, "if=/dev/urandom", NULL
  };
  status = spawnv (_P_WAIT, self, argv);
  if (!child_succeeded (status))
    {
      fprintf (stderr, "same-cohort child failed with status %d\n", status);
      return 1;
    }
  return 0;
}

static int
check_windows_child (const char *path_arg)
{
  const char *helper = getenv ("MSYS_TEST_WINDOWS_ARGV_HELPER");
  int status;

  if (!helper || !*helper)
    helper = access ("mingw/argv-conv-win.exe", X_OK) == 0
	     ? "mingw/argv-conv-win.exe" : "mingw/argv-conv-win";

  const char *const argv[] = {
    helper, path_arg, "if=/dev/urandom", NULL
  };
  status = spawnv (_P_WAIT, helper, argv);
  if (!child_succeeded (status))
    {
      fprintf (stderr, "native Windows child failed with status %d\n",
	       status);
      return 1;
    }
  return 0;
}

static int
check_optional_foreign_parent (const char *self)
{
  const char *bash = getenv ("MSYS_TEST_FOREIGN_PARENT");
  int status;

  if (!bash || !*bash)
    return 0;

  const char *const argv[] = {
    bash, "--noprofile", "--norc", "-c",
    "exec \"$1\" --foreign-child if=/dev/urandom",
    "argv-personality", self, NULL
  };
  status = spawnv (_P_WAIT, bash, argv);
  if (!child_succeeded (status))
    {
      fprintf (stderr, "foreign-parent control failed with status %d\n",
	       status);
      return 1;
    }
  return 0;
}

int
main (int argc, char **argv)
{
  char path_arg[PATH_MAX];
  char cwd[PATH_MAX];

  if (argc > 1 && strcmp (argv[1], "--msys-child") == 0)
    return argc != 4 || argv[2][0] != '/'
	   || !strstr (argv[2], "argv-personality-marker")
	   || strcmp (argv[3], "if=/dev/urandom") != 0;

  if (argc > 1 && strcmp (argv[1], "--foreign-child") == 0)
    return argc != 3 || strcmp (argv[2], "if=/Device/Null") != 0;

  if (argc != 1)
    return 2;

  if (getenv ("MSYS2_ARG_CONV_EXCL"))
    {
      fprintf (stderr, "MSYS2_ARG_CONV_EXCL must be unset for this test\n");
      return 1;
    }

  if (!getcwd (cwd, sizeof cwd)
      || snprintf (path_arg, sizeof path_arg,
		   "%s/argv-personality-marker", cwd) >= (int) sizeof path_arg)
    {
      perror ("getcwd");
      return 1;
    }

  return check_same_cohort (argv[0])
	 || check_random_read ()
	 || check_native_dd ()
	 || check_windows_child (path_arg)
	 || check_optional_foreign_parent (argv[0]);
}
