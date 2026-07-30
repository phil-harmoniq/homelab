# Raspberry Pi Talos Kubernetes Cluster

A three-node, highly-available Kubernetes cluster running on Raspberry Pi 4s with
[Talos Linux](https://www.talos.dev/), using [Cilium](https://cilium.io/) for
networking (CNI, kube-proxy replacement, load balancing, and Gateway API ingress).

Every node is both a control-plane and a worker, giving etcd quorum across three
nodes: the cluster tolerates any single node going down — for a reboot, an update,
or a failure — without losing the API, the workloads, or external load-balancer
traffic.

> This started as a learning project and turned into a genuinely resilient homelab
> platform. It's shared as a reference for anyone with similar hardware and goals.
> Adjust the IPs, hostnames, and interface names to match your own network.

## Architecture at a glance

```
                       Home network (10.1.1.0/24)
                                  |
                          FortiGate / router
                                  |
        +-------------------------+-------------------------+
        |                         |                         |
     rpi-1                     rpi-2                     rpi-3
   10.1.1.11                 10.1.1.12                 10.1.1.13
  control-plane             control-plane             control-plane
    + worker                  + worker                  + worker
        |                         |                         |
        +----------- etcd quorum (survives 1 node down) ----+

  Kubernetes API VIP:  10.1.1.10  (Talos-managed, floats between nodes)
  LoadBalancer pool:   10.1.1.200 - 10.1.1.250  (Cilium LB-IPAM + L2)
  Gateway (ingress):   10.1.1.200  ->  *.k8s.lan
```

## Hardware

| Component | Choice | Notes |
|-----------|--------|-------|
| Compute | 3x Raspberry Pi 4 (8GB) | arm64 |
| Boot/storage | 3x Samsung 870 EVO 250GB SATA SSD | DRAM cache matters for etcd fsync |
| Adapter | StarTech USB3S2SAT3CB (ASM1153E) | Known-good UASP bridge; boots over USB 3 |

**Storage lesson learned:** the cluster was originally built on USB flash drives, which
could not sustain etcd's fsync-heavy write pattern — this caused constant etcd
"took too long" warnings and downstream instability. Proper SATA SSDs behind a
quality UASP adapter fixed it completely. Do not use flash drives for etcd.

## Software versions

| Layer | Version |
|-------|---------|
| Talos Linux | v1.13.6 |
| Kubernetes | v1.36.2 |
| Cilium | 1.19.6 |
| Gateway API CRDs | v1.3.0 (+ experimental TLSRoute) |

## Network layout

| Purpose | Value |
|---------|-------|
| Node rpi-1 | `10.1.1.11` / `rpi-1.lan` |
| Node rpi-2 | `10.1.1.12` / `rpi-2.lan` |
| Node rpi-3 | `10.1.1.13` / `rpi-3.lan` |
| Kubernetes API VIP | `10.1.1.10` (`https://10.1.1.10:6443`) |
| LoadBalancer IP pool | `10.1.1.200` - `10.1.1.250` |
| Gateway / ingress entry | `10.1.1.200` |
| App hostname wildcard | `*.k8s.lan` -> `10.1.1.200` (DNS) |
| Node NIC | `end0` (driver `bcmgenet`) |

Static node IPs are assigned via DHCP reservation on the router. `*.k8s.lan` is a
wildcard A record on the home DNS server pointing at the Gateway IP, so any app
exposed as `something.k8s.lan` resolves to the single ingress entry point.

## Key design decisions

- **All nodes are control-plane + worker.** Three control planes give etcd quorum
  (tolerates one failure); `allowSchedulingOnControlPlanes: true` lets them also run
  workloads. Right choice for a small HA cluster.
- **Cilium instead of the defaults.** Flannel and kube-proxy are disabled in the Talos
  machine config (`cni: none`, `proxy.disabled: true`); Cilium provides the CNI,
  kube-proxy replacement (via Talos KubePrism at `localhost:7445`), LoadBalancer
  IP assignment (LB-IPAM), L2 announcement, and Gateway API ingress — one component
  for the whole network stack.
- **Gateway API instead of an Ingress controller.** The Cilium-native Gateway API is
  the modern, supported path (classic Ingress controllers are being wound down) and
  reuses the same LB-IPAM + L2 machinery, so LoadBalancer failover applies to ingress
  automatically.
- **Talos VIP for the API server.** A shared virtual IP (`10.1.1.10`) fronts the
  Kubernetes API so `kubectl` survives any single node going down.

## Repository contents

| File / dir | Purpose |
|------------|---------|
| `common.yaml` | Shared Talos machine-config patch: install disk, VIP, CNI-disable, scheduling |
| `controlplane-rpi-N.yaml` | Per-node Talos machine configs (generated; **contain secrets — not committed**) |
| `cilium-lb.yaml` | Cilium LoadBalancer IP pool + L2 announcement policy |
| `gateway.yaml` | Gateway API entry point on `10.1.1.200` |
| `local-path/` | Kustomize overlay for local-path-provisioner (default StorageClass) |
| `rpi-schematic.yaml` | Talos Image Factory schematic (rpi_generic overlay) |
| `build-talos-rpi-image.sh` | Builds/downloads the Talos image for flashing |
| `apply.sh` | Applies machine config to the nodes |

**Talos Image Factory schematic ID:**
`ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9`
(the bare `rpi_generic` overlay, no extra system extensions).

## Prerequisites

- `talosctl`, `kubectl`, and `helm` on your workstation (matching the Talos version above)
- Raspberry Pi 4s with USB boot enabled in the EEPROM
- A DHCP server for static reservations and a LAN DNS server for the `*.k8s.lan` wildcard
- The secrets bundle (`secrets.yaml`) — see "Secrets" below; **not** included in this repo

## High-level setup

1. Build the Talos image from the schematic and flash each SSD.
2. Boot the Pis into maintenance mode; confirm the disk and check `dmesg` for USB errors.
3. Apply per-node configs: `talosctl apply-config --insecure -n <ip> --file controlplane-rpi-N.yaml --config-patch @common.yaml`.
4. Bootstrap etcd **once** on a single node: `talosctl bootstrap -n 10.1.1.11`.
5. Fetch kubeconfig: `talosctl -n 10.1.1.11 kubeconfig`.
6. Install Cilium (kube-proxy replacement, L2 announcements, Gateway API) via Helm.
7. Apply `cilium-lb.yaml` (IP pool + L2 policy) and `gateway.yaml` (ingress).
8. Install a StorageClass (`local-path/`) before deploying anything stateful.

## Secrets

The rendered Talos machine configs embed the cluster CA and bootstrap secrets, so they
are **not** committed. Credentials are kept out of git entirely:

- `secrets.yaml` — Talos secret bundle (source of truth for the cluster's identity)
- `talosconfig` — Talos API client credentials
- `kubeconfig` — Kubernetes admin credentials

Store these in a password manager or encrypted secret store. Machine configs are
regenerated from `secrets.yaml` + the committed patches when needed.
