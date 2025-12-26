# llama-swappo-halo

[![Build & Push Container](https://github.com/Mootikins/llama-swappo-halo/actions/workflows/build.yml/badge.svg)](https://github.com/Mootikins/llama-swappo-halo/actions/workflows/build.yml)

Container image for running [llama-swappo](https://github.com/Mootikins/llama-swappo) (LLM proxy with Ollama API) on AMD Strix Halo (gfx1151) with ROCm.

Based on [kyuz0/amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes) which provides llama.cpp pre-built for gfx1151.

## Features

- llama-swappo proxy with Ollama API translation
- llama.cpp with ROCm/HIP acceleration for gfx1151
- Optional: whisper.cpp for speech-to-text

## Build

```bash
# LLM proxy only (default)
./build.sh

# With Whisper STT support
./build.sh --whisper
```

## Quick Start

```bash
# Pull from ghcr.io
docker pull ghcr.io/mootikins/llama-swappo-halo:latest

# Run (docker/podman/nerdctl)
docker run --rm -it \
  --device /dev/dri --device /dev/kfd \
  -v /path/to/models:/models:ro \
  -v /path/to/config.yaml:/app/config.yaml:ro \
  -p 8080:8080 \
  ghcr.io/mootikins/llama-swappo-halo:latest \
  -config /app/config.yaml
```

## Configuration

See [llama-swappo documentation](https://github.com/Mootikins/llama-swappo) for config.yaml format.

## Whisper STT

The whisper-enabled image must be built locally (ROCm toolchain ~5GB exceeds CI runner limits):

```bash
./build.sh --whisper
```

When built with `--whisper`, the image includes:

- `/app/whisper-server` - HTTP server for transcription
- `/app/whisper-cli` - CLI tool for transcription
- `ffmpeg` for audio processing

To use whisper alongside llama-swappo, configure llama-swappo to spawn whisper-server as needed, or run them as separate processes.

## Requirements

- AMD Strix Halo APU (gfx1151) or compatible
- ROCm drivers installed on host
- Access to `/dev/dri` and `/dev/kfd`

## License

MIT
