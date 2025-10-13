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

# Setup RPM build environment
RUN mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Copy required files
COPY livereduce.spec /home/builder/
COPY livereduce.service /home/builder/
COPY pyproject.toml /home/builder/
COPY dist/livereduce*.tar.gz /home/builder/rpmbuild/SOURCES/

# Build the RPM (source tarball already built by CI)
RUN rpmbuild -ba /home/builder/livereduce.spec

# Install the RPM (as root)
# Use --nodeps because nsd-app-wrap is SNS-specific and not in public repos
USER root
RUN rpm -ivh --nodeps /home/builder/rpmbuild/RPMS/noarch/python-livereduce-*.rpm

# Verify installation
RUN test -f /usr/bin/livereduce.sh && \
    test -f /usr/lib/systemd/system/livereduce.service && \
    echo "RPM installed successfully!"
