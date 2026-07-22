# Base: RunPod's own ComfyUI serverless worker image.
# Already has ComfyUI + the serverless request handler wired up correctly —
# we're only adding the custom nodes your workflow actually needs on top of it.
FROM runpod/worker-comfyui:latest-base

# Update ComfyUI core to the latest version. The pre-built base image above
# was built at some point in the past on Docker Hub and doesn't automatically
# track new ComfyUI releases — this is why native nodes like SCAIL2ColoredMask
# (added to ComfyUI core more recently than this image's build) weren't found
# at runtime. comfy-cli (already present in this base image) handles this.
RUN comfy --workspace /comfyui update

WORKDIR /comfyui/custom_nodes

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

WORKDIR /comfyui
