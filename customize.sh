PKG_NAME="me.weishu.kernelsu"
ARCH=arm64
ARCH_LIB=arm64-v8a
MODULE_ARCH=arm64
VPATH=/data/adb/vasuki/${MODPATH##*/}.apk

set_perm_recursive "$MODPATH/bin" 0 0 0755 0777

if su -M -c true >/dev/null 2>&1; then
	alias mm='su -M -c'
else
	alias mm='nsenter -t1 -m'
fi

mm grep -F "$PKG_NAME" /proc/mounts | while read -r line; do
	mp=${line#* } mp=${mp%% *}
	mm umount -l "${mp%%\\*}"
done

am force-stop "$PKG_NAME"

pmex() {
	OP=$(pm "$@" 2>&1 </dev/null)
	RET=$?
	echo "$OP"
	return $RET
}

install_apk() {
	[ -f "$MODPATH/$PKG_NAME.apk" ] || abort

	VERIF1=$(settings get global verifier_verify_adb_installs)
	VERIF2=$(settings get global package_verifier_enable)
	settings put global verifier_verify_adb_installs 0
	settings put global package_verifier_enable 0
	SZ=$(stat -c "%s" "$MODPATH/$PKG_NAME.apk")

	for IT in 1 2; do
		SES=$(pmex install-create --user 0 -i com.android.vending -r -d -S "$SZ") || { install_err="$SES"; break; }
		SES=${SES#*[} SES=${SES%]*}
		set_perm "$MODPATH/$PKG_NAME.apk" 1000 1000 644 u:object_r:apk_data_file:s0
		pmex install-write -S "$SZ" "$SES" "$PKG_NAME.apk" "$MODPATH/$PKG_NAME.apk" || { install_err="$op"; break; }
		if ! op=$(pmex install-commit "$SES"); then
			if [ "$IS_SYS" = false ]; then
				pmex uninstall -k --user 0 "$PKG_NAME" || { install_err="$op"; break; }
				continue
			fi
			install_err="$op"
			break
		fi
		BASEPATH=$(pmex path "$PKG_NAME") || { install_err="Manual install required"; break; }
		BASEPATH=${BASEPATH##*:}
		BASEPATH=${BASEPATH%/*}
		break
	done

	settings put global verifier_verify_adb_installs "$VERIF1"
	settings put global package_verifier_enable "$VERIF2"
	[ "$install_err" ] && abort "$install_err"
}

IS_SYS=false
INS=true

if BASEPATH=$(pmex path "$PKG_NAME"); then
	BASEPATH=${BASEPATH##*:}
	BASEPATH=${BASEPATH%/*}
	if [ "${BASEPATH:1:4}" != data ]; then
		IS_SYS=true
	elif [ ! -f "$MODPATH/$PKG_NAME.apk" ]; then
		INS=false
	elif "${MODPATH:?}/bin/arm64/cmpr" "$BASEPATH/base.apk" "$MODPATH/$PKG_NAME.apk"; then
		INS=false
	fi
else
	install_apk
fi

[ "$INS" = true ] && install_apk

BASEPATHLIB=${BASEPATH}/lib/${ARCH}
if [ "$INS" = true ] || [ -z "$(ls -A1 "$BASEPATHLIB")" ]; then
	mkdir -p "$BASEPATHLIB"
	rm -f "$BASEPATHLIB"/* >/dev/null 2>&1 || :
	unzip -o -j "$MODPATH/$PKG_NAME.apk" "lib/${ARCH_LIB}/*" -d "$BASEPATHLIB" || abort
	set_perm_recursive "${BASEPATH}/lib" 1000 1000 755 755 u:object_r:apk_data_file:s0
fi

set_perm "$MODPATH/base.apk" 1000 1000 644 u:object_r:apk_data_file:s0

mkdir -p "/data/adb/vasuki"
mv -f "$MODPATH/base.apk" "$VPATH"

mm mount -o bind "$VPATH" "$BASEPATH/base.apk" || abort

am force-stop "$PKG_NAME"
nohup cmd package compile --reset "$PKG_NAME" >/dev/null 2>&1 &

rm -rf "${MODPATH:?}/bin" "$MODPATH/$PKG_NAME.apk"