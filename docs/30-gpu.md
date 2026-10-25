# Module 30 - the GPU

The chain, host to pod - know every link:

    P2200 @ 0000:86:00 -> vfio-pci (host) -> hostpci0 (VM config)
    -> nonfree-kmod-nvidia-lts extension (driver 580, last Pascal branch)
    -> machine config loads nvidia* modules
    -> nvidia-container-toolkit-lts extension (containerd runtime "nvidia")
    -> RuntimeClass nvidia -> device plugin advertises nvidia.com/gpu
    -> DCGM exports metrics -> pod requests nvidia.com/gpu: 1

The GPU Operator runs with `driver.enabled=false, toolkit.enabled=false`:
on Talos those are system extensions baked into the image, not containers.
What the operator still owns: NFD labelling, the device plugin, DCGM, the
validator - and it is a fine specimen of a production operator to study
(`kubectl -n gpu-operator get clusterpolicy -o yaml`).

Smoke test:

```sh
kubectl run nvidia-smi --rm -it --restart=Never \
  --image=nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04 \
  --overrides='{"spec":{"runtimeClassName":"nvidia","tolerations":[{"key":"nvidia.com/gpu","operator":"Exists"}],"containers":[{"name":"nvidia-smi","image":"nvcr.io/nvidia/cuda:12.4.1-base-ubuntu22.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":1}}}]}}'
```

## Why no vLLM or NIM on this card

Pascal is compute capability 6.1. vLLM requires 7.0+ (Volta); NIM
requires newer still, plus an NGC licence. So: vLLM runs its CPU backend
(module 40) for the real API and metrics, the GPU serves through Ollama
(llama.cpp supports 6.1), and NIM is practised as a deployment pattern
against the mock. The *operational* work - scheduling, taints, runtime
class, driver lifecycle, DCGM, capacity - is identical with a bigger card.

## If nvidia still holds the card after a reboot

Two mechanisms defeat the binding silently, both met on lenora's first
attempt:

- **Duplicate `options vfio-pci` lines.** kmod applies *every* modprobe.d
  file, and the kernel keeps the **last** `ids=` assignment, in file-name
  order - a forgotten `vfio.conf` (sorting after `uc1-vfio.conf`) with a
  typo'd vendor id meant vfio-pci registered ids that matched nothing.
  The tell in dmesg: `vfio_pci: add [00de:1c31...]` - wrong vendor.
- **Force-loaded driver modules.** `blacklist nvidia` does not stop
  dependency loading: a `modules-load.d` entry for `nvidia_uvm` pulls
  `nvidia` in regardless, and it binds whatever vfio-pci failed to claim.

`prepare-proxmox.yml` now detects both and removes the offending files
with `-e cleanup_conflicts=true` (never `/etc/modules`, which it asks you
to edit by hand). Check the result after the next reboot:

```sh
lspci -nnk -s 86:00          # Kernel driver in use: vfio-pci, both functions
dmesg | grep vfio_pci:       # add [10de:1c31... - the right vendor
```

## Giving the GPU back to the host

Reverse of prepare-proxmox.yml: `tofu apply -var gpu_worker=false` (or
destroy), then on lenora delete `/etc/modprobe.d/uc1-vfio.conf` and
`/etc/modules-load.d/uc1-vfio.conf`, remove ` intel_iommu=on iommu=pt`
from `/etc/kernel/cmdline`, run `update-initramfs -u -k all &&
proxmox-boot-tool refresh`, reboot. The nvidia driver claims the card
again at boot.
