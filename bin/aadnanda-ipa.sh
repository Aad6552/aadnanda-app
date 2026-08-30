#!/usr/bin/env bash
set -euo pipefail

# Aad Nanda — iOS IPA builder + publisher
# --------------------------------------
# Builds a release IPA of the aadnanda.com Flutter webview app, moves it to
# ~/Documents/GitHub/ipa/aadnanda.ipa, and publishes it to a single rolling
# GitHub release ("ios-latest") that ALWAYS holds just the newest build — no
# per-version releases pile up.
#
# Stable download URLs:
#   https://github.com/Aad6552/aadnanda-app/releases/latest
#   https://github.com/Aad6552/aadnanda-app/releases/download/ios-latest/aadnanda.ipa
#
# Version bumping lives in bin/bump-version.sh. This script calls it when the
# working tree has uncommitted changes (or when you pass --bump / --version /
# --no-bump); a clean tree just rebuilds the current version.
#
# Common runs:
#   ./bin/aadnanda-ipa.sh
#   ./bin/aadnanda-ipa.sh --quick
#   ./bin/aadnanda-ipa.sh --bump patch
#   ./bin/aadnanda-ipa.sh --no-github-release      # build + commit only, no upload
#   ./bin/aadnanda-ipa.sh --prune-old             # one-time: delete old aadnanda-v* releases/tags
#   ./bin/aadnanda-ipa.sh --delete

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/bin"
PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
IPA_OUTPUT_DIR="$HOME/Documents/GitHub/ipa"
APP_NAME="Aad Nanda"
IPA_BUILD_DIR="$ROOT_DIR/build/ios/ipa"
IPA_FINAL_PATH="$IPA_OUTPUT_DIR/aadnanda.ipa"
GITHUB_REPO="Aad6552/aadnanda-app"
RELEASE_TAG="ios-latest"
RELEASE_TITLE="Aad Nanda — iOS (latest)"

GITHUB_RELEASE="true"
GIT_COMMIT="true"
GIT_PUSH="true"
SKIP_CLEAN="false"
DELETE_ONLY="false"
PRUNE_OLD="false"

usage() {
  cat <<'USAGE'
Aad Nanda — iOS IPA builder + publisher for the aadnanda.com webview app.

Builds the IPA and publishes it to one rolling GitHub release ("ios-latest")
that always holds only the newest build.

Usage:
  ./bin/aadnanda-ipa.sh [options]

Examples:
  ./bin/aadnanda-ipa.sh
  ./bin/aadnanda-ipa.sh --quick
  ./bin/aadnanda-ipa.sh --bump patch
  ./bin/aadnanda-ipa.sh --no-github-release
  ./bin/aadnanda-ipa.sh --prune-old
  ./bin/aadnanda-ipa.sh --delete

Options:
  --version X.Y.Z+B     Force a version (passed to bump-version.sh)
  --bump patch|minor|major|build
  --no-bump             Build the current version, don't bump
  --delete              Delete the local IPA and exit (no build)
  --repo OWNER/REPO     Override GitHub repo (default: Aad6552/aadnanda-app)
  --github-release      Publish the IPA to the rolling "ios-latest" release (default)
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

delete_old_ipa() {
  if [[ -f "$IPA_FINAL_PATH" ]]; then
    echo "Deleting old IPA: $IPA_FINAL_PATH"
    rm -f "$IPA_FINAL_PATH"
  fi
}

build_ipa() {
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

  echo ""
  echo "Building IPA..."
  rm -rf "$IPA_BUILD_DIR"
  flutter build ipa --release --export-method development

  local built_ipa
  built_ipa="$(find "$IPA_BUILD_DIR" -maxdepth 1 -name '*.ipa' -print -quit 2>/dev/null || true)"
  [[ -n "$built_ipa" && -f "$built_ipa" ]] || {
    echo "Error: no IPA found in $IPA_BUILD_DIR" >&2
    exit 1
  }

  echo ""
  echo "Moving IPA to $IPA_FINAL_PATH..."
  mkdir -p "$IPA_OUTPUT_DIR"
  mv -f "$built_ipa" "$IPA_FINAL_PATH"

  [[ -f "$IPA_FINAL_PATH" ]] || { echo "Error: failed to move IPA to $IPA_FINAL_PATH" >&2; exit 1; }
}

# Publish the IPA to ONE rolling release. Deletes the previous release and
# re-points the "ios-latest" tag at the current commit, so the release page
# only ever shows the newest build.
publish_latest_ipa() {
  require_gh
  require_git
  cd "$ROOT_DIR"

  local sha notes
  sha="$(git rev-parse --short HEAD)"
  notes="$APP_NAME iOS — version $VERSION
Built $(date '+%Y-%m-%d %H:%M %Z') from commit $sha.
This release always holds the latest build; older builds are not kept."

  echo "Moving rolling tag $RELEASE_TAG to $sha..."
  git tag -f "$RELEASE_TAG" >/dev/null
  git push -f origin "$RELEASE_TAG"

  if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    echo "Removing previous $RELEASE_TAG release..."
    gh release delete "$RELEASE_TAG" --repo "$GITHUB_REPO" --yes
  fi

  gh release create "$RELEASE_TAG" "$IPA_FINAL_PATH" \
    --repo "$GITHUB_REPO" \
    --title "$RELEASE_TITLE" \
    --notes "$notes" \
    --latest
  echo "GitHub: published $VERSION to $RELEASE_TAG"
  echo "  https://github.com/$GITHUB_REPO/releases/download/$RELEASE_TAG/$(basename "$IPA_FINAL_PATH")"
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

if [[ "$DELETE_ONLY" == "true" ]]; then
  delete_old_ipa
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
echo "  $APP_NAME — IPA Builder"
echo "  Site: https://aadnanda.com"
echo "════════════════════════════════════════"
echo "Version: $VERSION"
echo "════════════════════════════════════════"
echo ""

delete_old_ipa
build_ipa

if [[ "$GIT_PUSH" == "true" ]]; then
  git_push_branch
fi

if [[ "$GITHUB_RELEASE" == "true" ]]; then
  publish_latest_ipa
fi

echo ""
echo "════════════════════════════════════════"
echo "  Done!"
echo "════════════════════════════════════════"
echo "Version:    $VERSION"
echo "Built IPA:  $IPA_FINAL_PATH"
[[ "$GITHUB_RELEASE" == "true" ]] && echo "Release:    https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
echo "════════════════════════════════════════"
echo ""
