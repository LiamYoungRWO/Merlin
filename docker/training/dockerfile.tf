# syntax=docker/dockerfile:1
ARG IMAGE=nvcr.io/nvidia/tensorflow:22.03-tf2-py3
FROM ${IMAGE}

# Args
ARG CORE_VER=main
ARG HUGECTR_VER=master
ARG MODELS_VER=main
ARG NVTAB_VER=main
ARG SYSTEMS_VER=main
ARG TF4REC_VER=main

# Envs
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:/usr/local/lib:/repos/dist/lib
ENV CUDA_HOME=/usr/local/cuda
ENV CUDA_PATH=$CUDA_HOME
ENV CUDA_CUDA_LIBRARY=${CUDA_HOME}/lib64/stubs
ENV PATH=${CUDA_HOME}/lib64/:${PATH}:${CUDA_HOME}/bin

# Install system packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update -y --fix-missing && \
    apt install -y --no-install-recommends \
        libexpat1-dev \
	libsasl2-2 \
	libssl-dev \
        graphviz \
	openssl \
        protobuf-compiler \
	software-properties-common && \
    apt autoremove -y && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Install multiple packages
RUN pip install betterproto graphviz pybind11 pydot pytest mpi4py transformers==4.12
RUN pip install --upgrade notebook
RUN pip install --upgrade ipython
RUN pip install --upgrade horovod
RUN pip install nvidia-pyindex
RUN pip install tritonclient[all] grpcio-channelz
RUN pip install numba==0.55.1
RUN pip install git+https://github.com/rapidsai/asvdb.git@main

# Install arrow
ENV ARROW_HOME=/usr/local
RUN git clone --branch apache-arrow-5.0.0 --recurse-submodules https://github.com/apache/arrow.git build-env && \
    pushd build-env && \
      export PARQUET_TEST_DATA="${PWD}/cpp/submodules/parquet-testing/data" && \
      export ARROW_TEST_DATA="${PWD}/testing/data" && \
      pip install -r python/requirements-build.txt && \
      mkdir cpp/release && \
      pushd cpp/release && \
        cmake -DCMAKE_INSTALL_PREFIX=${ARROW_HOME} \
              -DCMAKE_INSTALL_LIBDIR=lib \
              -DCMAKE_LIBRARY_PATH=${CUDA_CUDA_LIBRARY} \
              -DARROW_FLIGHT=ON \
              -DARROW_GANDIVA=OFF \
              -DARROW_ORC=ON \
              -DARROW_WITH_BZ2=ON \
              -DARROW_WITH_ZLIB=ON \
              -DARROW_WITH_ZSTD=ON \
              -DARROW_WITH_LZ4=ON \
              -DARROW_WITH_SNAPPY=ON \
              -DARROW_WITH_BROTLI=ON \
              -DARROW_PARQUET=ON \
              -DARROW_PYTHON=ON \
              -DARROW_PLASMA=ON \
              -DARROW_BUILD_TESTS=ON \
              -DARROW_CUDA=ON \
              -DARROW_DATASET=ON \
              -DARROW_HDFS=ON \
              -DARROW_S3=ON \ 
              .. && \
        make -j$(nproc) && \
        make install && \
      popd && \
      pushd python && \
        export PYARROW_WITH_PARQUET=ON && \
        export PYARROW_WITH_CUDA=ON && \
        export PYARROW_WITH_ORC=ON && \
        export PYARROW_WITH_DATASET=ON && \
        export PYARROW_WITH_S3=ON && \
        export PYARROW_WITH_HDFS=ON && \
        python setup.py build_ext --build-type=release bdist_wheel && \
        pip install dist/*.whl --no-deps --force-reinstall && \
      popd && \
    popd && \
    rm -rf build-env

# Install Merlin Core
RUN git clone https://github.com/NVIDIA-Merlin/core.git /core/ && \
    cd /core/ && git checkout ${CORE_VER} && pip install --no-deps -e .
ENV PYTHONPATH=$PYTHONPATH:/core

# Install Merlin Systems
RUN git clone https://github.com/NVIDIA-Merlin/systems.git /systems/ && \
    cd /systems/ && git checkout ${SYSTEMS_VER} && pip install --no-deps -e .
    ENV PYTHONPATH=$PYTHONPATH:/systems

ARG INSTALL_NVT=true
# Install NVTabular
ENV PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION='python'
RUN if [ "$INSTALL_NVT" == "true" ]; then \
      git clone https://github.com/NVIDIA-Merlin/NVTabular.git /nvtabular/ && \
      cd /nvtabular/ && git checkout ${NVTAB_VER} && pip install --no-deps -e .; \
    fi
ENV PYTHONPATH=$PYTHONPATH:/nvtabular

# Install Transformers4Rec
RUN if [ "$INSTALL_NVT" == "true" ]; then \
      git clone https://github.com/NVIDIA-Merlin/Transformers4Rec.git /transformers4rec && \
      cd /transformers4rec/ && git checkout ${TF4REC_VER} && pip install . --no-deps; \
    fi
ENV PYTHONPATH=$PYTHONPATH:/transformers4rec

# Install Models
RUN git clone https://github.com/NVIDIA-Merlin/Models.git /models/ && \
    cd /models/ && git checkout ${MODELS_VER} && pip install -e . --no-deps
ENV PYTHONPATH=$PYTHONPATH:/models

# Add Merlin Repo
RUN git clone https://github.com/NVIDIA-Merlin/Merlin/ /Merlin

# Install HugeCTR
ENV LD_LIBRARY_PATH=/usr/local/hugectr/lib:$LD_LIBRARY_PATH \
    LIBRARY_PATH=/usr/local/hugectr/lib:$LIBRARY_PATH \
    PYTHONPATH=/usr/local/hugectr/lib:$PYTHONPATH

# Arguments "_XXXX" are only valid when $HUGECTR_DEV_MODE==false
ARG HUGECTR_DEV_MODE=false
ARG _HUGECTR_REPO="github.com/NVIDIA-Merlin/HugeCTR.git"
ARG _CI_JOB_TOKEN=""

RUN mkdir -p /usr/local/nvidia/lib64 && \
    ln -s /usr/local/cuda/lib64/libcusolver.so /usr/local/nvidia/lib64/libcusolver.so.10

RUN ln -s /usr/lib/x86_64-linux-gnu/libibverbs.so.1 /usr/lib/x86_64-linux-gnu/libibverbs.so

RUN if [ "$HUGECTR_DEV_MODE" == "false" ]; then \
        git clone https://${_CI_JOB_TOKEN}${_HUGECTR_REPO} build-env && \
        pushd build-env && \ 
          git checkout ${HUGECTR_VER} && \
          cd sparse_operation_kit && \
          python setup.py install && \
        popd && \
        rm -rf build-env; \
    fi

# Clean up
RUN rm -rf /repos
RUN rm -rf /usr/local/share/jupyter/lab/staging/node_modules/marked
RUN rm -rf /usr/local/share/jupyter/lab/staging/node_modules/node-fetch

HEALTHCHECK NONE
CMD ["/bin/bash"]
