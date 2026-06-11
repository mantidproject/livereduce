FROM registry.access.redhat.com/ubi9/ubi

USER root
WORKDIR /root

# Install EPEL and base packages
RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
RUN dnf install -y make rpm-build python3 python-unversioned-command jq

# Create required groups and users for livereduce
RUN groupadd -r users 2>/dev/null || true
RUN groupadd -r hfiradmin
RUN useradd -r -g users -G hfiradmin snsdata

# Verify that snsdata exists
RUN id snsdata

# Create builder user with passwordless sudo so rpm-test can install
# RPMs and exercise systemctl inside this image without changing user.
RUN useradd builder
RUN dnf install -y sudo && echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder && chmod 0440 /etc/sudoers.d/builder
USER builder
WORKDIR /home/builder

# Copy spec file to install build dependencies listed in the spec file
# Note: On ndav, run: sudo dnf builddep -y livereduce.spec
COPY livereduce.spec /tmp/
USER root
RUN dnf builddep -y /tmp/livereduce.spec

# Copy required files for RPM build
USER builder
COPY livereduce.spec /home/builder/
COPY livereduce.service /home/builder/
COPY pyproject.toml /home/builder/
COPY rpmbuild.sh /home/builder/
RUN mkdir -p /home/builder/dist/
COPY dist/livereduce*.tar.gz /home/builder/dist/

# Build the RPM using rpmbuild.sh
# (source tarball already built by CI, so pixi not needed in Docker)
# RPMs land at /home/builder/rpmbuild/RPMS/noarch/. Install and test
# happen outside this image, via `pixi run rpm-test` / `rpm-fetch`.
RUN /home/builder/rpmbuild.sh || exit 1
