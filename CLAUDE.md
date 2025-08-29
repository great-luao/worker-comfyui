# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目目标

我们的目标是将这个 RunPod ComfyUI worker 项目与我们在 network volume 中预装的 ComfyUI 实例结合，实现 serverless 部署。具体来说：

1. **Volume 集成策略**：不在 Docker 镜像中包含 ComfyUI，而是依赖挂载的 network volume 中的 ComfyUI（位于 `/runpod-volume/ComfyUI`）
2. **Serverless 适配**：通过修改 Dockerfile 和启动脚本，让 worker 能够自动检测并使用 volume 中的 ComfyUI 环境
3. **最近的改动**（参考 commit `c9e5f18`）：已经调整了 Dockerfile 跳过 ComfyUI 安装步骤，改为直接使用 volume 中的现有安装

这种方法的优势：
- 减小 Docker 镜像体积
- 复用预配置的 ComfyUI 环境和模型
- 更灵活的模型管理（直接在 volume 中添加/更新）
- 更快的部署和启动时间

## 最新进展 (2025-08-29)

### 已完成的优化
1. **依赖检测修复**：修正了虚拟环境依赖检测，使用完整路径 `/runpod-volume/ComfyUI/com_venv/bin/python`
2. **移除冗余配置**：
   - 删除了 extra_model_paths.yaml 操作（直接使用 ComfyUI 默认路径）
   - 移除了 ComfyUI-Manager 相关代码（volume 中未安装）
   - 删除了 custom node 安装脚本
3. **Docker 优化**：
   - 移除了多余的多阶段构建（`FROM base AS final`）
   - 更新 container name 为 `worker-comfyui`
   - 修正 volume 挂载路径为 `/runpod-volume/ComfyUI:/runpod-volume/ComfyUI`
4. **超时配置**：延长 ComfyUI 初始化超时到 5 分钟，检测间隔 30 秒
5. **调试增强**：添加了 debug_start.sh 脚本用于诊断容器启动问题

### 已知依赖要求
ComfyUI 虚拟环境 (`/runpod-volume/ComfyUI/com_venv`) 必须预装以下包：
- runpod
- requests  
- websocket-client
- paramiko (runpod 依赖)
- aiohttp-retry (runpod 依赖)
- boto3 (runpod 依赖)
- fastapi[all] (runpod 依赖)

### 测试状态
- ✅ 本地 docker-compose 测试成功
- ✅ FLUX 模型工作流测试通过（耗时约 4 分钟）
- ⚠️ RunPod serverless 部署需要进一步调试（容器创建失败问题）

## Project Overview

This is a RunPod serverless worker for ComfyUI - it allows running ComfyUI workflows as serverless API endpoints on the RunPod platform. The worker handles workflow execution, image processing, and optional S3 uploads.

## Key Architecture

### Core Components

1. **handler.py** - Main serverless handler that:
   - Validates incoming workflow requests
   - Manages WebSocket connections to ComfyUI server
   - Handles image uploads and downloads
   - Returns results as base64 strings or S3 URLs

2. **src/start.sh** - Startup script that:
   - Detects and activates ComfyUI from network volume at `/runpod-volume/ComfyUI`
   - Starts ComfyUI server on port 8188
   - Launches the RunPod handler

3. **Docker Setup** - Multi-stage Dockerfile that:
   - Uses nvidia/cuda base image for GPU support
   - Installs Python 3.12 and creates virtual environment with uv
   - **重要改动**：跳过 ComfyUI 安装，期望从 network volume 中使用

### Important Paths

- ComfyUI installation: `/runpod-volume/ComfyUI` (from network volume)
- Virtual environment: `/runpod-volume/ComfyUI/com_venv`
- Test workflows: `test_resources/workflows/`
- Test input example: `test_input.json`

## Common Commands

### Git Operations
```bash
# Push to GitHub using SSH key (in Pod/container environment)
GIT_SSH_COMMAND="ssh -i /tmp/id_github_temp -o StrictHostKeyChecking=no" git push origin main

# Pull from GitHub using SSH key
GIT_SSH_COMMAND="ssh -i /tmp/id_github_temp -o StrictHostKeyChecking=no" git pull origin main

# Note: This method bypasses host key verification and directly uses the SSH key,
# which is ideal for container environments where SSH configuration is ephemeral
```

### Testing
```bash
# Run unit tests
python -m unittest discover

# Test with specific input
python handler.py --test_input test_input.json
```

### Local Development
```bash
# Setup virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
# or
.\.venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt

# Run locally with Docker Compose
docker-compose up
```

### Docker Build
```bash
# Build base image
docker build -t runpod/worker-comfyui:dev-base --target base .

# Build with specific models (e.g., flux1-schnell)
docker build -t runpod/worker-comfyui:dev-flux1-schnell --target flux1-schnell .
```

## API Format

### Input Structure
```json
{
  "input": {
    "workflow": { /* ComfyUI workflow JSON */ },
    "images": [
      {
        "name": "input_image.png",
        "image": "base64_encoded_string"
      }
    ]
  }
}
```

### Output Structure (v5.0.0+)
```json
{
  "output": {
    "images": [
      {
        "filename": "ComfyUI_00001_.png",
        "type": "base64" | "s3_url",
        "data": "base64_string_or_url"
      }
    ]
  }
}
```

## Environment Variables

Key configuration options:
- `SERVE_API_LOCALLY`: Set to "true" for local testing
- `COMFY_LOG_LEVEL`: ComfyUI log level (default: INFO)
- `REFRESH_WORKER`: Force worker refresh after each job
- `WEBSOCKET_RECONNECT_ATTEMPTS`: WebSocket reconnect attempts (default: 5)
- `WEBSOCKET_RECONNECT_DELAY_S`: Delay between reconnect attempts (default: 3)s

## Machine Learning Context

This project works with ComfyUI, a node-based interface for Stable Diffusion and other diffusion models. Key ML concepts:
- Supports various diffusion models (FLUX, SDXL, SD3)
- Handles text encoders, VAEs, and checkpoints
- Processes workflows as node graphs for image generation
- GPU-accelerated inference via CUDA
- 专业的 Diffusion 模型知识对于理解和调试 workflow 非常重要

## Development Notes

- **关键依赖**：Worker 期望 ComfyUI 已经预装在 network volume 的 `/runpod-volume/ComfyUI` 目录
- **虚拟环境**：ComfyUI 的虚拟环境应该位于 `/runpod-volume/ComfyUI/com_venv`
- WebSocket connection management is critical - includes reconnection logic and diagnostics
- Images are processed as base64 strings with size limits (10MB for /run, 20MB for /runsync)
- Test resources include example workflows for different models (flux, sdxl, sd3)
- 当修改启动逻辑时，确保 `src/start.sh` 能正确检测和激活 volume 中的 ComfyUI