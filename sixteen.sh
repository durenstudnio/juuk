#!/bin/bash

if [ "$#" -lt 6 ]; then
    echo "Usage: $0 <STOCK_DEVICE> <USE_UI_8_TETHERING_APEX> <TARGET_DEVICE> <TARGET_DEVICE_CSC> <TARGET_DEVICE_IMEI> <OUTPUT_FILESYSTEM>"
    exit 1
fi

# Device info
export STOCK_DEVICE="$1"
export USE_UI_8_TETHERING_APEX="$2"
export TARGET_DEVICE="$3"
export TARGET_DEVICE_CSC="$4"
export TARGET_DEVICE_IMEI="$5"
export OUTPUT_FILESYSTEM="$6"

VERSION="1"

# Directories
export FIRM_DIR="$(pwd)/FW"
export OUT_DIR="$(pwd)/OUT"
export WORK_DIR="$(pwd)/WORK"
export APKTOOL="$(pwd)/bin/java/apktool.jar"
export DEVICES_DIR="$(pwd)/QuantumROM/Devices"
export VNDKS_COLLECTION="$(pwd)/QuantumROM/vndks"

export BUILD_PARTITIONS="product,system_ext,system"

# Source
source "$(pwd)/scripts/debloat.sh"
source "$(pwd)/scripts/QuantumRom.sh"

# =================================================================
# AUTOMATIC STRUCTURE FLATTENING FUNCTION (Anti-Nesting)
# =================================================================
FIX_SYSTEM_NESTING() {
    echo "========================================================="
    echo "- Checking for deep system-in-system nesting..."
    echo "========================================================="
    
    local TARGET_FW_DIR="${FIRM_DIR}/${TARGET_DEVICE}"
    local SYS_DIR="${TARGET_FW_DIR}/system"

    # Jeśli struktura jest zbyt głęboka (np. system/system/system/), spłaszczamy ją,
    # ale zachowujemy dokładnie jeden podfolder 'system' (czyli system/system/), 
    # ponieważ reszta Twojego potoku i skryptu QuantumRom.sh tego wymaga.
    while [ -d "${SYS_DIR}/system/system" ]; do
        echo "[!] Detected critically deep nesting. Flattening one level..."
        
        local TMP_DIR="${TARGET_FW_DIR}/system_tmp_nest"
        mkdir -p "$TMP_DIR"
        
        # Przenosimy zawartość z najgłębszego poziomu wyżej
        mv "${SYS_DIR}/system/system"/* "$TMP_DIR/"
        
        # Sprzątamy i nadpisujemy strukturę pośrednią
        rm -rf "${SYS_DIR}/system/system"
        mv "$TMP_DIR" "${SYS_DIR}/system/system"
    done

    # Jeśli obraz miał tylko płaski folder system/ (brak zagnieżdżenia),
    # to tworzymy wymagany przez Twój skrypt folder system/system, aby reszta kodu nie dostała błędów.
    if [ ! -d "${SYS_DIR}/system" ]; then
        echo "[*] Flat system detected. Creating required system/system structure for compatibility..."
        local TMP_DIR="${TARGET_FW_DIR}/system_tmp_flat"
        mkdir -p "$TMP_DIR"
        
        # Przenosimy wszystkie pliki (bin, etc, framework) oprócz ewentualnych product/system_ext
        for file in "${SYS_DIR}"/*; do
            [ -e "$file" ] || continue
            local name=$(basename "$file")
            if [ "$name" != "product" ] && [ "$name" != "system_ext" ]; then
                mv "$file" "$TMP_DIR/"
            fi
        done
        
        mkdir -p "${SYS_DIR}/system"
        mv "$TMP_DIR"/* "${SYS_DIR}/system/"
        rm -rf "$TMP_DIR"
    fi

    # Czyszczenie i korekta plików konfiguracyjnych SELinux / fs_config
    echo "[*] Polishing config files from multi-nested paths..."
    if [ -f "${SYS_DIR}/system/etc/selinux/plat_file_contexts" ]; then
        sed -i -E 's|(/system)+/|/system/system/|g' "${SYS_DIR}/system/etc/selinux/plat_file_contexts"
    fi
    if [ -f "${SYS_DIR}/system/etc/fs_config_dirs" ]; then
        sed -i -E 's|(system/)+|system/system/|g' "${SYS_DIR}/system/system/etc/fs_config_dirs"
    fi
    if [ -f "${SYS_DIR}/system/etc/fs_config_files" ]; then
        sed -i -E 's|(system/)+|system/system/|g' "${SYS_DIR}/system/system/etc/fs_config_files"
    fi

    echo "[+] System nesting resolution complete. Structure is now standardized."
    echo "========================================================="
}

# Pipeline start
#EXTRACT_FIRMWARE "$FIRM_DIR/$TARGET_DEVICE"
EXTRACT_SUPER_IMG "$FIRM_DIR/$TARGET_DEVICE"
EXTRACT_FIRMWARE_IMG "$FIRM_DIR/$TARGET_DEVICE" "all"

# === TU NASTĘPUJE UNIFORMIDACJA STRUKTURY POD TWÓJ SKRYPT ===
FIX_SYSTEM_NESTING

DECODE_OMC "$FIRM_DIR/$TARGET_DEVICE" "$WORK_DIR"
DEBLOAT "$FIRM_DIR/$TARGET_DEVICE"

APPLY_STOCK_CONFIG "$FIRM_DIR/$TARGET_DEVICE"
PATCH_CSC "$FIRM_DIR/$TARGET_DEVICE"

DISABLE_FBE "$FIRM_DIR/$TARGET_DEVICE"
DISABLE_FDE "$FIRM_DIR/$TARGET_DEVICE"

# Adjust partitions size

DECOMPILE "$APKTOOL" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework/services.jar" "$WORK_DIR"
DECOMPILE "$APKTOOL" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework/samsungkeystoreutils.jar" "$WORK_DIR"

PATCH_SSRM "$WORK_DIR/ssrm"
PATCH_FLAG_SECURE "$WORK_DIR/services"
PATCH_SECURE_FOLDER "$WORK_DIR/services"
PATCH_PRIVATE_SHARE "$WORK_DIR/samsungkeystoreutils"

RECOMPILE "$APKTOOL" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework" "$WORK_DIR/ssrm" "$WORK_DIR"
RECOMPILE "$APKTOOL" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework" "$WORK_DIR/services" "$WORK_DIR"
RECOMPILE "$APKTOOL" "$FIRM_DIR/$TARGET_DEVICE/system/system/framework" "$WORK_DIR/samsungkeystoreutils" "$WORK_DIR"
mv -f "$WORK_DIR"/*.jar "$FIRM_DIR/$TARGET_DEVICE/system/system/framework/"

PATCH_BT_LIB "$FIRM_DIR/$TARGET_DEVICE" "$WORK_DIR"

B_ID="$(grep -m1 '^ro.system.build.id=' "$FIRM_DIR/$TARGET_DEVICE/system/system/build.prop" | cut -d= -f2 | tr -d '\r')"
B_V="$(grep -m1 '^ro.system.build.version.release=' "$FIRM_DIR/$TARGET_DEVICE/system/system/build.prop" | cut -d= -f2 | tr -d '\r')"
B_D="$(grep -m1 '^ro.build.date.utc=' "$FIRM_DIR/$TARGET_DEVICE/system/system/build.prop" | cut -d= -f2 | tr -d '\r')"

SET_BASE_PROP "$FIRM_DIR/$TARGET_DEVICE" "$B_ID" "$B_V" "$B_D"

# Porting adjustments
ADJUST_SYSTEM_EXT "$FIRM_DIR/$TARGET_DEVICE"
FIX_VNDK "$FIRM_DIR/$TARGET_DEVICE" "$VNDKS_COLLECTION"

# Remount / read-write fix
PATCH_REMOUNT "$FIRM_DIR/$TARGET_DEVICE"

# Setup device files
SETUP_DEVICE_FILES "$DEVICES_DIR" "$TARGET_DEVICE" "$FIRM_DIR/$TARGET_DEVICE"

# Check apexes
CHECK_APEXES "$FIRM_DIR/$TARGET_DEVICE" "$WORK_DIR" "$USE_UI_8_TETHERING_APEX"

# Clear work dir
rm -rf "$WORK_DIR"/*

# Rebuild images
for p in $(echo "$BUILD_PARTITIONS" | tr ',' ' '); do
    BUILD_FIRMWARE_IMG "$FIRM_DIR/$TARGET_DEVICE" "$p" "$OUTPUT_FILESYSTEM"
done

BUILD_SUPER_IMG "$FIRM_DIR/$TARGET_DEVICE" "$OUT_DIR"

# Copy images to output folder
echo "Copying output images..."
for img in "$FIRM_DIR/$TARGET_DEVICE"/*.img; do
    [ -f "$img" ] || continue
    case "$(basename "$img")" in
        boot.img|init_boot.img|recovery.img|vbmeta.img|vbmeta_system.img|vbmeta_vendor.img|dtbo.img|vendor_boot.img)
            cp -f "$img" "$OUT_DIR/"
            echo "- Copied $(basename "$img") to OUT directory"
            ;;
    esac
done

echo "Done!"
