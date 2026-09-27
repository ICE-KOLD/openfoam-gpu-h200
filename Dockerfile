# =============================================================================
# OpenFOAM GPU (feature-gpu) + Umpire memory pool - NVIDIA H200
#
# One image: ghcr.io/ice-kold/openfoam-gpu-h200:latest
#
# - NVIDIA HPC SDK 24.11, CUDA 12.6, Hopper (cc90), stdpar GPU offload
# - mem:managed: the USYD Run:ai H200 nodes have no unified memory
#   (nvidia-smi -q: "Addressing Mode : None"), so a mem:unified build stops
#   at start
# - Umpire 2025.03.0 memory pool (feature-gpu wiki), FOAM_MEMORY_POOL default
#
# Build on the 16 vCPU / 32 GiB EC2 builder (see aws_openfoam_setup.md):
#   docker build -t openfoam-gpu-h200:latest .
# =============================================================================

FROM nvcr.io/nvidia/nvhpc:24.11-devel-cuda12.6-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# System dependencies
# -----------------------------------------------------------------------------

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    flex \
    libfl-dev \
    bison \
    cmake \
    ninja-build \
    wget \
    curl \
    ca-certificates \
    zlib1g-dev \
    libboost-system-dev \
    libboost-thread-dev \
    libreadline-dev \
    libncurses-dev \
    libxt-dev \
    libopenmpi-dev \
    openmpi-bin \
    libscotch-dev \
    libptscotch-dev \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Clone official OpenFOAM GPU development branch
# -----------------------------------------------------------------------------

WORKDIR /opt

RUN git clone \
    --branch feature-gpu \
    --single-branch \
    https://gitlab.com/openfoam/gpu/openfoam-ecse.git \
    openfoam-gpu

WORKDIR /opt/openfoam-gpu

# -----------------------------------------------------------------------------
# Configure GPU build
#
# IMPORTANT:
# The GPU branch distinguishes between:
#
#   Nvidia      = NVIDIA compiler, CPU build
#   Nvidia-gpu  = NVIDIA compiler + GPU offload
#
# Nvidia-gpu enables stdpar GPU offloading and FOAM_OFFLOAD.
# -----------------------------------------------------------------------------

RUN sed -i \
    's/^export WM_COMPILER=.*/export WM_COMPILER=Nvidia-gpu/' \
    etc/bashrc

# Disable floating-point exception trapping by default
RUN printf '\nexport FOAM_SIGFPE=false\n' >> etc/prefs.sh

# -----------------------------------------------------------------------------
# GPU compiler flags: CUDA 12.6 and managed memory
#
# cuda12.6: the builder has no NVIDIA driver, so NVHPC cannot determine the
# CUDA version itself and otherwise falls back to 11.8.
# mem:managed instead of mem:unified: the H200 nodes have no unified memory.
# The memory setting is in every compiled file; a change needs a full rebuild.
# -----------------------------------------------------------------------------

RUN sed -i \
    's/-gpu=cc90,mem:unified,managed/-gpu=cc90,cuda12.6,mem:managed/g' \
    wmake/rules/General/Nvidia-gpu/c++

# -----------------------------------------------------------------------------
# Verify configuration before starting expensive compilation
# -----------------------------------------------------------------------------

RUN /bin/bash -lc '\
    source /opt/openfoam-gpu/etc/bashrc && \
    echo "==================================================" && \
    echo "OpenFOAM GPU build configuration" && \
    echo "==================================================" && \
    echo "WM_PROJECT_VERSION=$WM_PROJECT_VERSION" && \
    echo "WM_PROJECT_DIR=$WM_PROJECT_DIR" && \
    echo "WM_COMPILER=$WM_COMPILER" && \
    echo "WM_OPTIONS=$WM_OPTIONS" && \
    echo "WM_ARCH=$WM_ARCH" && \
    echo "WM_MPLIB=$WM_MPLIB" && \
    echo "--------------------------------------------------" && \
    echo "nvc++ location:" && \
    which nvc++ && \
    echo "--------------------------------------------------" && \
    nvc++ --version && \
    echo "--------------------------------------------------" && \
    echo "GPU compiler rule:" && \
    cat wmake/rules/General/Nvidia-gpu/c++ && \
    echo "==================================================" && \
    test "$WM_COMPILER" = "Nvidia-gpu" \
    '

# -----------------------------------------------------------------------------
# Build OpenFOAM GPU
#
# 13 jobs on the 16 vCPU / 32 GiB builder: -j 16 fails there.
# -----------------------------------------------------------------------------

RUN /bin/bash -lc '\
    source /opt/openfoam-gpu/etc/bashrc && \
    ./Allwmake -j 13 \
    '

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# -----------------------------------------------------------------------------
# Umpire memory pool
#
# Built after OpenFOAM: Umpire is installed where etc/config.sh/umpire looks,
# then only src/OSspecific/POSIX (which reads FOAM_USE_UMPIRE) is recompiled
# and libOpenFOAM.so relinked, following the feature-gpu wiki (build +
# dependencies pages). A change here does not rebuild OpenFOAM.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# CMake >= 3.23 (Umpire 2025.03.0 requirement; Ubuntu 22.04 apt has 3.22)
# -----------------------------------------------------------------------------

RUN wget -q https://github.com/Kitware/CMake/releases/download/v3.30.5/cmake-3.30.5-linux-x86_64.tar.gz \
 && tar xzf cmake-3.30.5-linux-x86_64.tar.gz -C /opt \
 && rm cmake-3.30.5-linux-x86_64.tar.gz
ENV PATH=/opt/cmake-3.30.5-linux-x86_64/bin:${PATH}

# -----------------------------------------------------------------------------
# Umpire: static, position-independent (it is linked into libOpenFOAM.so),
# CUDA for Hopper (cc90), installed exactly where etc/config.sh/umpire looks:
#   $WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/umpire-2025.03.0
# Do not pass -DCMAKE_INSTALL_LIBDIR=lib: CMake then resolves "lib" against the
# working directory (/tmp) and installs libumpire.a and libfmt.a in /tmp/lib.
# -----------------------------------------------------------------------------

RUN source /opt/openfoam-gpu/etc/bashrc \
 && prefix="$WM_THIRD_PARTY_DIR/platforms/$WM_ARCH$WM_COMPILER/umpire-2025.03.0" \
 && nvcc_bin=$(find /opt/nvidia/hpc_sdk -path '*/cuda/12.6/bin/nvcc' | head -1) \
 && test -x "$nvcc_bin" \
 && echo "Umpire prefix: $prefix   nvcc: $nvcc_bin" \
 && cd /tmp \
 && wget -q https://github.com/LLNL/Umpire/releases/download/v2025.03.0/umpire-2025.03.0.tar.gz \
 && tar xzf umpire-2025.03.0.tar.gz \
 && cmake -S umpire-2025.03.0 -B umpire-build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DCMAKE_C_COMPILER=gcc \
      -DCMAKE_CXX_COMPILER=g++ \
      -DCMAKE_CUDA_COMPILER="$nvcc_bin" \
      -DCMAKE_CUDA_ARCHITECTURES=90 \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DBUILD_SHARED_LIBS=OFF \
      -DBLT_CXX_STD=c++17 \
      -DENABLE_CUDA=ON -DUMPIRE_ENABLE_CUDA=ON \
      -DENABLE_OPENMP=OFF -DENABLE_MPI=OFF -DENABLE_FORTRAN=OFF \
      -DENABLE_TESTS=OFF -DUMPIRE_ENABLE_TESTS=OFF \
      -DENABLE_BENCHMARKS=OFF -DUMPIRE_ENABLE_BENCHMARKS=OFF \
      -DENABLE_EXAMPLES=OFF -DUMPIRE_ENABLE_EXAMPLES=OFF \
      -DENABLE_DOCS=OFF -DUMPIRE_ENABLE_DOCS=OFF \
      -DUMPIRE_ENABLE_TOOLS=OFF \
 && cmake --build umpire-build -j "$(nproc)" \
 && cmake --install umpire-build \
 && rm -rf /tmp/umpire-* \
 && ls -l "$prefix/lib" \
 && test -f "$prefix/lib/libumpire.a" \
 && test -f "$prefix/lib/libcamp.a" \
 && test -f "$prefix/include/umpire/Umpire.hpp"

# -----------------------------------------------------------------------------
# Recompile OSspecific with -DFOAM_USE_UMPIRE and relink libOpenFOAM.so.
# wclean is required: wmake does not notice the new compile flags by itself.
# Never pipe into `grep -q` here: it exits at the first match, the writer gets
# SIGPIPE and pipefail turns that into exit code 141. `grep -c` reads to EOF.
# -----------------------------------------------------------------------------

RUN source /opt/openfoam-gpu/etc/bashrc \
 && bash "$WM_PROJECT_DIR/wmake/scripts/have_umpire" -test | tee /tmp/have_umpire.txt \
 && grep -q '^umpire=true' /tmp/have_umpire.txt \
 && cd "$WM_PROJECT_DIR/src/OSspecific/POSIX" \
 && wclean \
 && ./Allwmake 2>&1 | tee /tmp/log.OSspecific \
 && grep -q 'found umpire -- enabling memory pool interface' /tmp/log.OSspecific \
 && rm -f "$FOAM_LIBBIN/libOpenFOAM.so" \
 && cd "$WM_PROJECT_DIR/src" \
 && ./Allwmake-base -j "$(nproc)" 2>&1 | tail -40 \
 && test -f "$FOAM_LIBBIN/libOpenFOAM.so" \
 && echo "umpire symbols in libOpenFOAM.so: $(nm -C "$FOAM_LIBBIN/libOpenFOAM.so" | grep -c 'umpire::')" \
 && nm -C "$FOAM_LIBBIN/libOpenFOAM.so" | grep -c 'umpire::' > /dev/null \
 && ! ldd "$FOAM_LIBBIN/libOpenFOAM.so" | grep 'not found'

# Default memory pool from the feature-gpu wiki; a workload may override it.
ENV FOAM_MEMORY_POOL="managed; size=1024, incr=1024"

# -----------------------------------------------------------------------------
# Runtime environment
# -----------------------------------------------------------------------------

RUN echo 'source /opt/openfoam-gpu/etc/bashrc' >> /root/.bashrc

WORKDIR /workspace

CMD ["/bin/bash"]