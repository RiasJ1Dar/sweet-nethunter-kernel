#!/system/bin/sh
# vnc — керування графічним столом Kali у chroot Stryker
# start | stop | status | log

S=/data/data/com.zalexdev.stryker/files
MNT=/data/local/stryker/release
BB=$S/busybox

die() { echo "[-] $*"; exit 1; }

[ -x "$BB" ] || die "busybox Stryker не знайдено — застосунок встановлено?"
[ -d "$MNT" ] || die "chroot відсутній: $MNT"

inroot() { "$BB" chroot "$MNT" /bin/bash -c "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root USER=root; $*"; }

mount_chroot() {
    "$BB" mountpoint -q "$MNT/proc" && return 0
    echo "[*] монтую chroot…"
    sh "$S/bootroot" 2>&1 | sed 's/^/    /'
    # спільна тека зі здобиччю — та сама, що й у Kali
    mkdir -p /data/media/0/Loot "$MNT/loot" 2>/dev/null
    "$BB" mountpoint -q "$MNT/loot" || "$BB" mount -o bind /data/media/0/Loot "$MNT/loot"
    inroot '[ -L /root/loot ] || { rm -rf /root/loot 2>/dev/null; ln -sf /loot /root/loot; }'
}

case "${1:-start}" in
  start)
      mount_chroot
      inroot 'command -v vnc-up >/dev/null' || die "vnc-up немає — встанови VNC зі Stryker"
      inroot 'vnc-up'
      ;;
  stop)
      inroot 'vnc-down' 2>/dev/null || echo "[-] не вдалося зупинити"
      ;;
  status)
      echo "chroot:  $("$BB" mountpoint -q "$MNT/proc" && echo змонтовано || echo НЕ змонтовано)"
      for p in Xvfb x11vnc xfwm4; do
          printf '%-9s ' "$p:"; pidof "$p" >/dev/null 2>&1 && echo працює || echo зупинено
      done
      echo "порт:    $(netstat -tln 2>/dev/null | grep -q ':5901 ' && echo '5901 слухає' || echo 'не слухає')"
      a=$(ip -4 -o addr show 2>/dev/null | awk '$2!="lo"{split($4,b,"/"); print $2, b[1]}' \
            | sort -k1,1 | awk '/^wlan/{print $2; f=1; exit} {l=$2} END{if(!f && l) print l}')
      [ -n "$a" ] && echo "адреса: http://$a:6080/vnc.html"
      ;;
  log)
      inroot 'cat /tmp/vnc-up.log 2>/dev/null; echo; vnc-diag 2>/dev/null'
      ;;
  *)
      echo "використання: vnc {start|stop|status|log}"; exit 1 ;;
esac
