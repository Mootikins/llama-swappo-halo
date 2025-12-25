# llama-swappo-halo: LLM proxy for AMD Strix Halo
#
# NOTE: This Containerfile builds the llama-swap proxy only.
# For full builds with llama.cpp, use krohnos-k3s/docker/llama-swappo-halo
# or build locally with ROCm.
#
# Build: buildah bud -t llama-swappo-halo .

ARG BACKEND=rocm-6.4.4-rocwmma

# Build llama-swappo (Go proxy with Ollama translation)
FROM alpine:latest AS builder

RUN apk add --no-cache git go nodejs npm ca-certificates

WORKDIR /build
RUN git clone https://github.com/mootikins/llama-swappo.git && \
    cd llama-swappo/ui && npm install && npm run build && \
    cd .. && CGO_ENABLED=0 go build -o llama-swap . && strip llama-swap

# Runtime - using kyuz0 toolbox which has ROCm runtime
FROM kyuz0/amd-strix-halo-toolboxes:${BACKEND}

WORKDIR /app
RUN mkdir -p /models

COPY --from=builder /build/llama-swappo/llama-swap /app/llama-swap
RUN chmod +x /app/llama-swap

ENV PATH="/app:${PATH}"

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080
ENTRYPOINT ["/app/llama-swap"]
