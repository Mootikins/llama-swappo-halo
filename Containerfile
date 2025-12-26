# llama-swappo-halo: LLM proxy + llama.cpp for AMD Strix Halo (gfx1151)
#
# kyuz0/amd-strix-halo-toolboxes includes llama.cpp with ROCm
# We add llama-swappo (Go proxy with Ollama API translation)
# Optional: whisper.cpp for speech-to-text
#
# Build:
#   ./build.sh              # LLM only
#   ./build.sh --whisper    # LLM + Whisper STT
#   ./build.sh --ghcr       # Push to ghcr.io

ARG BACKEND=rocm-6.4.4-rocwmma
ARG WHISPER=false

# =============================================================================
# Stage: swappo-builder - Build llama-swappo binary
# =============================================================================
FROM alpine:latest AS swappo-builder

RUN apk add --no-cache git go nodejs npm ca-certificates

WORKDIR /build
RUN git clone https://github.com/mootikins/llama-swappo.git && \
    cd llama-swappo && \
    cd ui && npm install && npm run build && \
    cd .. && \
    CGO_ENABLED=0 go build -o llama-swap . && \
    strip llama-swap

# =============================================================================
# Stage: whisper-builder - Build whisper.cpp with ROCm/HIP for gfx1151
# Uses official ROCm dev image which has compilers (amdclang)
# Only runs full build when WHISPER=true
# =============================================================================
FROM rocm/dev-ubuntu-22.04:6.2.4 AS whisper-builder

ARG WHISPER
RUN if [ "$WHISPER" = "true" ]; then \
        apt-get update && apt-get install -y --no-install-recommends git cmake && \
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
        rm -rf /var/lib/apt/lists/*; \
    else \
        mkdir -p /build/whisper.cpp/build/bin \
                 /build/whisper.cpp/build/src \
                 /build/whisper.cpp/build/ggml/src && \
        touch /build/whisper.cpp/build/bin/whisper-server && \
        touch /build/whisper.cpp/build/bin/whisper-cli; \
    fi

# =============================================================================
# Final stage: Runtime image
# =============================================================================
FROM docker.io/kyuz0/amd-strix-halo-toolboxes:${BACKEND}

ARG WHISPER

WORKDIR /app
RUN mkdir -p /models /models/whisper /app/lib

# Copy llama-swappo binary
COPY --from=swappo-builder /build/llama-swappo/llama-swap /app/llama-swap
RUN chmod +x /app/llama-swap

# Copy whisper binaries and libs (only functional if WHISPER=true during build)
COPY --from=whisper-builder /build/whisper.cpp/build/bin/whisper-server /app/whisper-server
COPY --from=whisper-builder /build/whisper.cpp/build/bin/whisper-cli /app/whisper-cli
COPY --from=whisper-builder /build/whisper.cpp/build/src/libwhisper.so* /app/lib/
COPY --from=whisper-builder /build/whisper.cpp/build/ggml/src/libggml*.so* /app/lib/

# Install ffmpeg for audio processing (only if whisper enabled)
RUN if [ "$WHISPER" = "true" ]; then \
        chmod +x /app/whisper-server /app/whisper-cli && \
        dnf install -y ffmpeg-free && \
        dnf clean all && rm -rf /var/cache/dnf; \
    else \
        rm -f /app/whisper-server /app/whisper-cli && \
        rm -rf /app/lib; \
    fi

ENV LD_LIBRARY_PATH="/app/lib:${LD_LIBRARY_PATH}"

ENV PATH="/app:${PATH}"

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENTRYPOINT ["/app/llama-swap"]
