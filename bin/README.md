# bin/

Build + release scripts for the Aad Nanda iOS app.

## `aadnanda-ipa.sh`

Builds a release IPA of the aadnanda.com webview app, moves it to
`~/Documents/GitHub/ipa/aadnanda.ipa`, then (by default) commits the
version bump and pushes it to GitHub (`Aad6552/aadnanda-app`).

```bash
./bin/aadnanda-ipa.sh                 # interactive version menu, build, commit, push
./bin/aadnanda-ipa.sh --bump patch    # non-interactive patch bump
./bin/aadnanda-ipa.sh --quick         # skip `flutter clean`, auto patch bump
./bin/aadnanda-ipa.sh --bump minor --github-release   # also publish a GitHub release with the IPA
./bin/aadnanda-ipa.sh --no-git-commit --no-push       # build only
./bin/aadnanda-ipa.sh --delete        # remove the old IPA and exit
```

Run `./bin/aadnanda-ipa.sh --help` for the full option list.

### Requirements

- `flutter` on `PATH` (Xcode + a configured signing identity for `--export-method development`)
- `git` (for the default commit/push)
- `gh`, authenticated, only when using `--github-release`

### What it does

1. `git pull --rebase origin <branch>` so your commit lands on the tip of the
   shared branch (you're a collaborator on Aad's `main`). Skipped with
   `--no-git-commit --no-push`.
2. Bumps `version:` in `pubspec.yaml` (menu, `--bump`, `--version`, or `--no-bump`).
3. Commits the bump as `Release Aad Nanda X.Y.Z+B`.
4. `flutter clean` (unless `--quick`) → `flutter pub get` → regenerate launcher icons.
5. `flutter build ipa --release --export-method development`.
6. Moves the built IPA to `~/Documents/GitHub/ipa/aadnanda.ipa`.
7. Tags `aadnanda-vX.Y.Z+B` and pushes the commit + tag to `origin`.
8. With `--github-release`, creates/updates the matching GitHub release and uploads the IPA.

Order is: **bump → commit → build → tag/push**. If the build fails, the bump
commit is already made locally but nothing has been pushed — fix and re-run,
or `git commit --amend` / `git reset --soft HEAD~1`.
