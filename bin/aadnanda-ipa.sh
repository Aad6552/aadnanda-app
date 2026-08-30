#!/usr/bin/env bash
set -euo pipefail

# Aad Nanda — iOS IPA builder
# ---------------------------
# Builds a release IPA of the aadnanda.com Flutter webview app,
# moves it to ~/Documents/GitHub/ipa/aadnanda.ipa, then (by default)
# commits the version bump to git and pushes to GitHub.
#
# Common runs:
#   ./bin/aadnanda-ipa.sh
#   ./bin/aadnanda-ipa.sh --quick
#   ./bin/aadnanda-ipa.sh --bump patch
#   ./bin/aadnanda-ipa.sh --bump minor --github-release
#   ./bin/aadnanda-ipa.sh --no-git-commit --no-push
#   ./bin/aadnanda-ipa.sh --delete

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
IPA_OUTPUT_DIR="$HOME/Documents/GitHub/ipa"
APP_NAME="Aad Nanda"
IPA_BUILD_DIR="$ROOT_DIR/build/ios/ipa"
IPA_FINAL_PATH="$IPA_OUTPUT_DIR/aadnanda.ipa"
GITHUB_REPO="Aad6552/aadnanda-app"
TAG_PREFIX="aadnanda-v"

GITHUB_RELEASE="false"
GIT_COMMIT="true"
GIT_PUSH="true"
SKIP_CLEAN="false"
DELETE_ONLY="false"

usage() {
  cat <<'USAGE'
Aad Nanda — iOS IPA builder for the aadnanda.com webview app.

Usage:
  ./bin/aadnanda-ipa.sh [options]

Examples:
  ./bin/aadnanda-ipa.sh
  ./bin/aadnanda-ipa.sh --quick
  ./bin/aadnanda-ipa.sh --bump patch
  ./bin/aadnanda-ipa.sh --bump minor --github-release
  ./bin/aadnanda-ipa.sh --no-git-commit --no-push
  ./bin/aadnanda-ipa.sh --delete

Options:
  --version X.Y.Z+B     Set an explicit version
  --bump patch|minor|major|build
  --no-bump             Package the current version as-is
  --delete              Delete old IPA and exit (no build)
  --repo OWNER/REPO     Override GitHub repo (default: Aad6552/aadnanda-app)
  --github-release      Create/update a GitHub release and upload the IPA
  --no-github-release   (default)
  --git-commit          Commit the version bump (default)
  --no-git-commit       Skip the git commit
  --push                Push commit + tag to origin (default)
  --no-push             Skip the git push
  --quick               Skip flutter clean (faster rebuild)
  --help
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

parse_version() {
  local version="$1"
  echo "${version%+*}" "${version#*+}"
}

bump_version() {
  local current="$1"
  local part="$2"
  local version_part build_part major minor patch build

  read -r version_part build_part <<< "$(parse_version "$current")"
  IFS='.' read -r major minor patch <<< "$version_part"

  case "$part" in
    patch) patch=$((patch + 1)); build=$((build + 1)) ;;
    minor) minor=$((minor + 1)); patch=0; build=$((build + 1)) ;;
    major) major=$((major + 1)); minor=0; patch=0; build=$((build + 1)) ;;
    build) build=$((build + 1)) ;;
    *) echo "Error: bump must be patch, minor, major, or build" >&2; exit 1 ;;
  esac

  echo "$major.$minor.$patch+$build"
}

set_version() {
  local version="$1"
  validate_version "$version"
  sed -i '' "s/^version: .*/version: $version/" "$PUBSPEC_FILE"
}

choose_version_from_menu() {
  local current="$1"
  local choice="" custom_version=""

  while true; do
    cat >&2 <<MENU
Current version: $current

Choose release type:
  1) patch  ($(bump_version "$current" patch))
  2) minor  ($(bump_version "$current" minor))
  3) major  ($(bump_version "$current" major))
  4) build  ($(bump_version "$current" build))
  5) custom version
  6) no bump / package current version
MENU

    read -r -p "Enter choice (1-6, default=1): " choice
    choice="${choice:-1}"

    case "$choice" in
      1|patch|p) bump_version "$current" patch; return 0 ;;
      2|minor|m) bump_version "$current" minor; return 0 ;;
      3|major|M) bump_version "$current" major; return 0 ;;
      4|build|b) bump_version "$current" build; return 0 ;;
      5|custom|c)
        read -r -p "Enter version X.Y.Z+B: " custom_version
        validate_version "$custom_version"
        echo "$custom_version"
        return 0
        ;;
      6|none|no|n|current) echo "$current"; return 0 ;;
      *) echo "Please choose 1, 2, 3, 4, 5, or 6." >&2; echo "" >&2 ;;
    esac
  done
}

require_files() {
  [[ -f "$PUBSPEC_FILE" ]] || { echo "Error: missing pubspec.yaml at $PUBSPEC_FILE" >&2; exit 1; }
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

git_commit_release_files() {
  require_git
  cd "$ROOT_DIR"

  git add -u

  while IFS= read -r file; do
    case "$file" in
      build/*|*.ipa|*.zip) continue ;;
      *) git add "$file" ;;
    esac
  done < <(git ls-files --others --exclude-standard)

  if git diff --cached --quiet; then
    echo "Git: nothing to commit"
    return 0
  fi

  git commit -m "Release $APP_NAME $VERSION"
  echo "Git: committed release $VERSION"
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
    gh release upload "$tag" "$IPA_FINAL_PATH" --repo "$GITHUB_REPO" --clobber
    echo "GitHub: uploaded IPA to existing release $tag"
  else
    gh release create "$tag" "$IPA_FINAL_PATH" \
      --repo "$GITHUB_REPO" \
      --title "$title" \
      --notes "$APP_NAME iOS release $VERSION"
    echo "GitHub: created release $tag and uploaded IPA"
  fi
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

require_files

# On a shared branch (you're a collaborator on Aad's repo), get to the tip of
# origin first so the version-bump commit lands cleanly on top.
if [[ "$GIT_COMMIT" == "true" || "$GIT_PUSH" == "true" ]]; then
  require_git
  git_sync_branch
fi

if [[ "$SKIP_CLEAN" == "true" ]]; then
  [[ -z "$VERSION_OVERRIDE" && -z "$BUMP_PART" && "$NO_BUMP" == "false" ]] && BUMP_PART="patch"
fi

CURRENT_VERSION="$(get_version)"
validate_version "$CURRENT_VERSION"

ACTION_COUNT=0
[[ -n "$VERSION_OVERRIDE" ]] && ACTION_COUNT=$((ACTION_COUNT + 1))
[[ -n "$BUMP_PART" ]] && ACTION_COUNT=$((ACTION_COUNT + 1))
[[ "$NO_BUMP" == "true" ]] && ACTION_COUNT=$((ACTION_COUNT + 1))

if (( ACTION_COUNT > 1 )); then
  echo "Error: use only one of --version, --bump, or --no-bump" >&2
  exit 1
fi

if [[ -n "$VERSION_OVERRIDE" ]]; then
  NEXT_VERSION="$VERSION_OVERRIDE"
elif [[ -n "$BUMP_PART" ]]; then
  NEXT_VERSION="$(bump_version "$CURRENT_VERSION" "$BUMP_PART")"
elif [[ "$NO_BUMP" == "true" ]]; then
  NEXT_VERSION="$CURRENT_VERSION"
else
  NEXT_VERSION="$(choose_version_from_menu "$CURRENT_VERSION")"
fi

validate_version "$NEXT_VERSION"

if [[ "$NEXT_VERSION" != "$CURRENT_VERSION" ]]; then
  set_version "$NEXT_VERSION"
fi

VERSION="$(get_version)"
validate_version "$VERSION"

echo ""
echo "════════════════════════════════════════"
echo "  $APP_NAME — IPA Builder"
echo "  Site: https://aadnanda.com"
echo "════════════════════════════════════════"
echo "Current version: $CURRENT_VERSION"
echo "New version:     $VERSION"
echo "════════════════════════════════════════"
echo ""

delete_old_ipa

# 1) version bump is already written to pubspec.yaml above
# 2) commit it
if [[ "$GIT_COMMIT" == "true" ]]; then
  git_commit_release_files
fi

# 3) then build the IPA from the committed state
build_ipa

# 4) tag + push
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
echo "Current version: $CURRENT_VERSION"
echo "New version:     $VERSION"
echo "Updated:         $PUBSPEC_FILE"
echo "Built IPA:       $IPA_FINAL_PATH"
echo "════════════════════════════════════════"
echo ""
