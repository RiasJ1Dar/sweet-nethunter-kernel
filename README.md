# NetHunter kernel for Redmi Note 10 Pro (sweet)

Custom kernel with monitor mode + packet injection support for external USB Wi-Fi
adapters on Xiaomi Redmi Note 10 Pro / Pro Max (`sweet` / `sweetin`).

Built from official PixelOS sources, tested on **PixelOS 16.2 (Android 16)**.

```
Kernel:   4.14.356-openela-rc1-VantomKernel
Base:     PixelOS-Devices/android_kernel_xiaomi_sm6150 @ sixteen-qpr2
Root:     Magisk (KernelSU config also included)
Tested:   TP-Link TL-WN722N v1 (Atheros AR9271) — monitor + injection OK
```

## What this adds

| Feature | Config |
|---|---|
| mac80211 stack (absent in stock) | `CONFIG_MAC80211=y` |
| Atheros AR9271 / AR7010 | `CONFIG_ATH9K_HTC=m` |
| Ralink RT2800 series | `CONFIG_RT2800USB=m` |
| Realtek RTL8187 / RTL8192CU | `CONFIG_RTL8187=m`, `CONFIG_RTL8192CU=m` |
| USB HID gadget (already on) | `CONFIG_USB_CONFIGFS_F_HID=y` |

Verified capture: `802.11 radiotap`, 907 frames in 15 s, 0 dropped by kernel.

## Contents

```
config/sweet_defconfig                — final config (Magisk build)
config/sweet_defconfig.with-kernelsu  — variant with KernelSU + SUSFS enabled
patches/01-susfs-v1.5.5.patch         — SUSFS kernel-side patch (adapted)
patches/02-manual-syscall-hooks.patch — non-GKI manual hooks (backslashxx)
patches/all-changes.patch             — everything, single diff
prebuilt/Image.gz, dtb.img, dtbo.img  — compiled artifacts
prebuilt/modules/*.ko                 — wireless drivers
anykernel3/                           — flashable package template
```

## Build

```sh
git clone --depth=1 -b sixteen-qpr2 \
  https://github.com/PixelOS-Devices/android_kernel_xiaomi_sm6150.git
cd android_kernel_xiaomi_sm6150
patch -p1 < ../patches/all-changes.patch
cp ../config/sweet_defconfig arch/arm64/configs/

TC=/path/to/proton-clang
make O=out ARCH=arm64 \
  CC=$TC/bin/clang LD=$TC/bin/ld.lld \
  AR=$TC/bin/llvm-ar NM=$TC/bin/llvm-nm \
  OBJCOPY=$TC/bin/llvm-objcopy OBJDUMP=$TC/bin/llvm-objdump \
  STRIP=$TC/bin/llvm-strip \
  CROSS_COMPILE=$TC/bin/aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=$TC/bin/arm-linux-gnueabi- \
  CROSS_COMPILE_COMPAT=$TC/bin/arm-linux-gnueabi- \
  HOSTCC=gcc HOSTCXX=g++ HOSTLD=ld \
  sweet_defconfig
make -j$(nproc) O=out ARCH=arm64 [same flags]
```

## Gotchas worth knowing

**1. Symbol clash: `ath9k_htc` vs vendor Qualcomm driver**

Building `CONFIG_ATH9K_HTC=y` fails at link time:

```
ld.lld: error: duplicate symbol: htc_stop
  >>> ath9k/htc_hst.o
  >>> qca-wifi-host-cmn/htc/htc.o
```

Both use the `HTC` (Host-Target Communication) prefix — a legacy of Qualcomm
acquiring Atheros. **Fix:** build external Wi-Fi drivers as modules (`=m`),
keeping their symbols local to the `.ko`.

**2. `CROSS_COMPILE_COMPAT` is required**

Without it the 32-bit VDSO links with the host linker and fails:

```
ld: cannot represent machine `arm'
```

**3. Firmware must live in `/vendor/firmware/`**

`firmware_class.path` pointing at `/data/...` returns `-13 (EACCES)` — SELinux
denies the kernel domain access to `/data` regardless of file labels. Ship
`htc_9271.fw` via a systemless module instead (`system/vendor/firmware/`).

**4. KernelSU + SUSFS on non-GKI 4.14**

KernelSU-Next is incompatible with SUSFS patches — it restructured the tree
(`core/`, `feature/`, `supercall/`), while `10_enable_susfs_for_ksu.patch`
targets the flat upstream layout. SukiSU-Ultra ships no kernel-side SUSFS at all.
The only matching pair found: `cyberc3dr/KernelSU` branch `deprecated/susfs-legacy`
(15 SUSFS options, no `sus_map`) + simonpunk `susfs4ksu` branch `kernel-4.14` (v1.5.5).

Note that NetHunter and Stryker are written for Magisk; under KernelSU their
chroot handling breaks in non-obvious ways (`su: Permission denied`, hung `sudo`).
Magisk is the smoother path.

**5. Power draw**

AR9271 pulls up to 500 mA. On a bare OTG adapter it disconnects roughly every
6 minutes under load (`usb 1-1.2: USB disconnect`). A powered OTG hub fixes it.

## Credits

- [PixelOS-Devices](https://github.com/PixelOS-Devices) — kernel sources
- [backslashxx](https://github.com/backslashxx/KernelSU) — manual syscall hooks
- [simonpunk](https://gitlab.com/simonpunk/susfs4ksu) — SUSFS
- [osm0sis](https://github.com/osm0sis/AnyKernel3) — AnyKernel3

## License

GPL-2.0, inherited from the Linux kernel.
