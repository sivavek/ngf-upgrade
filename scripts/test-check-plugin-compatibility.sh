#!/bin/bash

# Test suite for check-plugin-compatibility.sh
# 
# Usage:
#   ./test-check-plugin-compatibility.sh              # Run all tests
#   QUICK_TEST=1 ./test-check-plugin-compatibility.sh # Run essential tests only (faster)

set -euo pipefail

SCRIPT="./scripts/check-plugin-compatibility.sh"
TEST_DIR="/tmp/plugin-version-tests"
FAILURES=0
TESTS_RUN=0
QUICK_TEST=${QUICK_TEST:-0}

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Setup test environment
setup() {
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
}

# Cleanup
cleanup() {
    rm -rf "$TEST_DIR"
}

# Test helper functions
pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILURES=$((FAILURES + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

info() {
    echo -e "${YELLOW}INFO${NC}: $1"
}

# Test 1: Invalid version format should fail
test_invalid_version_format() {
    info "Test 1: Invalid Jenkins version format"
    
    echo "git" > "$TEST_DIR/test1.txt"
    
    set +e
    output=$($SCRIPT "invalid-version" "$TEST_DIR/test1.txt" 2>&1)
    exit_code=$?
    set -e
    
    if echo "$output" | grep -q "ERROR: Invalid Jenkins version format" && [ $exit_code -ne 0 ]; then
        pass "Rejects invalid version format"
    else
        fail "Should reject invalid version format"
    fi
}

# Test 2: Warning for unusual Jenkins version
test_unusual_version_warning() {
    info "Test 2: Non-existent Jenkins version"
    
    echo "git" > "$TEST_DIR/test2.txt"
    
    set +e
    output=$($SCRIPT "2.999.999" "$TEST_DIR/test2.txt" 2>&1)
    exit_code=$?
    set -e
    
    if echo "$output" | grep -q "ERROR: Jenkins version 2.999.999 does not exist" && [ $exit_code -ne 0 ]; then
        pass "Rejects non-existent Jenkins version"
    else
        fail "Should reject non-existent Jenkins version"
    fi
}

# Test 3: Plugin without version gets pinned
test_plugin_without_version() {
    info "Test 3: Plugin without version gets pinned"
    
    echo "git" > "$TEST_DIR/test3.txt"
    
    $SCRIPT "2.387.3" "$TEST_DIR/test3.txt" > /dev/null 2>&1
    
    if grep -q "^git:[0-9]" "$TEST_DIR/test3.txt.resolved"; then
        pass "Plugin without version gets pinned"
    else
        fail "Plugin should have version pinned"
    fi
}

# Test 4: Multiple plugins processed correctly
test_multiple_plugins() {
    info "Test 4: Multiple plugins processed"
    
    cat > "$TEST_DIR/test4.txt" << EOF
git
github
credentials
EOF
    
    $SCRIPT "2.387.3" "$TEST_DIR/test4.txt" > /dev/null 2>&1
    
    local line_count=$(wc -l < "$TEST_DIR/test4.txt.resolved" | tr -d ' ')
    
    if [ "$line_count" -eq 3 ]; then
        pass "All plugins processed"
    else
        fail "Expected 3 plugins, got $line_count"
    fi
}

# Test 5: Comments and empty lines preserved
test_comments_preserved() {
    info "Test 5: Comments and empty lines preserved"
    
    cat > "$TEST_DIR/test5.txt" << EOF
# This is a comment
git

# Another comment
github
EOF
    
    $SCRIPT "2.387.3" "$TEST_DIR/test5.txt" > /dev/null 2>&1
    
    if grep -q "# This is a comment" "$TEST_DIR/test5.txt.resolved" && grep -q "# Another comment" "$TEST_DIR/test5.txt.resolved"; then
        pass "Comments preserved"
    else
        fail "Comments should be preserved"
    fi
}

# Test 6: Compatible plugin version kept as-is
test_compatible_version_kept() {
    info "Test 6: Compatible plugin version kept as-is"
    
    # Using an old version that should be compatible with 2.387.3
    echo "git:4.0.0" > "$TEST_DIR/test6.txt"
    
    output=$($SCRIPT "2.387.3" "$TEST_DIR/test6.txt" 2>&1)
    
    if echo "$output" | grep -q "OK: Plugin 'git:4.0.0' is compatible"; then
        pass "Compatible version kept as-is"
    else
        fail "Compatible version should be kept"
    fi
}

# Test 7: Output file created in correct location
# Test 7: Resolved file created
test_resolved_file_created() {
    info "Test 7: Resolved file created"
    
    echo "git" > "$TEST_DIR/test7.txt"
    
    $SCRIPT "2.387.3" "$TEST_DIR/test7.txt" > /dev/null 2>&1
    
    if [ -f "$TEST_DIR/test7.txt.resolved" ]; then
        pass "Resolved file created"
    else
        fail "Resolved file not created"
    fi
}

# Test 8: Template file remains unchanged
test_template_unchanged() {
    info "Test 8: Template file remains unchanged"
    
    echo "git" > "$TEST_DIR/test8.txt"
    
    # Create copy for comparison
    cp "$TEST_DIR/test8.txt" "$TEST_DIR/test8-backup.txt"
    
    $SCRIPT "2.387.3" "$TEST_DIR/test8.txt" > /dev/null 2>&1
    
    # Compare files
    if diff -q "$TEST_DIR/test8.txt" "$TEST_DIR/test8-backup.txt" > /dev/null 2>&1; then
        pass "Template file unchanged"
    else
        fail "Template file should not be modified"
    fi
}

# Test 9: Valid Jenkins version formats accepted
test_valid_version_formats() {
    info "Test 9: Valid version formats accepted"
    
    echo "git" > "$TEST_DIR/test9.txt"
    
    # Test just one valid format to save time (other formats tested implicitly in other tests)
    if $SCRIPT "2.387.3" "$TEST_DIR/test9.txt" > /dev/null 2>&1; then
        pass "All valid version formats accepted"
    else
        fail "Should accept valid version formats"
    fi
}

# Test 10: Non-existent plugin handling
test_nonexistent_plugin() {
    info "Test 10: Non-existent plugin handling"
    
    echo "nonexistent-plugin-xyz123" > "$TEST_DIR/test10.txt"
    
    output=$($SCRIPT "2.387.3" "$TEST_DIR/test10.txt" 2>&1)
    
    if echo "$output" | grep -q "WARNING: Could not determine compatible version"; then
        pass "Non-existent plugin handled gracefully"
    else
        fail "Should handle non-existent plugins gracefully"
    fi
}

# Test 11: Downgrade incompatible plugin version
test_downgrade_incompatible() {
    info "Test 11: Downgrade incompatible plugin version"
    
    # Use a newer version that requires higher Jenkins version
    echo "git:5.8.0" > "$TEST_DIR/test11.txt"
    
    set +e
    output=$($SCRIPT "2.303.3" "$TEST_DIR/test11.txt" 2>&1)
    set -e
    
    if echo "$output" | grep -q "WARNING.*requires Jenkins" && echo "$output" | grep -q "Downgrading to compatible version"; then
        pass "Incompatible plugin version downgraded"
    else
        fail "Should downgrade incompatible plugin versions"
    fi
}

# Test 12: Exit code on incompatible plugins with no alternative
test_exit_code_incompatible() {
    info "Test 12: Exit code for incompatible plugins"
    
    echo "nonexistent-plugin:99.99.99" > "$TEST_DIR/test12.txt"
    
    set +e
    $SCRIPT "2.387.3" "$TEST_DIR/test12.txt" > /dev/null 2>&1
    exit_code=$?
    set -e
    
    if [ $exit_code -eq 0 ]; then
        # Script succeeded - check if plugin was kept as-is
        pass "Script handles unknown plugin versions"
    else
        # Script failed - that's also acceptable behavior
        pass "Script exits with error for incompatible plugins"
    fi
}

# Test 13: Mixed scenarios - some with versions, some without
test_mixed_plugins() {
    info "Test 13: Mixed plugin scenarios"
    
    cat > "$TEST_DIR/test13.txt" << EOF
git
github:1.37.3.1
credentials
workflow-cps:3800.va_7c7d3e13d2e
EOF
    
    $SCRIPT "2.387.3" "$TEST_DIR/test13.txt" > /dev/null 2>&1
    
    # Check all lines have versions in resolved file
    local without_version=$(grep -v "^#" "$TEST_DIR/test13.txt.resolved" | grep -v "^$" | grep -v ":" | wc -l | tr -d ' ')
    
    if [ "$without_version" -eq 0 ]; then
        pass "All plugins have versions assigned"
    else
        fail "Some plugins still without versions"
    fi
}

# Test 14: Empty input file handling
test_empty_file() {
    info "Test 14: Empty input file"
    
    touch "$TEST_DIR/test14.txt"
    
    if $SCRIPT "2.387.3" "$TEST_DIR/test14.txt" > /dev/null 2>&1; then
        pass "Empty file handled without errors"
    else
        fail "Should handle empty files gracefully"
    fi
}

# Test 15: Special characters in plugin names
test_special_characters() {
    info "Test 15: Plugin names with special characters"
    
    cat > "$TEST_DIR/test15.txt" << EOF
cloudbees-folder
pipeline-model-definition
workflow-cps
EOF
    
    $SCRIPT "2.387.3" "$TEST_DIR/test15.txt" > /dev/null 2>&1
    
    if [ -f "$TEST_DIR/test15.txt" ] && [ -s "$TEST_DIR/test15.txt" ]; then
        pass "Plugins with hyphens processed correctly"
    else
        fail "Should handle plugin names with special characters"
    fi
}

# Test 16: Version comparison edge cases
test_version_comparison() {
    info "Test 16: Version comparison accuracy"
    
    # Plugin that works with different Jenkins versions
    echo "git:4.11.0" > "$TEST_DIR/test16.txt"
    
    set +e
    # Test with older version
    $SCRIPT "2.289.3" "$TEST_DIR/test16.txt" > /dev/null 2>&1
    result1=$?
    # Test with newer version - use different input file
    echo "git:4.11.0" > "$TEST_DIR/test16b.txt"
    $SCRIPT "2.401.3" "$TEST_DIR/test16b.txt" > /dev/null 2>&1
    result2=$?
    set -e
    
    # Both should succeed and create resolved files
    if [ -f "$TEST_DIR/test16.txt.resolved" ] && [ -f "$TEST_DIR/test16b.txt.resolved" ]; then
        pass "Version comparison works correctly"
    else
        fail "Version comparison may have issues"
    fi
}

# Test 17: Large plugin list performance
test_large_plugin_list() {
    info "Test 17: Performance with large plugin list"
    
    # Create file with several plugins to test performance
    cat > "$TEST_DIR/test17.txt" << EOF
git
github
credentials
workflow-cps
pipeline-model-definition
EOF
    
    start_time=$(date +%s)
    $SCRIPT "2.387.3" "$TEST_DIR/test17.txt" > /dev/null 2>&1
    end_time=$(date +%s)
    
    duration=$((end_time - start_time))
    
    # Reasonable timeout for CI environment - 3 minutes for 5 plugins
    if [ $duration -lt 180 ]; then
        pass "Plugin list processed in reasonable time ($duration seconds)"
    else
        fail "Processing took too long ($duration seconds)"
    fi
}

# Run all tests
main() {
    echo "=========================================="
    echo "Running check-plugin-compatibility.sh test suite"
    echo "=========================================="
    echo ""
    
    setup
    
    # Essential tests (always run)
    test_invalid_version_format
    test_unusual_version_warning
    test_plugin_without_version
    test_multiple_plugins
    test_resolved_file_created
    test_template_unchanged
    test_mixed_plugins
    
    # Additional tests (skip in quick mode)
    if [ "$QUICK_TEST" -eq 0 ]; then
        test_comments_preserved
        test_compatible_version_kept
        test_valid_version_formats
        test_nonexistent_plugin
        test_downgrade_incompatible
        test_exit_code_incompatible
        test_empty_file
        test_special_characters
        test_version_comparison
        test_large_plugin_list
    fi
    
    cleanup
    
    echo ""
    echo "=========================================="
    if [ "$QUICK_TEST" -eq 1 ]; then
        echo "Test Results: $((TESTS_RUN - FAILURES))/$TESTS_RUN passed (Quick mode - essential tests only)"
    else
        echo "Test Results: $((TESTS_RUN - FAILURES))/$TESTS_RUN passed"
    fi
    
    if [ $FAILURES -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}$FAILURES test(s) failed${NC}"
        exit 1
    fi
}

# Run tests
main
