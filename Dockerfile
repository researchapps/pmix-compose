FROM rockylinux:8

# ------------------------------------------------------------
# Install required packages
# ------------------------------------------------------------
RUN yum -y update && \
    yum -y install \
    openssh-server \
    openssh-clients \
    libevent \
    libevent-devel \
    gcc \
    gcc-gfortran \
    gcc-c++ \
    gdb \
    python3 \
    strace \
    binutils \
    less \
    wget \
    which \
    sudo \
    perl \
    perl-Data-Dumper \
    autoconf \
    automake \
    libtool \
    flex \
    bison \
    iproute \
    net-tools \
    hwloc \
    make \
    git \
    libnl3 \
    gtk2 \
    atk \
    cairo \
    tcl \
    tcsh \
    tk \
    pciutils \
    lsof \
    ethtool \
    bc \
    file \
    psmisc \
    valgrind && \
    yum -y install epel-release && \
    yum clean all

# ------------------------------------------------------------
# Openmpi (and openpmix it seems?) Install
# ------------------------------------------------------------
WORKDIR /opt/hpc/local/build
RUN git clone -b v4.0.x https://github.com/open-mpi/ompi && \
    cd ompi && \
    git submodule update --init --recursive && \
    ./autogen.pl && \
    ./configure --prefix=/usr && \
    make -j 10 && \
    make install -j 10

# ------------------------------------------------------------
# PMIx Install
# ------------------------------------------------------------
ENV PMIX_ROOT=/opt/hpc/external/pmix
ENV LD_LIBRARY_PATH="$PMIX_ROOT/lib:${LD_LIBRARY_PATH}"
ENV PATH=/usr/lib64/openmpi/bin:$PATH

RUN wget https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz && \
    tar -xzvf libevent-2.1.12-stable.tar.gz && \
    cd libevent-2.1.12-stable && \
    ./configure --prefix=/usr --disable-openssl && \
    make && \
    make install

RUN wget https://github.com/open-mpi/hwloc/archive/refs/tags/hwloc-2.8.0.tar.gz && \
    tar -xzvf hwloc-2.8.0.tar.gz && \
    ls && \
    cd hwloc-hwloc-2.8.0 && \
    ./autogen.sh && \
    ./configure --prefix=/usr && \
    make && \
    make install

# With version 5.x I ran into this bug
# https://bbs.archlinux.org/viewtopic.php?id=279267
RUN cd /opt/hpc/local/build && \
    git clone -b v4.2 https://github.com/openpmix/openpmix.git && \
    cd openpmix && \
    git submodule update --init --recursive && \
    ./autogen.pl && \
    ./configure --prefix=/usr && \
    make -j 10 && \
    make -j 10 install 

# ------------------------------------------------------------
# PRRTE Install
# ------------------------------------------------------------
ENV PRRTE_ROOT=/opt/hpc/external/prrte

ENV LD_LIBRARY_PATH=/usr/include:$LD_LIBRARY_PATH
RUN cd /opt/hpc/local/build && \
    git clone -q -b master https://github.com/openpmix/prrte.git && \
    cd prrte && \
    # This is the commit of master I used to build
    git checkout 1a01710b7d47b7d1e1cca029e62b79252119537b && \
    git submodule update --init --recursive && \
    ./autogen.pl && \
    ./configure --prefix=/usr \
                --with-pmix=/usr && \
    make -j 10 && \
    make install 

# ------------------------------------------------------------
# Copy in an MPI test program
# ------------------------------------------------------------
RUN mkdir -p /opt/hpc/examples && chmod og+rwX /opt/hpc/examples && \
    mkdir -p /opt/hpc/etc && chmod og+rwX /opt/hpc/etc
COPY tests /opt/hpc/examples
RUN cd /opt/hpc/examples && make

# ------------------------------------------------------------
# Fixup the ssh login
# ------------------------------------------------------------
RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N "" && \
    ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key  -N "" && \
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key  -N "" && \
    echo "        LogLevel ERROR" >> /etc/ssh/ssh_config && \
    echo "        StrictHostKeyChecking no" >> /etc/ssh/ssh_config && \
    echo "        UserKnownHostsFile=/dev/null" >> /etc/ssh/ssh_config

# ------------------------------------------------------------
# Adjust default ulimit for core files
# ------------------------------------------------------------
RUN echo '*               hard    core            -1' >> /etc/security/limits.conf && \
    echo '*               soft    core            -1' >> /etc/security/limits.conf && \
    echo 'ulimit -c unlimited' >> /root/.bashrc

# ------------------------------------------------------------
# Create a user account
# ------------------------------------------------------------
RUN groupadd -r mpiuser && useradd --no-log-init -r -m -b /home -g mpiuser -G wheel mpiuser
USER mpiuser
RUN  cd /home/mpiuser && \
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa && chmod og+rX . && \
        cd .ssh && cat id_rsa.pub > authorized_keys && chmod 644 authorized_keys

# ------------------------------------------------------------
# Give the user passwordless sudo powers
# ------------------------------------------------------------
USER root
RUN echo "mpiuser    ALL = NOPASSWD: ALL" >> /etc/sudoers
RUN cd /root && \
    mkdir -p /run/sshd && \
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa && chmod og+rX . && \
    cd .ssh && cat id_rsa.pub > authorized_keys && chmod 644 authorized_keys

ENV PRRTE_MCA_prrte_default_hostfile=/opt/hpc/etc/hostfile.txt
# Need to do this so that the 'mpiuser' can have them too, not just root
RUN echo "export LD_LIBRARY_PATH=/usr/lib64/usr/lib" >> /etc/bashrc && \
    echo "ulimit -c unlimited" >> /etc/bashrc && \
    echo "alias pd=pushd" >> /etc/bashrc

# ------------------------------------------------------------
# Kick off the ssh daemon
# ------------------------------------------------------------
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]