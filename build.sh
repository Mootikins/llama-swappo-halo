#!/bin/bash
# Build llama-swappo-halo container
# Works with: docker, nerdctl, buildah, podman
#
# Usage:
#   ./build.sh                    # Default build
#   ./build.sh --whisper          # Include whisper STT
#   ./build.sh --push             # Push to registry
#   BACKEND=vulkan ./build.sh     # Different backend
#   CONTAINER_CMD=nerdctl ./build.sh  # Use nerdctl

set -e

# Auto-detect container command
detect_container_cmd() {
    if [ -n "$CONTAINER_CMD" ]; then echo "$CONTAINER_CMD"
    elif command -v nerdctl &>/dev/null; then echo "nerdctl"
    elif command -v docker &>/dev/null; then echo "docker"
    elif command -v podman &>/dev/null; then echo "podman"
    elif command -v buildah &>/dev/null; then echo "buildah"
    else echo "docker"  # fallback
    fi
}

CTR=$(detect_container_cmd)
echo "Using: $CTR"

# Configuration
BACKEND=${BACKEND:-"rocm-rocwmma"}
IMAGE_NAME="${IMAGE_NAME:-llama-swappo-halo}"
REGISTRY=${REGISTRY:-""}
VERSION=${VERSION:-"latest"}
ENABLE_WHISPER=0
PUSH=0

# Parse args
for arg in "$@"; do
    case $arg in
        --whisper) ENABLE_WHISPER=1 ;;
        --push) PUSH=1 ;;
        --help|-h)
            echo "Usage: $0 [--whisper] [--push]"
            echo "  BACKEND=<vulkan|rocm-base|rocm-rocwmma>"
            echo "  REGISTRY=ghcr.io/user/"
            echo "  CONTAINER_CMD=<docker|nerdctl|podman|buildah>"
            exit 0
            ;;
    esac
done

# Backend to base tag mapping
case "$BACKEND" in
    "vulkan")       BASE_TAG="vulkan-radv" ;;
    "rocm-base")    BASE_TAG="rocm-6.4.4" ;;
    "rocm-rocwmma") BASE_TAG="rocm-6.4.4-rocwmma" ;;
    *)
        echo "Unknown backend: $BACKEND"
        echo "Available: vulkan, rocm-base, rocm-rocwmma"
        exit 1
        ;;
esac

# Build image tag
TAG_SUFFIX="$BACKEND"
[ "$ENABLE_WHISPER" = "1" ] && TAG_SUFFIX="${TAG_SUFFIX}-stt"
FULL_IMAGE="${REGISTRY}${IMAGE_NAME}:${TAG_SUFFIX}"

echo "Building: $FULL_IMAGE"
echo "  Backend: $BACKEND"
echo "  Whisper: $([ "$ENABLE_WHISPER" = "1" ] && echo "yes" || echo "no")"

# Build command varies by tool
case "$CTR" in
    buildah)
        buildah bud --layers \
            --build-arg BACKEND="$BASE_TAG" \
            --build-arg ENABLE_WHISPER="$ENABLE_WHISPER" \
            -t "$FULL_IMAGE" \
            -f Containerfile .
        ;;
    *)
        $CTR build \
            --build-arg BACKEND="$BASE_TAG" \
            --build-arg ENABLE_WHISPER="$ENABLE_WHISPER" \
            -t "$FULL_IMAGE" \
            -f Containerfile .
        ;;
esac

echo "Built: $FULL_IMAGE"

# Push if requested
if [ "$PUSH" = "1" ]; then
    echo "Pushing..."
    case "$CTR" in
        buildah) buildah push "$FULL_IMAGE" ;;
        *) $CTR push "$FULL_IMAGE" ;;
    esac
fi

# Import to k3s containerd if available
if [ -x "$(command -v k3s)" ] && [ "$CTR" = "buildah" ]; then
    echo "Importing to k3s..."
    buildah push "$FULL_IMAGE" "docker-archive:/dev/stdout:$FULL_IMAGE" | \
        sudo k3s ctr -n k8s.io images import - 2>/dev/null || true
fi

echo ""
echo "Run: $CTR run -p 8080:8080 --device /dev/dri --device /dev/kfd -v /models:/models $FULL_IMAGE"
