#!/bin/bash
# Setup script for LiveReduce RPM testing environment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}    LiveReduce RPM Testing Environment Setup ${NC}"
echo -e "${BLUE}===============================================${NC}"

# Check if we're on a supported system
if ! command -v dnf &>/dev/null; then
    echo -e "${RED}Unsupported system. This script requires dnf (available since RHEL 8).${NC}"
    exit 1
fi

# Install build dependencies from spec file
echo -e "\n${YELLOW}Installing build dependencies from spec file...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ ! -f "$PROJECT_ROOT/livereduce.spec" ]]; then
    echo -e "${RED}Error: livereduce.spec not found in project root${NC}"
    exit 1
fi

sudo dnf builddep -y "$PROJECT_ROOT/livereduce.spec"
echo -e "${GREEN}✓${NC} Build dependencies installed"

# Also install rpmdevtools which is not in the spec
sudo dnf install -y rpmdevtools
echo -e "${GREEN}✓${NC} rpmdevtools installed"

# Create required users and groups for testing
echo -e "\n${YELLOW}Setting up test users and groups...${NC}"

# Create groups
if ! getent group users &>/dev/null; then
    echo -e "${YELLOW}Creating group 'users'...${NC}"
    sudo groupadd -r users
else
    echo -e "${GREEN}✓${NC} Group 'users' already exists"
fi

if ! getent group hfiradmin &>/dev/null; then
    echo -e "${YELLOW}Creating group 'hfiradmin'...${NC}"
    sudo groupadd -r hfiradmin
else
    echo -e "${GREEN}✓${NC} Group 'hfiradmin' already exists"
fi

# Create user
if ! id snsdata &>/dev/null; then
    echo -e "${YELLOW}Creating user 'snsdata'...${NC}"
    sudo useradd -r -g users -G hfiradmin snsdata
else
    echo -e "${GREEN}✓${NC} User 'snsdata' already exists"
    # Ensure user is in correct groups
    sudo usermod -g users -G hfiradmin snsdata
fi

# Verify setup
echo -e "\n${BLUE}Verifying setup...${NC}"

# Check key packages
all_installed=true
KEY_PACKAGES=("rpm-build" "rpmdevtools" "systemd-rpm-macros")
for package in "${KEY_PACKAGES[@]}"; do
    if rpm -q "$package" &>/dev/null; then
        echo -e "${GREEN}✓${NC} $package installed"
    else
        echo -e "${RED}✗${NC} $package not installed"
        all_installed=false
    fi
done

# Check users and groups
if id snsdata &>/dev/null; then
    echo -e "${GREEN}✓${NC} User snsdata exists"
    echo "  Groups: $(groups snsdata)"
else
    echo -e "${RED}✗${NC} User snsdata not found"
    all_installed=false
fi

for group in "users" "hfiradmin"; do
    if getent group "$group" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Group $group exists"
    else
        echo -e "${RED}✗${NC} Group $group not found"
        all_installed=false
    fi
done

# Create log directory with proper permissions
echo -e "\n${YELLOW}Setting up log directory...${NC}"
sudo mkdir -p /var/log/SNS_applications
sudo chown snsdata:users /var/log/SNS_applications
sudo chmod 1755 /var/log/SNS_applications

if [[ -d "/var/log/SNS_applications" ]]; then
    echo -e "${GREEN}✓${NC} Log directory created with proper permissions"
    ls -la /var/log/SNS_applications/..
else
    echo -e "${RED}✗${NC} Failed to create log directory"
    all_installed=false
fi

echo -e "\n${BLUE}===============================================${NC}"
if $all_installed; then
    echo -e "${GREEN}✅ Setup completed successfully!${NC}"
    echo -e "${GREEN}You can now run the RPM tests.${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Run the build and test suite: ./test/rpm/build_and_test.sh"
    echo "2. Or run individual tests from test/rpm/"
else
    echo -e "${RED}❌ Setup incomplete. Please resolve the issues above.${NC}"
    exit 1
fi
echo -e "${BLUE}===============================================${NC}"
