#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.


set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_FILE="$(dirname "$0")/run-docker-tests.log"

# Redirect output to log file and stdout
exec > >(tee -i "$LOG_FILE") 2>&1

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    exit 1
fi

# Check if Go is available
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed or not in PATH${NC}"
    exit 1
fi

show_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║         Docker Package - Integration Tests Runner         ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -N              Run specific test number (e.g., -5 to run test 5)"
    echo "  -N -M -P        Run multiple tests (e.g., -5 -7 -8)"
    echo "  --all           Run all tests with prompts between each"
    echo "  --all-auto      Run all tests automatically without prompts"
    echo "  (no args)       Run in interactive menu mode"
    echo
    echo "Examples:"
    echo "  $0              # Interactive mode"
    echo "  $0 -5           # Run only test 5"
    echo "  $0 -5 -7 -8     # Run tests 5, 7, and 8"
    echo "  $0 --all        # Run all tests with prompts"
    echo "  $0 --all-auto   # Run all tests automatically"
    echo
    exit 0
}

get_test_info() {
    local test_num="$1"
    case $test_num in
        1) echo "TestIntegration_pullHelloWorld|Pull hello-world Image" ;;
        2) echo "TestIntegration_runHelloWorld|Run hello-world Container" ;;
        3) echo "TestIntegration_runAlpineEcho|Run Echo Command in Alpine" ;;
        4) echo "TestIntegration_runAlpineWithEnv|Run Alpine with Environment Variable" ;;
        5) echo "TestIntegration_imageInspect|Inspect Docker Image" ;;
        6) echo "TestIntegration_listContainers|List All Containers" ;;
        7) echo "TestIntegration_networkOperations|Network Operations (Create/Inspect/Remove)" ;;
        8) echo "TestIntegration_complexCommand|Complex Docker Command" ;;
        9) echo "TestIntegration_interactiveShell|Interactive Shell with -it Flags (TTY Detection Demo)" ;;
        10) echo "TestIntegration_buildImage|Build Docker Image" ;;
        11) echo "TestIntegration_runDaemon|Run Container in Daemon Mode" ;;
        12) echo "TestIntegration_stopContainer|Stop Running Container" ;;
        *) echo "|Invalid test number" ;;
    esac
}

show_menu() {
    echo -e "${BLUE}Available Integration Tests:${NC}"
    echo
    echo "  1) Pull hello-world Image"
    echo "  2) Run hello-world Container"
    echo "  3) Run Echo Command in Alpine"
    echo "  4) Run Alpine with Environment Variable"
    echo "  5) Inspect Docker Image"
    echo "  6) List All Containers"
    echo "  7) Network Operations (Create/Inspect/Remove)"
    echo "  8) Complex Docker Command"
    echo "  9) Interactive Shell with -it Flags (TTY Detection Demo)"
    echo " 10) Build Docker Image"
    echo " 11) Run Container in Daemon Mode"
    echo " 12) Stop Running Container"
    echo
    echo "  a) Run ALL tests in sequence"
    echo " aa) Run ALL tests automatically (no prompts)"
    echo "  q) Quit"
    echo
}

run_example() {
    local example_name="$1"
    local example_num="$2"
    
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Running Example ${example_num}...${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    
    cd "$SCRIPT_DIR"
    if go test -v ./cli/src/pkg/docker/... -run "^${example_name}$" 2>&1 2>&1; then
        echo
        echo -e "${GREEN}✅ Example completed successfully${NC}"
        return 0
    else
        echo
        echo -e "${RED}❌ Example failed${NC}"
        return 1
    fi
    
    echo
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
}

run_all_examples() {
    echo -e "${CYAN}Running all examples in sequence...${NC}"
    echo
    
    run_example "TestIntegration_pullHelloWorld" "1"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_runHelloWorld" "2"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_runAlpineEcho" "3"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_runAlpineWithEnv" "4"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_imageInspect" "5"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_listContainers" "6"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_networkOperations" "7"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_complexCommand" "8"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_interactiveShell" "9"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_buildImage" "10"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_runDaemon" "11"
    read -p "Press Enter to continue to next example..."
    
    run_example "TestIntegration_stopContainer" "12"
    
    echo -e "${GREEN}✅ All examples completed!${NC}"
}

run_all_examples_auto() {
    echo -e "${CYAN}Running all examples automatically (no prompts)...${NC}"
    echo
    
    local failed_count=0
    local total_count=12
    
    run_example "TestIntegration_pullHelloWorld" "1" || ((failed_count++))
    run_example "TestIntegration_runHelloWorld" "2" || ((failed_count++))
    run_example "TestIntegration_runAlpineEcho" "3" || ((failed_count++))
    run_example "TestIntegration_runAlpineWithEnv" "4" || ((failed_count++))
    run_example "TestIntegration_imageInspect" "5" || ((failed_count++))
    run_example "TestIntegration_listContainers" "6" || ((failed_count++))
    run_example "TestIntegration_networkOperations" "7" || ((failed_count++))
    run_example "TestIntegration_complexCommand" "8" || ((failed_count++))
    run_example "TestIntegration_interactiveShell" "9" || ((failed_count++))
    run_example "TestIntegration_buildImage" "10" || ((failed_count++))
    run_example "TestIntegration_runDaemon" "11" || ((failed_count++))
    run_example "TestIntegration_stopContainer" "12" || ((failed_count++))
    
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    if [ $failed_count -eq 0 ]; then
        echo -e "${GREEN}✅ All $total_count examples completed successfully!${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        return 0
    else
        local passed_count=$((total_count - failed_count))
        echo -e "${RED}❌ $failed_count out of $total_count examples failed${NC}"
        echo -e "${YELLOW}   ($passed_count passed, $failed_count failed)${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        return 1
    fi
}

run_selected_tests() {
    local test_numbers=("$@")
    local failed_count=0
    local total_count=${#test_numbers[@]}
    
    echo -e "${CYAN}Running ${total_count} selected test(s)...${NC}"
    echo
    
    for test_num in "${test_numbers[@]}"; do
        local test_info=$(get_test_info "$test_num")
        local test_name=$(echo "$test_info" | cut -d'|' -f1)
        local test_desc=$(echo "$test_info" | cut -d'|' -f2)
        
        if [ -z "$test_name" ] || [ "$test_name" = "" ]; then
            echo -e "${RED}Error: Invalid test number: $test_num${NC}"
            ((failed_count++))
            continue
        fi
        
        run_example "$test_name" "$test_num" || ((failed_count++))
    done
    
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    if [ $failed_count -eq 0 ]; then
        echo -e "${GREEN}✅ All $total_count test(s) completed successfully!${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        return 0
    else
        local passed_count=$((total_count - failed_count))
        echo -e "${RED}❌ $failed_count out of $total_count test(s) failed${NC}"
        echo -e "${YELLOW}   ($passed_count passed, $failed_count failed)${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
        return 1
    fi
}

main() {
    # Check for command-line arguments
    if [ $# -gt 0 ]; then
        # Handle --help or -h
        if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
            show_usage
        fi
        
        # Handle --all flag
        if [ "$1" = "--all" ]; then
            show_banner
            run_all_examples
            exit $?
        fi
        
        # Handle --all-auto (auto-run all)
        if [ "$1" = "--all-auto" ]; then
            show_banner
            run_all_examples_auto
            exit $?
        fi
        
        # Handle individual test numbers (e.g., -5 -7 -8)
        local test_numbers=()
        for arg in "$@"; do
            if [[ "$arg" =~ ^-([0-9]+)$ ]]; then
                test_numbers+=("${BASH_REMATCH[1]}")
            else
                echo -e "${RED}Error: Invalid argument '$arg'${NC}"
                echo "Use --help for usage information"
                exit 1
            fi
        done
        
        if [ ${#test_numbers[@]} -gt 0 ]; then
            show_banner
            run_selected_tests "${test_numbers[@]}"
            exit $?
        fi
        
        # If we get here, unknown option
        echo -e "${RED}Error: Unknown option '$1'${NC}"
        echo "Use --help for usage information"
        exit 1
    fi
    
    # No arguments - run interactive mode
    show_banner
    
    while true; do
        show_menu
        read -p "Select an example (1-12, a, aa, q): " choice
        
        case $choice in
            1)
                run_example "TestIntegration_pullHelloWorld" "1"
                read -p "Press Enter to return to menu..."
                ;;
            2)
                run_example "TestIntegration_runHelloWorld" "2"
                read -p "Press Enter to return to menu..."
                ;;
            3)
                run_example "TestIntegration_runAlpineEcho" "3"
                read -p "Press Enter to return to menu..."
                ;;
            4)
                run_example "TestIntegration_runAlpineWithEnv" "4"
                read -p "Press Enter to return to menu..."
                ;;
            5)
                run_example "TestIntegration_imageInspect" "5"
                read -p "Press Enter to return to menu..."
                ;;
            6)
                run_example "TestIntegration_listContainers" "6"
                read -p "Press Enter to return to menu..."
                ;;
            7)
                run_example "TestIntegration_networkOperations" "7"
                read -p "Press Enter to return to menu..."
                ;;
            8)
                run_example "TestIntegration_complexCommand" "8"
                read -p "Press Enter to return to menu..."
                ;;
            9)
                run_example "TestIntegration_interactiveShell" "9"
                read -p "Press Enter to return to menu..."
                ;;
            10)
                run_example "TestIntegration_buildImage" "10"
                read -p "Press Enter to return to menu..."
                ;;
            11)
                run_example "TestIntegration_runDaemon" "11"
                read -p "Press Enter to return to menu..."
                ;;
            12)
                run_example "TestIntegration_stopContainer" "12"
                read -p "Press Enter to return to menu..."
                ;;
            a|A)
                run_all_examples
                read -p "Press Enter to return to menu..."
                ;;
            aa|AA)
                run_all_examples_auto
                exit_code=$?
                echo
                read -p "Press Enter to return to menu..."
                ;;
            q|Q)
                echo
                echo -e "${CYAN}Goodbye!${NC}"
                echo
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please select 1-12, a, aa, or q.${NC}"
                sleep 1
                ;;
        esac
        
        clear
        show_banner
    done
}

# Run main function
main "$@"
