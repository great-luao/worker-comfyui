#!/usr/bin/env bash

echo "=== ComfyUI Worker Starting ==="
echo "📅 Startup time: $(date '+%Y-%m-%d %H:%M:%S')"

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
if [ -n "$TCMALLOC" ]; then
    export LD_PRELOAD="${TCMALLOC}"
    echo "✅ Using memory allocator: $TCMALLOC"
fi

# Environment detection
COMFYUI_PATH=""
PYTHON_CMD=""

# Check for ComfyUI in volume
echo "🔍 Checking for ComfyUI in volume..."
if [ ! -f "/runpod-volume/ComfyUI/main.py" ]; then
    echo "❌ ERROR: ComfyUI main.py not found at /runpod-volume/ComfyUI/main.py"
    echo "Please ensure your network volume is properly mounted."
    exit 1
fi

if [ ! -d "/runpod-volume/ComfyUI/com_venv" ]; then
    echo "❌ ERROR: Virtual environment not found at /runpod-volume/ComfyUI/com_venv"
    echo "Please ensure ComfyUI virtual environment is properly set up."
    exit 1
fi

if [ ! -f "/runpod-volume/ComfyUI/com_venv/bin/python" ]; then
    echo "❌ ERROR: Python executable not found in virtual environment"
    exit 1
fi

echo "✅ Found ComfyUI in volume: /runpod-volume/ComfyUI"
COMFYUI_PATH="/runpod-volume/ComfyUI"

# Activate virtual environment
export VIRTUAL_ENV="/runpod-volume/ComfyUI/com_venv"
export PATH="$VIRTUAL_ENV/bin:$PATH"
PYTHON_CMD="python"
echo "✅ Activated virtual environment: $VIRTUAL_ENV"

# Verify Python version and essential packages
echo "📋 System information:"
$PYTHON_CMD --version
$PYTHON_CMD -c "import torch; print(f'  PyTorch: {torch.__version__}')" 2>/dev/null || echo "  PyTorch: Not found"
$PYTHON_CMD -c "import torch; print(f'  CUDA Available: {torch.cuda.is_available()}')" 2>/dev/null || true

# Verify API dependencies are installed (no installation, just check)
echo "📥 Verifying API dependencies..."
# Use full path to ensure we're using the correct Python from venv
if ! /runpod-volume/ComfyUI/com_venv/bin/python -c "import runpod; import requests; import websocket" 2>/dev/null; then
    echo "❌ ERROR: Required API dependencies not found in virtual environment!"
    echo "Please ensure the following packages are installed in /runpod-volume/ComfyUI/com_venv:"
    echo "  - runpod (with its dependencies: paramiko, aiohttp-retry, boto3, fastapi)"
    echo "  - requests"
    echo "  - websocket-client"
    exit 1
fi
echo "✅ All API dependencies verified"

# Extra model paths removed - using ComfyUI's default model paths

# Set log level
: "${COMFY_LOG_LEVEL:=INFO}"

echo "🚀 Starting ComfyUI from: $COMFYUI_PATH"

# Start ComfyUI
echo "🚀 Starting ComfyUI server..."
echo "  Command: $PYTHON_CMD -u $COMFYUI_PATH/main.py --listen --port 8188"

$PYTHON_CMD -u $COMFYUI_PATH/main.py \
    --disable-auto-launch \
    --disable-metadata \
    --listen \
    --port 8188 \
    --verbose "${COMFY_LOG_LEVEL}" \
    --log-stdout &

COMFY_PID=$!
echo "📊 ComfyUI started with PID: $COMFY_PID"

# Verify the process actually started
sleep 2
if ! kill -0 $COMFY_PID 2>/dev/null; then
    echo "❌ ERROR: ComfyUI process died immediately after starting!"
    echo "Check the logs above for error details."
    exit 1
fi

# Wait for ComfyUI to be ready with better feedback
echo "⏳ Waiting for ComfyUI server to be ready on port 8188..."
MAX_WAIT=300  # Maximum 5 minutes wait time
WAIT_INTERVAL=30  # Check every 30 seconds
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if curl -s http://localhost:8188/ > /dev/null 2>&1; then
        echo "🎉 ComfyUI server is ready! (took ${ELAPSED}s)"
        # Double-check with a proper API endpoint
        if curl -s http://localhost:8188/system_stats > /dev/null 2>&1; then
            echo "✅ ComfyUI API endpoints verified"
        fi
        break
    fi
    
    # Check if process is still alive
    if ! kill -0 $COMFY_PID 2>/dev/null; then
        echo "❌ ERROR: ComfyUI process died while waiting for startup!"
        exit 1
    fi
    
    echo "  Waiting... (${ELAPSED}s / ${MAX_WAIT}s) - checking every ${WAIT_INTERVAL}s"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ ERROR: ComfyUI failed to start within ${MAX_WAIT} seconds (5 minutes)!"
    echo "Checking if process is still running..."
    if kill -0 $COMFY_PID 2>/dev/null; then
        echo "Process is running but not responding on port 8188"
        echo "Check firewall settings or port conflicts"
    else
        echo "Process has died"
    fi
    exit 1
fi

# Start RunPod Handler
echo "🔧 Starting RunPod Handler..."
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "  Mode: Local API server on port 8000"
    echo "  Command: $PYTHON_CMD -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0"
    $PYTHON_CMD -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "  Mode: RunPod serverless worker"
    echo "  Command: $PYTHON_CMD -u /handler.py"
    $PYTHON_CMD -u /handler.py
fi

# This should not be reached unless handler exits
echo "⚠️ Handler exited unexpectedly!"
exit 1