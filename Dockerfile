# Analogous to jupyter/systemuser, but based on CC7 and inheriting directly from cernphsft/notebook.
# Run with the DockerSpawner in JupyterHub.

FROM gitlab-registry.cern.ch/swan/docker-images/notebook:v4.0.1

MAINTAINER SWAN Admins <swan-admins@cern.ch>

ARG BUILD_TAG=daily
ENV VERSION_DOCKER_IMAGE=$BUILD_TAG

RUN echo "Building systemuser image with tag ${VERSION_DOCKER_IMAGE}"

# Disable requiretty and secure path - required by systemuser.sh
RUN yum -y install sudo && \
    sed -i'' '/Defaults \+requiretty/d'  /etc/sudoers && \
    sed -i'' '/Defaults \+secure_path/d' /etc/sudoers

# Install ROOT prerequisites
RUN yum -y install \
    libXpm \
    libXft

# Install bs4 - required by sparkconnector.serverextension
RUN pip3 install bs4

# Install tk - required by matplotlib
RUN yum -y install tk

# Install Cloudera dependencies - required by IT Spark clusters
RUN yum -y  install \
            alsa-lib \
            at \
            bc \
            cronie \
            cronie-anacron \
            crontabs \
            cvs \
            db4-cxx \
            db4-devel \
            ed \
            file \
            gdbm-devel \
            gettext \
            jpackage-utils \
            libXi \
            libXtst \
            man \
            passwd \
            pax \
            perl-CGI \
            perl-ExtUtils-MakeMaker \
            perl-ExtUtils-ParseXS \
            perl-Test-Harness \
            perl-Test-Simple \
            perl-devel \
            redhat-lsb-core \
            rsyslog \
            time \
            xz \
            xz-lzma-compat

# Install openmotif - required by Geant4 (libXm)
RUN yum -y install openmotif

# Install libaio - required by Oracle
RUN yum -y install libaio

# Install cern-get-sso-cookie and update CERN CA certs - ATLAS TDAQ, UCA-63
RUN yum -y install cern-get-sso-cookie && \
    yum -y update CERN-CA-certs

# Install grid certificates
RUN echo $'[carepo]\n\
name=IGTF CA Repository\n\
baseurl=http://linuxsoft.cern.ch/mirror/repository.egi.eu/sw/production/cas/1/current/\n\
enabled=1\n\
gpgcheck=0' > /etc/yum.repos.d/ca.repo && \
    yum install -y voms-clients-cpp  fetch-crl ca_CERN-GridCA-1.90-1.noarch

# Create truststore for NXCALS Spark connection
RUN yum -y install java-1.8.0-openjdk && \
    keytool -import -alias cerngridCA -file /etc/pki/tls/certs/CERN_Grid_Certification_Authority.crt \
        -keystore /etc/pki/tls/certs/truststore.jks -storepass 'password' -noprompt && \
    keytool -import -alias cernRootCA2 -file /etc/pki/tls/certs/CERN_Root_Certification_Authority_2.crt \
        -keystore /etc/pki/tls/certs/truststore.jks -storepass 'password' -noprompt && \
    yum -y erase java-1.8.0-openjdk && \
    rm -rf /usr/lib/jvm/

# Install HEP_OSlibs - includes atlas blas
RUN yum -y install HEP_OSlibs


####################################################################
# Nvidia related commands                                          #
# https://gitlab.com/nvidia/cuda/blob/centos7/10.0/base/Dockerfile #
####################################################################

ENV CUDA_VERSION 10.0.130
ENV CUDNN_VERSION 7.5.1.10


# Installing CUDA
RUN NVIDIA_GPGKEY_SUM=d1be581509378368edeec8c1eb2958702feedf3bc3d17011adbf24efacce4ab5 && \
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/7fa2af80.pub | sed '/^Version/d' > /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA && \
    echo "$NVIDIA_GPGKEY_SUM  /etc/pki/rpm-gpg/RPM-GPG-KEY-NVIDIA" | sha256sum -c --strict -

COPY cuda.repo /etc/yum.repos.d/cuda.repo

ENV CUDA_PKG_VERSION 10-0-$CUDA_VERSION-1
# For libraries in the cuda-compat-* package: https://docs.nvidia.com/cuda/eula/index.html#attachment-a
# CUDA BASE 
RUN yum install -y \
        cuda-cudart-$CUDA_PKG_VERSION \
        cuda-compat-10-0 && \
    ln -s cuda-10.0 /usr/local/cuda 

#CUDA RUNTIME https://gitlab.com/nvidia/cuda/blob/centos7/10.0/runtime/Dockerfile
RUN yum install -y \
        cuda-libraries-$CUDA_PKG_VERSION \
        cuda-nvtx-$CUDA_PKG_VERSION 

#CUDA DEVEL https://gitlab.com/nvidia/cuda/blob/centos7/10.0/devel/Dockerfile
# RUN yum install -y \
#         cuda-libraries-dev-$CUDA_PKG_VERSION \
#         cuda-nvml-dev-$CUDA_PKG_VERSION \
#         cuda-minimal-build-$CUDA_PKG_VERSION \
#         cuda-command-line-tools-$CUDA_PKG_VERSION

####################
# Installing CUDNN #
####################
        
LABEL com.nvidia.cudnn.version="${CUDNN_VERSION}"

# cuDNN RUNTIME https://gitlab.com/nvidia/cuda/blob/centos7/10.0/runtime/cudnn7/Dockerfile
# cuDNN license: https://developer.nvidia.com/cudnn/license_agreement
RUN CUDNN_DOWNLOAD_SUM=c0a4ec438920aa581dd567117b9c316745b4a451ac739b1e04939a3d8b229985 && \
    curl -fsSL http://developer.download.nvidia.com/compute/redist/cudnn/v7.5.1/cudnn-10.0-linux-x64-v7.5.1.10.tgz -O && \
    echo "$CUDNN_DOWNLOAD_SUM  cudnn-10.0-linux-x64-v7.5.1.10.tgz" | sha256sum -c - && \
    tar --no-same-owner -xzf cudnn-10.0-linux-x64-v7.5.1.10.tgz -C /usr/local --wildcards 'cuda/lib64/libcudnn.so.*' && \
    rm cudnn-10.0-linux-x64-v7.5.1.10.tgz && \
    ldconfig

# cuDNN DEVEL https://gitlab.com/nvidia/cuda/blob/centos7/10.0/devel/cudnn7/Dockerfile
# RUN CUDNN_DOWNLOAD_SUM=c0a4ec438920aa581dd567117b9c316745b4a451ac739b1e04939a3d8b229985 && \
#     curl -fsSL http://developer.download.nvidia.com/compute/redist/cudnn/v7.5.1/cudnn-10.0-linux-x64-v7.5.1.10.tgz -O && \
#     echo "$CUDNN_DOWNLOAD_SUM  cudnn-10.0-linux-x64-v7.5.1.10.tgz" | sha256sum -c - && \
#     tar --no-same-owner -xzf cudnn-10.0-linux-x64-v7.5.1.10.tgz -C /usr/local && \
#     rm cudnn-10.0-linux-x64-v7.5.1.10.tgz && \
#     ldconfig
        
# nvidia-docker 
RUN echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf && \
    echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf

ENV PATH /usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH /usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/compat:${LD_LIBRARY_PATH}
ENV CUDA_HOME /usr/local/cuda

# nvidia-container-runtime
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES compute,utility
ENV NVIDIA_REQUIRE_CUDA "cuda>=10.0 brand=tesla,driver>=384,driver<385 brand=tesla,driver>=410,driver<411"

RUN pip3 install 'tensorflow-gpu==1.13.1'


# WORKAROUND
# Hide from Jupyter the Python3 kernel by hand
RUN mv /usr/local/lib/python3.6/site-packages/ipykernel /usr/local/lib/python3.6/site-packages/ipykernelBACKUP && \
    mv /usr/local/share/jupyter/kernels /usr/local/share/jupyter/kernelsBACKUP

# Add ipykernel and its dependencies to an isolated place referenced by PYTHONPATH in user env (Py3)
# Needed to prevent updated Jupyter code to break with older LCG versions (this way it picks always the correct pkgs)
RUN mkdir /usr/local/lib/swan && \
    pip3 install 'ipykernel==4.8.2' -t /usr/local/lib/swan

# Download and install all of our extensions
# Dummy var to force docker to build from this point on (otherwise, due to the caching, this layer would not get the latest release-daily)
ARG CI_PIPELINE
# For testing purposes we can specify a different url to look for the extensions
ARG URL_NBEXTENSIONS
# Replace this value to update the version of the extensions deployed
ARG VERSION_NBEXTENSIONS=v7.2
ENV VERSION_NBEXTENSIONS=$VERSION_NBEXTENSIONS
RUN mkdir /tmp/jupyter_extensions && \
    if [ -n "$URL_NBEXTENSIONS" ]; then \
        echo "Downloading Extensions from a provided URL" ; \
        wget $URL_NBEXTENSIONS -O extensions.zip ; \
    elif [ "$VERSION_NBEXTENSIONS" = "daily" ]; then \
        echo "Downloading Extensions build: daily" ; \
        wget https://gitlab.cern.ch/api/v4/projects/25624/jobs/artifacts/qa/download?job=release-daily -O extensions.zip ; \
    else \
        echo "Downloading Extensions build: ${VERSION_NBEXTENSIONS}" ; \
        wget https://gitlab.cern.ch/api/v4/projects/25624/jobs/artifacts/$VERSION_NBEXTENSIONS/download?job=release-version -O extensions.zip ; \
    fi  && \
    unzip extensions.zip && \
    rm -rf /usr/local/lib/python3.6/site-packages/notebook/templates && \
    mv -f templates /usr/local/lib/python3.6/site-packages/notebook/ && \
    # Install all SWAN extensions which are packaged as python modules
    # Ignore dependencies because they have already been installed or come from CVMFS
    ls -d ./*/ | xargs -n1 sh -c 'cd $0 ; pip install --no-deps .' && \
    # Automatically install all nbextensions from their python module (all extensions need to implement the api even if they return 0 nbextensions)
    ls -d ./*/ | xargs -n1 sh -c 'extension=$(basename $0) ; jupyter nbextension install --py --system ${extension,,} || exit 1' && \
    # Enable the server extensions
    server_extensions=('swancontents' 'sparkmonitor' 'swannotebookviewer' 'swangallery') && \
    for extension in ${server_extensions[@]}; do jupyter serverextension enable --py --system $extension || exit 1 ; done && \
    # Enable the nb extensions
    # Not all nbextensions are activated as some of them are activated on session startup or by the import in the templates
    nb_extensions=('swanhelp' 'swannotifications' 'swanshare' 'swanintro' 'sparkmonitor') && \
    for extension in ${nb_extensions[@]}; do jupyter nbextension enable --py --system $extension || exit 1; done && \
    # Force nbextension_configurator systemwide to prevent users disabling it
    jupyter nbextensions_configurator enable --system && \
    # Spark Monitor/Connector also need to be available to the user environment since they have kernel extensions
    mkdir /usr/local/lib/swan/extensions && \
    ln -s /usr/local/lib/python3.6/site-packages/sparkmonitor /usr/local/lib/swan/extensions/ && \
    ln -s /usr/local/lib/python3.6/site-packages/sparkconnector /usr/local/lib/swan/extensions/ && \
    ln -s /usr/local/lib/python3.6/site-packages/swankernelenv /usr/local/lib/swan/extensions/ && \
    # Clean
    rm -rf /tmp/jupyter_extensions

RUN yum clean all && \
    rm -rf /var/cache/yum

EXPOSE 8888

ENV SHELL /bin/bash

ADD systemuser.sh /srv/singleuser/systemuser.sh
ADD userconfig.sh /srv/singleuser/userconfig.sh
ADD executables/start_ipykernel.py /usr/local/bin/start_ipykernel.py
ADD executables/jupyterhub-singleuser /usr/local/bin/jupyterhub-singleuser
RUN chmod 705 /usr/local/bin/start_ipykernel.py && \
    chmod 705 /usr/local/bin/jupyterhub-singleuser

WORKDIR /root
CMD ["sh", "/srv/singleuser/systemuser.sh"]
