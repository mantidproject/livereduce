FROM registry.access.redhat.com/ubi9/ubi

USER root

# Install EPEL and base packages
RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
RUN dnf install -y make rpm-build python3 python-unversioned-command

# Copy spec file to install build dependencies listed in the spec file
# Note: On ndav, run: sudo dnf builddep -y livereduce.spec
COPY livereduce.spec /tmp/
RUN dnf builddep -y /tmp/livereduce.spec

# Create required groups and users for livereduce
RUN groupadd -r users 2>/dev/null || true
RUN groupadd -r hfiradmin
RUN useradd -r -g users -G hfiradmin snsdata

# Create builder user
RUN useradd builder
USER builder
WORKDIR /home/builder

# Copy required files for RPM build
COPY livereduce.spec /home/builder/
COPY livereduce.service /home/builder/
COPY pyproject.toml /home/builder/
COPY rpmbuild.sh /home/builder/
RUN mkdir -p /home/builder/dist/
COPY dist/livereduce*.tar.gz /home/builder/dist/

# Build the RPM using rpmbuild.sh
# (source tarball already built by CI, so pixi not needed in Docker)
RUN /home/builder/rpmbuild.sh || exit 1

# Install the RPM (as root)
# Use --nodeps because nsd-app-wrap is SNS-specific and not in public repos
USER root
RUN rpm -ivh --nodeps /home/builder/rpmbuild/RPMS/noarch/python-livereduce-*.rpm

# Verify installation
RUN test -f /usr/bin/livereduce.sh && \
    test -f /usr/lib/systemd/system/livereduce.service && \
    echo "RPM installed successfully!"
