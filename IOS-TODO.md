# iOS port: things to fix

Running list for the `local-build` branch. Tick items off in the same commit as the fix.

## Broken on device

- [ ] **File browser copy / cut / move / rename do nothing.** `FileManager:moveFile`, `copyFileFromTo` and `copyRecursive` (`frontend/apps/filemanager/filemanager.lua:1300-1315`) run `/bin/mv` and `/bin/cp` through `ffiUtil.execute` (`base/ffi/util.lua:275`), which uses `fork()` + `execl`. iOS allows neither, and those binaries don't exist there. Delete still works (`os.remove`, `ffiUtil.purgeDir`).
  Fix idea: when `KO_IOS == "1"`, use `os.rename` for move/rename, with a copy-then-delete fallback for moves across file providers (cloud folders added with `iosfilepicker`), and a Lua read/write loop for copy (walking directories with `lfs` for recursive copy).
- [ ] **Audit other uses of `ffiUtil.execute`, `os.execute` and `io.popen`** in frontend and bundled plugins. Each fails on iOS the same way. Hide, stub or rewrite them in Lua.

- [ ] **The iOS keyboard always auto-capitalizes and autocorrects,** which is wrong for usernames, passwords and URLs. `S.startTextInput` (`base/ffi/SDL3.lua:195`) calls plain `SDL_StartTextInput`, so iOS uses its defaults: capitalize sentences, autocorrect on.
  Fix idea: switch to `SDL_StartTextInputWithProperties` with `SDL_PROP_TEXTINPUT_CAPITALIZATION_NUMBER = SDL_CAPITALIZE_NONE` and `SDL_PROP_TEXTINPUT_AUTOCORRECT_BOOLEAN = false` by default. Better still, pass a type hint from `InputText` (`frontend/ui/widget/inputtext.lua`, `Device:startTextInput()` calls) so password fields get `SDL_TEXTINPUT_TYPE_TEXT_PASSWORD_HIDDEN`, and URL and username fields get their own types; prose fields such as notes could keep smart capitalization. Needs the properties API declared in `base/ffi/SDL3_h.lua`.

- [x] **Settings pointed at an old data container after reinstalling.** iOS can move the app's data container (`/var/mobile/Containers/Data/Application/<UUID>/`) when the app is reinstalled or updated, and KOReader stores absolute paths. The result was that user plugins (Bookshelf) stopped loading, because `extra_plugin_paths` was stale, and home_dir, lastdir and history were broken. Fixed by `frontend/device/sdl/ios_container.lua`, which `reader.lua` runs at startup: it rewrites the container UUID in `settings.reader.lua`, `history.lua` and `settings/**/*.lua` whenever the container differs from the one recorded in `settings/.ios_container_id`.
- [ ] The same container move leaves other stored paths stale: the cover browser's `settings/bookinfo_cache.sqlite3` is keyed by directory, so every cover gets re-extracted and old rows pile up; and the `doc_path` in each book's `.sdr` sidecar. Consider an SQL `UPDATE` in the migration.

- [ ] **Dialogs end up behind the native keyboard,** e.g. the add-OPDS dialog's buttons. KOReader moves dialogs above its *own* on-screen keyboard but can't see the height of the iOS keyboard. Idea: a small native function in `platform/ios/` (like `ko_ios_get_safe_area_pixels`) that watches `UIKeyboardWillChangeFrameNotification` and reports the keyboard's top edge in pixels, read from Lua through FFI. `InputDialog` and friends would then position themselves above it. That works on iPhone and iPad, and is better than hezi/koreader-ios#4's overlay "Hide keyboard" button: that button hides the keyboard through UIKit behind SDL's and KOReader's backs, so KOReader still thinks the field is being edited.

## Updating to current upstream

- [x] Rebased onto v2026.07.2 (2026-11-13). Before that, the port was about 7 months behind. Frontend: forked from upstream `240f591d3` (2026-04-24), and upstream master is 558 commits ahead (checked 2026-11-13; latest release v2026.07.2). Base: forked from `656dbec1` (2026-04-23), and the base commit upstream master pins (`f64c3eb1`) is 369 commits ahead.
- [ ] Make updating repeatable: keep the iOS changes as a short patch series on each repo and rebase it onto upstream (or onto a release tag), with a script that does the fetch, rebase, submodule pointer update and build.

## Third-party plugins

- [ ] **Bookshelf (AndyHazz/bookshelf.koplugin, v6.4.2):** its in-app updater (`lib/bookshelf_updater.lua`, `os.execute`) won't work. For now, update it by hand by replacing `Documents/plugins/bookshelf.koplugin`.
  - Hardcover's `io.popen` (`lib/bookshelf_hardcover.lua:443-455`) runs `unzip` to read an EPUB's OPF for identifiers. That's not a `curl` call. It could use base's in-process `ffi/archiver` instead, with no native code needed.
  - `lib/bookshelf_http.lua` only falls back to `curl` when LuaSocket/LuaSec fails, so that fallback may never be reached on iOS. Check before building a native HTTP bridge for it.

## Open from the fork / upstream

- [x] Applied the `SDL_EVENT_FINGER_CANCELED` handling from `hezi/koreader-base-ios#1`, the base companion to PR #12 (base `3b2d631c`). Skipped from that PR: the home-indicator hint (already set in `ios_loader.m`), the HiDPI framebuffer change (not needed on iPad; try it if iPhone renders blurry), and the libarchive zstd switch (not needed so far).
- [ ] Release (non-Debug) builds fail (open issue on hezi/koreader-ios).
- [x] Custom fonts (open issue on hezi/koreader-ios): `.ttf`/`.otf` files in the app's `Documents/fonts` (Files app: On My iPad → KOReader → fonts) are now scanned. Restart KOReader after adding fonts.
- [ ] No button to hide the on-screen keyboard (open issue on hezi/koreader-ios).

## Build and signing

- [x] Team and bundle id now come from `platform/ios/local.config` (git-ignored), so `make TARGET=ios xcodeproj` keeps them. `platform/ios/deploy.sh` builds, signs, installs and launches on a connected device in one command.
- [x] Fixed by rebasing onto the v2026.07.2 tag: the version is now `v2026.07.2-<n>-g<hash>`. Old problem: the build had no release tag, so KOReader reported no version: `git-rev` is a bare hash and the app version falls back to `0.0.<commit count>`. Plugins that gate on the KOReader version see "unknown". Consider a fake tag such as `v2026.04-ios`.

## Known limits (probably won't fix)

- Terminal and SSH plugins can't work (they need `fork()`).
- PDF reflow (libk2pdfopt) is disabled in the fork.
- Signed with a paid developer account (1-year profiles), so an iCloud container entitlement is available if wanted.
