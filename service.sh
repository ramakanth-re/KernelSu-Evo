#!/system/bin/sh
MODDIR=${0%/*}
PKG_NAME="me.weishu.kernelsu"
VAPK="/data/adb/vasuki/${MODDIR##*/}.apk"

until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 1; done
until [ -d /sdcard/Android ]; do sleep 1; done

tries=0
while [ $tries -lt 15 ]; do
  pm path "$PKG_NAME" >/dev/null 2>&1 || { sleep 1; tries=$((tries+1)); continue; }

  BASEPATH="$(pm path "$PKG_NAME" 2>/dev/null | sed -n 's/^package://p' | sed 's!/base\.apk$!!')"
  [ -n "$BASEPATH" ] || { sleep 1; tries=$((tries+1)); continue; }

  grep -F "$PKG_NAME" /proc/mounts | while read -r line; do
    mp=${line#* } ; mp=${mp%% *}
    umount -l "${mp%%\\*}" 2>/dev/null || true
  done

  [ -f "$VAPK" ] || exit 0

  chown 1000:1000 "$VAPK" 2>/dev/null || true
  chmod 0644 "$VAPK" 2>/dev/null || true
  chcon u:object_r:apk_data_file:s0 "$VAPK" 2>/dev/null || true

  mount -o bind "$VAPK" "$BASEPATH/base.apk" || { sleep 1; tries=$((tries+1)); continue; }

  restorecon -FR "$BASEPATH" 2>/dev/null || true
  am force-stop "$PKG_NAME" >/dev/null 2>&1 || true
  cmd package compile --reset "$PKG_NAME" >/dev/null 2>&1 || true
  rm -rf /data/system/package_cache/* >/dev/null 2>&1 || true
  exit 0
done

exit 1
