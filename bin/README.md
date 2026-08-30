# bin/

Build + release scripts for the Aad Nanda app (`aadnanda.com` webview).

| script | what it does | output |
|---|---|---|
| `bump-version.sh` | resolve next version → write `pubspec.yaml` → commit `Release Aad Nanda X.Y.Z+B` | — |
| `aadnanda-ipa.sh` | (bump if needed) → build iOS IPA → push → publish to the rolling `ios-latest` release | `~/Documents/GitHub/ipa/aadnanda.ipa` |
| `aadnanda-apk.sh` | (bump if needed) → build Android APK/AAB → push → publish to the rolling `android-latest` release | `~/Documents/GitHub/apk/aadnanda.apk` / `.aab` |

### Rolling GitHub release — always just the latest

Each build publishes to **one** GitHub release per platform and replaces
whatever was there. No per-version releases or tags accumulate.

- iOS:     `https://github.com/Aad6552/aadnanda-app/releases/download/ios-latest/aadnanda.ipa`
- Android: `https://github.com/Aad6552/aadnanda-app/releases/download/android-latest/aadnanda.apk`
- newest overall: `https://github.com/Aad6552/aadnanda-app/releases/latest`

Publishing is **on by default**; pass `--no-github-release` to skip it. It needs
`gh` installed and `gh auth login` done.

`--prune-old` (run once) deletes any leftover `aadnanda-v*` per-version releases
and tags from the earlier scheme, then exits.

## `bump-version.sh`

The single home for version logic. Run it directly, or let the build scripts
call it.

```bash
./bin/bump-version.sh                 # interactive menu
./bin/bump-version.sh --bump patch    # 1.2.3+7 -> 1.2.4+8
./bin/bump-version.sh --bump build    # 1.2.3+7 -> 1.2.3+8  (build number only)
./bin/bump-version.sh --version 1.3.0+10
./bin/bump-version.sh --no-bump       # keep the version, still commit the tree
./bin/bump-version.sh --no-commit     # rewrite pubspec.yaml only
./bin/bump-version.sh --bump patch --push
```

The commit stages tracked changes plus new files, skipping build artifacts
(`*.ipa`, `*.apk`, `*.aab`, `*.zip`, `build/`, `Podfile.lock`).

## `aadnanda-ipa.sh` / `aadnanda-apk.sh`

Same options on both (`--apk` script adds `--aab`):

```bash
./bin/aadnanda-ipa.sh                 # bump-if-dirty, build, push, publish rolling release
./bin/aadnanda-apk.sh --aab           # build an .aab instead of an .apk
./bin/aadnanda-ipa.sh --bump patch    # force a patch bump, non-interactive
./bin/aadnanda-apk.sh --quick         # skip `flutter clean` (implies patch bump)
./bin/aadnanda-ipa.sh --no-github-release             # build + commit + push only
./bin/aadnanda-ipa.sh --no-git-commit --no-push       # build only
./bin/aadnanda-ipa.sh --delete        # remove the local artifact and exit
```

### When does it bump the version?

| situation | behavior |
|---|---|
| `--bump` / `--version` / `--no-bump` given | runs `bump-version.sh` with that instruction |
| no flag, **working tree dirty** | runs `bump-version.sh` interactively (uncommitted changes = something to release) |
| no flag, **working tree clean** | no bump — rebuilds the current version as-is |
| `--quick`, no flag | forces a non-interactive `patch` bump |

**Building IPA + APK for one release:** run whichever first (it bumps + commits,
leaving the tree clean), then run the other — it sees a clean tree, skips the
bump, and builds the same version.

```bash
./bin/aadnanda-ipa.sh --bump patch
./bin/aadnanda-apk.sh            # clean tree -> same version, no second bump
```

### Order of operations

1. `bump-version.sh` runs if needed (bump `pubspec.yaml`, commit the tree).
2. `git pull --rebase origin <branch>` — rebases the fresh commit onto origin's
   tip (you're a collaborator on Aad's `main`).
3. `flutter clean` (unless `--quick`) → `flutter pub get` → regenerate launcher icons.
4. Build the IPA / APK / AAB.
5. Copy the artifact into `~/Documents/GitHub/{ipa,apk}/`.
6. Push the branch to `origin` (unless `--no-push`).
7. Publish (unless `--no-github-release`): force-move the `ios-latest` /
   `android-latest` tag to `HEAD`, delete the old release, create a fresh one
   with the new artifact attached.

If the build fails after a bump, the commit is local only — nothing was pushed.
Fix and re-run, or `git reset --soft HEAD~1`.

### Requirements

- `flutter` on `PATH`
  - iOS: Xcode + a signing identity (`flutter build ipa --export-method development`)
  - Android: a release signing config, or it falls back to debug keys
- `git` — you have collaborator write access to `Aad6552/aadnanda-app`, so a
  plain `git push origin main` works; make sure your git credential helper is
  set up for that repo (or use an SSH remote)
- `gh`, installed + `gh auth login` — needed for the default publish step
  (`--no-github-release` removes that requirement)

## Generated / build files in `git status`

The first `flutter build` on a fresh clone touches a batch of files.

**Ignored** (`.gitignore`) — regenerated per machine, never committed:

- `ios/Podfile.lock`, `macos/Podfile.lock`
- `*.ipa`, `*.apk`, `*.aab` — the built artifacts live in `~/Documents/GitHub/`
- `build/`, `.dart_tool/`, `ios/Pods/`, `ios/Flutter/Generated.xcconfig`, etc.
  — already ignored by the stock Flutter `.gitignore` files

**Tracked — commit once, then stable** (real project files; the initial diff is
a one-time CocoaPods / dependency integration):

- `pubspec.lock`
- `ios/Podfile`, `macos/Podfile`
- `ios/Flutter/Debug.xcconfig`, `ios/Flutter/Release.xcconfig`
- `macos/Flutter/Flutter-Debug.xcconfig`, `macos/Flutter/Flutter-Release.xcconfig`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner.xcworkspace/contents.xcworkspacedata`

Do **not** untrack `project.pbxproj` / the `.xcconfig` files — collaborators
need them to build. Commit the one-time diff:

```bash
git add ios/ macos/ pubspec.lock
git commit -m "chore: CocoaPods integration for webview_flutter"
git push
```

If a run committed `ios/Podfile.lock` before it was ignored:

```bash
git rm --cached ios/Podfile.lock macos/Podfile.lock 2>/dev/null
git commit -m "chore: stop tracking Podfile.lock"
git push
```
