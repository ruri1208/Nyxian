#!/bin/bash
# Increment build number across all targets and append build configuration

if [ -z "$SRCROOT" ]; then
  SRCROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
fi
cd "$SRCROOT"

# Current date
current_date=$(date "+%Y%m%d")

# Get build configuration (Debug/Release) from Xcode, uppercased
build_config=$(echo "$CONFIGURATION" | tr '[:lower:]' '[:upper:]')

# Fallback if not set
if [ -z "$build_config" ]; then
  build_config="UNKNOWN"
fi

# Read previous build number
previous_build_number=$(awk -F "=" '/BUILD_NUMBER/ {print $2}' Config.xcconfig | tr -d ' ')

# Extract date + counter from previous build number
previous_date="${previous_build_number%%.*}"
rest="${previous_build_number#*.}"
counter="${rest%%.*}"

# Increment or reset counter
if [[ "$current_date" == "$previous_date" ]]; then
  new_counter=$((counter + 1))
else
  new_counter=1
fi

# New build number with build config
new_build_number="${current_date}.${new_counter}.${build_config}"

# Replace in config
sed -i -e "/BUILD_NUMBER =/ s/= .*/= $new_build_number/" Config.xcconfig

# Remove sed backup
rm -f Config.xcconfig-e

# Exporting all headers
KERNEL_SOURCE_DIR="$SRCROOT/Nyxian"
SHARED_KERNEL_DIR="$SRCROOT/Shared/kernel"
rm -rf "$SHARED_KERNEL_DIR"
mkdir -p "$SHARED_KERNEL_DIR"
rsync -am --include='*/' --include='*.h' --exclude='*' "$KERNEL_SOURCE_DIR/" "$SHARED_KERNEL_DIR/"
cp "$SRCROOT/ksurface_config.h" "$SRCROOT/Shared/kernel/ksurface_config.h"
cp "$SRCROOT/ksurface_abi.h" "$SRCROOT/Shared/kernel/ksurface_abi.h"
