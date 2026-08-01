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

# Install the full CUDA 12.8 development toolkit, plus Python's development
# headers. The base image ships only a stripped-down CUDA install (enough to
# run existing compiled code, but missing headers like cusparse.h needed to
# compile new CUDA code from source) — confirmed by hitting this exact gap
# when building SageAttention on the pod. Python.h is a separate gap on top
# of that — needed because SageAttention compiles actual Python C extensions,
# not just CUDA kernels, and dev headers aren't included by default.
# NOTE: CUDA version here must match what this container's PyTorch was
# actually built against (12.8) — not necessarily the same version as any
# other pod or container, confirmed by a real version-mismatch build failure.
RUN apt-get update && apt-get install -y cuda-toolkit-12-8 python3-dev python3.12-dev

# Install SageAttention, compiled from source against this exact container's
# PyTorch/CUDA build. No prebuilt wheel reliably matches any given PyTorch
# build in this ecosystem — confirmed by extensive testing — so this always
# builds from source rather than trying to match a wheel to a version.
# TORCH_CUDA_ARCH_LIST must be set explicitly here: unlike the pod (which has
# a real GPU attached, letting the build auto-detect the target architecture),
# this Docker build runs on a GPU-less build server, so there's no hardware
# to detect from — confirmed by the exact failure this caused on the first
# two attempts. 12.0 = Blackwell (your RTX PRO 6000's architecture).
ENV TORCH_CUDA_ARCH_LIST="12.0"
RUN pip install --no-cache-dir git+https://github.com/thu-ml/SageAttention.git --no-build-isolation

RUN printf 'runpod_worker_comfy:\n  base_path: /runpod-volume/runpod-slim/ComfyUI/\n  checkpoints: models/checkpoints/\n  loras: models/loras/\n  vae: models/vae/\n  text_encoders: models/text_encoders/\n  clip_vision: models/clip_vision/\n  diffusion_models: models/diffusion_models/\n' > /comfyui/extra_model_paths.yaml

RUN mkdir -p /runpod-volume/output && rm -rf /comfyui/output && ln -s /runpod-volume/output /comfyui/output

WORKDIR /comfyui/custom_nodes

RUN git clone https://github.com/collbroGTR/comfyui-scail2-infinity

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
