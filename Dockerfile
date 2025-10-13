FROM registry.access.redhat.com/ubi9/ubi

USER root

# Install EPEL and required packages
RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
RUN dnf install -y make rpm-build python3 python-unversioned-command
RUN dnf install -y bash systemd-rpm-macros
RUN dnf install -y pyproject-rpm-macros python3-build python3-pip python3-hatchling python3-devel

# Create required groups and users for livereduce
RUN groupadd -r users 2>/dev/null || true
RUN groupadd -r hfiradmin
RUN useradd -r -g users -G hfiradmin snsdata

# Create builder user
RUN useradd builder
USER builder
WORKDIR /home/builder

# Copy required files
COPY livereduce.spec /home/builder/
COPY livereduce.service /home/builder/
COPY pyproject.toml /home/builder/
COPY rpmbuild.sh /home/builder/
RUN mkdir -p /home/builder/dist/
COPY dist/livereduce*.tar.gz /home/builder/dist/

# Build the RPM
RUN /home/builder/rpmbuild.sh || exit 1

# Install it (as root)
USER root
RUN dnf install -y /home/builder/rpmbuild/RPMS/noarch/python-livereduce*.noarch.rpm || exit 1

# Verify installation
USER builder
RUN python3 -c "import livereduce; print('livereduce imported successfully')" || exit 1
