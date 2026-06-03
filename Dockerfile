FROM pytorch/pytorch:2.9.1-cuda13.0-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV HF_HOME=/models/huggingface
ENV HF_HUB_CACHE=/models/huggingface/hub
ENV HUGGINGFACE_HUB_CACHE=/models/huggingface/hub
ENV TRANSFORMERS_CACHE=/models/huggingface/transformers
ENV PYTHONPATH=/workspace/specedge
WORKDIR /workspace/specedge


RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    openssh-client \
    curl \
    wget \
    iputils-ping \
    iperf3 \
    net-tools \
    iproute2 \
    dnsutils \
    vim \
    git \
    ca-certificates \
    build-essential \
    pkg-config \
    rsync \
    lsof \
    tree \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd /root/.ssh \
    && chmod 700 /root/.ssh


RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# # 复制项目代码
# COPY . /workspace/specedge

COPY requirements.runtime.txt /tmp/requirements.runtime.txt

RUN python -m pip install --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir -r /tmp/requirements.runtime.txt

# RUN python -m pip install --upgrade pip setuptools wheel 

# 暴露 SSH 端口；实际能不能访问还要看 K8s Service / NetworkPolicy
EXPOSE 22

# 默认进入 bash。
# 如果你想容器启动后自动开 sshd，可以改成下面注释的 CMD。
# CMD ["/bin/bash"]

# 自动启动 sshd 并保持容器运行的写法：
CMD ["/bin/bash", "-lc", "/usr/sbin/sshd && sleep infinity"]
