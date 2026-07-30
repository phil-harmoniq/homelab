#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Optional but recommended if you'll want Longhorn/iSCSI storage later:
# add iscsi-tools and util-linux-tools under systemExtensions.
cat > rpi-schematic.yaml <<'EOF'
overlay:
  name: rpi_generic
  image: siderolabs/sbc-raspberrypi
customization:
  systemExtensions:
    officialExtensions: []
EOF

SCHEMATIC_ID=$(curl -s -X POST --data-binary @rpi-schematic.yaml \
  https://factory.talos.dev/schematics -H "Content-Type: application/x-yaml" \
  | jq -r '.id')
echo "Schematic: ${SCHEMATIC_ID}"

TALOS_VERSION=v1.13.6
curl -LO "https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/metal-arm64.raw.xz"
xz -d "$SCRIPT_DIR/metal-arm64.raw.xz"

# curl -LO https://factory.talos.dev/image/ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9/v1.13.6/metal-arm64.raw.xz
