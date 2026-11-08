#!/system/bin/sh
# Вантажимо драйвери після монтування overlay; раніше /vendor/lib/modules ще не видно.
sleep 45

LOG=/data/local/tmp/drivers-load.log
: > "$LOG"
MODDIR=/vendor/lib/modules

# Стокові модулі LineageOS, які лежать у тій самій теці й нам не потрібні:
# mmc_test і msm-geni-ir лише смітять помилками в dmesg.
SKIP="mmc_test msm-geni-ir"

# DVB/тюнери навмисно НЕ вантажимо: ядерний драйвер захоплює RTL-SDR свисток
# і тоді librtlsdr (rtl_tcp_andro, gqrx, rtl_433) не може його відкрити.
# Потрібен ядерний режим — insmod вручну.
SKIP="$SKIP dvb-usb-rtl28xxu dvb_usb_v2 rtl2830 rtl2832 rtl2832_sdr
      e4000 fc0012 fc0013 fc2580 mn88472 mn88473 mt2060 mxl5005s
      qt1010 r820t si2157 si2168 tua9001"

# Порядок має значення: спершу бібліотеки, потім драйвери, які на них посилаються.
# Інакше dmesg засмічується «Unknown symbol» з невдалих ранніх спроб.
ORDER="ath ath9k_hw ath9k_common ath9k_htc
       eeprom_93cx6 carl9170
       rt2x00lib rt2x00usb rt2800lib rt2800usb
       rtlwifi rtl_usb rtl8192c-common rtl8192cu rtl8187 rtl8xxxu
       mt7601u
       btbcm btintel btrtl btusb hci_uart hci_vhci
       usbserial ch341 cp210x ftdi_sio pl2303 cdc-acm"

load() {
    name=$(echo "$1" | tr '-' '_')
    grep -q "^$name " /proc/modules && return 0
    [ -f "$MODDIR/$1.ko" ] || return 1
    insmod "$MODDIR/$1.ko" 2>>"$LOG" && echo "+ $name" >> "$LOG"
}

for m in $ORDER; do load "$m"; done

# Усе інше, що лишилось у теці й не в чорному списку.
skipped() { for s in $SKIP; do [ "$s" = "$1" ] && return 0; done; return 1; }
for ko in "$MODDIR"/*.ko; do
    base=$(basename "$ko" .ko)
    skipped "$base" || load "$base"
done

echo "=== завантажено модулів: $(grep -c . /proc/modules) ===" >> "$LOG"
