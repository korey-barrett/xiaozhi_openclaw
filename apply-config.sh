#!/bin/bash

# Merge the xiaozhi configuration into the OpenClaw configuration file

CONFIG_FILE="$HOME/.openclaw/openclaw.json"
CONFIG_PATCH="/home/hackers365/.openclaw/workspace/xiaozhi-integration/config-patch.json"

# Check whether the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: configuration file does not exist: $CONFIG_FILE"
  exit 1
fi

# Back up the original configuration
cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
echo "Configuration backed up to: $CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Merge the configuration with jq (if jq is installed)
if command -v jq &> /dev/null; then
  echo "Merging configuration with jq..."
  jq -s '.[0] * .[1]' "$CONFIG_FILE" "$CONFIG_PATCH" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  echo "✅ Configuration merged successfully!"
else
  echo "Warning: jq is not installed. Please merge the configuration manually."
  echo ""
  echo "Add the following content to $CONFIG_FILE manually:"
  cat "$CONFIG_PATCH"
  echo ""
  echo "Or run: sudo apt-get install jq && ./apply-config.sh"
  exit 1
fi

echo ""
echo "Configuration content has been updated. Please review:"
echo "cat $CONFIG_FILE"
