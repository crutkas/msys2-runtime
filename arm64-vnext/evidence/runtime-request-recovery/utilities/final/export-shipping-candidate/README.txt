These executables are utilities owned by the msys2-runtime package.

Disposition: source-utilities shipping candidate pending independent provider intake; not a complete runtime package

This utility-only ARM64 export does not transfer or create independent
ownership of the runtime DLL, compiler, SDK, or a complete runtime package.

The binaries were built from the pinned source commit and the normal configured
winsup/utils recipes. No libcygwin.a alias was used. See MANIFEST.json,
evidence/build-command.json, the link maps, and qualification outputs.
