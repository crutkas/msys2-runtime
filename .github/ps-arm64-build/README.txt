This directory records the owned native ARM64 MSYS ps.exe, mount.exe, and
cygpath.exe utility build.

The source is copied from the pinned runtime source snapshot identified by
manifest.json. The build uses the normal winsup/utils configured compile and
link commands, rewritten only from retained Linux paths to the paired Windows
compiler and this owned source/build directory.

Generated binaries, object files, logs, and the final immutable handoff are
written outside the repository under the current session artifact directory.
Run build.ps1, qualify.ps1, and seal.ps1 in that order.
