FROM runpod/worker-comfyui:latest-base

# Update ComfyUI core to the latest version. The pre-built base image above
# was built at some point in the past on Docker Hub and doesn't automatically
# track new ComfyUI releases — this is why native nodes like SCAIL2ColoredMask
# and int8_tensorwise quantization support (added to ComfyUI core more recently
# than this image's build) weren't found at runtime. Using direct git commands
# rather than `comfy update`, since that command internally does a plain
# `git pull`, which fails here — this base image's ComfyUI checkout sits on a
# detached tag (not a branch), and `pull` needs a branch to merge into.
WORKDIR /comfyui
RUN git fetch --all --tags && \
    git reset --hard && \
    git checkout $(git describe --tags $(git rev-list --tags --max-count=1)) && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir "transformers>=4.50.3,<5" "huggingface-hub<1.0"

# Install the full CUDA 13.0 development toolkit. The base image ships only a
# stripped-down CUDA install (enough to run existing compiled code, but
# missing headers like cusparse.h needed to compile new CUDA code from
# source) — confirmed by hitting this exact gap when building SageAttention
# on the pod. This installs the complete toolkit rather than hunting down
# individual missing headers one at a time.
RUN apt-get update && apt-get install -y cuda-toolkit-13-0

# Install SageAttention, compiled from source against this exact container's
# PyTorch/CUDA build. No prebuilt wheel reliably matches any given PyTorch
# build in this ecosystem — confirmed by extensive testing — so this always
# builds from source rather than trying to match a wheel to a version.
RUN pip install --no-cache-dir git+https://github.com/thu-ml/SageAttention.git --no-build-isolation

RUN printf 'runpod_worker_comfy:\n  base_path: /runpod-volume/runpod-slim/ComfyUI/\n  checkpoints: models/checkpoints/\n  loras: models/loras/\n  vae: models/vae/\n  text_encoders: models/text_encoders/\n  clip_vision: models/clip_vision/\n  diffusion_models: models/diffusion_models/\n' > /comfyui/extra_model_paths.yaml

RUN mkdir -p /runpod-volume/output && rm -rf /comfyui/output && ln -s /runpod-volume/output /comfyui/output

WORKDIR /comfyui/custom_nodes

RUN git clone https://github.com/collbroGTR/comfyui-scail2-infinity

RUN git clone https://github.com/Comfy-Org/ComfyUI-Manager

RUN git clone https://github.com/kijai/ComfyUI-KJNodes && pip install --no-cache-dir -r ComfyUI-KJNodes/requirements.txt

RUN git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && pip install --no-cache-dir -r ComfyUI-VideoHelperSuite/requirements.txt

RUN git clone https://github.com/yolain/ComfyUI-Easy-Use && pip install --no-cache-dir -r ComfyUI-Easy-Use/requirements.txt

RUN git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation && \
    pip install --no-cache-dir -r ComfyUI-Frame-Interpolation/requirements-no-cupy.txt

RUN git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts

RUN git clone https://github.com/Comfy-Org/Nvidia_RTX_Nodes_ComfyUI && pip install --no-cache-dir nvidia-vfx

# Smoke-test that ComfyUI actually starts with everything installed above —
# core, custom nodes, all of it. This catches a startup-breaking dependency
# HERE at build time, with a clear error message, instead of discovering it
# later as a confusing "server not reachable" failure on a live, already-paid-for
# worker.
WORKDIR /comfyui
RUN timeout 300 python main.py --quick-test-for-ci --cpu

# NOTE: models are intentionally NOT copied into this image.
# They stay on your Network Volume (already populated), which you attach
# to the endpoint separately — that's what keeps this image small and fast
# to build, instead of a 50GB+ Docker push.

WORKDIR /comfyui
