# OpenFOAM GPU H200

Docker build of the experimental OpenCFD OpenFOAM GPU implementation targeting NVIDIA H200 GPUs.

## Target

- NVIDIA H200
- NVIDIA Hopper architecture
- Compute capability 9.0
- CUDA 12.6
- NVIDIA HPC SDK 24.11
- OpenFOAM GPU `feature-gpu` branch
- Managed memory (`mem:managed`): the target H200 nodes have no unified memory
- Umpire 2025.03.0 memory pool

## Build

Build on a 16 vCPU / 32 GiB CPU-only EC2 instance (several hours), then push:

```bash
docker build -t openfoam-gpu-h200:latest .
docker tag openfoam-gpu-h200:latest ghcr.io/ice-kold/openfoam-gpu-h200:latest
docker push ghcr.io/ice-kold/openfoam-gpu-h200:latest
```

The GitHub Actions workflow starts only by hand; a hosted runner is too small for this build.

## Container

The completed image is published to:

```text
ghcr.io/ice-kold/openfoam-gpu-h200:latest
```