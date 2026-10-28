#!/system/bin/sh
# wifi-fix — підняти Wi-Fi після monitor mode, без перезавантаження
# Драйвер qcacld вкомпільовано в ядро, тож перезавантажити його не можна:
# відновлюємо тип інтерфейсу і перезапускаємо стек.

log() { echo "[wifi-fix] $*"; }

# 0. QCA: повернути драйвер зі режиму монітора у station
CM=/sys/module/wlan/parameters/con_mode
if [ -f "$CM" ]; then
    cur=$(cat "$CM" 2>/dev/null)
    if [ "$cur" != "0" ]; then
        log "con_mode=$cur -> повертаю 0 (station)"
        echo 0 > "$CM" 2>/dev/null && log "con_mode скинуто"
        sleep 2
    else
        log "con_mode вже 0"
    fi
fi

log "вимикаю Wi-Fi у фреймворку"
svc wifi disable 2>/dev/null
sleep 2

# 1. прибрати monitor-інтерфейси, якщо їх створили
for i in $(ip -br link 2>/dev/null | awk '{print $1}' | grep -E '^(mon|wlan[0-9]*mon|prism|nethunter)'); do
    log "видаляю інтерфейс $i"
    ip link set "$i" down 2>/dev/null
    iw dev "$i" del 2>/dev/null
done

# 2. повернути wlan0 у managed
if ip link show wlan0 >/dev/null 2>&1; then
    t=$(iw dev wlan0 info 2>/dev/null | awk '/type/{print $2}')
    log "wlan0 зараз type=${t:-?}"
    if [ "$t" != "managed" ]; then
        ip link set wlan0 down 2>/dev/null
        iw dev wlan0 set type managed 2>/dev/null && log "повернув wlan0 у managed"
    fi
    ip link set wlan0 up 2>/dev/null
else
    log "УВАГА: wlan0 відсутній"
fi

# 3. перезапустити стек Wi-Fi
log "перезапускаю wpa_supplicant / wificond / wifi HAL"
stop wpa_supplicant 2>/dev/null
stop wificond 2>/dev/null
stop vendor.wifi_hal_legacy 2>/dev/null
sleep 2
start vendor.wifi_hal_legacy 2>/dev/null
start wificond 2>/dev/null
sleep 1
start wpa_supplicant 2>/dev/null
sleep 2

# 4. увімкнути Wi-Fi
log "вмикаю Wi-Fi"
svc wifi enable 2>/dev/null
sleep 4

# 5. підсумок
st=$(cmd wifi status 2>/dev/null | head -1)
t=$(iw dev wlan0 info 2>/dev/null | awk '/type/{print $2}')
log "результат: ${st:-немає відповіді} | wlan0 type=${t:-?}"
