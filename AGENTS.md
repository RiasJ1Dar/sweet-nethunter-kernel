# Agent notes

Context for AI coding agents working in this repository.

## What this repo is

A **kernel configuration and patch set**, not a kernel tree. It carries the
delta needed to give Xiaomi Redmi Note 10 Pro (`sweet` / `sweetin`) monitor-mode
and packet-injection support for external USB Wi-Fi adapters, plus the compiled
artifacts from a known-good build.

The 2.1 GB kernel source is **deliberately not vendored**. Everything here is
applied on top of an upstream clone:

```
PixelOS-Devices/android_kernel_xiaomi_sm6150  branch sixteen-qpr2
kernel 4.14.356   EXTRAVERSION=-openela-rc1   CONFIG_LOCALVERSION="-VantomKernel"
```

Those three version strings must match the running device exactly, otherwise
out-of-tree `.ko` modules fail to load.

## Target

| | |
|---|---|
| SoC | Qualcomm SM6150 (Snapdragon 732G), arm64 |
| Kernel | 4.14.356, **non-GKI** |
| Partitions | A-only, dynamic (`BOARD_SUPER_PARTITION_SIZE := 9126805504`) |
| Boot image | header v2 — kernel + ramdisk + dtb sections |
| OS tested | PixelOS 16.2 (Android 16) |
| Root | Magisk 30.7 |
| Adapter | TP-Link TL-WN722N **v1** (Atheros AR9271) |

## Layout

```
config/sweet_defconfig                 final config, Magisk build (CONFIG_KSU unset)
config/sweet_defconfig.with-kernelsu   variant with KernelSU + SUSFS enabled
patches/01-susfs-v1.5.5.patch          SUSFS kernel side, adapted for 4.14
patches/02-manual-syscall-hooks.patch  non-GKI manual hooks
patches/all-changes.patch              squashed diff — apply this one
prebuilt/Image.gz dtb.img dtbo.img     artifacts of the verified build
prebuilt/modules/*.ko                  14 wireless driver modules
anykernel3/                            flashable zip template
```

## What an agent can and cannot do here

**Realistic tasks:** reviewing or rebasing the patches, auditing the defconfig
for missing symbols, writing build/flash scripts, documentation, diffing a new
upstream branch against this patch set.

**Not realistic in a sandboxed environment:** compiling. A build needs the 2.1 GB
upstream clone, a ~1.5 GB Proton Clang toolchain, and roughly 25 minutes on 14
cores. Both downloads require network access, which Codex cloud tasks do not have
after the setup phase. Do not attempt a build unless the environment was
explicitly prepared with sources and toolchain already present — check for
`arch/arm64/configs/sweet_defconfig` and a `clang` that reports an aarch64 target
before trying.

**Never** edit files under `prebuilt/` or `anykernel3/modules/`. They are binary
outputs of one specific verified build; a mismatched `.ko` bricks Wi-Fi on the
device. They are replaced only by a full rebuild.

## Build invocation

The host toolchain must stay the system one. Putting the Proton Clang `bin` on
`PATH` breaks host tool compilation:

```
ld: unknown type [0x13] section `.relr.dyn'
```

So the cross compiler is passed explicitly and host tools are pinned to GCC:

```sh
TC=/path/to/proton-clang
make -j"$(nproc)" O=out ARCH=arm64 \
  CC="ccache $TC/bin/clang" LD=$TC/bin/ld.lld \
  AR=$TC/bin/llvm-ar NM=$TC/bin/llvm-nm \
  OBJCOPY=$TC/bin/llvm-objcopy OBJDUMP=$TC/bin/llvm-objdump \
  STRIP=$TC/bin/llvm-strip \
  CROSS_COMPILE=$TC/bin/aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=$TC/bin/arm-linux-gnueabi- \
  CROSS_COMPILE_COMPAT=$TC/bin/arm-linux-gnueabi- \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  HOSTCC=gcc HOSTCXX=g++ HOSTLD=ld
```

Every one of those assignments earned its place — see the constraints below
before removing any of them.

## Hard constraints

**1. External Wi-Fi drivers must be `=m`, never `=y`.**
The vendor Qualcomm driver and `ath9k_htc` both export an `HTC`
(Host-Target Communication) symbol namespace, a legacy of Qualcomm acquiring
Atheros. Built in, they collide at link time:

```
ld.lld: error: duplicate symbol: htc_stop
  >>> drivers/net/wireless/ath/ath9k/htc_hst.o
  >>> drivers/staging/qca-wifi-host-cmn/htc/htc.o
```

As modules the symbols stay local to each `.ko`.

**2. `CROSS_COMPILE_COMPAT` is not optional.**
`LD_COMPAT ?= $(CROSS_COMPILE_COMPAT)ld` — left empty it resolves to the host
linker and the 32-bit VDSO fails with `ld: cannot represent machine 'arm'`.

**3. Firmware belongs in `/vendor/firmware/`.**
`firmware_class.path` pointing anywhere under `/data` returns `-13 EACCES`;
SELinux denies the kernel domain access to `/data` regardless of file labels.
`/vendor` is read-only EROFS, so firmware is delivered by a systemless Magisk
module overlaying `system/vendor/firmware/`.

**4. Driver autoload runs from `service.sh`, not `post-fs-data.sh`.**
`post-fs-data.sh` executes before the module overlay is mounted, so the `.ko`
files are not yet visible. `service.sh` with a 45-second sleep works; shorter
delays race the Wi-Fi HAL, and renaming or downing `wlan0` while the external
adapter is absent takes down the built-in chip and crashes the Settings
Wi-Fi page.

**5. KernelSU + SUSFS on non-GKI 4.14 is a narrow window.**
KernelSU-Next restructured its tree (`core/`, `feature/`, `supercall/`) and no
longer matches `10_enable_susfs_for_ksu.patch`, which targets the flat upstream
layout. SukiSU-Ultra ships no kernel-side SUSFS at all. The only combination
that applies cleanly: `cyberc3dr/KernelSU` branch `deprecated/susfs-legacy`
(15 SUSFS options, no `sus_map`, provides `CONFIG_KSU_MANUAL_HOOK`) with
simonpunk `susfs4ksu` branch `kernel-4.14` (v1.5.5).

Two hunks in that patch need manual placement — `fs/proc/cmdline.c`, where the
spoof hook goes ahead of the `ALTER_CMDLINE` block, and `fs/proc/task_mmu.c`,
which needs `#include <linux/susfs_def.h>`.

The shipped default is nonetheless Magisk: NetHunter and Stryker are written
against Magisk, and under KernelSU their chroot handling fails in non-obvious
ways (`su: Permission denied`, hung `sudo`).

## Hardware note

AR9271 draws up to 500 mA. On a bare OTG adapter it drops off the bus roughly
every six minutes under load (`usb 1-1.2: USB disconnect`). A powered OTG hub
resolves it — not a software problem, don't chase it in the driver.

## Verified result

```
802.11 radiotap  (type=803)
907 frames captured in 15 s, 0 dropped by kernel
deauthentication injection confirmed working
```
