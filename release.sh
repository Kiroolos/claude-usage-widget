#!/usr/bin/env bash
#
# Cut a new release: bump version, build both signed APKs (original and ultra
# package names), tag, and publish to GitHub Releases with stable asset names.
#
#   ./release.sh 1.1
#
# versionName is the argument you pass. versionCode is derived from the git
# commit count, so it is always monotonic without any stored state.
#
# Requires the GitHub CLI (`gh`) authenticated against this repo, plus a
# signing config at .signing/keystore.properties (the whole .signing/ folder
# is gitignored). storeFile is resolved relative to the project root:
#
#   storeFile=.signing/release.keystore
#   storePassword=...
#   keyAlias=claude-usage-widget
#   keyPassword=...

set -euo pipefail

FLAVORS=(original ultra)
declare -A ASSET_NAMES=(
    [original]="claude-usage-widget.apk"
    [ultra]="claude-usage-widget-ultra.apk"
)
GRADLE_FILE="app/build.gradle.kts"

if [[ $# -ne 1 ]]; then
    echo "usage: ./release.sh <versionName>   e.g. ./release.sh 1.1" >&2
    exit 1
fi

VERSION_NAME="$1"
TAG="v${VERSION_NAME}"

if [[ ! -f .signing/keystore.properties ]]; then
    echo "error: .signing/keystore.properties not found. See the header of this script for the expected format." >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "error: the GitHub CLI (gh) is required." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree is dirty. Commit or stash first." >&2
    exit 1
fi

# versionCode = number of commits, guaranteed to increase every release.
VERSION_CODE="$(git rev-list --count HEAD)"

echo "==> Setting versionName=${VERSION_NAME}, versionCode=${VERSION_CODE}"
sed -i -E "s/versionCode = [0-9]+/versionCode = ${VERSION_CODE}/" "$GRADLE_FILE"
sed -i -E "s/versionName = \"[^\"]*\"/versionName = \"${VERSION_NAME}\"/" "$GRADLE_FILE"

echo "==> Building signed release APKs"
./gradlew :app:assembleRelease

echo "==> Committing version bump and tagging ${TAG}"
git add "$GRADLE_FILE"
git commit -m "release: ${TAG}"
git tag "$TAG"
git push origin HEAD --tags

echo "==> Publishing GitHub Release ${TAG}"
ASSETS=()
for flavor in "${FLAVORS[@]}"; do
    cp "app/build/outputs/apk/${flavor}/release/app-${flavor}-release.apk" "${ASSET_NAMES[$flavor]}"
    ASSETS+=("${ASSET_NAMES[$flavor]}")
done
gh release create "$TAG" "${ASSETS[@]}" \
    --title "$TAG" \
    --generate-notes
rm -f "${ASSETS[@]}"

echo "==> Done. $(gh release view "$TAG" --json url -q .url)"
