import std/[os, strutils]

# all vendor subdirectories
for dir in walkDir(thisDir() / "vendor"):
  if dir.kind == pcDir:
    switch("path", dir.path)
    switch("path", dir.path / "src")

switch("path", thisDir() / "vendor/libchat/nim-bindings")
switch("path", thisDir() / "vendor/libchat/nim-bindings/src")

# nwaku (PR #3807) consumes deps via nimble rather than vendored submodules,
# so add each package dir under nimbledeps/pkgs2 (and its src/) to the nim
# search path. The dir name carries the "<name>-<version>-<sha>" stamp; nim
# resolves imports by package name relative to those paths.
let nwakuDeps = thisDir() / "vendor/nwaku/nimbledeps/pkgs2"
if dirExists(nwakuDeps):
  for pkg in walkDir(nwakuDeps):
    if pkg.kind == pcDir:
      # The chat ships its own FFI framework via vendor/nim-ffi; skip the
      # nwaku-vendored `ffi` package(s) to avoid a declareLibrary API clash.
      if pkg.path.lastPathPart.startsWith("ffi-"):
        continue
      switch("path", pkg.path)
      if dirExists(pkg.path / "src"):
        switch("path", pkg.path / "src")