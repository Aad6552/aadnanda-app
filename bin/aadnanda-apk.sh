#!/usr/bin/env bash
set -euo pipefail

# Aad Nanda — Android APK/AAB builder + publisher
# ----------------------------------------------
# Builds a release APK (or AAB) of the aadnanda.com Flutter webview app, moves
# it to ~/Documents/GitHub/apk/aadnanda.apk (or .aab), and publishes it to a
# single rolling GitHub release ("android-latest") that ALWAYS holds just the
# newest build — no per-version releases pile up.
#
# Stable download URL:
#   https://github.com/Aad6552/aadnanda-app/releases/download/android-latest/aadnanda.apk
#
# Version bumping lives in bin/bump-version.sh. This script calls it when the
# working tree has uncommitted changes (or when you pass --bump / --version /
# --no-bump); a clean tree just rebuilds the current version.
#
# Pair with bin/aadnanda-ipa.sh: run one, then run the other on the (now clean)
# tree so both artifacts share a version.
#
# Common runs:
#   ./bin/aadnanda-apk.sh
#   ./bin/aadnanda-apk.sh --aab
#   ./bin/aadnanda-apk.sh --quick
#   ./bin/aadnanda-apk.sh --bump patch
#   ./bin/aadnanda-apk.sh --no-github-release
#   ./bin/aadnanda-apk.sh --prune-old
#   ./bin/aadnanda-apk.sh --delete

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
APK_OUTPUT_DIR="$HOME/Documents/GitHub/apk"
APP_NAME="Aad Nanda"
GITHUB_REPO="Aad6552/aadnanda-app"
RELEASE_TAG="android-latest"
RELEASE_TITLE="Aad Nanda — Android (latest)"

BUILD_TYPE="apk"
GITHUB_RELEASE="true"
GIT_COMMIT="true"
GIT_PUSH="true"
SKIP_CLEAN="false"
DELETE_ONLY="false"
PRUNE_OLD="false"

usage() {
  cat <<'USAGE'
Aad Nanda — Android APK/AAB builder + publisher for the aadnanda.com webview app.

Builds the APK/AAB and publishes it to one rolling GitHub release
("android-latest") that always holds only the newest build.

Usage:
  ./bin/aadnanda-apk.sh [options]

Examples:
  ./bin/aadnanda-apk.sh
  ./bin/aadnanda-apk.sh --aab
  ./bin/aadnanda-apk.sh --quick
  ./bin/aadnanda-apk.sh --bump patch
  ./bin/aadnanda-apk.sh --no-github-release
  ./bin/aadnanda-apk.sh --prune-old
  ./bin/aadnanda-apk.sh --delete

Options:
  --aab                 Build an Android App Bundle instead of an APK
  --version X.Y.Z+B     Force a version (passed to bump-version.sh)
  --bump patch|minor|major|build
  --no-bump             Build the current version, don't bump
  --delete              Delete the local APK/AAB and exit (no build)
  --repo OWNER/REPO     Override GitHub repo (default: Aad6552/aadnanda-app)
  --github-release      Publish to the rolling "android-latest" release (default)
  --no-github-release   Build + commit only, don't touch GitHub releases
  --prune-old           Delete leftover per-version aadnanda-v* releases/tags, then exit
  --git-commit          Let bump-version.sh commit the bump (default)
  --no-git-commit       Rewrite pubspec.yaml only, don't commit
  --push                Push the branch to origin (default)
  --no-push             Skip the git push
  --quick               Skip flutter clean (faster rebuild)
  --help

Version bump: with no --version/--bump/--no-bump, bump-version.sh runs its
interactive menu whenever the working tree is dirty; a clean tree builds the
current version untouched.
USAGE
}

get_version() {
  awk '/^version:/ {print $2}' "$PUBSPEC_FILE"
}

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
    echo "Error: version must use X.Y.Z+B format, example 1.0.0+1" >&2
    exit 1
  fi
}

require_files() {
  [[ -f "$PUBSPEC_FILE" ]] || { echo "Error: missing pubspec.yaml at $PUBSPEC_FILE" >&2; exit 1; }
  [[ -x "$BIN_DIR/bump-version.sh" ]] || { echo "Error: missing bin/bump-version.sh" >&2; exit 1; }
  command -v flutter >/dev/null 2>&1 || { echo "Error: flutter command is required" >&2; exit 1; }
}

require_git() {
  command -v git >/dev/null 2>&1 || { echo "Error: git command is required" >&2; exit 1; }
  git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: $ROOT_DIR is not a git repository" >&2
    exit 1
  }
}

require_gh() {
  command -v gh >/dev/null 2>&1 || {
    echo "Error: GitHub CLI is required to publish. Install with 'brew install gh', or pass --no-github-release." >&2
    exit 1
  }
  gh auth status >/dev/null 2>&1 || { echo "Error: GitHub CLI is not logged in. Run: gh auth login" >&2; exit 1; }
}

working_tree_dirty() {
  [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]
}

git_sync_branch() {
  require_git
  cd "$ROOT_DIR"
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  echo "Git: syncing $branch with origin (pull --rebase)..."
  if ! git pull --rebase origin "$branch"; then
    echo "Warning: 'git pull --rebase origin $branch' failed — continuing with local state." >&2
  fi
}

git_push_branch() {
  require_git
  cd "$ROOT_DIR"
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git push origin "$branch"
  echo "Git: pushed $branch"
}

delete_old_artifact() {
  for ext in apk aab; do
    if [[ -f "$APK_OUTPUT_DIR/aadnanda.$ext" ]]; then
      echo "Deleting old artifact: $APK_OUTPUT_DIR/aadnanda.$ext"
      rm -f "$APK_OUTPUT_DIR/aadnanda.$ext"
    fi
  done
}

build_artifact() {
  echo ""
  if [[ "$SKIP_CLEAN" == "true" ]]; then
    echo "Skipping flutter clean (--quick)..."
  else
    echo "Cleaning..."
    flutter clean
  fi

  echo ""
  echo "Getting dependencies..."
  flutter pub get

  echo ""
  echo "Generating app icons..."
  dart run flutter_launcher_icons >/dev/null 2>&1 || \
    flutter pub run flutter_launcher_icons >/dev/null 2>&1 || \
    echo "Warning: flutter_launcher_icons step skipped"

  local src
  if [[ "$BUILD_TYPE" == "aab" ]]; then
    echo ""
    echo "Building AAB..."
    flutter build appbundle --release
    src="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
  else
    echo ""
    echo "Building APK..."
    flutter build apk --release
    src="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
  fi

  [[ -f "$src" ]] || { echo "Error: artifact not found at $src" >&2; exit 1; }

  echo ""
  echo "Moving artifact to $ARTIFACT_FINAL_PATH..."
  mkdir -p "$APK_OUTPUT_DIR"
  cp -f "$src" "$ARTIFACT_FINAL_PATH"

  [[ -f "$ARTIFACT_FINAL_PATH" ]] || { echo "Error: failed to copy artifact to $ARTIFACT_FINAL_PATH" >&2; exit 1; }
}

# Publish the artifact to ONE rolling release. Deletes the previous release and
# re-points the "android-latest" tag at the current commit, so the release page
# only ever shows the newest build.
publish_latest_artifact() {
  require_gh
  require_git
  cd "$ROOT_DIR"

  local sha notes
  sha="$(git rev-parse --short HEAD)"
  notes="$APP_NAME Android — version $VERSION ($BUILD_TYPE)
Built $(date '+%Y-%m-%d %H:%M %Z') from commit $sha.
This release always holds the latest build; older builds are not kept."

  echo "Moving rolling tag $RELEASE_TAG to $sha..."
  git tag -f "$RELEASE_TAG" >/dev/null
  git push -f origin "$RELEASE_TAG"

  if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    echo "Removing previous $RELEASE_TAG release..."
    gh release delete "$RELEASE_TAG" --repo "$GITHUB_REPO" --yes
  fi

  gh release create "$RELEASE_TAG" "$ARTIFACT_FINAL_PATH" \
    --repo "$GITHUB_REPO" \
    --title "$RELEASE_TITLE" \
    --notes "$notes"
  echo "GitHub: published $VERSION to $RELEASE_TAG"
  echo "  https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$(basename "$ARTIFACT_FINAL_PATH")"
}

# One-time cleanup of the old per-version scheme.
prune_old_releases() {
  require_gh
  require_git
  cd "$ROOT_DIR"

  echo "Pruning old per-version releases and tags (aadnanda-v*)..."
  local t
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    case "$t" in
      aadnanda-v*)
        echo "  release $t"
        gh release delete "$t" --repo "$GITHUB_REPO" --yes --cleanup-tag || true
        ;;
    esac
  done < <(gh release list --repo "$GITHUB_REPO" --limit 200 --json tagName -q '.[].tagName' 2>/dev/null || true)

  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    echo "  tag $t"
    git push origin ":refs/tags/$t" 2>/dev/null || true
    git tag -d "$t" 2>/dev/null || true
  done < <(git tag -l 'aadnanda-v*')

  echo "Prune complete."
}

VERSION_OVERRIDE=""
BUMP_PART=""
NO_BUMP="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aab) BUILD_TYPE="aab"; shift ;;
    --version) VERSION_OVERRIDE="${2:-}"; shift 2 ;;
    --bump) BUMP_PART="${2:-}"; shift 2 ;;
    --no-bump) NO_BUMP="true"; shift ;;
    --delete) DELETE_ONLY="true"; shift ;;
    --prune-old) PRUNE_OLD="true"; shift ;;
    --repo) GITHUB_REPO="${2:-}"; shift 2 ;;
    --github-release) GITHUB_RELEASE="true"; shift ;;
    --no-github-release) GITHUB_RELEASE="false"; shift ;;
    --git-commit) GIT_COMMIT="true"; shift ;;
    --no-git-commit) GIT_COMMIT="false"; shift ;;
    --push) GIT_PUSH="true"; shift ;;
    --no-push) GIT_PUSH="false"; shift ;;
    --quick) SKIP_CLEAN="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Error: unknown option $1" >&2; usage; exit 1 ;;
  esac
done

ARTIFACT_FINAL_PATH="$APK_OUTPUT_DIR/aadnanda.$BUILD_TYPE"

if [[ "$DELETE_ONLY" == "true" ]]; then
  delete_old_artifact
  exit 0
fi

if [[ "$PRUNE_OLD" == "true" ]]; then
  require_git
  prune_old_releases
  exit 0
fi

require_files
require_git

# --quick with no explicit version instruction => non-interactive patch bump
if [[ "$SKIP_CLEAN" == "true" ]]; then
  [[ -z "$VERSION_OVERRIDE" && -z "$BUMP_PART" && "$NO_BUMP" == "false" ]] && BUMP_PART="patch"
fi

CURRENT_VERSION="$(get_version)"
validate_version "$CURRENT_VERSION"

# ── Version bump (delegated to bin/bump-version.sh) ───────────────────────────
# Run it when an explicit version instruction was given, or when the working
# tree is dirty. A clean tree with no flags builds the current version as-is.
RUN_BUMP="false"
if [[ -n "$VERSION_OVERRIDE" || -n "$BUMP_PART" || "$NO_BUMP" == "true" ]]; then
  RUN_BUMP="true"
elif working_tree_dirty; then
  echo "Uncommitted changes detected — running bump-version.sh"
  RUN_BUMP="true"
else
  echo "Working tree clean and no --bump/--version — building current version $CURRENT_VERSION"
fi

if [[ "$RUN_BUMP" == "true" ]]; then
  BUMP_ARGS=()
  [[ -n "$VERSION_OVERRIDE" ]] && BUMP_ARGS+=(--version "$VERSION_OVERRIDE")
  [[ -n "$BUMP_PART" ]] && BUMP_ARGS+=(--bump "$BUMP_PART")
  [[ "$NO_BUMP" == "true" ]] && BUMP_ARGS+=(--no-bump)
  [[ "$GIT_COMMIT" == "true" ]] || BUMP_ARGS+=(--no-commit)
  "$BIN_DIR/bump-version.sh" ${BUMP_ARGS[@]+"${BUMP_ARGS[@]}"}
fi

VERSION="$(get_version)"
validate_version "$VERSION"

# Sync the (now clean) branch so the release commit rebases onto origin's tip.
if [[ "$GIT_COMMIT" == "true" || "$GIT_PUSH" == "true" ]]; then
  git_sync_branch
fi

echo ""
echo "════════════════════════════════════════"
echo "  $APP_NAME — Android Builder"
echo "  Site: https://aadnanda.com"
echo "  Type: $BUILD_TYPE"
echo "════════════════════════════════════════"
echo "Version: $VERSION"
echo "════════════════════════════════════════"
echo ""

delete_old_artifact
build_artifact

if [[ "$GIT_PUSH" == "true" ]]; then
  git_push_branch
fi

if [[ "$GITHUB_RELEASE" == "true" ]]; then
  publish_latest_artifact
fi

echo ""
echo "════════════════════════════════════════"
echo "  Done!"
echo "════════════════════════════════════════"
echo "Version:        $VERSION"
echo "Built artifact: $ARTIFACT_FINAL_PATH"
[[ "$GITHUB_RELEASE" == "true" ]] && echo "Release:        https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
echo "════════════════════════════════════════"
echo ""
