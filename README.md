# llama-swappo-halo

[![Build & Push Container](https://github.com/Mootikins/llama-swappo-halo/actions/workflows/build.yml/badge.svg)](https://github.com/Mootikins/llama-swappo-halo/actions/workflows/build.yml)

Container image for running [llama-swappo](https://github.com/Mootikins/llama-swappo) (LLM proxy with Ollama API) on AMD Strix Halo (gfx1151).

Based on [kyuz0/amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes) which provides llama.cpp pre-built for gfx1151.

## Available Images

| Tag | Backend | Description |
|-----|---------|-------------|
| `latest`, `rocm` | ROCm/HIP | Full ROCm compute stack, supports Whisper STT |
| `vulkan` | Vulkan/RADV | Mesa RADV driver, better gfx1151 stability |

```bash
# ROCm backend (default)
docker pull ghcr.io/mootikins/llama-swappo-halo:latest

# Vulkan backend (recommended for gfx1151 stability)
docker pull ghcr.io/mootikins/llama-swappo-halo:vulkan
```

## Features

- llama-swappo proxy with Ollama API translation
- GPU acceleration via ROCm/HIP or Vulkan
- Optional: whisper.cpp for speech-to-text (ROCm only)

## Build

```bash
# ROCm backend (default)
./build.sh

# Vulkan backend
./build.sh --vulkan

# ROCm with Whisper STT support
./build.sh --whisper

# Push to ghcr.io
./build.sh --ghcr
./build.sh --vulkan --ghcr
```

## Quick Start

```bash
# Run with ROCm
docker run --rm -it \
  --device /dev/dri --device /dev/kfd \
  -v /path/to/models:/models:ro \
  -v /path/to/config.yaml:/app/config.yaml:ro \
  -p 8080:8080 \
  ghcr.io/mootikins/llama-swappo-halo:latest \
  -config /app/config.yaml

# Run with Vulkan (no /dev/kfd needed)
docker run --rm -it \
  --device /dev/dri \
  -v /path/to/models:/models:ro \
  -v /path/to/config.yaml:/app/config.yaml:ro \
  -p 8080:8080 \
  ghcr.io/mootikins/llama-swappo-halo:vulkan \
  -config /app/config.yaml
```

## Configuration

See [llama-swappo documentation](https://github.com/Mootikins/llama-swappo) for config.yaml format.

**Note:** The llama-server binary path differs between backends:
- ROCm: `/usr/local/bin/llama-server`
- Vulkan: `/usr/bin/llama-server`

## Whisper STT

The whisper-enabled image must be built locally (ROCm toolchain ~5GB exceeds CI runner limits):

```bash
./build.sh --whisper
```

Whisper is only supported with the ROCm backend. When built with `--whisper`, the image includes:

- `/app/whisper-server` - HTTP server for transcription
- `/app/whisper-cli` - CLI tool for transcription
- `ffmpeg` for audio processing

## ROCm vs Vulkan

| Feature | ROCm | Vulkan |
|---------|------|--------|
| Compute performance | Higher | Good |
| gfx1151 stability | Experimental | Stable |
| Whisper support | Yes | No |
| Required devices | `/dev/dri`, `/dev/kfd` | `/dev/dri` |

**Recommendation:** Use Vulkan for gfx1151 (Strix Point) until ROCm support matures.

## Requirements

- AMD Strix Halo APU (gfx1151) or compatible
- For ROCm: ROCm drivers + `/dev/dri` and `/dev/kfd`
- For Vulkan: Mesa RADV + `/dev/dri`

## License

MIT
