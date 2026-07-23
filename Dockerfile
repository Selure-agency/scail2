# Base: RunPod's own ComfyUI serverless worker image.
# Already has ComfyUI + the serverless request handler wired up correctly —
# we're only adding the custom nodes your workflow actually needs on top of it.
FROM runpod/worker-comfyui:latest-base

# Update ComfyUI core to the latest version. The pre-built base image above
# was built at some point in the past on Docker Hub and doesn't automatically
# track new ComfyUI releases — this is why native nodes like SCAIL2ColoredMask
# (added to ComfyUI core more recently than this image's build) weren't found
# at runtime. Using direct git commands rather than `comfy update`, since that
# command internally does a plain `git pull`, which fails here — this base
# image's ComfyUI checkout sits on a detached tag (not a branch), and `pull`
# needs a branch to merge into. Fetching + checking out the newest tag
# directly sidesteps that restriction entirely.
WORKDIR /comfyui
# ComfyUI's own requirements.txt allows unbounded transformers/huggingface-hub
# versions. A fresh install can pull breaking major versions (transformers 5.x /
# huggingface-hub 1.x) that crash ComfyUI at startup — surfacing as a misleading
# "ComfyUI server not reachable" error at runtime instead of a clear build error.
# This is the exact same pin the base image's own maintainers use, for the same reason.
RUN git fetch --all --tags && \
    git reset --hard && \
    git checkout $(git describe --tags $(git rev-list --tags --max-count=1)) && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir "transformers>=4.50.3,<5" "huggingface-hub<1.0"

# Tell ComfyUI to also look on the Network Volume for models. Mounting the
# volume alone doesn't do this automatically — ComfyUI only checks its own
# internal /comfyui/models/ folder by default. On a pod, this same volume
# mounts at /workspace; on serverless, it mounts at /runpod-volume instead —
# same files, different path, hence this explicit config.
RUN printf 'runpod_worker_comfy:\n  base_path: /runpod-volume/runpod-slim/ComfyUI/\n  checkpoints: models/checkpoints/\n  loras: models/loras/\n  vae: models/vae/\n  text_encoders: models/text_encoders/\n  clip_vision: models/clip_vision/\n  diffusion_models: models/diffusion_models/\n' > /comfyui/extra_model_paths.yaml

WORKDIR /comfyui/custom_nodes

# Redirect ComfyUI's output folder onto the Network Volume via symlink.
# Root cause found by reading the actual handler.py source: this worker's API
# response handler only recognizes "images"-keyed node outputs. VHS_VideoCombine
# (used for all your final video outputs) produces a "gifs"-keyed output instead,
# which the handler explicitly does not support returning — confirmed directly
# in their code, not inferred. The video generates successfully either way; it's
# only the "hand it back through the API response" step that's unsupported.
# This symlink means the finished file lands on your persistent volume instead,
# where it can be pulled down with the same `aws s3 cp` you already used for
# uploading input files — sidestepping the limitation entirely rather than
# fighting it.
RUN mkdir -p /runpod-volume/output && rm -rf /comfyui/output && ln -s /runpod-volume/output /comfyui/output

# --- Custom nodes, in the same order your pod's boot log showed them loading ---

# SCAIL-2 Infinity (WanSCAILInfinity) — unlimited-length video wrapper
RUN git clone https://github.com/collbroGTR/comfyui-scail2-infinity

# KJNodes — PathchSageAttentionKJ, ModelPatchTorchSettings
RUN git clone https://github.com/kijai/ComfyUI-KJNodes && \
    pip install --no-cache-dir -r ComfyUI-KJNodes/requirements.txt

# Video Helper Suite — VHS_LoadVideo, VHS_VideoCombine
RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    pip install --no-cache-dir -r ComfyUI-VideoHelperSuite/requirements.txt

# Easy-Use — easy imageColorMatch, easy clearCacheAll, easy cleanGpuUsed
RUN git clone https://github.com/yolain/ComfyUI-Easy-Use && \
    pip install --no-cache-dir -r ComfyUI-Easy-Use/requirements.txt

# Frame Interpolation — RIFE VFI (using the no-cupy requirements file;
# this repo has no plain requirements.txt, and its install.py CUDA-detection
# script is documented as unreliable in automated/headless builds like this one)
RUN git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation && \
    pip install --no-cache-dir -r ComfyUI-Frame-Interpolation/requirements-no-cupy.txt

# Custom Scripts (pysssss) — MathExpression|pysssss
# (no pip install needed — this repo has no requirements.txt, it's a pure
# JS/UI extension pack with no extra Python dependencies)
RUN git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts

# NVIDIA RTX Nodes — RTXVideoSuperResolution (needs the nvidia-vfx package too)
RUN git clone https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI && \
    pip install --no-cache-dir nvidia-vfx

# NOTE: models are intentionally NOT copied into this image.
# They stay on your Network Volume (already populated), which you attach
# to the endpoint separately — that's what keeps this image small and fast
# to build, instead of a 50GB+ Docker push.

# Smoke-test that ComfyUI actually starts with everything installed above —
# core, custom nodes, all of it. This catches a startup-breaking dependency
# HERE at build time, with a clear error message, instead of discovering it
# later as a confusing "server not reachable" failure on a live, already-paid-for
# worker (exactly what just happened before this line was added).
WORKDIR /comfyui
RUN timeout 300 python main.py --quick-test-for-ci --cpu

WORKDIR /comfyui
