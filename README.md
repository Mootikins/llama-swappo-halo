# Llama Swappo Docker Compose

A complete Docker Compose setup for running Llama Swappo with Traefik reverse proxy and automatic HTTPS. Perfect for deploying AMD GPU-accelerated LLM inference services.

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose installed
- AMD GPU with ROCm drivers installed
- Sufficient system memory (32GB+ recommended for large models)
- Ports 80 and 443 available on the host

### 1. Configuration

Copy the environment template and configure it:

```bash
cp .env.example .env
```

Edit `.env` with your specific configuration:

```bash
# Required settings
DOMAIN=your-domain.com
MODELS_PATH=/path/to/your/models/directory
CONFIG_PATH=./config/config.yaml

# GPU settings (AMD ROCm)
ROCR_VISIBLE_DEVICES=0
HIP_VISIBLE_DEVICES=0
```

### 2. Directory Structure

Create the necessary directories:

```bash
# Create config directory for your config.yaml
mkdir -p config

# Create cache directory
mkdir -p cache

# Create certificates directory for Traefik
mkdir -p certs
```

### 3. Build (Optional)

You have two options for the Llama Swappo image:

#### Option A: Use Pre-built Image (Default)
Set `BUILD_LOCAL=false` in your `.env` file (this is the default).

#### Option B: Build from Source
If you want to build the image from source or customize it:

```bash
# Set build configuration in .env
BUILD_LOCAL=true
LLAMA_SWAPPO_BACKEND=rocm-6.4.4-rocwmma  # or: rocm-base, vulkan

# Build the image manually (optional)
cd docker
./build.sh

# Or let docker-compose build it automatically
docker-compose build
```

Available backends:
- `rocm-6.4.4-rocwmma` (recommended): ROCm with hipBLASLt optimization
- `rocm-6.4.4`: ROCm base libraries
- `vulkan-radv`: Vulkan-based rendering

### 4. Start Services

```bash
# Start all services in the background
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f
```

### 5. Access the Service

- **Main Service**: `https://your-domain.com`
- **Health Check**: `https://your-domain.com/health`
- **Metrics**: `https://your-domain.com/metrics`
- **Traefik Dashboard**: `https://traefik.your-domain.com` (if configured)

## 📁 File Structure

```
llama-swappo/
├── docker-compose.yml          # Main docker-compose configuration
├── docker-compose.prod.yml     # Production overrides
├── .env.example               # Environment variables template
├── .env                       # Your configuration (copy from .env.example)
├── docker/
│   ├── Dockerfile             # Llama Swappo Dockerfile
│   └── build.sh               # Build script for different backends
├── config/
│   └── config.yaml           # Llama Swappo configuration
├── traefik/
│   ├── traefik.yml           # Traefik static configuration
│   └── dynamic.yml           # Traefik dynamic configuration
├── certs/                    # SSL certificates directory
├── cache/                    # Llama cache directory
└── README.md                 # This file
```

## 🔧 Configuration

### Environment Variables

Key variables in `.env`:

| Variable | Description | Default |
|----------|-------------|---------|
| `DOMAIN` | Your domain name | `your-domain.com` |
| `MODELS_PATH` | Path to models directory | `/path/to/models` |
| `CONFIG_PATH` | Path to config.yaml | `./config/config.yaml` |
| `CACHE_PATH` | Cache directory path | `./cache` |
| `ROCR_VISIBLE_DEVICES` | AMD GPU devices | `0` |
| `LLAMA_SWAPPO_IMAGE` | Docker image name | `llama-swappo-halo-rocm-rocwmma:latest` |

### Llama Swappo Configuration

Your `config/config.yaml` should contain model definitions and service settings. Example structure:

```yaml
# Example config.yaml structure
models:
  embeddings:
    - name: "nomic-embed-text-v1.5"
      path: "/models/nomic-ai/nomic-embed-text-v1.5-GGUF/nomic-embed-text-v1.5.Q4_K_M.gguf"

  main:
    - name: "qwen2-7b-instruct"
      path: "/models/Qwen/Qwen2-7B-Instruct-GGUF/qwen2-7b-instruct-q4_k_m.gguf"

server:
  host: "0.0.0.0"
  port: 8080
  workers: 1

cache:
  directory: "/models/llama-cache"
  max_size: "80GB"
```

## 🔒 Security

### HTTPS/SSL

- **Development**: Self-signed certificates (browser warnings expected)
- **Production**: Use real domains with Let's Encrypt (configured by default)

### Authentication

- **Traefik Dashboard**: Basic authentication (admin:admin default - CHANGE!)
- **Metrics Endpoint**: Optional basic authentication
- **Main Service**: No authentication (add middleware if needed)

### Network Security

- Main service only accessible through Traefik reverse proxy
- Internal network isolation
- Security headers enabled by default
- GPU access restricted to privileged container

## 🚀 Deployment Options

### Development

```bash
# Start development environment
docker-compose up -d
```

### Production

```bash
# Start production environment with Let's Encrypt
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Monitoring Stack (Production)

The production configuration includes optional monitoring:

- **Jaeger**: Distributed tracing
- **Prometheus**: Metrics collection
- **Grafana**: Visualization dashboard

## 🐳 Container Details

### Llama Swappo Container

- **Image**: `llama-swappo-halo-rocm-rocwmma:latest`
- **Resources**: 32GB RAM minimum, 96GB limit
- **GPU**: Full AMD GPU access with privileged mode
- **Mounts**:
  - Models directory (read-only)
  - Configuration file (read-only)
  - GPU devices (`/dev/dri`, `/dev/kfd`)
  - Cache directory

### Traefik Container

- **Image**: `traefik:v2.11`
- **Ports**: 80 (HTTP), 443 (HTTPS)
- **Features**:
  - Automatic HTTPS certificates
  - HTTP to HTTPS redirection
  - Load balancing
  - Security headers
  - Rate limiting
  - Health checks

## 📊 Monitoring

### Health Checks

Both services include comprehensive health checks:

```bash
# Check service health
docker-compose exec llama-swappo curl -f http://localhost:8080/health

# Check Traefik health
docker-compose exec traefik traefik healthcheck --ping
```

### Metrics

- **Llama Swappo**: `https://your-domain.com/metrics`
- **Traefik**: Built-in Prometheus metrics
- **Production**: Full monitoring stack with Grafana

### Logs

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f llama-swappo
docker-compose logs -f traefik

# Follow logs with tail
docker-compose logs -f --tail=100
```

## 🛠️ Troubleshooting

### Common Issues

#### GPU Not Detected
```bash
# Check ROCm installation
rocminfo
clinfo

# Verify Docker GPU access
docker run --rm --device=/dev/dri --device=/dev/kfd rocm/pytorch rocm-smi
```

#### Certificate Issues
```bash
# Regenerate certificates (self-signed)
docker-compose restart traefik

# Clear browser cache for certificate issues
# Check certificate paths in ./certs/
```

#### Network Issues
```bash
# Check if ports are available
netstat -tlnp | grep -E ':(80|443)'

# Check Docker networks
docker network ls
docker network inspect llama-swappo_traefik-public
```

#### Memory Issues
```bash
# Check memory usage
docker stats

# Adjust memory limits in docker-compose.yml
# Reduce model cache size in config.yaml
```

### Debug Mode

Enable debug logging by modifying `.env`:

```bash
LOG_LEVEL=DEBUG
```

## 🌟 Features

- **🔒 Secure by Default**: HTTPS, security headers, network isolation
- **⚡ High Performance**: AMD GPU acceleration with ROCm
- **📈 Auto-Scaling**: Load balancing and health checks
- **🔧 Easy Configuration**: Environment-based configuration
- **📊 Monitoring**: Built-in metrics and optional monitoring stack
- **🛡️ Production Ready**: Separate production configuration
- **🔄 Zero Downtime**: Health checks and graceful restarts

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This Docker Compose configuration is provided as-is. Please refer to the individual project licenses for Llama Swappo, Traefik, and other components.

## 🆘 Support

For issues related to:

- **Llama Swappo**: Check the project's documentation
- **Traefik**: [Traefik Documentation](https://traefik.io/documentation/)
- **AMD GPU**: [AMD ROCm Documentation](https://rocm.docs.amd.com/)
- **Docker Compose**: [Docker Documentation](https://docs.docker.com/compose/)

---

**Note**: This configuration is optimized for AMD GPUs with ROCm support. For NVIDIA GPUs, you'll need to modify the GPU device mappings and runtime configuration.