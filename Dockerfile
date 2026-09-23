# =============================================================================
# OpenFOAM GPU - NVIDIA H200
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
# -----------------------------------------------------------------------------

RUN /bin/bash -lc '\
    source /opt/openfoam-gpu/etc/bashrc && \
    ./Allwmake -j 2 \
    '

# -----------------------------------------------------------------------------
# Runtime environment
# -----------------------------------------------------------------------------

RUN echo 'source /opt/openfoam-gpu/etc/bashrc' >> /root/.bashrc

WORKDIR /workspace

CMD ["/bin/bash"]