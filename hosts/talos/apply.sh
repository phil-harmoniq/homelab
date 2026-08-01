talosctl apply-config --insecure -n 10.1.1.11 --file controlplane-rpi-1.yaml --config-patch @common.yaml

talosctl apply-config --insecure -n 10.1.1.12 --file controlplane-rpi-2.yaml --config-patch @common.yaml

talosctl apply-config --insecure -n 10.1.1.13 --file controlplane-rpi-3.yaml --config-patch @common.yaml