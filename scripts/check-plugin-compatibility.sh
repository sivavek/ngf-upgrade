#!/bin/bash

#How to test locally:
#./scripts/check-plugin-compatibility.sh "2.528.2" "plugins.txt"
#This will create plugins.txt.resolved with pinned versions

set -euo pipefail

# Check if all required parameters are provided
if [ $# -lt 2 ]; then
    echo "ERROR: Missing required parameters"
    echo ""
    echo "Usage: $0 <JENKINS_VERSION> <PLUGINS_FILE>"
    echo ""
    echo "Parameters:"
    echo "  JENKINS_VERSION  - Jenkins Core version (e.g., 2.387.3, 2.462.1)"
    echo "  PLUGINS_FILE     - File with plugin names (with or without versions)"
    echo ""
    echo "Example:"
    echo "  $0 \"2.387.3\" \"plugins.txt\""
    echo ""
    echo "Note: This script creates <PLUGINS_FILE>.resolved with pinned versions"
    echo "      The original file remains unchanged"
    exit 1
fi

JENKINS_VERSION="$1"
PLUGINS_FILE="$2"
RESOLVED_FILE="${PLUGINS_FILE}.resolved"
PLUGIN_VERSIONS_URL="https://updates.jenkins.io/current/plugin-versions.json"

echo "Checking plugin compatibility with Jenkins ${JENKINS_VERSION}..."
echo "Input file: ${PLUGINS_FILE}"
echo "Output file: ${RESOLVED_FILE}"
echo ""

# Validate Jenkins version format
if [[ ! "$JENKINS_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "ERROR: Invalid Jenkins version format: $JENKINS_VERSION"
    echo "Expected format: X.Y or X.Y.Z (e.g., 2.387.3, 2.462.1)"
    exit 1
fi

# Verify Jenkins version exists
echo "Verifying Jenkins version exists..."
JENKINS_CORE_URL="https://repo.jenkins-ci.org/releases/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war.sha1"
if ! curl -sf "$JENKINS_CORE_URL" > /dev/null; then
    echo "ERROR: Jenkins version ${JENKINS_VERSION} does not exist"
    echo "Check available versions at: https://repo.jenkins-ci.org/releases/org/jenkins-ci/main/jenkins-war/"
    exit 1
fi
echo "Jenkins version ${JENKINS_VERSION} verified"

# Download plugin versions metadata (with caching)
PLUGIN_VERSIONS_JSON="/tmp/plugin-versions.json"
CACHE_MAX_AGE=3600  # 1 hour

if [ -f "$PLUGIN_VERSIONS_JSON" ]; then
    # Check if cache is still fresh (less than 1 hour old)
    if [ $(($(date +%s) - $(stat -f %m "$PLUGIN_VERSIONS_JSON" 2>/dev/null || stat -c %Y "$PLUGIN_VERSIONS_JSON" 2>/dev/null))) -lt $CACHE_MAX_AGE ]; then
        echo "Using cached plugin metadata (less than 1 hour old)"
    else
        echo "Downloading Jenkins plugin versions metadata..."
        curl -sL "$PLUGIN_VERSIONS_URL" > "$PLUGIN_VERSIONS_JSON"
    fi
else
    echo "Downloading Jenkins plugin versions metadata..."
    curl -sL "$PLUGIN_VERSIONS_URL" > "$PLUGIN_VERSIONS_JSON"
fi

# Function to compare versions (returns 0 if v1 >= v2, 1 otherwise)
version_compare() {
    local v1=$1
    local v2=$2
    
    # Remove non-numeric suffixes
    v1=$(echo "$v1" | sed 's/[^0-9.].*//')
    v2=$(echo "$v2" | sed 's/[^0-9.].*//')
    
    if [ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v2" ]; then
        return 0
    else
        return 1
    fi
}

# Function to find compatible version from plugin versions
find_compatible_version() {
    local plugin_name=$1
    local jenkins_version=$2
    
    # Get all versions of the plugin sorted in reverse order (newest first)
    local versions=$(jq -r ".plugins[\"$plugin_name\"] | keys[]" "$PLUGIN_VERSIONS_JSON" 2>/dev/null | sort -V -r || echo "")
    
    if [ -z "$versions" ]; then
        echo ""
        return
    fi
    
    # Find the latest version that is compatible
    while read -r version; do
        local required_core=$(jq -r ".plugins[\"$plugin_name\"][\"$version\"].requiredCore // empty" "$PLUGIN_VERSIONS_JSON" 2>/dev/null)
        
        if [ -n "$required_core" ]; then
            if version_compare "$jenkins_version" "$required_core"; then
                echo "$version"
                return
            fi
        fi
    done <<< "$versions"
    
    echo ""
}

# Function to get required Jenkins version for a specific plugin version
get_required_jenkins_version() {
    local plugin_name=$1
    local plugin_version=$2
    
    local required=$(jq -r ".plugins[\"$plugin_name\"][\"$plugin_version\"].requiredCore // empty" "$PLUGIN_VERSIONS_JSON" 2>/dev/null)
    echo "$required"
}

UPDATED_PLUGINS=()
INCOMPATIBLE_PLUGINS=()

# Create empty resolved file
> "$RESOLVED_FILE"

# Process each line in plugins.txt
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
        echo "$line" >> "$RESOLVED_FILE"
        continue
    fi
    
    # Parse plugin name and version
    if [[ "$line" =~ ^([^:]+):(.+)$ ]]; then
        plugin_name="${BASH_REMATCH[1]}"
        plugin_version="${BASH_REMATCH[2]}"
        
        # Check if this version is compatible
        required_jenkins=$(get_required_jenkins_version "$plugin_name" "$plugin_version")
        
        if [ -n "$required_jenkins" ]; then
            if ! version_compare "$JENKINS_VERSION" "$required_jenkins"; then
                echo "WARNING: Plugin '$plugin_name:$plugin_version' requires Jenkins $required_jenkins"
                compatible_version=$(find_compatible_version "$plugin_name" "$JENKINS_VERSION")
                
                if [ -n "$compatible_version" ]; then
                    echo "   Downgrading to compatible version: $compatible_version"
                    echo "${plugin_name}:${compatible_version}" >> "$RESOLVED_FILE"
                    UPDATED_PLUGINS+=("$plugin_name: $plugin_version → $compatible_version")
                else
                    echo "   ERROR: No compatible version found"
                    echo "$line" >> "$RESOLVED_FILE"
                    INCOMPATIBLE_PLUGINS+=("$plugin_name:$plugin_version")
                fi
            else
                echo "OK: Plugin '$plugin_name:$plugin_version' is compatible"
                echo "$line" >> "$RESOLVED_FILE"
            fi
        else
            echo "$line" >> "$RESOLVED_FILE"
        fi
    else
        # Plugin without version - find latest compatible
        plugin_name="$line"
        echo "INFO: Plugin '$plugin_name' has no version specified"
        
        compatible_version=$(find_compatible_version "$plugin_name" "$JENKINS_VERSION")
        
        if [ -n "$compatible_version" ]; then
            echo "   Pinning to compatible version: $compatible_version"
            echo "${plugin_name}:${compatible_version}" >> "$RESOLVED_FILE"
            UPDATED_PLUGINS+=("$plugin_name: latest → $compatible_version")
        else
            echo "   WARNING: Could not determine compatible version, keeping as is"
            echo "$line" >> "$RESOLVED_FILE"
        fi
    fi
done < "$PLUGINS_FILE"

echo ""
echo "Created ${RESOLVED_FILE} with pinned plugin versions"

# Cleanup
rm -f "$PLUGIN_VERSIONS_JSON"

echo ""
echo "=========================================="

if [ ${#UPDATED_PLUGINS[@]} -gt 0 ]; then
    echo "Updated ${#UPDATED_PLUGINS[@]} plugin(s) to compatible versions:"
    printf '  %s\n' "${UPDATED_PLUGINS[@]}"
    echo ""
fi

if [ ${#INCOMPATIBLE_PLUGINS[@]} -gt 0 ]; then
    echo "ERROR: Found ${#INCOMPATIBLE_PLUGINS[@]} plugin(s) with no compatible version:"
    printf '  %s\n' "${INCOMPATIBLE_PLUGINS[@]}"
    echo "=========================================="
    exit 1
fi

if [ ${#UPDATED_PLUGINS[@]} -eq 0 ] && [ ${#INCOMPATIBLE_PLUGINS[@]} -eq 0 ]; then
    echo "All plugins are compatible with Jenkins ${JENKINS_VERSION}"
fi

echo "=========================================="
