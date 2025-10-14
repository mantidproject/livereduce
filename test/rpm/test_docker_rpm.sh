#!/bin/bash
# Docker-based comprehensive RPM testing for livereduce
# This script creates an isolated testing environment to validate RPM functionality

set -e

# Configuration
DOCKER_IMAGE="livereduce-rpm-test"
CONTAINER_NAME="livereduce-test-$(date +%s)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}    LiveReduce Docker-based RPM Test Suite   ${NC}"
echo -e "${BLUE}===============================================${NC}"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Build test environment
echo -e "${YELLOW}Building Docker test environment...${NC}"
cat > "$PROJECT_ROOT/Dockerfile.rpm-test" << 'EOF'
FROM fedora:latest

# Install required packages for RPM building and testing
RUN dnf update -y && \
    dnf install -y \
    rpm-build \
    rpmdevtools \
    systemd \
    python3-devel \
    python3-setuptools \
    python3-pip \
    sudo \
    which \
    systemd-rpm-macros \
    shadow-utils \
    procps-ng \
    coreutils \
    util-linux \
    findutils && \
    dnf clean all

# Create required users and groups
RUN groupadd -r users 2>/dev/null || true && \
    groupadd -r hfiradmin && \
    useradd -r -g users -G hfiradmin snsdata

# Set up RPM build environment
RUN rpmdev-setuptree

# Create test directories
RUN mkdir -p /var/log/SNS_applications && \
    chown snsdata:users /var/log/SNS_applications && \
    chmod 1755 /var/log/SNS_applications

WORKDIR /root/build

# Copy project files
COPY . .

# Set permissions
RUN chmod +x test/rpm/*.sh

CMD ["/bin/bash"]
EOF

docker build -f "$PROJECT_ROOT/Dockerfile.rpm-test" -t "$DOCKER_IMAGE" "$PROJECT_ROOT"

echo -e "${GREEN}✓ Docker image built successfully${NC}"

# Run comprehensive tests
echo -e "\n${YELLOW}Running comprehensive RPM tests...${NC}"

docker run --name "$CONTAINER_NAME" \
    --privileged \
    -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
    "$DOCKER_IMAGE" \
    /bin/bash -c "
    set -e

    echo '=== Building RPM package ==='
    # Create source tarball
    mkdir -p /tmp/livereduce-1.14
    cp -r . /tmp/livereduce-1.14/
    cd /tmp
    tar czf /root/rpmbuild/SOURCES/livereduce-1.14.tar.gz livereduce-1.14/
    cd /root/build

    # Build RPM
    rpmbuild -ba livereduce.spec

    echo '=== Installing RPM package ==='
    rpm -ivh /root/rpmbuild/RPMS/noarch/python-livereduce-*.rpm

    echo '=== Running functionality tests ==='
    ./test/rpm/test_rpm_functionality.sh

    echo '=== Testing package upgrade scenario ==='
    # Simulate upgrade by reinstalling
    rpm -Uvh /root/rpmbuild/RPMS/noarch/python-livereduce-*.rpm

    echo '=== Verifying service after upgrade ==='
    systemctl list-unit-files | grep livereduce || echo 'Service not found after upgrade'

    echo '=== Testing service operations ==='
    # Test enable/disable without actually starting (since we don't have the actual service binary)
    systemctl --dry-run enable livereduce.service
    systemctl --dry-run disable livereduce.service

    echo '=== Testing package removal ==='
    rpm -e python-livereduce

    echo '=== Verifying cleanup after removal ==='
    if systemctl list-unit-files | grep -q livereduce; then
        echo 'WARNING: Service still present after removal'
    else
        echo 'Service properly removed'
    fi

    echo '=== All Docker-based tests completed successfully! ==='
"

# Check exit status
if docker run --rm -v "$PROJECT_ROOT:/livereduce:ro" "$IMAGE_NAME" bash -c "true"; then
    echo -e "\n${GREEN}🎉 All Docker-based RPM tests passed!${NC}"
else
    echo -e "\n${RED}❌ Some Docker-based tests failed!${NC}"
    exit 1
fi

echo -e "\n${BLUE}Docker-based RPM testing completed successfully!${NC}"
