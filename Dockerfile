FROM nvcr.io/nvidia/nvhpc:24.11-devel-cuda12.6-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# OpenFOAM GPU source
# ---------------------------------------------------------------------------

WORKDIR /opt

RUN git clone \
    --branch feature-gpu \
    --single-branch \
    https://gitlab.com/openfoam/gpu/openfoam-ecse.git \
    openfoam-gpu

WORKDIR /opt/openfoam-gpu

# ---------------------------------------------------------------------------
# OpenFOAM configuration
# ---------------------------------------------------------------------------

# NVIDIA compiler configuration
RUN sed -i 's/^WM_COMPILER=.*/WM_COMPILER=Nvidia/' etc/bashrc

# Disable floating-point trapping during the container build/runtime setup
RUN sed -i 's/^FOAM_SIGFPE=.*/FOAM_SIGFPE=false/' etc/bashrc

# H200 = NVIDIA Hopper, compute capability 9.0
ENV NVARCH=90

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

RUN /bin/bash -lc '\
    source /opt/openfoam-gpu/etc/bashrc && \
    echo "WM_PROJECT_DIR=$WM_PROJECT_DIR" && \
    echo "WM_COMPILER=$WM_COMPILER" && \
    echo "NVARCH=$NVARCH" && \
    which nvc++ && \
    nvc++ --version \
    '

# ---------------------------------------------------------------------------
# Build OpenFOAM GPU
# ---------------------------------------------------------------------------

RUN /bin/bash -lc '\
    source /opt/openfoam-gpu/etc/bashrc && \
    ./Allwmake -j 2 \
    '

# ---------------------------------------------------------------------------
# Runtime environment
# ---------------------------------------------------------------------------

RUN echo "source /opt/openfoam-gpu/etc/bashrc" >> /root/.bashrc

WORKDIR /workspace

CMD ["/bin/bash"]