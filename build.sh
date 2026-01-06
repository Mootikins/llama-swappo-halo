#!/bin/bash
# Build llama-swappo-halo container
#
# Usage:
#   ./build.sh              # LLM proxy only (ROCm backend)
#   ./build.sh --vulkan     # LLM with Vulkan backend (RADV)
#   ./build.sh --whisper    # LLM + Whisper STT
#   ./build.sh --push       # Push to local registry
#   ./build.sh --ghcr       # Push to ghcr.io/mootikins/llama-swappo-halo

set -e

IMAGE="${IMAGE_NAME:-llama-swappo-halo}"
GHCR_IMAGE="ghcr.io/mootikins/llama-swappo-halo"
TAG="latest"
WHISPER="false"
BACKEND="rocm-6.4.4-rocwmma"
BUILD_ARGS=""

for arg in "$@"; do
    case $arg in
        --whisper)
            WHISPER="true"
            ;;
        --vulkan)
            BACKEND="vulkan-radv"
            ;;
        --push) PUSH=1 ;;
        --ghcr) GHCR=1 ;;
    esac
done

# Build tag based on options
if [ "$BACKEND" = "vulkan-radv" ]; then
    TAG="vulkan"
    [ "$WHISPER" = "true" ] && TAG="vulkan-whisper"
else
    TAG="latest"
    [ "$WHISPER" = "true" ] && TAG="whisper"
fi

BUILD_ARGS="--build-arg WHISPER=$WHISPER --build-arg BACKEND=$BACKEND"

echo "Building $IMAGE:$TAG (BACKEND=$BACKEND, WHISPER=$WHISPER)"

# Use buildah for rootless builds
buildah bud --layers $BUILD_ARGS -t "$IMAGE:$TAG" -f Containerfile .

[ "$PUSH" = "1" ] && buildah push "$IMAGE:$TAG"

# Push to ghcr.io
if [ "$GHCR" = "1" ]; then
    echo "Tagging and pushing to $GHCR_IMAGE:$TAG..."
    buildah tag "$IMAGE:$TAG" "$GHCR_IMAGE:$TAG"
    buildah push "$GHCR_IMAGE:$TAG"
fi

# Import to k3s if available
if command -v k3s &>/dev/null; then
    echo "Importing to k3s containerd..."
    buildah push "$IMAGE:$TAG" "docker-archive:/dev/stdout:$IMAGE:$TAG" | \
        k3s ctr -n k8s.io images import - 2>/dev/null || true
fi

echo "Done: $IMAGE:$TAG"
