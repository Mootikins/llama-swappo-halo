# llama-swappo-halo: Unified LLM + STT container for AMD Strix Halo
# Features:
#   - llama-swappo proxy with Ollama API compatibility
#   - Optional whisper-server for speech-to-text (--build-arg ENABLE_WHISPER=1)
#
# Usage:
#   buildah bud -t llama-swappo-halo:latest .
#   buildah bud -t llama-swappo-halo:stt --build-arg ENABLE_WHISPER=1 .

# Global ARGs
ARG BACKEND=rocm-6.4.4-rocwmma
ARG ENABLE_WHISPER=0

# =============================================================================
# Stage 1: Build llama-swappo
# =============================================================================
FROM alpine:latest AS swappo-builder

RUN apk add --no-cache git go nodejs npm ca-certificates

WORKDIR /build
RUN git clone https://github.com/mootikins/llama-swappo.git && \
    cd llama-swappo/ui && \
    npm install && npm run build && \
    cd .. && \
    CGO_ENABLED=0 go build -o llama-swap . && \
    strip llama-swap

# =============================================================================
# Stage 2: Build whisper.cpp (conditional)
# =============================================================================
FROM alpine:latest AS whisper-source
RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git /src

FROM docker.io/rocm/dev-ubuntu-22.04:6.4.4-complete AS whisper-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake build-essential && \
    rm -rf /var/lib/apt/lists/*

COPY --from=whisper-source /src /build/whisper.cpp
WORKDIR /build/whisper.cpp

# Build with HIP support for gfx1151 (Strix Halo)
RUN cmake -B build \
    -DGGML_HIP=ON \
    -DGPU_TARGETS="gfx1151" \
    -DCMAKE_C_COMPILER=/opt/rocm/bin/amdclang \
    -DCMAKE_CXX_COMPILER=/opt/rocm/bin/amdclang++ \
    -DCMAKE_PREFIX_PATH="/opt/rocm" \
    -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build -j$(nproc)

# =============================================================================
# Stage 3: Final runtime image
# =============================================================================
FROM kyuz0/amd-strix-halo-toolboxes:${BACKEND}

ARG ENABLE_WHISPER

WORKDIR /app

# Create directories
RUN mkdir -p /models /models/stt /app/lib

# Copy llama-swappo binary
COPY --from=swappo-builder /build/llama-swappo/llama-swap /app/llama-swap
RUN chmod +x /app/llama-swap

# Conditionally copy whisper binaries and libs
RUN if [ "${ENABLE_WHISPER}" = "1" ]; then \
      echo "Whisper enabled - binaries will be copied"; \
    else \
      echo "Whisper disabled"; \
    fi

# Copy whisper files (these layers are cached even if not used)
COPY --from=whisper-builder /build/whisper.cpp/build/bin/whisper-server /tmp/whisper-server
COPY --from=whisper-builder /build/whisper.cpp/build/bin/whisper-cli /tmp/whisper-cli
COPY --from=whisper-builder /build/whisper.cpp/build/src/libwhisper.so* /tmp/lib/
COPY --from=whisper-builder /build/whisper.cpp/build/ggml/src/libggml*.so* /tmp/lib/

# Move whisper files to final location if enabled
RUN if [ "${ENABLE_WHISPER}" = "1" ]; then \
      mv /tmp/whisper-server /app/whisper-server && \
      mv /tmp/whisper-cli /app/whisper-cli && \
      mv /tmp/lib/* /app/lib/ && \
      chmod +x /app/whisper-server /app/whisper-cli && \
      dnf install -y ffmpeg-free && dnf clean all; \
    fi && \
    rm -rf /tmp/whisper-* /tmp/lib

ENV LD_LIBRARY_PATH=/app/lib:/opt/rocm/lib:$LD_LIBRARY_PATH
ENV PATH="/app:${PATH}"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENTRYPOINT ["/app/llama-swap"]