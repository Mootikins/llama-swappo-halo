# llama-swappo-halo: LLM proxy + llama.cpp for AMD Strix Halo (gfx1151)
#
# kyuz0/amd-strix-halo-toolboxes includes llama.cpp with ROCm or Vulkan
# We add llama-swappo (Go proxy with Ollama API translation)
# Optional: whisper.cpp for speech-to-text (ROCm only)
# Vulkan image: stable-diffusion.cpp sd-server for image generation and edit
#
# Build:
#   ./build.sh              # ROCm backend (default)
#   ./build.sh --vulkan     # Vulkan backend (RADV)
#   ./build.sh --whisper    # LLM + Whisper STT (ROCm only)
#   ./build.sh --ghcr       # Push to ghcr.io
#
# Available images:
#   ghcr.io/mootikins/llama-swappo-halo:latest  - ROCm backend
#   ghcr.io/mootikins/llama-swappo-halo:rocm    - ROCm backend (alias)
#   ghcr.io/mootikins/llama-swappo-halo:vulkan  - Vulkan/RADV backend

ARG BACKEND=rocm-6.4.4-rocwmma
ARG WHISPER=false

# =============================================================================
# Stage: swappo-builder - Build llama-swappo binary
# =============================================================================
FROM alpine:latest AS swappo-builder

RUN apk add --no-cache git go nodejs npm ca-certificates

WORKDIR /build
# Fork branch fix/tool-response-position-matching (same commit as main/master).
# 1c52441 binds identifier-less Ollama tool responses to the pending assistant
# tool calls (explicit id, then function name, then position). Without that,
# clients such as Zed lose tool results. Upstream PR:
# https://github.com/kooshi/llama-swappo/pull/18
# The SHA is pinned so this layer is not reused from an older clone of the branch.
# Current upstream builds the Svelte UI from ui/ into internal/server/ui_dist
# and embeds it with -tags embed_ui. Alpine's go is 1.26 with GOTOOLCHAIN=local;
# GOTOOLCHAIN=auto downloads the 1.27.1 toolchain go.mod requires.
RUN git clone --branch fix/tool-response-position-matching https://github.com/mootikins/llama-swappo.git && \
    cd llama-swappo && \
    git -c advice.detachedHead=false checkout 1c524412ca645d28b1b96802dba589356dd45d66 && \
    cd ui && npm install && npm run build && \
    cd .. && \
    GOTOOLCHAIN=auto CGO_ENABLED=0 go build -tags embed_ui -o llama-swap . && \
    strip llama-swap

# =============================================================================
# Stage: whisper-builder - Build whisper.cpp with ROCm/HIP for gfx1151
# Must be built locally - ROCm toolchain too large for CI runners
# Note: Whisper is only supported with ROCm backend (not Vulkan)
# =============================================================================
FROM docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-6.4.4-rocwmma AS whisper-builder

ARG WHISPER
ARG BACKEND
RUN if [ "$WHISPER" = "true" ] && echo "$BACKEND" | grep -q "^rocm"; then \
        dnf install -y git cmake make gcc gcc-c++ glibc-devel libstdc++-devel rocm-hip-sdk && \
        git clone https://github.com/ggml-org/whisper.cpp.git /build/whisper.cpp && \
        cd /build/whisper.cpp && \
        mkdir build && cd build && \
        cmake .. \
            -DGPU_TARGETS="gfx1151" \
            -DGGML_HIP=ON \
            -DCMAKE_C_COMPILER=/opt/rocm/bin/amdclang \
            -DCMAKE_CXX_COMPILER=/opt/rocm/bin/amdclang++ \
            -DCMAKE_PREFIX_PATH="/opt/rocm" \
            -DCMAKE_BUILD_TYPE=Release && \
        cmake --build . --config Release -j$(nproc) && \
        strip bin/whisper-server bin/whisper-cli && \
        dnf clean all && rm -rf /var/cache/dnf; \
    else \
        mkdir -p /build/whisper.cpp/build/bin \
                 /build/whisper.cpp/build/src \
                 /build/whisper.cpp/build/ggml/src && \
        touch /build/whisper.cpp/build/bin/whisper-server && \
        touch /build/whisper.cpp/build/bin/whisper-cli && \
        touch /build/whisper.cpp/build/src/libwhisper.so && \
        touch /build/whisper.cpp/build/ggml/src/libggml.so; \
    fi

# =============================================================================
# Stage: sd-fetch - Get the stable-diffusion.cpp Vulkan release (sd-server)
# The release binaries have RUNPATH $ORIGIN, so they load their own ggml from
# /app/sd and not the ggml of llama.cpp in /usr/lib64. Do not copy these libs
# to /app/lib: LD_LIBRARY_PATH has priority over RUNPATH for llama-server.
# Only the Vulkan image gets sd-server.
# =============================================================================
FROM alpine:latest AS sd-fetch

ARG BACKEND
ARG SDCPP_TAG=master-945-a1ded76
RUN mkdir -p /sd && \
    if echo "$BACKEND" | grep -q "^vulkan"; then \
        apk add --no-cache curl unzip && \
        SHA=${SDCPP_TAG##*-} && \
        curl -fsSL -o /tmp/sd.zip \
            "https://github.com/leejet/stable-diffusion.cpp/releases/download/${SDCPP_TAG}/sd-master-${SHA}-bin-Linux-Ubuntu-24.04-x86_64-vulkan.zip" && \
        unzip -q /tmp/sd.zip -d /sd && \
        rm /tmp/sd.zip; \
    fi

# =============================================================================
# Stage: llama-builder - Build llama.cpp at a pinned ref (Vulkan only)
# The kyuz0 base can lag llama.cpp. When LLAMA_CPP_REF is set, this stage
# builds that ref, and its files replace the llama.cpp of the base. When the
# ref is empty, /out stays empty and the base llama.cpp is kept. The
# workflow sets the ref for the Vulkan image. Remove the ref from the workflow
# when the kyuz0 base has that ref or a newer one, or the pin replaces a newer
# llama.cpp of the base.
# The sed applies the kyuz0 grammar patch (kyuz0 issue #70) for large tool schemas.
# =============================================================================
FROM registry.fedoraproject.org/fedora:44 AS llama-builder

ARG BACKEND
ARG LLAMA_CPP_REF=
RUN mkdir -p /out && \
    if [ -n "$LLAMA_CPP_REF" ] && echo "$BACKEND" | grep -q "^vulkan"; then \
        dnf -y --nodocs --setopt=install_weak_deps=False install \
            git make gcc gcc-c++ cmake ninja-build libcurl-devel rdma-core-devel \
            vulkan-loader-devel spirv-headers-devel glslc && \
        git clone --depth 1 --branch "$LLAMA_CPP_REF" https://github.com/ggml-org/llama.cpp.git /src && \
        cd /src && \
        sed -i 's/^#define MAX_REPETITION_THRESHOLD 2000$/#define MAX_REPETITION_THRESHOLD 100000/' src/llama-grammar.cpp && \
        grep -q 'MAX_REPETITION_THRESHOLD 100000' src/llama-grammar.cpp && \
        cmake -S . -B build -G Ninja \
            -DGGML_VULKAN=ON \
            -DGGML_RPC=ON \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX=/usr \
            -DLLAMA_BUILD_TESTS=OFF \
            -DLLAMA_BUILD_EXAMPLES=ON \
            -DLLAMA_BUILD_SERVER=ON && \
        cmake --build build --config Release && \
        DESTDIR=/out cmake --install build --config Release; \
    fi

# =============================================================================
# Final stage: Runtime image
# =============================================================================
FROM docker.io/kyuz0/amd-strix-halo-toolboxes:${BACKEND}

ARG WHISPER
ARG BACKEND

WORKDIR /app
RUN mkdir -p /models /models/whisper /app/lib

# Replace the base llama.cpp with the pinned build (no-op when /out is empty)
COPY --from=llama-builder /out/ /
RUN ldconfig

# Copy llama-swappo binary
COPY --from=swappo-builder /build/llama-swappo/llama-swap /app/llama-swap
RUN chmod +x /app/llama-swap

# Copy whisper binaries and libs (only functional if WHISPER=true during build)
COPY --from=whisper-builder /build/whisper.cpp/build/bin/whisper-server /app/whisper-server
COPY --from=whisper-builder /build/whisper.cpp/build/bin/whisper-cli /app/whisper-cli
COPY --from=whisper-builder /build/whisper.cpp/build/src/libwhisper.so* /app/lib/
COPY --from=whisper-builder /build/whisper.cpp/build/ggml/src/libggml*.so* /app/lib/

# Install ffmpeg for audio processing (only if whisper enabled with ROCm backend)
RUN if [ "$WHISPER" = "true" ] && echo "$BACKEND" | grep -q "^rocm"; then \
        chmod +x /app/whisper-server /app/whisper-cli && \
        dnf install -y ffmpeg-free && \
        dnf clean all && rm -rf /var/cache/dnf; \
    else \
        rm -f /app/whisper-server /app/whisper-cli && \
        rm -rf /app/lib; \
    fi

# Copy sd-server, sd-cli and their libs (empty for the ROCm image)
COPY --from=sd-fetch /sd /app/sd

ENV LD_LIBRARY_PATH="/app/lib:${LD_LIBRARY_PATH}"

ENV PATH="/app:/app/sd:${PATH}"

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENTRYPOINT ["/app/llama-swap"]
