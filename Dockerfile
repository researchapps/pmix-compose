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

RUN mkdir -p /opt/hpc/local/build


# ------------------------------------------------------------
# Openmpi (and openpmix it seems?) Install
# ------------------------------------------------------------
RUN cd /opt/hpc/local/build && git clone https://github.com/open-mpi/ompi && \
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

ENV _BUILD_HWLOC_VERSION=2.8.0
ENV _BUILD_LIBEVENT_VERSION=2.1.12
ENV _BUILD_FLEX_VERSION=2.6.4

WORKDIR /opt/hpc/src
COPY ./src/libevent-${_BUILD_LIBEVENT_VERSION}-stable.tar.gz /opt/hpc/src/libevent-${_BUILD_LIBEVENT_VERSION}-stable.tar.gz
COPY ./src/hwloc-${_BUILD_HWLOC_VERSION}.tar.gz /opt/hpc/src/hwloc-${_BUILD_HWLOC_VERSION}.tar.gz
RUN mkdir build1 && \
    cd build1 && \
    tar -zxf /opt/hpc/src/libevent-${_BUILD_LIBEVENT_VERSION}-stable.tar.gz && \
    cd libevent* && \
    ./configure --prefix=/usr --disable-openssl && \
    make && \
    make install && \
    cd ../ && \
    mkdir ./build2 && \
    cd build2 && \
    tar -zxf /opt/hpc/src/hwloc-${_BUILD_HWLOC_VERSION}.tar.gz && \
    cd hwloc-${_BUILD_HWLOC_VERSION} && \
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
        cd .ssh && cat id_rsa.pub > authorized_keys && chmod 644 authorized_keys && \
        exit

# ------------------------------------------------------------
# Give the user passwordless sudo powers
# ------------------------------------------------------------
USER root
RUN echo "mpiuser    ALL = NOPASSWD: ALL" >> /etc/sudoers

# ------------------------------------------------------------
# Adjust the default environment
# ------------------------------------------------------------
USER root

ENV PRRTE_MCA_prrte_default_hostfile=/opt/hpc/etc/hostfile.txt
# Need to do this so that the 'mpiuser' can have them too, not just root
RUN echo "export PMIX_ROOT=/opt/hpc/external/pmix" >> /etc/bashrc && \
    echo "export PRRTE_ROOT=/opt/hpc/external/prrte" >> /etc/bashrc  && \
    echo "export MPI_ROOT=/opt/hpc/external/ompi" >> /etc/bashrc  && \
    echo "export PATH=\$MPI_ROOT/bin:\$PATH" >> /etc/bashrc  && \
    echo "export PATH=\$PRRTE_ROOT/bin:\$MPI_ROOT/bin:\$PATH" >> /etc/bashrc  && \
    echo "export LD_LIBRARY_PATH=\$MPI_ROOT/lib:\$LD_LIBRARY_PATH" >> /etc/bashrc && \
    echo "export LD_LIBRARY_PATH=\$PMIX_ROOT/lib:\$LD_LIBRARY_PATH" >> /etc/bashrc && \
    echo "export LD_LIBRARY_PATH=$HWLOC_INSTALL_PATH/lib:$LIBEVENT_INSTALL_PATH/lib:\$LD_LIBRARY_PATH" >> /etc/bashrc && \
    echo "export LD_LIBRARY_PATH=\$PRRTE_ROOT/lib:\$LD_LIBRARY_PATH" >> /etc/bashrc && \
    echo "export PRRTE_MCA_prrte_default_hostfile=$PRRTE_MCA_prrte_default_hostfile" >> /etc/bashrc && \
    echo "export LIBEVENT_INSTALL_PATH=/opt/hpc/local/libevent" >> /etc/bashrc && \
    echo "export HWLOC_INSTALL_PATH=/opt/hpc/local/hwloc" >> /etc/bashrc && \
    echo "ulimit -c unlimited" >> /etc/bashrc && \
    echo "alias pd=pushd" >> /etc/bashrc

# ------------------------------------------------------------
# Kick off the ssh daemon
# ------------------------------------------------------------
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]