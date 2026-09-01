#!/bin/sh
set -e
cd "$(dirname "$0")"

ACLOCAL=${ACLOCAL:-/usr/bin/aclocal}
AUTOCONF=${AUTOCONF:-/usr/bin/autoconf}
AUTOMAKE=${AUTOMAKE:-/usr/bin/automake}
RM=${RM:-/bin/rm}

"$ACLOCAL" --force
"$AUTOCONF" -f
"$AUTOMAKE" -ac
"$RM" -rf autom4te.cache
