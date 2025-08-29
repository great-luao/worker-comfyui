# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# === MODIFIED FOR VOLUME-BASED DEPLOYMENT ===
# Original version created /opt/venv here with uv
# We now use ComfyUI's pre-existing venv from /workspace/ComfyUI/com_venv
# This significantly reduces image size and ensures consistency with the volume environment

# Install curl for health checks in start.sh
RUN apt-get update && apt-get install -y curl && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure basic Python tools are available at system level (fallback only)
RUN python3.12 -m pip install --upgrade pip setuptools wheel 2>/dev/null || true

# Set working directory to root
WORKDIR /

# Extra model paths removed - using ComfyUI's default model paths from volume

# === COMMENTED OUT: Dependencies are pre-installed in ComfyUI's venv from volume ===
# # Install Python runtime dependencies for the handler
# RUN uv pip install runpod requests websocket-client
# === END COMMENTED SECTION ===
# Note: runpod, requests, websocket-client must be pre-installed in /workspace/ComfyUI/com_venv

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add debug information during build
RUN echo "=== Build Debug Info ===" && \
    echo "Python version:" && python --version && \
    echo "Current directory:" && pwd && \
    echo "Files in root:" && ls -la / | head -20

# Create a debug wrapper script
RUN echo '#!/bin/bash' > /debug_start.sh && \
    echo 'echo "========================================="' >> /debug_start.sh && \
    echo 'echo "=== Container Starting at $(date) ==="' >> /debug_start.sh && \
    echo 'echo "========================================="' >> /debug_start.sh && \
    echo 'echo ""' >> /debug_start.sh && \
    echo 'echo "=== Environment Variables ==="' >> /debug_start.sh && \
    echo 'echo "RUNPOD_POD_ID: $RUNPOD_POD_ID"' >> /debug_start.sh && \
    echo 'echo "RUNPOD_GPU_COUNT: $RUNPOD_GPU_COUNT"' >> /debug_start.sh && \
    echo 'echo "WORKSPACE: $WORKSPACE"' >> /debug_start.sh && \
    echo 'echo "PWD: $(pwd)"' >> /debug_start.sh && \
    echo 'echo ""' >> /debug_start.sh && \
    echo 'echo "=== Checking /workspace directory ==="' >> /debug_start.sh && \
    echo 'if [ -d "/workspace" ]; then' >> /debug_start.sh && \
    echo '    echo "Contents of /workspace:"' >> /debug_start.sh && \
    echo '    ls -la /workspace/ | head -10' >> /debug_start.sh && \
    echo 'else' >> /debug_start.sh && \
    echo '    echo "/workspace directory NOT FOUND"' >> /debug_start.sh && \
    echo 'fi' >> /debug_start.sh && \
    echo 'echo ""' >> /debug_start.sh && \
    echo 'echo "=== Checking for ComfyUI ==="' >> /debug_start.sh && \
    echo 'if [ -f "/workspace/ComfyUI/main.py" ]; then' >> /debug_start.sh && \
    echo '    echo "✓ Found ComfyUI at /workspace/ComfyUI"' >> /debug_start.sh && \
    echo 'else' >> /debug_start.sh && \
    echo '    echo "✗ ComfyUI NOT found at /workspace/ComfyUI"' >> /debug_start.sh && \
    echo '    echo "Searching for main.py in other locations:"' >> /debug_start.sh && \
    echo '    find / -name "main.py" -path "*/ComfyUI/*" 2>/dev/null | head -5' >> /debug_start.sh && \
    echo 'fi' >> /debug_start.sh && \
    echo 'echo ""' >> /debug_start.sh && \
    echo 'echo "=== Checking for virtual environment ==="' >> /debug_start.sh && \
    echo 'if [ -d "/workspace/ComfyUI/com_venv" ]; then' >> /debug_start.sh && \
    echo '    echo "✓ Found venv at /workspace/ComfyUI/com_venv"' >> /debug_start.sh && \
    echo 'else' >> /debug_start.sh && \
    echo '    echo "✗ Virtual environment NOT found"' >> /debug_start.sh && \
    echo 'fi' >> /debug_start.sh && \
    echo 'echo ""' >> /debug_start.sh && \
    echo 'echo "=== Starting actual application ==="' >> /debug_start.sh && \
    echo 'exec /start.sh' >> /debug_start.sh && \
    chmod +x /debug_start.sh

# Set the default command to run the debug wrapper
CMD ["/debug_start.sh"]

# No need for model download stage since we use network volume