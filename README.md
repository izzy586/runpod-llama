# runpod-llama

One command that turns a fresh RunPod GPU pod into a llama.cpp server for SillyTavern. Everything heavy (llama.cpp, the model, your API key) is stored on your RunPod **network volume**, so it downloads once and every future pod starts in seconds.

Default model: **L3-8B-Stheno-v3.2 Q8_0** (best-quality 8B quant; ~8.5 GB, trivial for a 24 GB 3090, ~100 tok/s).

## Deploy the pod (RunPod website)

1. If the old A6000 pod (`overall_orange_lemming`) is still listed under **Pods**, terminate it first.
2. **Pods → Deploy**:
   - GPU: **RTX 3090** (24 GB). Community Cloud is ~US$0.22/hr, Secure Cloud ~US$0.50/hr.
   - Datacenter: **the same one your network volume lives in** (RunPod shows the volume's datacenter when you attach it — a pod in a different datacenter cannot see the volume).
   - Attach your existing **network volume**.
   - Template: **RunPod PyTorch** (any recent version).
   - Under **Expose HTTP Ports**, make sure **5000** is listed (add it if not).
3. Start the pod, open its web terminal (or SSH), and run the one command below.

## The one command

```bash
curl -sL https://raw.githubusercontent.com/izzy586/runpod-llama/main/setup.sh -o /workspace/setup.sh; bash /workspace/setup.sh
```

It ends by printing your endpoint URL and API key. Keep that output.

## What setup.sh does (rundown)

1. **llama.cpp**: downloads the pinned CUDA 12.8 build (`b12444`) plus its CUDA runtime libs into `/workspace/llama.cpp`. Skipped on later runs — the binary lives on your volume, not the pod's throwaway disk.
2. **Model**: downloads the GGUF from Hugging Face into `/workspace/models` (resumable; only moved into place when complete). Skipped if already there.
3. **API key**: generates one random key, stores it in `/workspace/.llama_api_key`, reuses it every run. The RunPod proxy URL is public internet, so the key keeps strangers off your GPU.
4. **Launch**: kills any old server on the port, then starts `llama-server` in the background (`nohup`, log at `/workspace/llama-server.log`) with all layers on the GPU, 8192 context, flash attention, bound to `0.0.0.0:5000`.
5. **Health check + printout**: waits until the server answers, then prints the SillyTavern endpoint and the API key.

## Using Vast.ai instead of RunPod

Same script, same one command. Differences:

- Template: **PyTorch (Vast)** — the official one, CUDA 12 preinstalled. Before renting, **edit the template to expose port 5000**, set disk to **~40 GB**, and pick a **verified** RTX 3090 host, **On-Demand** (not Interruptible).
- On Vast, `/workspace` is the instance disk: it survives stops but is **wiped when the instance is destroyed**. No problem — re-running the one command re-downloads everything automatically (a few minutes for the model).
- There is no proxy URL. Your endpoint is `http://<public IP>:<external port>/v1` — after the instance starts, the **Instances** tab shows the public IP and the external port forwarded to 5000. The script prints this reminder too.

## Connect SillyTavern (on your Mac)

You no longer need the local llama-server terminal at all. Just SillyTavern:

```bash
cd ~/Desktop/SillyTavern; ./start.sh
```

In SillyTavern (phone or Mac):

- API: **Chat Completion**
- Source: **Custom (OpenAI-compatible)**
- Endpoint: the URL the script printed, e.g. `https://<pod-id>-5000.proxy.runpod.net/v1`
- API key: the key the script printed
- Your chats, characters, Memory Books and Vector Storage all work as before — they live in SillyTavern; only the model moved to the 3090.

## Changing the model

Edit the two lines at the top of `setup.sh` (here on GitHub, then re-run the one command — or edit the copy at `/workspace/setup.sh` on the pod):

```bash
MODEL_REPO="bartowski/L3-8B-Stheno-v3.2-GGUF"
MODEL_FILE="L3-8B-Stheno-v3.2-Q8_0.gguf"
```

A 24 GB 3090 also fits 14B models at Q8/Q6 and 32B models at Q4 (tight, shorter context). New downloads land on the volume and persist.

## Costs and pod hygiene

- GPU billing runs while the pod exists. **Terminate the pod when you're done** — everything needed for next time is on the volume, which costs only a few dollars a month in storage.
- Because setup is one paste, a fresh pod is chatting again in about a minute (plus model download the very first time only).

## Troubleshooting

- **Script prints the endpoint but SillyTavern can't connect**: the pod's Expose HTTP Ports is missing 5000 — edit the pod or redeploy with 5000 exposed.
- **`/workspace` is empty / no ComfyUI folder**: the pod is in a different datacenter than your volume. Redeploy in the volume's datacenter.
- **Server didn't come up**: `tail -50 /workspace/llama-server.log` shows why.
- **Check the server from the pod terminal**: `curl -s -H "Authorization: Bearer $(cat /workspace/.llama_api_key)" http://127.0.0.1:5000/health`
