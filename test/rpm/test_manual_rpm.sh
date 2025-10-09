#!/bin/bash
# Manual RPM testing script for livereduce
# Tests specific scenarios that require manual verification

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_PKG_NAME="python-livereduce"
TEST_SERVICE_NAME="livereduce.service"

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}     LiveReduce Manual RPM Test Scenarios    ${NC}"
echo -e "${BLUE}===============================================${NC}"

# Function to prompt user for confirmation
confirm_step() {
    local step_name="$1"
    local description="$2"

    echo -e "\n${YELLOW}=== $step_name ===${NC}"
    echo -e "${BLUE}$description${NC}"
    echo -e "${YELLOW}Press Enter to continue or Ctrl+C to abort...${NC}"
    read
}

# Function to check and display current state
show_current_state() {
    echo -e "\n${BLUE}=== Current System State ===${NC}"

    # Package status
    if rpm -q "$TEST_PKG_NAME" &>/dev/null; then
        echo -e "${GREEN}✓${NC} Package installed: $(rpm -q "$TEST_PKG_NAME")"
    else
        echo -e "${RED}✗${NC} Package not installed"
    fi

    # Service status
    if systemctl list-unit-files | grep -q "$TEST_SERVICE_NAME"; then
        echo -e "${GREEN}✓${NC} Service file present"
        echo "  - Loaded: $(systemctl is-loaded "$TEST_SERVICE_NAME" 2>/dev/null || echo 'not-found')"
        echo "  - Enabled: $(systemctl is-enabled "$TEST_SERVICE_NAME" 2>/dev/null || echo 'disabled')"
        echo "  - Active: $(systemctl is-active "$TEST_SERVICE_NAME" 2>/dev/null || echo 'inactive')"
    else
        echo -e "${RED}✗${NC} Service file not present"
    fi

    # User/group status
    if id snsdata &>/dev/null; then
        echo -e "${GREEN}✓${NC} User snsdata exists"
        echo "  - Groups: $(groups snsdata 2>/dev/null || echo 'N/A')"
    else
        echo -e "${RED}✗${NC} User snsdata does not exist"
    fi

    # Log directory
    if [[ -d "/var/log/SNS_applications" ]]; then
        echo -e "${GREEN}✓${NC} Log directory exists"
        echo "  - Owner: $(stat -c '%U:%G' /var/log/SNS_applications 2>/dev/null || echo 'N/A')"
        echo "  - Permissions: $(stat -c '%a' /var/log/SNS_applications 2>/dev/null || echo 'N/A')"
    else
        echo -e "${RED}✗${NC} Log directory does not exist"
    fi
}

# Test scenario 1: Fresh installation
test_fresh_installation() {
    confirm_step "Test 1: Fresh Installation" \
        "This test verifies fresh package installation behavior.

        We will:
        1. Ensure the package is not currently installed
        2. Install the package
        3. Verify all components are properly set up
        4. Check systemd scriptlets executed correctly"

    echo -e "\n${YELLOW}Checking if package is currently installed...${NC}"
    if rpm -q "$TEST_PKG_NAME" &>/dev/null; then
        echo -e "${YELLOW}Package is installed. Removing for fresh install test...${NC}"
        sudo rpm -e "$TEST_PKG_NAME"
        echo -e "${GREEN}Package removed${NC}"
    fi

    show_current_state

    echo -e "\n${YELLOW}Installing package...${NC}"
    if [[ -f "$(find . -name "python-livereduce-*.rpm" | head -1)" ]]; then
        sudo rpm -ivh "$(find . -name "python-livereduce-*.rpm" | head -1)"
    else
        echo -e "${RED}RPM file not found. Please build the package first.${NC}"
        return 1
    fi

    echo -e "\n${GREEN}Package installed. Checking post-installation state...${NC}"
    show_current_state

    # Verify systemd recognizes the service
    if systemctl list-unit-files | grep -q "$TEST_SERVICE_NAME"; then
        echo -e "${GREEN}✓ Service registered with systemd${NC}"
    else
        echo -e "${RED}✗ Service not registered with systemd${NC}"
    fi

    echo -e "${GREEN}Fresh installation test completed${NC}"
}

# Test scenario 2: Package upgrade
test_package_upgrade() {
    confirm_step "Test 2: Package Upgrade" \
        "This test verifies package upgrade behavior.

        We will:
        1. Ensure the package is currently installed
        2. Simulate an upgrade by reinstalling
        3. Verify service restart behavior
        4. Check that configuration is preserved"

    if ! rpm -q "$TEST_PKG_NAME" &>/dev/null; then
        echo -e "${RED}Package not installed. Installing first...${NC}"
        test_fresh_installation
    fi

    show_current_state

    echo -e "\n${YELLOW}Simulating package upgrade...${NC}"
    if [[ -f "$(find . -name "python-livereduce-*.rpm" | head -1)" ]]; then
        sudo rpm -Uvh "$(find . -name "python-livereduce-*.rpm" | head -1)"
    else
        echo -e "${RED}RPM file not found.${NC}"
        return 1
    fi

    echo -e "\n${GREEN}Package upgraded. Checking post-upgrade state...${NC}"
    show_current_state

    echo -e "${GREEN}Package upgrade test completed${NC}"
}

# Test scenario 3: Service lifecycle
test_service_lifecycle() {
    confirm_step "Test 3: Service Lifecycle" \
        "This test verifies systemd service management.

        We will:
        1. Test service enable/disable
        2. Test service start/stop (if binary is available)
        3. Verify service configuration"

    if ! rpm -q "$TEST_PKG_NAME" &>/dev/null; then
        echo -e "${RED}Package not installed. Please install first.${NC}"
        return 1
    fi

    echo -e "\n${YELLOW}Testing service enable...${NC}"
    if sudo systemctl enable "$TEST_SERVICE_NAME"; then
        echo -e "${GREEN}✓ Service enabled successfully${NC}"
    else
        echo -e "${RED}✗ Failed to enable service${NC}"
    fi

    echo -e "\n${YELLOW}Testing service disable...${NC}"
    if sudo systemctl disable "$TEST_SERVICE_NAME"; then
        echo -e "${GREEN}✓ Service disabled successfully${NC}"
    else
        echo -e "${RED}✗ Failed to disable service${NC}"
    fi

    echo -e "\n${YELLOW}Checking service configuration...${NC}"
    if systemctl cat "$TEST_SERVICE_NAME" &>/dev/null; then
        echo -e "${GREEN}✓ Service configuration accessible${NC}"
        echo "Service file content:"
        systemctl cat "$TEST_SERVICE_NAME" | head -20
    else
        echo -e "${RED}✗ Cannot access service configuration${NC}"
    fi

    echo -e "${GREEN}Service lifecycle test completed${NC}"
}

# Test scenario 4: Package removal
test_package_removal() {
    confirm_step "Test 4: Package Removal" \
        "This test verifies package removal behavior.

        We will:
        1. Remove the package
        2. Verify service is properly stopped and disabled
        3. Check cleanup of files and directories
        4. Verify systemd no longer recognizes the service"

    if ! rpm -q "$TEST_PKG_NAME" &>/dev/null; then
        echo -e "${RED}Package not installed. Nothing to remove.${NC}"
        return 1
    fi

    show_current_state

    echo -e "\n${YELLOW}Removing package...${NC}"
    sudo rpm -e "$TEST_PKG_NAME"

    echo -e "\n${GREEN}Package removed. Checking post-removal state...${NC}"
    show_current_state

    # Verify service is no longer recognized
    if systemctl list-unit-files | grep -q "$TEST_SERVICE_NAME"; then
        echo -e "${RED}✗ Service still present after removal${NC}"
    else
        echo -e "${GREEN}✓ Service properly removed${NC}"
    fi

    echo -e "${GREEN}Package removal test completed${NC}"
}

# Test scenario 5: Dependency verification
test_dependencies() {
    confirm_step "Test 5: Dependency Verification" \
        "This test verifies package dependencies.

        We will:
        1. Check RPM dependencies are properly declared
        2. Verify user/group requirements
        3. Test dependency resolution"

    if ! rpm -q "$TEST_PKG_NAME" &>/dev/null; then
        echo -e "${RED}Package not installed. Installing for dependency test...${NC}"
        test_fresh_installation
    fi

    echo -e "\n${YELLOW}Checking package dependencies...${NC}"
    echo "Declared dependencies:"
    rpm -qR "$TEST_PKG_NAME" | grep -E "(user|group|systemd)" || echo "No user/group/systemd dependencies found"

    echo -e "\n${YELLOW}Checking user dependencies...${NC}"
    if rpm -qR "$TEST_PKG_NAME" | grep -q "user(snsdata)"; then
        echo -e "${GREEN}✓ user(snsdata) dependency declared${NC}"
    else
        echo -e "${RED}✗ user(snsdata) dependency missing${NC}"
    fi

    echo -e "\n${YELLOW}Checking group dependencies...${NC}"
    for group in "users" "hfiradmin"; do
        if rpm -qR "$TEST_PKG_NAME" | grep -q "group($group)"; then
            echo -e "${GREEN}✓ group($group) dependency declared${NC}"
        else
            echo -e "${RED}✗ group($group) dependency missing${NC}"
        fi
    done

    echo -e "${GREEN}Dependency verification test completed${NC}"
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n${BLUE}===============================================${NC}"
        echo -e "${BLUE}         Manual RPM Test Menu                 ${NC}"
        echo -e "${BLUE}===============================================${NC}"
        echo "1. Test Fresh Installation"
        echo "2. Test Package Upgrade"
        echo "3. Test Service Lifecycle"
        echo "4. Test Package Removal"
        echo "5. Test Dependencies"
        echo "6. Show Current State"
        echo "7. Run All Tests"
        echo "0. Exit"
        echo -e "${BLUE}===============================================${NC}"

        read -p "Select test (0-7): " choice

        case $choice in
            1) test_fresh_installation ;;
            2) test_package_upgrade ;;
            3) test_service_lifecycle ;;
            4) test_package_removal ;;
            5) test_dependencies ;;
            6) show_current_state ;;
            7)
                echo -e "\n${YELLOW}Running all tests...${NC}"
                test_fresh_installation
                test_package_upgrade
                test_service_lifecycle
                test_dependencies
                test_package_removal
                echo -e "\n${GREEN}All tests completed!${NC}"
                ;;
            0)
                echo -e "${GREEN}Exiting...${NC}"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please try again.${NC}"
                ;;
        esac
    done
}

# Check if we're running as root or with sudo access
if [[ $EUID -eq 0 ]]; then
    echo -e "${YELLOW}Running as root${NC}"
elif sudo -n true 2>/dev/null; then
    echo -e "${GREEN}Sudo access available${NC}"
else
    echo -e "${RED}This script requires sudo access for RPM operations${NC}"
    echo "Please run: sudo -v"
    exit 1
fi

# Start main menu
main_menu
