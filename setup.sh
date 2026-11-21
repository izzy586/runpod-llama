#!/usr/bin/env bash
# runpod-llama: one-command llama.cpp server on a RunPod GPU pod.
# Downloads llama.cpp (CUDA build) and the model ONCE onto your network
# volume (/workspace), then launches the server. Re-running it on a new
# pod skips the downloads and just starts the server.
set -euo pipefail

# ---------- settings (edit these to change the model) ----------
MODEL_REPO="QuantFactory/Llama-3.1-8B-Stheno-v3.4-GGUF"
MODEL_FILE="Llama-3.1-8B-Stheno-v3.4.Q8_0.gguf"
PORT=5000
CTX=32768
LLAMA_VER="b12444"
# ---------------------------------------------------------------

WORK=/workspace
LLAMA_DIR="$WORK/llama.cpp"
MODEL_DIR="$WORK/models"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
mkdir -p "$LLAMA_DIR" "$MODEL_DIR"

# 1) llama.cpp CUDA build + CUDA runtime libs (kept on the volume)
if [ ! -x "$LLAMA_DIR/llama-server" ]; then
  echo ">> Downloading llama.cpp $LLAMA_VER (CUDA 12.8)..."
  BASE="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_VER"
  curl -sL "$BASE/llama-$LLAMA_VER-bin-ubuntu-cuda-12.8-x64.tar.gz" -o /tmp/llama.tar.gz
  curl -sL "$BASE/cudart-llama-$LLAMA_VER-bin-ubuntu-cuda-12.8-x64.tar.gz" -o /tmp/cudart.tar.gz
  rm -rf /tmp/llama-x /tmp/cudart-x; mkdir -p /tmp/llama-x /tmp/cudart-x
  tar -xzf /tmp/llama.tar.gz -C /tmp/llama-x
  tar -xzf /tmp/cudart.tar.gz -C /tmp/cudart-x
  BIN_DIR="$(dirname "$(find /tmp/llama-x -name llama-server -type f | head -1)")"
  cp -r "$BIN_DIR"/. "$LLAMA_DIR"/
  find /tmp/cudart-x -name "*.so*" -exec cp {} "$LLAMA_DIR"/ \; 2>/dev/null || true
  echo ">> llama.cpp installed to $LLAMA_DIR"
fi

# 2) Model (kept on the volume; resumable download, moved into place when complete)
if [ ! -f "$MODEL_PATH" ]; then
  echo ">> Downloading $MODEL_FILE (one time, ~8.5 GB)..."
  curl -L -C - "https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_FILE" -o "$MODEL_PATH.tmp"
  mv "$MODEL_PATH.tmp" "$MODEL_PATH"
  echo ">> Model saved to $MODEL_PATH"
fi

# 3) API key (created once, kept on the volume, printed at the end)
KEY_FILE="$WORK/.llama_api_key"
if [ ! -f "$KEY_FILE" ]; then
  head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$KEY_FILE"
fi
API_KEY="$(cat "$KEY_FILE")"

# 4) Launch (kills any previous instance on this port first)
pkill -f "llama-server.*--port $PORT" 2>/dev/null || true
sleep 1
export LD_LIBRARY_PATH="$LLAMA_DIR:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
echo ">> Starting llama-server on port $PORT..."
nohup "$LLAMA_DIR/llama-server" -m "$MODEL_PATH" -ngl 99 -c "$CTX" -fa on \
  -ctk q8_0 -ctv q8_0 \
  --host 0.0.0.0 --port "$PORT" --api-key "$API_KEY" \
  > "$WORK/llama-server.log" 2>&1 &

# 5) Wait for health, then print how to connect
for i in $(seq 1 90); do
  if curl -s -H "Authorization: Bearer $API_KEY" "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo ""
echo "============================================================"
echo "  llama-server is UP on port $PORT"
echo ""
echo "  SillyTavern endpoint (Custom / OpenAI-compatible):"
if [ -n "${RUNPOD_POD_ID:-}" ]; then
  echo "  https://${RUNPOD_POD_ID}-${PORT}.proxy.runpod.net/v1"
else
  echo "  http://<instance public IP>:<external port mapped to $PORT>/v1"
  echo "  (Vast.ai: the Instances tab shows the IP and forwarded port.)"
fi
echo ""
echo "  API key: $API_KEY"
echo ""
echo "  Watch it work:  tail -f $WORK/llama-server.log"
echo "  When done: stop/terminate the instance to stop billing."
echo "  Everything needed for next time stays in /workspace."
echo "============================================================"
