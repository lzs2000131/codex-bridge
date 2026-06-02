#!/usr/bin/env bash
#
# docker-publish.sh — build and push the codex-bridge image to a registry.
#
# Tags pushed:  <REGISTRY>/<IMAGE>:<version>  and  :latest
# Version is read from package.json (falls back to "0.0.0" if jq/node missing).
#
# Usage:
#   ./scripts/docker-publish.sh                 # build + push using env / defaults
#   REGISTRY=ghcr.io/me IMAGE=codex-bridge ./scripts/docker-publish.sh
#   PLATFORMS=linux/amd64,linux/arm64 ./scripts/docker-publish.sh   # multi-arch (buildx)
#   ./scripts/docker-publish.sh --dry-run       # print the commands, run nothing
#
# Environment:
#   REGISTRY   registry + namespace, e.g. ghcr.io/yourname or docker.io/yourname
#              (empty = local build only, push is skipped)
#   IMAGE      image name (default: codex-bridge)
#   VERSION    override the tag (default: version from package.json)
#   PLATFORMS  comma-separated buildx platforms (default: empty = native single-arch)
#   PUSH       set to 0 to build without pushing (default: 1 when REGISTRY is set)

set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

IMAGE="${IMAGE:-codex-bridge}"
REGISTRY="${REGISTRY:-}"

# Resolve version from package.json without requiring jq.
if [[ -z "${VERSION:-}" ]]; then
  if command -v node >/dev/null 2>&1; then
    VERSION="$(node -p "require('./package.json').version" 2>/dev/null || echo "0.0.0")"
  else
    VERSION="$(grep -m1 '"version"' package.json | sed -E 's/.*"version" *: *"([^"]+)".*/\1/' || echo "0.0.0")"
  fi
fi

if [[ -n "$REGISTRY" ]]; then
  REPO="${REGISTRY%/}/${IMAGE}"
else
  REPO="$IMAGE"
fi

TAG_VERSION="${REPO}:${VERSION}"
TAG_LATEST="${REPO}:latest"
PLATFORMS="${PLATFORMS:-}"
PUSH="${PUSH:-$([[ -n "$REGISTRY" ]] && echo 1 || echo 0)}"

run() {
  echo "+ $*"
  if [[ "$DRY_RUN" -eq 0 ]]; then "$@"; fi
}

echo "==> codex-bridge image publish"
echo "    repo      : ${REPO}"
echo "    version   : ${VERSION}"
echo "    platforms : ${PLATFORMS:-native}"
echo "    push      : $([[ "$PUSH" -eq 1 ]] && echo yes || echo 'no (local build)')"
echo

if [[ -n "$PLATFORMS" ]]; then
  # Multi-arch builds require buildx and push directly to the registry.
  if [[ "$PUSH" -ne 1 ]]; then
    echo "ERROR: multi-arch (PLATFORMS set) requires pushing to a registry. Set REGISTRY." >&2
    exit 1
  fi
  run docker buildx build \
    --platform "$PLATFORMS" \
    -t "$TAG_VERSION" \
    -t "$TAG_LATEST" \
    --push \
    .
else
  run docker build -t "$TAG_VERSION" -t "$TAG_LATEST" .
  if [[ "$PUSH" -eq 1 ]]; then
    run docker push "$TAG_VERSION"
    run docker push "$TAG_LATEST"
  fi
fi

echo
echo "==> done: ${TAG_VERSION}${PUSH:+ (and :latest)}"
