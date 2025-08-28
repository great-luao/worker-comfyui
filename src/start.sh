#!/usr/bin/env bash

echo "=== ComfyUI Worker Starting ==="

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Environment detection
COMFYUI_PATH=""
PYTHON_CMD=""

# Check for ComfyUI in volume
if [ -f "/workspace/ComfyUI/main.py" ] && [ -d "/workspace/ComfyUI/com_venv" ]; then
    echo "✅ Found ComfyUI in volume: /workspace/ComfyUI"
    if [ -f "/workspace/ComfyUI/com_venv/bin/python" ]; then
        echo "✅ Found virtual environment"
        COMFYUI_PATH="/workspace/ComfyUI"
        # Activate virtual environment
        export VIRTUAL_ENV="/workspace/ComfyUI/com_venv"
        export PATH="$VIRTUAL_ENV/bin:$PATH"
        PYTHON_CMD="python"
        echo "✅ Activated virtual environment"
    fi
else
    echo "❌ No ComfyUI found in /workspace/ComfyUI"
    echo "Please ensure your network volume is properly mounted with:"
    echo "  - /workspace/ComfyUI/main.py"
    echo "  - /workspace/ComfyUI/com_venv/"
    exit 1
fi

# Check and install API dependencies if needed
echo "📥 Checking API dependencies..."
if $PYTHON_CMD -c "import runpod; import requests; import websocket" 2>/dev/null; then
    echo "✅ API dependencies already installed"
else
    echo "Installing missing API dependencies..."
    $PYTHON_CMD -m pip install --no-cache-dir runpod requests websocket-client
fi

# Copy extra model paths if exists
if [ -f "/tmp/extra_model_paths.yaml" ] && [ -d "$COMFYUI_PATH" ]; then
    cp /tmp/extra_model_paths.yaml $COMFYUI_PATH/
    echo "✅ Copied extra_model_paths.yaml"
fi

# Set ComfyUI-Manager to offline mode if exists
if [ -d "$COMFYUI_PATH/custom_nodes/ComfyUI-Manager" ]; then
    comfy-manager-set-mode offline || echo "Could not set ComfyUI-Manager to offline mode"
fi

# Set log level
: "${COMFY_LOG_LEVEL:=INFO}"

echo "🚀 Starting ComfyUI from: $COMFYUI_PATH"

# Start ComfyUI
$PYTHON_CMD -u $COMFYUI_PATH/main.py \
    --disable-auto-launch \
    --disable-metadata \
    --listen \
    --verbose "${COMFY_LOG_LEVEL}" \
    --log-stdout &

COMFY_PID=$!
echo "📊 ComfyUI started with PID: $COMFY_PID"

# Wait for ComfyUI to be ready
echo "⏳ Waiting for ComfyUI to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:8188/ > /dev/null 2>&1; then
        echo "🎉 ComfyUI is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Start RunPod Handler
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "🌐 Starting RunPod Handler in local API mode..."
    $PYTHON_CMD -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "🚀 Starting RunPod Handler..."
    $PYTHON_CMD -u /handler.py
fi