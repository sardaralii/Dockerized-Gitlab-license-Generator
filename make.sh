#!/bin/bash

echo "[i] GitLab License Generator"
echo "[i] Copyright (c) 2023 Tim Cook, All Rights Not Reserved"

# Exit immediately if a command exits with a non-zero status
set -e

# Change to the script's directory
cd "$(dirname "$0")"

# Check if the project directory is correct
if [ ! -f ".root" ]; then
    echo "[!] Failed to locate project directory, aborting..."
    exit 1
fi
WORKING_DIR=$(pwd)

# Create a temporary directory if it doesn't exist
mkdir -p temp

# Fetch the latest ruby gem version
echo "[*] Fetching ruby gem version..."
RB_GEM_NAME="gitlab-license"
RB_GEM_LIST_OUTPUT=$(gem list --remote $RB_GEM_NAME)

RB_GEM_VERSION=""
while IFS= read -r line; do
    if [[ $line == "gitlab-license ("* ]]; then
        RB_GEM_VERSION=${line#"gitlab-license ("}
        RB_GEM_VERSION=${RB_GEM_VERSION%")"}
        break
    fi
done <<< "$RB_GEM_LIST_OUTPUT"

echo "[*] gitlab-license version: $RB_GEM_VERSION"
RB_GEM_DOWNLOAD_URL="https://rubygems.org/downloads/gitlab-license-$RB_GEM_VERSION.gem"
RB_GEM_DOWNLOAD_PATH="$WORKING_DIR/temp/gem/gitlab-license.gem"
mkdir -p "$(dirname $RB_GEM_DOWNLOAD_PATH)"
curl -L $RB_GEM_DOWNLOAD_URL -o $RB_GEM_DOWNLOAD_PATH > /dev/null 2>&1
pushd "$(dirname $RB_GEM_DOWNLOAD_PATH)" > /dev/null
tar -xf gitlab-license.gem
tar -xf data.tar.gz

if [ ! -f "./lib/gitlab/license.rb" ]; then
    echo "[!] Failed to locate gem file, aborting..."
    exit 1
fi

echo "[*] Copying gem..."
rm -rf "$WORKING_DIR/lib" || true
mkdir -p "$WORKING_DIR/lib"
cp -r ./lib/gitlab/* $WORKING_DIR/lib
popd > /dev/null

# Patch the library requirements
pushd "$WORKING_DIR/lib" > /dev/null
echo "[*] Patching lib requirements gem..."

find . -type f | while read -r file; do
    if grep -q "require 'gitlab/license/" "$file"; then
        sed -i 's/require '\''gitlab\/license\//require_relative '\''license\//g' "$file"
    fi
done

popd > /dev/null

echo "[*] Updated gem"

# Function to clone GitLab repository with retries
clone_repo_with_retries() {
    local url=$1
    local dir=$2
    local max_retries=5
    local count=0
    local success=0

    while [ $count -lt $max_retries ]; do
        if git clone --depth=1 $url $dir; then
            success=1
            break
        fi
        count=$((count + 1))
        echo "[*] Retry $count/$max_retries in 10 seconds..."
        sleep 10
    done

    if [ $success -ne 1 ]; then
        echo "[!] Failed to clone repository after $max_retries attempts."
        exit 1
    fi
}

# Fetch GitLab source code
echo "[*] Fetching GitLab source code..."
GITLAB_SOURCE_CODE_DIR="$WORKING_DIR/temp/src/"
if [ -d "$GITLAB_SOURCE_CODE_DIR" ]; then
    echo "[*] GitLab source code already exists, skipping cloning..."
else
    echo "[*] Cloning GitLab source code..."
    clone_repo_with_retries "https://gitlab.com/gitlab-org/gitlab.git" "$GITLAB_SOURCE_CODE_DIR"
fi

echo "[*] Updating GitLab source code..."
pushd $GITLAB_SOURCE_CODE_DIR > /dev/null
git clean -fdx -f > /dev/null
git reset --hard > /dev/null
git pull > /dev/null
popd > /dev/null

# Create build directory
BUILD_DIR="$WORKING_DIR/build"
mkdir -p $BUILD_DIR

# Scan features
echo "[*] Scanning features..."
FEATURE_LIST_FILE="$BUILD_DIR/features.json"
rm -f $FEATURE_LIST_FILE || true
./src/scan.features.rb -o $FEATURE_LIST_FILE -s $GITLAB_SOURCE_CODE_DIR

# Generate key pair
echo "[*] Generating key pair..."
PUBLIC_KEY_FILE="$BUILD_DIR/public.key"
PRIVATE_KEY_FILE="$BUILD_DIR/private.key"
cp -f ./keys/public.key $PUBLIC_KEY_FILE
cp -f ./keys/private.key $PRIVATE_KEY_FILE

# Uncomment to generate new keys
# ./src/generator.keys.rb --public-key $PUBLIC_KEY_FILE --private-key $PRIVATE_KEY_FILE

# Generate license
echo "[*] Generating license..."
LICENSE_FILE="$BUILD_DIR/result.gitlab-license"
LICENSE_JSON_FILE="$BUILD_DIR/license.json"

./src/generator.license.rb -f $FEATURE_LIST_FILE --public-key $PUBLIC_KEY_FILE --private-key $PRIVATE_KEY_FILE -o $LICENSE_FILE --plain-license $LICENSE_JSON_FILE

echo "[*] Done $(basename $0)"
