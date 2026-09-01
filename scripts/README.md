# Scripts

This directory contains utility scripts for managing Jenkins plugin versions.

## check-plugin-compatibility.sh

Automatically finds and pins compatible Jenkins plugin versions based on the Jenkins Core version.

### Purpose

When building a Jenkins Docker image, plugin compatibility is critical. This script:
- Reads a plugins file with plugin names (with or without versions)
- Queries Jenkins Update Center for all available plugin versions
- Finds the latest version of each plugin compatible with your Jenkins version
- Generates a plugins.txt.resolved file with pinned versions

### Usage

```bash
./scripts/check-plugin-compatibility.sh <JENKINS_VERSION> <PLUGINS_FILE>
```

**Parameters:**
- `JENKINS_VERSION` - Jenkins Core version (e.g., `2.387.3`, `2.462.1`)
- `PLUGINS_FILE` - File with plugin names (with or without versions)

**Example:**
```bash
./scripts/check-plugin-compatibility.sh "2.387.3" "plugins.txt"
```

**Note:** This script creates a new file `<PLUGINS_FILE>.resolved` with pinned versions. The original file remains unchanged.

### Input Format (plugins.txt - tracked in git)

Simple list of plugin names, one per line:
```
git
github
credentials
cloudbees-folder
```

Or with specific versions (will be validated and updated if incompatible):
```
git:5.2.1
github
credentials:1319.v7eb_51b_3a_c97b_
cloudbees-folder
```

Comments and empty lines are preserved:
```
# Version control plugins
git
github

# Security plugins
credentials
```

### Output Format (plugins.txt.resolved - generated, not tracked in git)

All plugins with pinned versions in a new file:
```
git:5.2.1
github:1.37.3.1
credentials:1319.v7eb_51b_3a_c97b_
cloudbees-folder:6.858.v898218f3609d
```

**Important:** The `.resolved` file is ignored in git (added to `.gitignore`) so local testing doesn't affect the repository.

### Performance Optimizations

The script includes several optimizations for faster execution:

- **Metadata caching**: Plugin metadata is cached in `/tmp/plugin-versions.json` for 1 hour
- **Reuse cache**: Multiple runs within 1 hour use cached data instead of re-downloading (saves ~5-10 seconds per run)
- **Quick test mode**: Set `QUICK_TEST=1` to run only essential tests (7 tests instead of 17)

### How It Works

1. **Validates Jenkins version format** - Ensures correct format (X.Y or X.Y.Z)
2. **Verifies Jenkins version exists** - Checks Jenkins repository to confirm version exists
3. **Downloads/loads metadata** - Fetches or uses cached plugin-versions.json from Jenkins Update Center
4. **Processes each plugin:**
   - If no version specified: finds latest compatible version
   - If version specified: checks compatibility, downgrades if needed
5. **Version comparison** - Uses semantic versioning to compare requiredCore vs Jenkins version
6. **Generates output** - Creates new file with all plugins pinned to compatible versions

### Exit Codes

- `0` - Success, all plugins compatible
- `1` - Error (invalid version format, incompatible plugins with no alternative)

### Error Handling

**Invalid version format:**
```
ERROR: Invalid Jenkins version format: abc
Expected format: X.Y or X.Y.Z (e.g., 2.387.3, 2.462.1)
```

**Non-existent Jenkins version:**
```
ERROR: Jenkins version 5.0.0 does not exist
Check available versions at: https://repo.jenkins-ci.org/releases/org/jenkins-ci/main/jenkins-war/
```

**Incompatible plugin:**
```
WARNING: Plugin 'git:5.8.0' requires Jenkins 2.400
   Downgrading to compatible version: 5.2.1
```

**Plugin not found:**
```
INFO: Plugin 'unknown-plugin' has no version specified
   WARNING: Could not determine compatible version, keeping as is
```

### Integration with Dockerfile

Dockerfile uses the generated plugins.txt.resolved file:

```dockerfile
# Install plugins
COPY plugins.txt.resolved $JENKINS_STAGING/plugins.txt
RUN jenkins-plugin-cli --plugin-file $JENKINS_STAGING/plugins.txt
```

### Integration with Jenkinsfile

The script is called during CI/CD pipeline before Docker build:

```groovy
stage('Validate and Resolve Plugin Versions') {
    steps {
        script {
            echo "Running plugin compatibility tests..."
            sh './scripts/test-check-plugin-compatibility.sh'
            
            echo "Resolving plugin versions for Jenkins ${env.UPSTREAM_JENKINS_VERSION}..."
            sh """
                ./scripts/check-plugin-compatibility.sh "${env.UPSTREAM_JENKINS_VERSION}" "plugins.txt"
            """
            
            echo "Plugin versions resolved. Generated plugins.txt.resolved:"
            sh 'head -20 plugins.txt.resolved'
        }
    }
}
```

### Workflow

1. **Development:** Edit `plugins.txt` with plugin names (no versions)
2. **Testing locally:** Run script to generate `plugins.txt.resolved` (ignored by git)
3. **Commit:** Only commit changes to `plugins.txt` (without versions)
4. **CI/CD:** Jenkinsfile runs script to generate `plugins.txt.resolved`
5. **Docker build:** Uses `plugins.txt.resolved` for installation

This approach keeps the repository clean while allowing local testing without affecting version control.

---

## test-check-plugin-compatibility.sh

Automated test suite for check-plugin-compatibility.sh.

### Purpose

Ensures the plugin compatibility script works correctly across various scenarios.

### Usage

```bash
./scripts/test-check-plugin-compatibility.sh
```

### Test Coverage

The test suite includes 17 tests covering:

1. **Validation tests:**
   - Invalid Jenkins version format rejection
   - Non-existent Jenkins version rejection
   - Valid version format acceptance (2.X, 2.X.Y)

2. **Plugin processing tests:**
   - Plugins without versions get pinned
   - Multiple plugins processed correctly
   - Mixed scenarios (some with versions, some without)
   - Plugins with special characters (hyphens)

3. **Compatibility tests:**
   - Compatible plugin versions kept as-is
   - Incompatible versions downgraded
   - Version comparison accuracy

4. **File handling tests:**
   - Comments and empty lines preserved
   - Template file remains unchanged
   - Output file created in correct location
   - Empty input file handling

5. **Error handling tests:**
   - Non-existent plugin handling
   - Exit codes for incompatible plugins

6. **Performance tests:**
   - Large plugin list processing (10+ plugins in <120 seconds)

### Output

```
==========================================
Running check-plugin-compatibility.sh test suite
==========================================

INFO: Test 1: Invalid Jenkins version format
PASS: Rejects invalid version format
INFO: Test 2: Warning for unusual Jenkins version
PASS: Warns about unusual version
...
==========================================
Test Results: 17/17 passed
All tests passed!
```

### Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

### Running Specific Tests

The test suite runs all tests automatically. To run manually or debug:

1. Check test setup:
   ```bash
   TEST_DIR="/tmp/plugin-version-tests"
   mkdir -p "$TEST_DIR"
   ```

2. Run a single scenario:
   ```bash
   echo "git" > "$TEST_DIR/test.txt"
   ./scripts/check-plugin-compatibility.sh "2.387.3" "$TEST_DIR/test.txt" "$TEST_DIR/output.txt"
   ```

### Adding New Tests

To add a new test, follow this pattern:

```bash
test_my_new_test() {
    info "Test X: Description"
    
    # Setup
    echo "plugin-name" > "$TEST_DIR/testX.txt"
    
    # Execute
    output=$($SCRIPT "2.387.3" "$TEST_DIR/testX.txt" "$TEST_DIR/outputX.txt" 2>&1)
    
    # Assert
    if [[ condition ]]; then
        pass "Test description"
    else
        fail "Error description"
    fi
}
```

Then add to main():
```bash
main() {
    setup
    # ... existing tests ...
    test_my_new_test
    cleanup
}
```

---

## Workflow

### Local Development

1. **Edit plugins.txt:**
   ```bash
   vim plugins.txt
   ```

2. **Test locally:**
   ```bash
   ./scripts/check-plugin-compatibility.sh "2.387.3" "plugins.txt"
   ```

3. **Review changes:**
   ```bash
   git diff plugins.txt
   ```

4. **Run tests:**
   ```bash
   ./scripts/test-check-plugin-compatibility.sh
   ```

### Docker Build

The Dockerfile now uses pre-processed `plugins.txt`:
1. `plugins.txt` is processed by Jenkinsfile stage before Docker build
2. Docker build copies already resolved `plugins.txt`
3. Installs plugins using `jenkins-plugin-cli`

### CI/CD Integration

In Jenkinsfile, the script runs in a dedicated stage:

```groovy
stage('Validate and Resolve Plugin Versions') {
    steps {
        script {
            sh './scripts/test-check-plugin-compatibility.sh'
            sh './scripts/check-plugin-compatibility.sh "${params.JENKINS_VERSION}" "plugins.txt"'
        }
    }
}
```

---

## Troubleshooting

### Script fails to download metadata

**Error:** `curl: (6) Could not resolve host`

**Solution:** Check internet connectivity or use a proxy:
```bash
export https_proxy=http://proxy:8080
./scripts/check-plugin-compatibility.sh ...
```

### Plugin version not found

**Error:** `WARNING: Could not determine compatible version`

**Possible causes:**
1. Plugin doesn't exist in Update Center
2. Plugin name is misspelled
3. No version compatible with your Jenkins version exists

**Solution:** Check plugin name at https://plugins.jenkins.io/

### Build fails with incompatible plugins

If the Docker build fails, check the script output:
```bash
docker build --no-cache . 2>&1 | grep -A 5 "WARNING"
```

Look for plugins that couldn't be downgraded and manually specify compatible versions in `plugins.txt.template`.

---

## Dependencies

- `bash` (4.0+)
- `curl` - For downloading metadata
- `jq` - For parsing JSON
- `sort` - For version comparison (with `-V` flag)

### Installing dependencies

**macOS:**
```bash
brew install jq
```

**Ubuntu/Debian:**
```bash
apt-get install jq curl
```

**Alpine (Docker):**
```bash
apk add bash curl jq coreutils
```

---

## Maintenance

### Updating to new Jenkins versions

The script automatically adapts to any Jenkins 2.x version. No updates needed.

### Adding new plugins

Simply add plugin name to `plugins.txt`:
```bash
echo "new-plugin" >> plugins.txt
git add plugins.txt
git commit -m "Add new-plugin"
```

The version will be resolved automatically during the next build.

### Debugging

Enable verbose output:
```bash
bash -x ./scripts/check-plugin-compatibility.sh "2.387.3" "plugins.txt.template" "plugins.txt"
```

---

## License

Part of the cloudsec_cdaas_jenkins-docker project.
