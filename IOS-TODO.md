# iOS port: things to fix

Running list for the `local-build` branch. Tick items off in the same commit as the fix.

## Broken on device

- [ ] **File browser copy / cut / move / rename do nothing.** `FileManager:moveFile`, `copyFileFromTo` and `copyRecursive` (`frontend/apps/filemanager/filemanager.lua:1300-1315`) run `/bin/mv` and `/bin/cp` through `ffiUtil.execute` (`base/ffi/util.lua:275`), which uses `fork()` + `execl`. iOS allows neither, and those binaries don't exist there. Delete still works (`os.remove`, `ffiUtil.purgeDir`).
  Fix idea: when `KO_IOS == "1"`, use `os.rename` for move/rename, with a copy-then-delete fallback for moves across file providers (cloud folders added with `iosfilepicker`), and a Lua read/write loop for copy (walking directories with `lfs` for recursive copy).
- [ ] **Audit other uses of `ffiUtil.execute`, `os.execute` and `io.popen`** in frontend and bundled plugins. Each fails on iOS the same way. Hide, stub or rewrite them in Lua.

## Third-party plugins

- [ ] **Bookshelf (AndyHazz/bookshelf.koplugin, v6.4.2):** its in-app updater (`lib/bookshelf_updater.lua`, `os.execute`) won't work. For now, update it by hand by replacing `Documents/plugins/bookshelf.koplugin`.
  - Hardcover's `io.popen` (`lib/bookshelf_hardcover.lua:443-455`) runs `unzip` to read an EPUB's OPF for identifiers. That's not a `curl` call. It could use base's in-process `ffi/archiver` instead, with no native code needed.
  - `lib/bookshelf_http.lua` only falls back to `curl` when LuaSocket/LuaSec fails, so that fallback may never be reached on iOS. Check before building a native HTTP bridge for it.

## Open from the fork / upstream

- [ ] Apply `hezi/koreader-base-ios#1`, the base companion to PR #12. Without it the edge-swipe input-freeze fix is incomplete.
- [ ] Release (non-Debug) builds fail (open issue on hezi/koreader-ios).
- [ ] Custom fonts (open issue on hezi/koreader-ios).
- [ ] No button to hide the on-screen keyboard (open issue on hezi/koreader-ios).

## Build and signing

- [ ] Change bundle id `rocks.koreader.ios` to one unique to the team (`platform/ios/project.yml` or `IOS_BUNDLE_ID`) so it doesn't need changing in Xcode after every `make TARGET=ios xcodeproj`.
- [ ] The build has no release tag, so KOReader reports no version: `git-rev` is a bare hash and the app version falls back to `0.0.<commit count>`. Plugins that gate on the KOReader version see "unknown". Consider a fake tag such as `v2026.04-ios`.

## Known limits (probably won't fix)

- Terminal and SSH plugins can't work (they need `fork()`).
- PDF reflow (libk2pdfopt) is disabled in the fork.
- Signed with a paid developer account (1-year profiles), so an iCloud container entitlement is available if wanted.
