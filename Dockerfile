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

# Copy model path configuration (will be placed in the volume later)
COPY src/extra_model_paths.yaml /tmp/extra_model_paths.yaml

# === COMMENTED OUT: Dependencies are pre-installed in ComfyUI's venv from volume ===
# # Install Python runtime dependencies for the handler
# RUN uv pip install runpod requests websocket-client
# === END COMMENTED SECTION ===
# Note: runpod, requests, websocket-client must be pre-installed in /workspace/ComfyUI/com_venv

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["/start.sh"]

# No need for model download stage since we use network volume
# Final stage is just the base stage
FROM base AS final