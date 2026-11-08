#!/system/bin/sh
# Автозапуск sshd у chroot Kali. Щоб вимкнути — видали файл autostart поруч.
MODDIR=${0%/*}
[ -f "$MODDIR/autostart" ] || exit 0

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 50

/system/bin/kssh start >> /data/local/tmp/kssh-autostart.log 2>&1
/system/bin/kvnc start >> /data/local/tmp/kvnc-autostart.log 2>&1
