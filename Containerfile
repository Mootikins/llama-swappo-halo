# llama-swappo-halo: LLM proxy + llama.cpp for AMD Strix Halo
#
# Build: buildah bud -t llama-swappo-halo .
#
# For STT support, use Containerfile.stt or run whisper-stt as sidecar

ARG BACKEND=rocm-6.4.4-rocwmma

# Build llama-swappo (Go proxy with Ollama translation)
FROM alpine:latest AS swappo-builder

RUN apk add --no-cache git go nodejs npm ca-certificates

WORKDIR /build
RUN git clone https://github.com/mootikins/llama-swappo.git && \
    cd llama-swappo/ui && npm install && npm run build && \
    cd .. && CGO_ENABLED=0 go build -o llama-swap . && strip llama-swap

# Build llama.cpp with ROCm/HIP for Strix Halo (gfx1151)
FROM kyuz0/amd-strix-halo-toolboxes:${BACKEND} AS llama-builder

WORKDIR /build

# Install build tools
RUN dnf install -y git cmake gcc-c++ make && dnf clean all

# Clone and build llama.cpp with ROCm support
ENV ROCM_PATH=/opt/rocm
ENV PATH="${ROCM_PATH}/bin:${PATH}"
ENV HIP_PATH="${ROCM_PATH}"

RUN git clone --depth 1 https://github.com/ggerganov/llama.cpp.git && \
    cd llama.cpp && \
    cmake -B build \
        -DCMAKE_PREFIX_PATH="${ROCM_PATH}" \
        -DGGML_HIP=ON \
        -DAMDGPU_TARGETS="gfx1151" \
        -DCMAKE_HIP_ARCHITECTURES="gfx1151" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=ON \
        -DLLAMA_BUILD_SERVER=ON && \
    cmake --build build --config Release -j$(nproc) && \
    cmake --install build --prefix /usr/local

# Runtime image
FROM kyuz0/amd-strix-halo-toolboxes:${BACKEND}

WORKDIR /app
RUN mkdir -p /models

# Copy llama.cpp binaries
COPY --from=llama-builder /usr/local/bin/llama-* /usr/local/bin/
COPY --from=llama-builder /usr/local/lib/lib*.so* /usr/local/lib/

# Copy llama-swappo
COPY --from=swappo-builder /build/llama-swappo/llama-swap /app/llama-swap
RUN chmod +x /app/llama-swap

# Copy conversion scripts
COPY --from=llama-builder /build/llama.cpp/convert_hf_to_gguf.py /usr/local/bin/
COPY --from=llama-builder /build/llama.cpp/gguf-py /usr/local/lib/python3.12/site-packages/gguf-py

RUN ldconfig

ENV PATH="/app:/usr/local/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/lib:/opt/rocm/lib"

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENTRYPOINT ["/app/llama-swap"]
