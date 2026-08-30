#!/usr/bin/env bash
set -euo pipefail

# Aad Nanda — Android APK/AAB builder
# ----------------------------------
# Builds a release APK (or AAB) of the aadnanda.com Flutter webview app and
# moves it to ~/Documents/GitHub/apk/aadnanda.apk (or .aab).
#
# Version bumping lives in bin/bump-version.sh. This script calls it when the
# working tree has uncommitted changes (or when you pass --bump / --version /
# --no-bump); a clean tree just rebuilds the current version.
#
# Pair with bin/aadnanda-ipa.sh: run one, then run the other on the (now clean)
# tree so both artifacts share a version and tag.
#
# Common runs:
#   ./bin/aadnanda-apk.sh
#   ./bin/aadnanda-apk.sh --aab
#   ./bin/aadnanda-apk.sh --quick
#   ./bin/aadnanda-apk.sh --bump patch
#   ./bin/aadnanda-apk.sh --bump minor --github-release
#   ./bin/aadnanda-apk.sh --no-git-commit --no-push
#   ./bin/aadnanda-apk.sh --delete

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
APK_OUTPUT_DIR="$HOME/Documents/GitHub/apk"
APP_NAME="Aad Nanda"
GITHUB_REPO="Aad6552/aadnanda-app"
TAG_PREFIX="aadnanda-v"

BUILD_TYPE="apk"
GITHUB_RELEASE="false"
GIT_COMMIT="true"
GIT_PUSH="true"
SKIP_CLEAN="false"
DELETE_ONLY="false"

usage() {
  cat <<'USAGE'
Aad Nanda — Android APK/AAB builder for the aadnanda.com webview app.

Usage:
  ./bin/aadnanda-apk.sh [options]

Examples:
  ./bin/aadnanda-apk.sh
  ./bin/aadnanda-apk.sh --aab
  ./bin/aadnanda-apk.sh --quick
  ./bin/aadnanda-apk.sh --bump patch
  ./bin/aadnanda-apk.sh --bump minor --github-release
  ./bin/aadnanda-apk.sh --no-git-commit --no-push
  ./bin/aadnanda-apk.sh --delete

Options:
  --aab                 Build an Android App Bundle instead of an APK
  --version X.Y.Z+B     Force a version (passed to bump-version.sh)
  --bump patch|minor|major|build
  --no-bump             Build the current version, don't bump
  --delete              Delete old APK/AAB and exit (no build)
  --repo OWNER/REPO     Override GitHub repo (default: Aad6552/aadnanda-app)
  --github-release      Create/update a GitHub release and upload the artifact
  --no-github-release   (default)
  --git-commit          Let bump-version.sh commit the bump (default)
  --no-git-commit       Rewrite pubspec.yaml only, don't commit
  --push                Push commit + tag to origin (default)
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
  command -v gh >/dev/null 2>&1 || { echo "Error: GitHub CLI is required. Install with: brew install gh" >&2; exit 1; }
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

git_create_tag() {
  require_git
  cd "$ROOT_DIR"
  local tag="$TAG_PREFIX$VERSION"

  if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "Git: tag already exists: $tag"
  else
    git tag "$tag"
    echo "Git: created tag $tag"
  fi
}

git_push_release() {
  require_git
  cd "$ROOT_DIR"

  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"

  git push origin "$current_branch"
  git push origin "$TAG_PREFIX$VERSION"
  echo "Git: pushed $current_branch and tag $TAG_PREFIX$VERSION"
}

publish_github_release() {
  require_gh

  local tag="$TAG_PREFIX$VERSION"
  local title="$APP_NAME $VERSION"

  if gh release view "$tag" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    gh release upload "$tag" "$ARTIFACT_FINAL_PATH" --repo "$GITHUB_REPO" --clobber
    echo "GitHub: uploaded $(basename "$ARTIFACT_FINAL_PATH") to existing release $tag"
  else
    gh release create "$tag" "$ARTIFACT_FINAL_PATH" \
      --repo "$GITHUB_REPO" \
      --title "$title" \
      --notes "$APP_NAME Android release $VERSION"
    echo "GitHub: created release $tag and uploaded $(basename "$ARTIFACT_FINAL_PATH")"
  fi
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
  git_create_tag
  git_push_release
fi

if [[ "$GITHUB_RELEASE" == "true" ]]; then
  git_create_tag
  publish_github_release
fi

echo ""
echo "════════════════════════════════════════"
echo "  Done!"
echo "════════════════════════════════════════"
echo "Version:        $VERSION"
echo "Built artifact: $ARTIFACT_FINAL_PATH"
echo "════════════════════════════════════════"
echo ""
