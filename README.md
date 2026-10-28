# NetHunter kernel for Redmi Note 10 Pro (sweet)

Custom kernel with monitor mode + packet injection support for external USB Wi-Fi
adapters on Xiaomi Redmi Note 10 Pro / Pro Max (`sweet` / `sweetin`).

Two builds live here. **LineageOS 23.2 is the current one**; the PixelOS build is
kept because its KernelSU + SUSFS work is still the only written-down recipe for
that combination on this device.

| | LineageOS 23.2 | PixelOS 16.2 |
|---|---|---|
| Android | 16 | 16 |
| Kernel | 4.14.357-openela-perf | 4.14.356-openela-rc1-VantomKernel |
| Root | Magisk | Magisk (KernelSU variant included) |
| Kernel patches needed | **none** | SUSFS + manual syscall hooks |
| Directory | [`lineage-23.2/`](lineage-23.2/) | [`config/`](config/), [`patches/`](patches/), [`prebuilt/`](prebuilt/) |

Tested adapter: **TP-Link TL-WN722N v1** (Atheros AR9271) — monitor mode and
injection both confirmed (`802.11 radiotap`, 907 frames in 15 s, 0 dropped;
deauthentication injection working).

## What this adds

Stock `sweet` kernels ship `cfg80211` but **no `mac80211`**, so no external
adapter can enter monitor mode. This build adds the stack plus the usual
chipsets:

| Feature | Config |
|---|---|
| mac80211 stack (absent in stock) | `CONFIG_MAC80211=y` |
| Atheros AR9271 / AR7010 | `CONFIG_ATH9K_HTC=m` |
| Atheros AR9170 | `CONFIG_CARL9170=m` |
| Ralink RT2800 series | `CONFIG_RT2800USB=m` |
| Realtek RTL8187 / RTL8192CU | `CONFIG_RTL8187=m`, `CONFIG_RTL8192CU=m` |
| USB HID gadget (already on) | `CONFIG_USB_CONFIGFS_F_HID=y` |

## Building (LineageOS 23.2)

No patches. LineageOS uses a Qualcomm base defconfig plus device fragments, so
the whole change is one extra fragment:

```sh
git clone --depth=1 -b lineage-23.2 \
  https://github.com/LineageOS/android_kernel_xiaomi_sm6150.git
cd android_kernel_xiaomi_sm6150
cp ../lineage-23.2/config/nethunter.config arch/arm64/configs/vendor/

TC=/path/to/proton-clang
ARGS="O=out ARCH=arm64 \
  CC=$TC/bin/clang LD=$TC/bin/ld.lld \
  AR=$TC/bin/llvm-ar NM=$TC/bin/llvm-nm \
  OBJCOPY=$TC/bin/llvm-objcopy OBJDUMP=$TC/bin/llvm-objdump \
  STRIP=$TC/bin/llvm-strip \
  CROSS_COMPILE=$TC/bin/aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=$TC/bin/arm-linux-gnueabi- \
  CROSS_COMPILE_COMPAT=$TC/bin/arm-linux-gnueabi- \
  HOSTCC=gcc HOSTCXX=g++ HOSTLD=ld"

make $ARGS vendor/sdmsteppe-perf_defconfig vendor/sweet.config vendor/nethunter.config
make -j"$(nproc)" $ARGS
```

Output: `out/arch/arm64/boot/Image` (and `Image.gz`) plus 15 `.ko` files.

### Installing

The kernel goes into the existing boot image, keeping the Magisk ramdisk. Do it
on the device with Magisk's own `magiskboot`:

```sh
adb push out/arch/arm64/boot/Image /data/local/tmp/bw/kernel
adb shell 'cd /data/local/tmp/bw && \
  dd if=/dev/block/by-name/boot of=boot.img && \
  /data/adb/magisk/magiskboot unpack boot.img'
# the unpack writes kernel/ramdisk.cpio/dtb — the pushed file replaces "kernel"
adb shell 'cd /data/local/tmp/bw && /data/adb/magisk/magiskboot repack boot.img new-boot.img'
adb pull /data/local/tmp/bw/new-boot.img
fastboot flash boot new-boot.img
```

Push the **uncompressed** `Image`: `magiskboot` decompresses on unpack and
re-compresses on repack, so handing it `Image.gz` double-compresses the kernel.

### Magisk modules

[`lineage-23.2/magisk-modules/`](lineage-23.2/magisk-modules/) holds two:

- **`ath9k_nethunter.zip`** — the 15 drivers plus AR9271 firmware, loaded at boot
- **`wifi-fix.zip`** — adds a `wifi-fix` command that brings Wi-Fi back after
  monitor mode without rebooting

Install with `magisk --install-module <zip>` or through the Magisk app.

## Gotchas worth knowing

**1. Symbol clash: `ath9k_htc` vs the vendor Qualcomm driver**

Building `CONFIG_ATH9K_HTC=y` fails at link time:

```
ld.lld: error: duplicate symbol: htc_stop
  >>> ath9k/htc_hst.o
  >>> qca-wifi-host-cmn/htc/htc.o
```

Both use the `HTC` (Host-Target Communication) prefix — a legacy of Qualcomm
acquiring Atheros. **Fix:** build external Wi-Fi drivers as modules (`=m`),
keeping their symbols local to each `.ko`.

**2. `CROSS_COMPILE_COMPAT` is required**

Without it the 32-bit VDSO links with the host linker and fails:

```
ld: cannot represent machine `arm'
```

Equally, do not put the Proton Clang `bin` on `PATH` — host tools then fail with
`unknown type [0x13] section '.relr.dyn'`. Pass the cross compiler explicitly and
pin `HOSTCC`/`HOSTLD` to the system GCC.

**3. Firmware must live in `/vendor/firmware/`**

`firmware_class.path` pointing at `/data/...` returns `-13 (EACCES)` — SELinux
denies the kernel domain access to `/data` regardless of file labels. `/vendor`
is read-only EROFS, so ship `htc_9271.fw` through a systemless module that
overlays `system/vendor/firmware/`.

**4. Load drivers from `service.sh`, not `post-fs-data.sh`**

`post-fs-data.sh` runs before the module overlay is mounted, so the `.ko` files
are not visible yet. `service.sh` with a 45 second sleep works; shorter delays
race the Wi-Fi HAL.

**5. An OTA silently reverts the kernel — and the version string will not tell you**

This build reports the same `uname -r` as the official LineageOS kernel, because
it is built from the same commit. After an OTA the stock kernel is back, still
with that name, but without `mac80211` — and the modules then fail with
`Unknown symbol`. Reflash the boot image after every system update.

**6. The internal Qualcomm chip has no nl80211 monitor mode**

`iw dev wlan0 set type monitor` returns `Operation not supported (-95)`. The
vendor driver switches modes through `/sys/module/wlan/parameters/con_mode`
(`0` station, `4` monitor) instead, and it is compiled into the kernel, so it
cannot be reloaded. If a tool leaves `con_mode` at `4`, Wi-Fi will not come back
until the parameter is reset — which is what the `wifi-fix` module does.

**7. KernelSU + SUSFS on non-GKI 4.14 (PixelOS build only)**

KernelSU-Next restructured its tree (`core/`, `feature/`, `supercall/`) and no
longer matches `10_enable_susfs_for_ksu.patch`, which targets the flat upstream
layout. SukiSU-Ultra ships no kernel-side SUSFS at all. The only pair that
applies cleanly: `cyberc3dr/KernelSU` branch `deprecated/susfs-legacy` with
simonpunk `susfs4ksu` branch `kernel-4.14` (v1.5.5).

NetHunter and Stryker are written against Magisk; under KernelSU their chroot
handling breaks in non-obvious ways (`su: Permission denied`, hung `sudo`).
Magisk is the smoother path, and on LineageOS it needs no kernel patches at all.

**8. Power draw**

AR9271 pulls up to 500 mA. On a bare OTG adapter it disconnects roughly every
six minutes under load (`usb 1-1.2: USB disconnect`). A powered OTG hub fixes it.

## Credits

- [LineageOS](https://github.com/LineageOS) and [PixelOS-Devices](https://github.com/PixelOS-Devices) — kernel sources
- [backslashxx](https://github.com/backslashxx/KernelSU) — manual syscall hooks
- [simonpunk](https://gitlab.com/simonpunk/susfs4ksu) — SUSFS
- [osm0sis](https://github.com/osm0sis/AnyKernel3) — AnyKernel3
- [qca/open-ath9k-htc-firmware](https://github.com/qca/open-ath9k-htc-firmware) — AR9271 firmware

## License

GPL-2.0, inherited from the Linux kernel.
