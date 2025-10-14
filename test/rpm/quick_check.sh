#!/bin/bash
# Quick validation script for LiveReduce RPM spec file changes

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Dynamically find the spec file relative to this script
SPEC_FILE="$(dirname "$(dirname "$(realpath "$0")")")/livereduce.spec"

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}    LiveReduce RPM Spec File Quick Check     ${NC}"
echo -e "${BLUE}===============================================${NC}\n"

# Check if spec file exists
if [[ ! -f "$SPEC_FILE" ]]; then
    echo -e "${RED}✗ Spec file not found at $SPEC_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Spec file found${NC}"

# Check for systemd-rpm-macros build requirement
if grep -q "BuildRequires:.*systemd-rpm-macros" "$SPEC_FILE"; then
    echo -e "${GREEN}✓ BuildRequires systemd-rpm-macros${NC}"
else
    echo -e "${RED}✗ Missing BuildRequires systemd-rpm-macros${NC}"
    exit 1
fi

# Check for user requirements
if grep -q "Requires:.*user(snsdata)" "$SPEC_FILE"; then
    echo -e "${GREEN}✓ Requires user(snsdata)${NC}"
else
    echo -e "${RED}✗ Missing user(snsdata) requirement${NC}"
    exit 1
fi

# Check for group requirements
if grep -q "Requires:.*group(users)" "$SPEC_FILE"; then
    echo -e "${GREEN}✓ Requires group(users)${NC}"
else
    echo -e "${RED}✗ Missing group(users) requirement${NC}"
    exit 1
fi

if grep -q "Requires:.*group(hfiradmin)" "$SPEC_FILE"; then
    echo -e "${GREEN}✓ Requires group(hfiradmin)${NC}"
else
    echo -e "${RED}✗ Missing group(hfiradmin) requirement${NC}"
    exit 1
fi

# Check for systemd scriptlets
if grep -q "%systemd_post.*livereduce.service" "$SPEC_FILE"; then
    echo -e "${GREEN}✓ %systemd_post scriptlet${NC}"
else
    echo -e "${RED}✗ Missing %systemd_post scriptlet${NC}"
    exit 1
fi

if grep -q "%systemd_preun.*livereduce.service" "$SPEC_FILE"; then
    echo -e "${GREEN}✓ %systemd_preun scriptlet${NC}"
else
    echo -e "${RED}✗ Missing %systemd_preun scriptlet${NC}"
    exit 1
fi

if grep -q "%systemd_postun_with_restart.*livereduce.service" "$SPEC_FILE"; then
    echo -e "${GREEN}✓ %systemd_postun_with_restart scriptlet${NC}"
else
    echo -e "${RED}✗ Missing %systemd_postun_with_restart scriptlet${NC}"
    exit 1
fi

# Check service file
SERVICE_FILE="$(dirname "$(dirname "$(realpath "$0")")")/livereduce.service"
if [[ -f "$SERVICE_FILE" ]]; then
    echo -e "${GREEN}✓ Service file exists${NC}"

    if grep -q "User=snsdata" "$SERVICE_FILE"; then
        echo -e "${GREEN}✓ Service runs as snsdata user${NC}"
    else
        echo -e "${RED}✗ Service not configured to run as snsdata${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Service file not found${NC}"
    exit 1
fi

echo -e "\n${GREEN}🎉 All RPM improvements are correctly implemented!${NC}"
echo -e "\n${YELLOW}Summary of changes:${NC}"
echo "• Added systemd-rpm-macros build requirement"
echo "• Added user(snsdata) requirement"
echo "• Added group(users) requirement"
echo "• Added group(hfiradmin) requirement"
echo "• Added %systemd_post scriptlet for service installation"
echo "• Added %systemd_preun scriptlet for service removal"
echo "• Added %systemd_postun_with_restart scriptlet for automatic restart on upgrade"

echo -e "\n${BLUE}Next steps:${NC}"
echo "1. Install build prerequisites: ./test/rpm/setup_test_environment.sh"
echo "2. Build and test RPM: ./test/rpm/build_and_test.sh"
echo "3. Run manual tests: ./test/rpm/test_manual_rpm.sh"
