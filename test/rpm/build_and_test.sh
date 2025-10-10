#!/bin/bash
# RPM build and test orchestrator for livereduce
# This script builds the RPM and runs comprehensive tests

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BUILD_DIR="$PROJECT_ROOT/build"
RPMBUILD_DIR="$PROJECT_ROOT/rpmbuild"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}      LiveReduce RPM Build & Test Suite      ${NC}"
echo -e "${BLUE}===============================================${NC}"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up temporary files...${NC}"
    rm -rf "$BUILD_DIR" "$RPMBUILD_DIR" 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup EXIT

# Function to setup RPM build environment
setup_rpm_environment() {
    echo -e "${YELLOW}Using existing rpmbuild.sh for building...${NC}"

    # Note: This uses the project's existing rpmbuild.sh script
    # rather than reproducing the build logic
    if [[ ! -f "$PROJECT_ROOT/rpmbuild.sh" ]]; then
        echo -e "${RED}✗ rpmbuild.sh not found in project root${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Found existing build script${NC}"
}

# Function to build RPM package
build_rpm() {
    echo -e "${YELLOW}Building RPM package using rpmbuild.sh...${NC}"

    # Use the existing rpmbuild.sh script
    cd "$PROJECT_ROOT"
    if ! ./rpmbuild.sh; then
        echo -e "${RED}✗ RPM build failed${NC}"
        return 1
    fi

    # Check if build was successful
    local rpm_file=$(find ~/rpmbuild/RPMS -name "python-livereduce-*.rpm" 2>/dev/null | head -1)
    if [[ -z "$rpm_file" ]]; then
        rpm_file=$(find "$PROJECT_ROOT/dist" -name "python-livereduce-*.rpm" 2>/dev/null | head -1)
    fi

    if [[ -f "$rpm_file" ]]; then
        echo -e "${GREEN}✓ RPM built successfully: $rpm_file${NC}"

        # Show RPM info
        echo -e "\n${BLUE}RPM Package Information:${NC}"
        rpm -qip "$rpm_file" | head -20

        echo -e "\n${BLUE}RPM Package Files:${NC}"
        rpm -qlp "$rpm_file"

        echo -e "\n${BLUE}RPM Package Dependencies:${NC}"
        rpm -qRp "$rpm_file" | grep -E "(user|group|systemd)" || echo "No user/group/systemd dependencies found"

        return 0
    else
        echo -e "${RED}✗ RPM build failed - package not found${NC}"
        return 1
    fi
}# Function to run automated tests
run_automated_tests() {
    echo -e "\n${YELLOW}=== Running Automated Tests ===${NC}"

    # Make test scripts executable
    chmod +x "$SCRIPT_DIR"/*.sh

    # Run quick validation check
    echo -e "${BLUE}Running quick validation check...${NC}"
    "$SCRIPT_DIR/quick_check.sh"
}

# Function to run Docker tests
run_docker_tests() {
    echo -e "\n${YELLOW}=== Running Docker-based Tests ===${NC}"

    if command -v docker &>/dev/null; then
        "$SCRIPT_DIR/test_docker_rpm.sh"
    else
        echo -e "${YELLOW}Docker not available, skipping Docker tests${NC}"
    fi
}

# Function to show manual test instructions
show_manual_test_instructions() {
    echo -e "\n${BLUE}===============================================${NC}"
    echo -e "${BLUE}        Manual Testing Instructions           ${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${YELLOW}To run manual tests:${NC}"
    echo "1. Run: $SCRIPT_DIR/test_manual_rpm.sh"
    echo "2. Follow the interactive prompts"
    echo "3. Test installation, upgrade, and removal scenarios"
    echo ""
    echo -e "${YELLOW}To install the built RPM:${NC}"
    echo "sudo rpm -ivh $(find "$PROJECT_ROOT" -name "python-livereduce-*.rpm" | head -1)"
    echo ""
    echo -e "${YELLOW}To upgrade the RPM:${NC}"
    echo "sudo rpm -Uvh $(find "$PROJECT_ROOT" -name "python-livereduce-*.rpm" | head -1)"
    echo ""
    echo -e "${YELLOW}To remove the RPM:${NC}"
    echo "sudo rpm -e python-livereduce"
}

# Function to validate spec file
validate_spec_file() {
    echo -e "${YELLOW}Validating spec file...${NC}"

    # Use the quick check script for validation
    "$SCRIPT_DIR/quick_check.sh"
}

# Main execution
main() {
    echo -e "${BLUE}Starting RPM build and test process...${NC}"
    echo -e "${BLUE}Project root: $PROJECT_ROOT${NC}"
    echo -e "${BLUE}Test script directory: $SCRIPT_DIR${NC}"

    # Step 1: Validate spec file
    validate_spec_file

    # Step 2: Setup build environment
    setup_rpm_environment

    # Step 3: Build RPM
    build_rpm

    # Step 4: Run automated tests
    run_automated_tests

    # Step 5: Run Docker tests if available
    if [[ "${1:-}" != "--no-docker" ]]; then
        run_docker_tests
    fi

    # Step 6: Show manual test instructions
    show_manual_test_instructions

    echo -e "\n${GREEN}===============================================${NC}"
    echo -e "${GREEN}    RPM Build and Test Process Complete      ${NC}"
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${GREEN}✓ Spec file validated${NC}"
    echo -e "${GREEN}✓ RPM package built${NC}"
    echo -e "${GREEN}✓ Automated tests completed${NC}"
    echo -e "${YELLOW}→ Manual testing available${NC}"

    local rpm_file=$(find "$PROJECT_ROOT" -name "python-livereduce-*.rpm" | head -1)
    if [[ -f "$rpm_file" ]]; then
        echo -e "\n${BLUE}Built RPM: $rpm_file${NC}"
        echo -e "${BLUE}Size: $(du -h "$rpm_file" | cut -f1)${NC}"
    fi
}

# Check prerequisites
check_prerequisites() {
    local missing_deps=()

    if ! command -v rpmbuild &>/dev/null; then
        missing_deps+=("rpm-build")
    fi

    if ! command -v rpmdev-setuptree &>/dev/null; then
        missing_deps+=("rpmdevtools")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Missing dependencies: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}Install with: sudo dnf install ${missing_deps[*]}${NC}"
        exit 1
    fi
}

# Check if running with correct parameters
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--no-docker]"
    echo ""
    echo "Options:"
    echo "  --no-docker    Skip Docker-based tests"
    echo "  --help, -h     Show this help message"
    exit 0
fi

# Run prerequisite check and main function
check_prerequisites
main "$@"
