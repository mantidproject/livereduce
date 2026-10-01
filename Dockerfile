# ubi-init (systemd as PID 1), so the same image can also run `pixi run test-systemd`
FROM registry.access.redhat.com/ubi9/ubi-init

USER root
WORKDIR /root

# Install EPEL and base packages: build tooling, plus inotify-tools/procps-ng/which for
# livereduce_filewatch.sh and nsd-app-wrap.sh when this image is run under systemd
RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
RUN dnf install -y make rpm-build python3 python-unversioned-command jq inotify-tools procps-ng which \
    && dnf clean all

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
# RPMs land at /home/builder/rpmbuild/RPMS/noarch/. Installing and testing them happens outside
# this image, via `pixi run rpm-test` / `rpm-fetch` / `test-systemd`, against a fresh container.
RUN /home/builder/rpmbuild.sh || exit 1

# Stand-ins for mantid's livereduce.py and SNS's nsd-app-wrap, not available here - used by
# `pixi run test-systemd` to exercise the rpm-installed services under real systemd (PID 1,
# --privileged). Kept out of the way under /usr/local/share until that task installs the rpm
# and overlays the fake livereduce.py over the real one it ships.
USER root
COPY test/systemd/fake_livereduce.py /usr/local/share/livereduce-test/livereduce.py
COPY test/systemd/nsd-app-wrap.sh /usr/local/bin/
COPY test/systemd/check_restarts.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/check_restarts.sh /usr/local/bin/nsd-app-wrap.sh

CMD ["/sbin/init"]
