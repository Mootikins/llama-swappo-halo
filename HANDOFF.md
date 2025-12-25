# HANDOFF: llama-swappo-halo Migration to ghcr.io

## Current Status: TESTING PASSED ✅

### Validation Results (2025-12-25)
```
OpenAI API (https://llama.krohnos.io/v1/models): 24 models ✅
Ollama API (https://llama.krohnos.io/api/tags): 24 models ✅
Chat completion test: Working ✅
Pod running from ghcr.io/mootikins/llama-swappo-halo:latest ✅
```

## Architecture

**Key Insight:** The `kyuz0/amd-strix-halo-toolboxes:rocm-6.4.4-rocwmma` base image already includes llama.cpp with ROCm pre-built. We just add llama-swappo (Go proxy with Ollama API translation) on top.

```
┌─────────────────────────────────────────┐
│ ghcr.io/mootikins/llama-swappo-halo     │
├─────────────────────────────────────────┤
│ /app/llama-swap (Go proxy)              │ ← Built in CI
├─────────────────────────────────────────┤
│ kyuz0/amd-strix-halo-toolboxes          │
│ - /usr/local/bin/llama-server           │ ← Pre-built
│ - /usr/local/bin/llama-*                │
│ - ROCm 6.4.4 + rocwmma                  │
│ - Fedora 43                             │
└─────────────────────────────────────────┘
```

## Remaining Tasks

### 1. Clean up krohnos-k3s (NEXT)

**Old files to archive/remove:**
```
~/krohnos-k3s/docker/llama-swappo-halo/
├── .dockerignore
├── build.sh
├── Dockerfile.llama-swappo-halo
├── llama-swappo-fork.tar (8GB - DELETE, not in git)
└── test-config.yaml
```

**Actions:**
```bash
# Backup old Dockerfile
mkdir -p ~/backups/krohnos-k3s-docker
cp -r ~/krohnos-k3s/docker/llama-swappo-halo ~/backups/krohnos-k3s-docker/

# Remove the 8GB tar (not tracked in git anyway)
rm ~/krohnos-k3s/docker/llama-swappo-halo/llama-swappo-fork.tar

# Remove the docker directory from krohnos-k3s
rm -rf ~/krohnos-k3s/docker/llama-swappo-halo

# Commit the removal
cd ~/krohnos-k3s
git add -A
git commit -m "refactor: remove llama-swappo-halo docker dir, now at github.com/Mootikins/llama-swappo-halo"
```

### 2. Update krohnos-k3s deployment (DONE)

Already updated:
- `~/krohnos-k3s/applications/ai/llama-swappo/deployment.yaml`
  - Changed: `image: ghcr.io/mootikins/llama-swappo-halo:latest`
  - Changed: `imagePullPolicy: Always`

**Commit this change:**
```bash
cd ~/krohnos-k3s
git add applications/ai/llama-swappo/deployment.yaml
git commit -m "feat: use ghcr.io/mootikins/llama-swappo-halo for llama-swappo deployment"
```

### 3. Security Check (DONE)

**llama-swappo-halo repo - NO SECRETS FOUND:**
- `.env.example` - template only
- `config/config.yaml.example` - template only
- `traefik/*.yml` - example configs with placeholder comments
- `.github/workflows/build.yml` - uses `secrets.GITHUB_TOKEN` (standard)

**No force-push needed.**

### 4. Update AGENTS.md in krohnos-k3s

Update the deployment section to reference ghcr.io:
```markdown
### Deployment Steps
1. **Images auto-build on push to github.com/Mootikins/llama-swappo-halo**
2. **Deploy to K3s**:
   kubectl apply -k applications/ai/llama-swappo/
```

## Repository Links

- **Container source:** https://github.com/Mootikins/llama-swappo-halo
- **Container image:** ghcr.io/mootikins/llama-swappo-halo:latest
- **llama-swappo fork:** https://github.com/mootikins/llama-swappo
- **kyuz0 toolboxes:** https://github.com/kyuz0/amd-strix-halo-toolboxes

## CI/CD Flow

```
Push to Mootikins/llama-swappo-halo main
    ↓
GitHub Actions builds Containerfile
    ↓
Pushes to ghcr.io/mootikins/llama-swappo-halo:latest
    ↓
k3s pulls on next pod restart (imagePullPolicy: Always)
```

**To force update:**
```bash
kubectl rollout restart deployment/llama-swappo -n ai-services
```

## Files in llama-swappo-halo

```
.github/workflows/build.yml  - CI: builds and pushes to ghcr.io
Containerfile                - Main build (llama-swappo + kyuz0 toolbox)
Containerfile.stt            - With whisper (copies from whisper-stt-rocm)
build.sh                     - Local build script (--ghcr to push)
LICENSE                      - MIT
config/config.yaml.example   - Example llama-swap config
docker-compose*.yml          - For standalone docker usage
traefik/                     - Traefik configs for standalone
```

## Target Hardware

- **GMKtec EVO X2** (AMD Strix Halo, gfx1151)
- 128GB unified memory
- ROCm 6.4.4 with rocwmma optimizations

## Quick Commands

```bash
# Rebuild and push from local
cd ~/llama-swappo-halo
./build.sh --ghcr

# Check CI status
gh run list -R Mootikins/llama-swappo-halo

# Restart pod to pull latest
kubectl rollout restart deployment/llama-swappo -n ai-services

# Check pod logs
kubectl logs -n ai-services -l app=llama-swappo -f
```
