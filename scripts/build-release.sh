#!/bin/bash
# build-release.sh — clean release build + optional GitHub publish for PeekDock
#
# Usage:
#   ./scripts/build-release.sh                        # build only
#   ./scripts/build-release.sh --version 1.1          # explicit version
#   ./scripts/build-release.sh --publish               # build + publish to GitHub Releases
#   ./scripts/build-release.sh --version 1.1 --publish
#   ./scripts/build-release.sh --publish --draft       # publish as draft (review before going live)
#
# Requires: xcodegen, gh (GitHub CLI) — install with: brew install gh xcodegen
# Output:   dist/PeekDock-<version>.zip

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

step()  { echo -e "\n${BLUE}${BOLD}▶ $1${RESET}"; }
ok()    { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
warn()  { echo -e "${YELLOW}⚠ $1${RESET}"; }
fail()  { echo -e "${RED}${BOLD}✗ $1${RESET}"; exit 1; }

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="PeekDock"
PROJECT="$PROJECT_ROOT/${APP_NAME}.xcodeproj"
SCHEME="$APP_NAME"
DIST_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$PROJECT_ROOT/build"

# ── Parse arguments ───────────────────────────────────────────────────────────
VERSION=""
PUBLISH=false
DRAFT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --publish) PUBLISH=true; shift ;;
        --draft)   DRAFT=true;   shift ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

# Read version from Info.plist if not provided
if [[ -z "$VERSION" ]]; then
    VERSION=$(defaults read "$PROJECT_ROOT/WindowManager/App/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
    # Note: source folder stays WindowManager/ — only the app name changed
fi

ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo -e "\n${BOLD}Building ${APP_NAME} v${VERSION}${RESET}"
echo "────────────────────────────────────────"

# ── Step 1: Regenerate Xcode project ─────────────────────────────────────────
step "Regenerating Xcode project"
cd "$PROJECT_ROOT"
xcodegen generate --quiet
ok "Project generated"

# ── Step 2: Clean previous build ─────────────────────────────────────────────
step "Cleaning previous build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    clean \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    > "$BUILD_DIR/clean.log" 2>&1 || fail "Clean failed — see $BUILD_DIR/clean.log"

ok "Clean complete"

# ── Step 3: Build ─────────────────────────────────────────────────────────────
step "Building Release"
BUILD_LOG="$BUILD_DIR/build.log"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CURRENT_PROJECT_VERSION="$VERSION" \
    MARKETING_VERSION="$VERSION" \
    build \
    2>&1 | tee "$BUILD_LOG" | grep -E "^(error:|warning:|note:|.*BUILD (SUCCEEDED|FAILED))" || true

# Check build result from log
if grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    ok "Build succeeded"
elif grep -q "BUILD FAILED" "$BUILD_LOG"; then
    echo ""
    warn "Build errors:"
    grep "error:" "$BUILD_LOG" | head -20
    fail "Build failed — full log at $BUILD_LOG"
fi

# ── Step 4: Locate the built .app ─────────────────────────────────────────────
BUILT_PRODUCTS_DIR=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -showBuildSettings \
    CODE_SIGN_IDENTITY="-" \
    2>/dev/null | awk '/BUILT_PRODUCTS_DIR/{print $3; exit}')

APP_PATH="$BUILT_PRODUCTS_DIR/${APP_NAME}.app"

if [[ ! -d "$APP_PATH" ]]; then
    fail ".app not found at $APP_PATH"
fi

APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
ok "App bundle: $APP_PATH ($APP_SIZE)"

# ── Step 5: Package as zip ────────────────────────────────────────────────────
step "Packaging"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

ZIP_SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
ok "Zip created: $ZIP_SIZE"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────"
echo -e "${GREEN}${BOLD}✅ Release ready${RESET}"
echo -e "   File:    ${BOLD}dist/$ZIP_NAME${RESET}"
echo -e "   Size:    $ZIP_SIZE"
echo -e "   Version: $VERSION"
echo ""
echo -e "${YELLOW}Install note for users:${RESET}"
echo "  1. Unzip and move PeekDock.app to /Applications"
echo "  2. Right-click → Open on first launch to bypass Gatekeeper"
echo "  3. Grant Accessibility + Screen Recording permissions when prompted"
echo ""

# ── Step 6: Publish to GitHub Releases (optional) ─────────────────────────────
if [[ "$PUBLISH" == true ]]; then
    step "Publishing to GitHub Releases"

    # Check gh is installed
    if ! command -v gh &>/dev/null; then
        fail "GitHub CLI (gh) not found. Install with: brew install gh"
    fi

    # Check gh is authenticated
    if ! gh auth status &>/dev/null; then
        fail "Not logged in to GitHub CLI. Run: gh auth login"
    fi

    TAG="v${VERSION}"
    RELEASE_TITLE="${APP_NAME} ${VERSION}"

    RELEASE_NOTES="## What's new in ${VERSION}

<!-- TODO: describe what changed in this release -->

---

### Installation
1. Download \`${ZIP_NAME}\` below
2. Unzip and move **${APP_NAME}.app** to \`/Applications\`
3. **Right-click → Open** on first launch (unsigned app — Gatekeeper bypass)
4. Grant **Accessibility** and **Screen Recording** permissions when prompted

### Requirements
- macOS 14 Sonoma or later
- Apple Silicon or Intel

---

Built with ♥ by [Pritam](https://developerpritam.in) · [Website](https://peekdock.developerpritam.in)"

    # Build the gh release command
    GH_FLAGS=(
        release create "$TAG"
        "$ZIP_PATH"
        --title "$RELEASE_TITLE"
        --notes "$RELEASE_NOTES"
    )

    if [[ "$DRAFT" == true ]]; then
        GH_FLAGS+=(--draft)
        warn "Publishing as DRAFT — go to GitHub Releases to make it public"
    fi

    gh "${GH_FLAGS[@]}"

    echo ""
    echo -e "────────────────────────────────────────"
    if [[ "$DRAFT" == true ]]; then
        echo -e "${YELLOW}${BOLD}📋 Draft release created${RESET}"
        echo -e "   Tag:   $TAG"
        echo -e "   Open GitHub → Releases to review and publish"
    else
        echo -e "${GREEN}${BOLD}🚀 Published!${RESET}"
        echo -e "   Tag:     $TAG"
        REPO_URL=$(gh repo view --json url -q .url 2>/dev/null || echo "your GitHub repo")
        echo -e "   Release: ${REPO_URL}/releases/tag/${TAG}"
    fi
    echo ""
fi
