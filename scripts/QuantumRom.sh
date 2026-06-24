#!/bin/bash

###################################################################################################

REAL_USER=${SUDO_USER:-$USER}

# QT DIR
QT_DIR="$(pwd)"

# Binary
export lpmake="$QT_DIR/bin/lp/lpmake"
export lpunpack="$QT_DIR/bin/lp/lpunpack"
export make_ext4fs="$QT_DIR/bin/ext4/make_ext4fs"
export make_f2fs="$QT_DIR/bin/f2fs-tools/mkfs.f2fs"
export sload_f2fs="$QT_DIR/bin/f2fs-tools/sload.f2fs"
export omc_decoder="$QT_DIR/bin/java/omc-decoder.jar"
export mkfs_erofs="$QT_DIR/bin/erofs-utils/mkfs.erofs"
export extract_erofs="$QT_DIR/bin/erofs-utils/extract.erofs"
export imgextractor_py="$QT_DIR/bin/py_scripts/imgextractor.py"

chmod +x "$lpmake"
chmod +x "$lpunpack"
chmod +x "$make_f2fs"
chmod +x "$sload_f2fs"
chmod +x "$mkfs_erofs"
chmod +x "$make_ext4fs"
chmod +x "$extract_erofs"


CHECK_FILE() {
    if [ ! -f "$1" ]; then
        echo -e "[!] File not found: $1"
        echo -e "- Skipping..."
        return 1
    fi
    return 0
}


REMOVE_LINE() {
    if [ "$#" -ne 2 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <TARGET_LINE> <TARGET_FILE>"
        return 1
    fi

    local LINE="$1"
    local FILE="$2"

    echo -e "- Deleting $LINE from $FILE"
    grep -vxF "$LINE" "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
}


GET_PROP() {
    if [ "$#" -ne 3 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR> <PARTITION> <PROP>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"
    local PARTITION="$2"
    local PROP="$3"

    case "$PARTITION" in
        system)
            FILE="${EXTRACTED_FIRM_DIR}/system/system/build.prop"
            ;;
        vendor)
            FILE="${EXTRACTED_FIRM_DIR}/vendor/build.prop"
            ;;
        product)
            FILE="${EXTRACTED_FIRM_DIR}/product/etc/build.prop"
            ;;
        system_ext)
            FILE="${EXTRACTED_FIRM_DIR}/system_ext/etc/build.prop"
            ;;
        odm)
            FILE="${EXTRACTED_FIRM_DIR}/odm/etc/build.prop"
            ;;
        *)
            echo -e "Unknown partition: $PARTITION"
            return 1
            ;;
    esac

    if [ ! -f "$FILE" ]; then
        echo -e "- File not found: $FILE"
        return 1
    fi

    local VALUE=$(grep -m1 "^${PROP}=" "$FILE" | cut -d'=' -f2-)

    if [ -z "$VALUE" ]; then
        return 1
    fi

    echo -e "$VALUE"
}


GET_FF_VALUE() {
    local KEY="$1"
    local FILE="$2"

    awk -F'[<>]' -v key="$KEY" '
        $2 == key { print $3; exit }
    ' "$FILE"
}


DETECT_FILESYSTEM() {
    local imgfile="$1"

    [ ! -f "$imgfile" ] && {
        echo "unknown"
        return 1
    }

    local fstype=$(blkid -o value -s TYPE "$imgfile" 2>/dev/null)
    [ -z "$fstype" ] && fstype=$(file -b "$imgfile" 2>/dev/null)

    case "$fstype" in
        *"Android sparse image"*)
            echo "sparse"
            ;;
        *"ext2"*)
            echo "ext2"
            ;;
        *"ext3"*)
            echo "ext3"
            ;;
        *"ext4"*)
            echo "ext4"
            ;;
        *"f2fs"*|*"F2FS"*)
            echo "f2fs"
            ;;
        *"erofs"*|*"EROFS"*)
            echo "erofs"
            ;;
        *"squashfs"*|*"Squashfs"*)
            echo "squashfs"
            ;;
        *"LZ4 compressed"*)
            echo "lz4"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}


DOWNLOAD_GITHUB_ARTIFACT() {
    echo " "

    if [ "$#" -ne 2 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <ARTIFACT_RUN_ID_OR_URL> <DOWNLOAD_DIRECTORY>"
        return 1
    fi

    local INPUT_ID="$1"
    local DOWN_DIR="$2"
    local RUN_ID=""

    if [[ "$INPUT_ID" == *"github.com"* ]]; then
        RUN_ID=$(echo "$INPUT_ID" | sed -E 's|.*/runs/([^/]+).*|\1|')
    else
        RUN_ID="$INPUT_ID"
    fi

    rm -rf "$DOWN_DIR"
    mkdir -p "$DOWN_DIR"

    echo -e "======================================"
    echo -e "   GitHub Artifact Downloader         "
    echo -e "======================================"
    echo -e "Run ID: $RUN_ID"
    echo -e "Downloading to: $DOWN_DIR"

    # Pobiera i automatycznie wypakowuje zawartość artefaktów z danego run-id do katalogu docelowego
    gh run download "$RUN_ID" --repo "durenstudnio/johnas" --dir "$DOWN_DIR"

    if [ $? -ne 0 ]; then
        echo -e "⛔️ GitHub Artifact download failed! Sprawdź Run ID lub uprawnienia tokenu (GH_TOKEN)."
        exit 1
    fi

    echo -e "✅ Download and extraction complete."
}


EXTRACT_FIRMWARE() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <FIRMWARE_DIRECTORY>"
        return 1
    fi

    local FIRM_DIR="$1"

    echo -e "Extracting downloaded firmware."

    if [ ! -d "$FIRM_DIR" ]; then
        echo -e "- Directory not found: $FIRM_DIR"
        exit
    fi

    # ---- ZIP ----
    for file in "$FIRM_DIR"/*.zip; do
        [ -e "$file" ] || continue

        echo -e "Extracting zip: $(basename "$file")"
        7z x -y -bd -bsp1 -o"$FIRM_DIR" "$file"

        rm -f "$file"
    done

    # remove unwanted archives before extraction
    rm -f "$FIRM_DIR"/BL_*.tar.md5
    rm -f "$FIRM_DIR"/CP_*.tar.md5
    rm -f "$FIRM_DIR"/HOME_CSC_*.tar.md5
    rm -f "$FIRM_DIR"/USERDATA_*.tar.md5

    # ---- XZ ----
    for file in "$FIRM_DIR"/*.xz; do
        [ -e "$file" ] || continue

        echo -e "Extracting xz: $(basename "$file")"
        7z x -y -bd -bsp1 -o"$FIRM_DIR" "$file"

        rm -f "$file"
    done

    # ---- RENAME .MD5 -> .TAR ----
    for file in "$FIRM_DIR"/*.md5; do
        [ -e "$file" ] || continue

        mv -- "$file" "${file%.md5}"
    done

    # ---- TAR ----
    for file in "$FIRM_DIR"/*.tar; do
        [ -e "$file" ] || continue

        echo -e "Extracting tar: $(basename "$file")"

        tar -xf "$file" -C "$FIRM_DIR"

        # remove only samsung firmware tar archives
        case "$(basename "$file")" in
            AP_*|BL_*|CP_*|CSC_*|HOME_CSC_*)
                rm -f "$file"
                ;;
        esac
    done

    # ---- REMOVE UNWANTED LZ4 FILES ----
    rm -rf \
        "$FIRM_DIR/meta-data" \
        "$FIRM_DIR"/*.txt \
        "$FIRM_DIR"/*.pit \
        "$FIRM_DIR"/*.bin \
        "$FIRM_DIR"/cache.img.lz4 \
        "$FIRM_DIR"/dtbo.img.lz4 \
        "$FIRM_DIR"/efuse.img.lz4 \
        "$FIRM_DIR"/gz-verified.img.lz4 \
        "$FIRM_DIR"/lk-verified.img.lz4 \
        "$FIRM_DIR"/md1img.img.lz4 \
        "$FIRM_DIR"/md_udc.img.lz4 \
        "$FIRM_DIR"/misc.bin.lz4 \
        "$FIRM_DIR"/omr.img.lz4 \
        "$FIRM_DIR"/param.bin.lz4 \
        "$FIRM_DIR"/preloader.img.lz4 \
        "$FIRM_DIR"/recovery.img.lz4 \
        "$FIRM_DIR"/scp-verified.img.lz4 \
        "$FIRM_DIR"/spmfw-verified.img.lz4 \
        "$FIRM_DIR"/sspm-verified.img.lz4 \
        "$FIRM_DIR"/tee-verified.img.lz4 \
        "$FIRM_DIR"/tzar.img.lz4 \
        "$FIRM_DIR"/up_param.bin.lz4 \
        "$FIRM_DIR"/userdata.img.lz4 \
        "$FIRM_DIR"/vbmeta.img.lz4 \
        "$FIRM_DIR"/vbmeta_system.img.lz4 \
        "$FIRM_DIR"/audio_dsp-verified.img.lz4 \
        "$FIRM_DIR"/cam_vpu1-verified.img.lz4 \
        "$FIRM_DIR"/cam_vpu2-verified.img.lz4 \
        "$FIRM_DIR"/cam_vpu3-verified.img.lz4 \
        "$FIRM_DIR"/dpm-verified.img.lz4 \
        "$FIRM_DIR"/init_boot.img.lz4 \
        "$FIRM_DIR"/mcupm-verified.img.lz4 \
        "$FIRM_DIR"/pi_img-verified.img.lz4 \
        "$FIRM_DIR"/uh.bin.lz4 \
        "$FIRM_DIR"/vendor_boot.img.lz4 \
        "$FIRM_DIR"/ssu.img.lz4

    # ---- LZ4 ----
    for file in "$FIRM_DIR"/*.lz4; do
        [ -e "$file" ] || continue

        echo -e "Extracting lz4: $(basename "$file")"

        lz4 -d "$file" "${file%.lz4}"

        rm -f "$file"
    done

    echo -e "Firmware Extraction complete."
}


EXTRACT_SUPER_IMG() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <FIRMWARE_DIRECTORY>"
        return 1
    fi

    local FIRM_DIR="$1"

    if [ -f "$FIRM_DIR/super.img" ]; then
        echo -e "Extracting super.img"
        if [ "$(DETECT_FILESYSTEM "$FIRM_DIR/super.img")" = "sparse" ]; then
            echo -e "Converting to raw super.img"
            simg2img "$FIRM_DIR/super.img" "$FIRM_DIR/super_raw.img"
            rm -f "$FIRM_DIR/super.img"
            mv -f "$FIRM_DIR/super_raw.img" "$FIRM_DIR/super.img"
        fi

        echo "- Extracting partitions from super.img"
        "$lpunpack" "$FIRM_DIR/super.img" "$FIRM_DIR" || return 1
        rm -f "$FIRM_DIR/super.img"

        echo -e "super.img extraction complete"

    else
        echo -e "No super.img found."
    fi
}


PREPARE_PARTITIONS() {
    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"

    echo -e "Preparing partitions. $STOCK_DEVICE"
    
    if [ ! -d "$EXTRACTED_FIRM_DIR" ]; then
        echo -e "- Directory not found: $EXTRACTED_FIRM_DIR"
        return 1
    fi

    if [ -z "$STOCK_DEVICE" ] || [ "$STOCK_DEVICE" = "None" ]; then
        export BUILD_PARTITIONS="odm,odm_dlkm,product,system,system_ext,system_dlkm,vendor,vendor_dlkm,odm_a,odm_dlkm_a,product_a,system_a,system_ext_a,system_dlkm_a,vendor_a,vendor_dlkm_a,optics,optics_a"
    fi

    if [ -n "$STOCK_DEVICE" ] && [ -f "${DEVICES_DIR}/$STOCK_DEVICE/config" ]; then
        export STOCK_HAS_AB_SLOT="$(grep -m1 '^STOCK_HAS_AB_SLOT=' "${DEVICES_DIR}/$STOCK_DEVICE/config" | cut -d= -f2 | tr -d '\r')"
    fi

    # Delete empty b slot images
    find "$EXTRACTED_FIRM_DIR" -type f -name '*_b.img' -size 0c -exec rm -rf {} +

    for img in "$EXTRACTED_FIRM_DIR"/*_a.img; do
        [ -f "$img" ] || continue

        new="${img%_a.img}.img"
        mv -f "$img" "$new"
    done

    IFS=',' read -r -a KEEP <<< "$BUILD_PARTITIONS"

    for i in "${!KEEP[@]}"; do
        KEEP[$i]=$(echo -e "${KEEP[$i]}" | xargs)
    done

    shopt -s nullglob dotglob

    for item in "$EXTRACTED_FIRM_DIR"/*; do
        base=$(basename "$item")

        [[ "$base" == *.img ]] && base="${base%.img}"

        keep_this=0
        for k in "${KEEP[@]}"; do
            [[ "$k" == "$base" ]] && keep_this=1 && break
        done

        if [[ $keep_this -eq 0 ]]; then
            rm -rf -- "$item"
        fi
    done

    shopt -u nullglob dotglob
}


EXTRACT_FIRMWARE_IMG() {
    echo " "

    if [ "$#" -ne 2 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR> all|img_name"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"
    local MODE="$2"

    if ! ls "$EXTRACTED_FIRM_DIR"/*.img >/dev/null 2>&1; then
        echo -e "No .img files found in: $EXTRACTED_FIRM_DIR"
        return 1
    fi

    echo -e "Extracting images from: $EXTRACTED_FIRM_DIR"

    extract_img() {
        local imgfile="$1"

        [ -e "$imgfile" ] || return

        local img_name="$(basename "$imgfile")"

        if [[ "$img_name" == "boot.img" || "$img_name" == "recovery.img" ]]; then
            echo -e "- Skipping $img_name"
            return
        fi

        local partition="$(basename "${imgfile%.img}")"
        local ORG_IMG_SIZE=$(stat -c%s -- "$imgfile")

        rm -rf "${EXTRACTED_FIRM_DIR}/$partition"

        local fstype=$(DETECT_FILESYSTEM "$imgfile")
        if [ "$fstype" = "sparse" ]; then
            echo -e "$partition.img is SPARSE. Converting to raw img."

            local tmp_raw="${imgfile}.raw"

            if ! simg2img "$imgfile" "$tmp_raw" >/dev/null 2>&1; then
                echo -e "Failed to convert sparse image: $img_name"
                return
            fi

            if [ ! -f "$tmp_raw" ]; then
                echo -e "- Sparse conversion output missing: $tmp_raw"
                return
            fi

            rm -f "$imgfile"
            mv "$tmp_raw" "$imgfile"
        fi

        local fstype=$(DETECT_FILESYSTEM "$imgfile")

        case "$fstype" in
            ext4)
                echo " "
                echo -e "$partition.img Detected ext4. Size: $ORG_IMG_SIZE bytes. Extracting..."
                python3 "$imgextractor_py" "$imgfile" "$EXTRACTED_FIRM_DIR"
                ;;

            erofs)
                echo " "
                echo -e "$partition.img Detected erofs. Size: $ORG_IMG_SIZE bytes. Extracting..."
                "$extract_erofs" -i "$imgfile" -x -f -o "$EXTRACTED_FIRM_DIR" >/dev/null 2>&1
                ;;

            f2fs)
                echo " "
                echo -e "$partition.img Detected f2fs. Size: $ORG_IMG_SIZE bytes. Extracting..."
                bash "$QT_DIR/scripts/extract_img.sh" "$imgfile" "$EXTRACTED_FIRM_DIR"
                ;;

            *)
                echo -e "- $img_name unsupported filesystem type: ($fstype), skipping"
                ;;
        esac
    }

    if [ "$MODE" = "all" ]; then
        PREPARE_PARTITIONS "$EXTRACTED_FIRM_DIR"
        for imgfile in "$EXTRACTED_FIRM_DIR"/*.img; do
            [ -e "$imgfile" ] || continue
            extract_img "$imgfile"
        done

        rm -rf "$EXTRACTED_FIRM_DIR"/*.img

    else
        local TARGET_IMG="${EXTRACTED_FIRM_DIR}/$MODE"

        if [ ! -f "$TARGET_IMG" ]; then
            echo -e "- Image not found: $TARGET_IMG"
            return 1
        fi

        extract_img "$TARGET_IMG"
    fi

    chown -R "$REAL_USER:$REAL_USER" "$EXTRACTED_FIRM_DIR"
    chmod -R u+rwX "$EXTRACTED_FIRM_DIR"
}


DISABLE_FBE() {
    local EXTRACTED_FIRM_DIR="$1"

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIRECTORY>"
        return 1
    fi

    if [ ! -d "${EXTRACTED_FIRM_DIR}/vendor/etc" ]; then
        return 1
    fi

    local fstab_files=$(grep -lr 'fileencryption' "${EXTRACTED_FIRM_DIR}/vendor/etc" 2>/dev/null)

    for i in $fstab_files; do
        if [ -f "$i" ]; then
            echo -e "- Disabling file-based encryption (FBE) for /data."
            echo -e "- Found $i."
            sed -i -e 's/^\([^#].*\)fileencryption=[^,]*\(.*\)$/# &\n\1encryptable\2/g' "$i"
        fi
    done
}


DISABLE_FDE() {
    local EXTRACTED_FIRM_DIR="$1"

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIRECTORY>"
        return 1
    fi

    if [ ! -d "${EXTRACTED_FIRM_DIR}/vendor/etc" ]; then
        return 1
    fi

    local fstab_files=$(grep -lr 'forceencrypt' "${EXTRACTED_FIRM_DIR}/vendor/etc" 2>/dev/null)

    for i in $fstab_files; do
        if [ -f "$i" ]; then
            echo -e "- Disabling full-disk encryption (FDE) for /data..."
            echo -e "- Found $i."
            md5=$(md5 "$i")
            sed -i -e 's/^\([^#].*\)forceencrypt=[^,]*\(.*\)$/# &\n\1encryptable\2/g' "$i"
            file_changed "$i" "$md5"
        fi
    done
}


INSTALL_FRAMEWORK() {
    echo " "

    if [ "$#" -ne 2 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <APKTOOL_JAR_DIR> <framework-res.apk>"
        return 1
    fi

    local APKTOOL="$1"
    local framework_apk="$2"

    if [ ! -f "$framework_apk" ]; then
        echo -e "- File not found: $framework_apk"
        return 1
    fi

    echo -e "Installing: $framework_apk"
    java -jar "$APKTOOL" install-framework "$framework_apk"
}


DECOMPILE() {
    echo " "

    if [ "$#" -ne 4 ]; then
        echo -e "Usage: DECOMPILE <APKTOOL_JAR_DIR> <FRAMEWORK_DIR> <FILE> <DECOMPILE_DIR>"
        return 1
    fi

    local APKTOOL="$1"
    local FRAMEWORK_DIR="$2"
    local FILE="$3"
    local DECOMPILE_DIR="$4"
    local BASENAME="$(basename "${FILE%.*}")"
    local OUT="$DECOMPILE_DIR/$BASENAME"

    echo -e "Decompiling: $FILE"

    if [ ! -f "$FILE" ]; then
        echo -e "- File not found: $FILE"
        return 1
    fi

    rm -rf "$OUT"
    java -jar "$APKTOOL" d --force --frame-path "$FRAMEWORK_DIR" --match-original "$FILE" -o "$OUT"
}


RECOMPILE() {
    echo " "

    if [ "$#" -ne 4 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <APKTOOL_JAR_DIR> <FRAMEWORK_DIR> <DECOMPILED_DIR> <RECOMPILE_DIR>"
        return 1
    fi

    local APKTOOL="$1"
    local FRAMEWORK_DIR="$2"
    local DECOMPILED_DIR="$3"
    local RECOMPILE_DIR="$4"

    local org_file_name=$(awk '/^apkFileName:/ {print $2}' "$DECOMPILED_DIR/apktool.yml")
    local name="${org_file_name%.*}"
    local ext="${org_file_name##*.}"
    local built_file="$RECOMPILE_DIR/${name}.$ext"

    echo -e "Recompiling: $DECOMPILED_DIR"

    if [ ! -d "$DECOMPILED_DIR" ]; then
        echo -e "- Directory not found: $DECOMPILED_DIR"
        return 1
    fi

    java -jar "$APKTOOL" b "$DECOMPILED_DIR" --copy-original --frame-path "$FRAMEWORK_DIR" -o "$built_file"
    rm -rf "$DECOMPILED_DIR"
}


REPLACE_SMALI_METHOD() {
    local FILE="$1"
    local METHOD_NAME="$2"
    local NEW_BODY=$(echo -e "$3" | tail -n +2)

    echo -e "- Patching: $FILE"
    echo -e "- Method: $METHOD_NAME"

    if ! grep -Fq "$METHOD_NAME" "$FILE"; then
        echo -e "- Method not found → Skipped"
        return 0
    fi

    local METHOD_KEY=$(echo "$METHOD_NAME" | sed -E 's/.* ([^ ]+\().*/\1/')

    sed -i "
/^[[:space:]]*\.method.*$METHOD_KEY/,/^[[:space:]]*\.end method/{
    /^[[:space:]]*\.method/{
        p
        r /dev/stdin
        d
    }
    /^[[:space:]]*\.end method/p
    d
}" "$FILE" <<< "$NEW_BODY"
}


HEX_PATCH() {
    echo " "

    if [ "$#" -ne 3 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <FILE> <TARGET_VALUE> <REPLACE_VALUE>"
        return 1
    fi

    local FILE="$1"
    local FROM="$(echo -e "$2" | tr '[:upper:]' '[:lower:]')"
    local TO="$(echo -e "$3" | tr '[:upper:]' '[:lower:]')"

    [ ! -f "$FILE" ] && { echo -e "File not found: $FILE"; return 1; }

    xxd -p -c 0 "$FILE" | grep -q "$FROM" || {
        echo -e "- Pattern not found: $FROM"
        return 1
    }

    echo -e "- Patching: $FILE"
    echo -e "- From $FROM to $TO"
    [ -f "$FILE.bak" ] || cp "$FILE" "$FILE.bak"

    xxd -p -c 0 "$FILE" | sed "s/$FROM/$TO/" | xxd -r -p > "$FILE.tmp" &&
    mv "$FILE.tmp" "$FILE"

    xxd -p -c 0 "$FILE" | grep -q "$TO" && {
        echo -e "- Patch success"
        rm -rf "$FILE.bak"        
        return 0
    }

    echo -e "- Patch failed, restoring backup"
    mv "$FILE.bak" "$FILE"
    return 1
}


PATCH_FLAG_SECURE() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo -e "Patching flag secure."

    local FILE_1="${1}/smali_classes2/com/android/server/wm/WindowState.smali"
    local METHOD_NAME_1=".method public final isSecureLocked()Z"
    local REPLACE_BODY_1='
    .locals 1

    const/4 v0, 0x0

    return v0
    '
    REPLACE_SMALI_METHOD "$FILE_1" "$METHOD_NAME_1" "$REPLACE_BODY_1"
  
    local FILE_2="${1}/smali_classes2/com/android/server/wm/WindowManagerService.smali"
    local METHOD_NAME_2=".method public final notifyScreenshotListeners(I)Ljava/util/List;"
    local REPLACE_BODY_2='
    .locals 3
    .annotation system Ldalvik/annotation/Signature;
        value = {
            "(I)",
            "Ljava/util/List<",
            "Landroid/content/ComponentName;",
            ">;"
        }
    .end annotation

    const-string/jumbo v0, "android.permission.STATUS_BAR_SERVICE"

    const-string/jumbo v1, "notifyScreenshotListeners()"

    const/4 v2, 0{BUILD_SUPER_IMG}1 {BUILD_SUPER_IMG}	invoke-virtual {p0, v0, v1, v2}, Lcom/android/server/wm/WindowManagerService;->checkCallingPermission$1(Ljava/lang/String;Ljava/lang/String;Z)Z

    move-result v0

    if-eqz v0, :cond_43

    invoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;

    move-result-object p0

    return-object p0

    :cond_43
    new-instance p0, Ljava/lang/SecurityException;

    const-string/jumbo p1, "Requires STATUS_BAR_SERVICE permission"

    invoke-direct {p0, p1}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V

    throw p0
    '
    REPLACE_SMALI_METHOD "$FILE_2" "$METHOD_NAME_2" "$REPLACE_BODY_2"
}


PATCH_SECURE_FOLDER() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo -e "Patching secure folder."

    local FILE_1="${1}/smali/com/android/server/knox/dar/DarManagerService.smali"
    local METHOD_NAME_1=".method public final checkDeviceIntegrity([Ljava/security/cert/Certificate;)Z"
    local METHOD_NAME_2=".method public final isDeviceRootKeyInstalled()Z"
    local METHOD_NAME_3=".method public final isKnoxKeyInstallable()Z"
    
    local REPLACE_BODY_1='
    .locals 0
 
    const/4 p0, 1
 
    return p0
    '

    REPLACE_SMALI_METHOD "$FILE_1" "$METHOD_NAME_1" "$REPLACE_BODY_1"
    REPLACE_SMALI_METHOD "$FILE_1" "$METHOD_NAME_2" "$REPLACE_BODY_1"
    REPLACE_SMALI_METHOD "$FILE_1" "$METHOD_NAME_3" "$REPLACE_BODY_1"

    local FILE_2="${1}/smali/com/android/server/StorageManagerService.smali"
    local METHOD_NAME_4=".method public static isRootedDevice()Z"
    local REPLACE_BODY_2='
    .locals 1
 
    const/4 v0, 0x0
 
    return v0
    '
    REPLACE_SMALI_METHOD "$FILE_2" "$METHOD_NAME_4" "$REPLACE_BODY_2"
}


PATCH_PRIVATE_SHARE() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo -e "Patching private share."
    
    local FILE="${1}/smali/com/samsung/android/security/keystore/AttestParameterSpec.smali"
    local METHOD_NAME=".method public i{BUILD_SUPER_IMG}sVerifiableIntegrity()Z"
    local REPLACE_BODY='
    .locals 1
 
    const/4 v0, 1
 
    return v0
    '
    REPLACE_SMALI_METHOD "$FILE" "$METHOD_NAME" "$REPLACE_BODY"
}


DISABLE_SIGNATURE_VERIFICATION() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo -e "Disabling signature verification."

    local FILE="${1}/smali_classes4/android/util/apk/ApkSignatureVerifier.smali"
    local METHOD_NAME=".method public static blacklist getMinimumSignatureSchemeVersionForTargetSdk(I)I"
    local REPLACE_BODY='
    .locals 1

    const/4 v0, 1
 
    return v0
    '
    REPLACE_SMALI_METHOD "$FILE" "$METHOD_NAME" "$REPLACE_BODY"
}


PATCH_KNOX_GUARD() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_SERVICES_DIRECTORY>"
        return 1
    fi

    echo -e "Patching knox guard."
    local FILE="${1}/smali_classes2/com/samsung/android/knoxguard/service/KnoxGuardSeService.smali"
    local METHOD_NAME_1=".method public constructor <init>(Landroid/content/Context;)V"
    local REPLACE_BODY_1='
    .locals 0
 
    invoke-direct {p0}, Lcom/samsung/android/knoxguard/IKnoxGuardManager$Stub;-><init>()V
 
    const/4 p1, 0x0
 
    iput-object p1, p0, Lcom/samsung/android/knoxguard/service/KnoxGuardSeService;->mConnectivityManagerService:Landroid/net/ConnectivityManager;
 
    new-instance p0, Ljava/lang/UnsupportedOperationException;
 
    const-string p1, "KnoxGuard is disabled"
 
    invoke-direct {p0, p1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V

    throw p0
    '
    REPLACE_SMALI_METHOD "$FILE" "$METHOD_NAME_1" "$REPLACE_BODY_1"
    rm -rf "$FIRM_DIR/$TARGET_DEVICE/system/system/priv-app/KnoxGuard"
}


UPDATE_SDHMS() {
    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIRECTORY>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"

    if [ "$USE_ALT_SDHMS_APP" = "TRUE" ]; then
        echo "- Adding alternative SDHMS app."
        rm -rf "${EXTRACTED_FIRM_DIR}/system/priv-app/SamsungDeviceHealthManagerService"
        cp -a "$(pwd)/QuantumROM/Mods/Apps/SDHMS/." "${EXTRACTED_FIRM_DIR}/system"
    fi
}


PATCH_SSRM() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_SSRM_DIRECTORY>"
        return 1
    fi

    local SSRM_DIR="$1"
    local FILE="$SSRM_DIR/smali/com/android/server/ssrm/Feature.smali"

    echo -e "Patching SSRM."
    echo -e "- Patching: $FILE"

    if [ ! -f "$FILE" ]; then
        echo -e "- File not found! Skipping..."
        return 1
    fi

    if grep -Eq 'const-string v[0-9]+, "siop_' "$FILE"; then
        echo -e "- Found siop_ → Replacing"
        sed -i 's/\(const-string v[0-9]\+,\s*"\)siop_[^"]*"/\1'"$STOCK_SIOP_POLICY_FILENAME"'"/g' "$FILE"
    else
        echo -e "- siop filename not found → Skipped"
    fi

    if grep -Eq 'const-string v[0-9]+, "dvfs_policy_[^"]*_[^"]*"' "$FILE"; then
        echo -e "- Found dvfs_policy_*_* → Replacing"

        sed -i '/dvfs_policy_default/! {
            s/\(const-string v[0-9]\+,\s*"\)dvfs_policy_[^"]*_[^"]*"/\1'"$STOCK_DVFS_FILENAME"'"/g
        }' "$FILE"

    else
        echo -e "- dvfs_policy file name not found → Skipped"
    fi
}


PATCH_BT_LIB() {
    echo " "

    if [ "$#" -ne 2 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIRECTORY> <WORK_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"
    local WORK_DIR="$2"
    local BT_LIB_FILE="$WORK_DIR/libbluetooth_jni.so"

    echo -e "Patching Bluetooth library."
    
    if ! ls "$EXTRACTED_FIRM_DIR"/system/system/apex/com.android.bt*.apex >/dev/null 2>&1; then
        echo -e "- No bluetooth apex file found."
        return 1
    fi

    7z e "${EXTRACTED_FIRM_DIR}/system/system/apex/com.android.bt"*.apex \
        "apex_payload.img" \
        -o"$WORK_DIR" -y >/dev/null

    debugfs -R "dump /lib64/libbluetooth_jni.so $WORK_DIR/libbluetooth_jni.so" \
        "$WORK_DIR/apex_payload.img" >/dev/null

    rm -rf "$WORK_DIR/apex_payload.img"

    declare -A hex=(
        [136]=00122a0140395f01086b00020054 [1136]=00122a0140395f01086bde030014
        [135]=480500352800805228 [1135]=530100142800805228
        [134]=6804003528008052 [1134]=2b00001428008052
        [133]=6804003528008052 [1133]=2a00001428008052
        [132]=........f9031f2af3031f2a41 [1132]=1f2003d5f9031f2af3031f2a48
        [131]=........f9031f2af3031f2a41 [1131]=1f2003d5f9031f2af3031f2a48
        [130]=........f3031f2af4031f2a3e [1130]=1f2003d5f3031f2af4031f2a3e
        [129]=........f4031f2af3031f2ae8030032 [1129]=1f2003d5f4031f2af3031f2af3031f2ae8031f2a
        [128]=88000034e8030032 [1128]=1f2003d5e8031f2a
        [127]=88000034e8030032 [1127]=1f2003d5e8031f2a
        [126]=88000034e8030032 [1126]=1f2003d5e8031f2a
        [234]=4e7e4448bb [1234]=4e7e4437e0
        [233]=4e7e4440bb [1233]=4e7e4432e0
        [231]=20b14ff000084ff000095ae0 [1231]=00bf4ff000084ff0000964e0
        [230]=18b14ff0000b00254a [1230]=00204ff0000b002554
        [229]=..b100250120 [1229]=00bf00250020
        [228]=..b101200028 [1228]=00bf00200028
        [227]=09b1012032e0 [1227]=00bf002032e0
        [226]=08b1012031e0 [1226]=00bf002031e0
        [225]=087850bbb548 [1225]=08785ae1b548
        [224]=007840bb6a48 [1224]=0078c4e06a48
        [330]=88000054691180522925c81a69000037 [1330]=1f2003d5691180522925c81a1f2003d5
        [329]=88000054691180522925c81a69000037 [1329]=1f2003d5691180522925c81a1f2003d5
        [328]=7f1d0071e91700f9e83c0054 [1328]=7f1d0071e91700f9e7010014
        [429]=....0034f3031f2af4031f2a....0014 [1429]=1f2003d5f3031f2af4031f2a47000014
        [531]=10b1002500244ce0 [1531]=00bf0025002456e0
        [530]=18b100244ff0000b4d [1530]=002000244ff0000b57
        [529]=44387810b1002400254a [1529]=44387800200024002556
        [629]=90387810b1002400254a [1629]=90387800200024002558
    )

    local PATCHED=0

    for idx in "${!hex[@]}"; do
        (( idx >= 1000 )) && continue

        local from="${hex[$idx]}"
        local to="${hex[$((idx + 1000))]}"
        [ -z "$to" ] && continue

        local from_regex="$(echo "$from" | sed -E 's/\.\./[0-9a-f]{2}/g')"

        if perl -e '
            $/ = undef;
            open(F, shift) or exit 1;
            $_ = <F>;
            my $hex = unpack("H*", $_);
            exit ($hex =~ /'"$from_regex"'/i ? 0 : 1);
        ' "$BT_LIB_FILE"; then
            echo -e "- Found Bluetooth patch pattern [$idx]"
            HEX_PATCH "$BT_LIB_FILE" "$from" "$to" || return 1
            PATCHED=1
            mv -f "$BT_LIB_FILE" "${EXTRACTED_FIRM_DIR}/system/system/lib64/"
            break
        fi
    done

    if [ "$PATCHED" -eq 0 ]; then
        echo -e "- No known Bluetooth patch pattern matched."
        rm -rf "$BT_LIB_FILE"
        return 1
    fi

    return 0
}


FIX_VNDK() {
    echo " "

    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIRECTORY>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"
    local TARGET_ROM_SYSTEM_EXT_DIR="$(GET_SYSTEM_EXT_DIR "$EXTRACTED_FIRM_DIR")"

    echo -e "Checking $STOCK_DEVICE and $TARGET_DEVICE vndk version."

    export SDK="$(GET_PROP "$EXTRACTED_FIRM_DIR" "system" ro.build.version.sdk_full)"
    echo "- Target rom SDK version: $SDK"

    if [ -f "${TARGET_ROM_SYSTEM_EXT_DIR}/apex/com.android.vndk.v${STOCK_VNDK_VERSION}.apex" ]; then
        echo -e "- VNDK matched. ${TARGET_ROM_SYSTEM_EXT_DIR}/apex/com.android.vndk.v${STOCK_VNDK_VERSION}.apex"
    else
        echo -e "- VNDK mismatch. Adding SDK $SDK com.android.vndk.v${STOCK_VNDK_VERSION}.apex"
        rm -rf "${TARGET_ROM_SYSTEM_EXT_DIR}/apex"
        7z x "$VNDKS_COLLECTION/$SDK/${STOCK_VNDK_VERSION}.zip" -o"${TARGET_ROM_SYSTEM_EXT_DIR}/" -y >/dev/null 2>&1
    fi
}


ADD_SYSTEM_EXT_IN_SYSTEM_ROOT() {
    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"

    echo -e "- Copying system_ext content into system root"
    rm -rf "${EXTRACTED_FIRM_DIR}/system/system_ext"
    mv "${EXTRACTED_FIRM_DIR}/system_ext" "${EXTRACTED_FIRM_DIR}/system"

    echo -e "- Cleaning and merging system_ext file contexts and configs"

    SYSTEM_EXT_CONFIG_FILE="${EXTRACTED_FIRM_DIR}/config/system_ext_fs_config"
    SYSTEM_EXT_CONTEXTS_FILE="${EXTRACTED_FIRM_DIR}/config/system_ext_file_contexts"
    SYSTEM_CONFIG_FILE="${EXTRACTED_FIRM_DIR}/config/system_fs_config"
    SYSTEM_CONTEXTS_FILE="${EXTRACTED_FIRM_DIR}/config/system_file_contexts"

    SYSTEM_EXT_TEMP_CONFIG="${SYSTEM_EXT_CONFIG_FILE}.tmp"
    SYSTEM_EXT_TEMP_CONTEXTS="${SYSTEM_EXT_CONTEXTS_FILE}.tmp"

    grep -v '^/ u:object_r:system_file:s0$' "$SYSTEM_EXT_CONTEXTS_FILE" \
    | grep -v '^/system_ext u:object_r:system_file:s0$' \
    | grep -v '^/system_ext(.*)? u:object_r:system_file:s0$' \
    | grep -v '^/system_ext/ u:object_r:system_file:s0$' \
    > "$SYSTEM_EXT_TEMP_CONTEXTS" && mv "$SYSTEM_EXT_TEMP_CONTEXTS" "$SYSTEM_EXT_CONTEXTS_FILE"

    grep -v '^/ 0 0 0755$' "$SYSTEM_EXT_CONFIG_FILE" \
    | grep -v '^system_ext/ 0 0 0755$' \
    > "$SYSTEM_EXT_TEMP_CONFIG" && mv "$SYSTEM_EXT_TEMP_CONFIG" "$SYSTEM_EXT_CONFIG_FILE"

    sed -i 's|^/system_ext/|system/system_ext/|g' "$SYSTEM_EXT_CONTEXTS_FILE"
    sed -i 's|^/system_ext$|system/system_ext|g' "$SYSTEM_EXT_CONTEXTS_FILE"
    sed -i 's|^system_ext/|system/system_ext/|g' "$SYSTEM_EXT_CONFIG_FILE"

    cat "$SYSTEM_EXT_CONTEXTS_FILE" >> "$SYSTEM_CONTEXTS_FILE"
    cat "$SYSTEM_EXT_CONFIG_FILE" >> "$SYSTEM_CONFIG_FILE"

    rm -rf "$SYSTEM_EXT_CONTEXTS_FILE" "$SYSTEM_EXT_CONFIG_FILE"
}


FLATTEN_SYSTEM() {
    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"
    local SYSTEM_ROOT="${EXTRACTED_FIRM_DIR}/system"

    if [ ! -d "$SYSTEM_ROOT" ]; then
        echo "- System directory not found."
        return 1
    fi

    echo "- Szukam najgłębszego 'system'..."
    
    local CURRENT="$SYSTEM_ROOT"
    while [ -d "$CURRENT/system" ] && [ ! -L "$CURRENT/system" ]; do
        CURRENT="$CURRENT/system"
    done

    if [ "$CURRENT" != "$SYSTEM_ROOT" ]; then
        echo "- Znaleziono zagnieżdżony system w: $CURRENT"
        echo "- Spłaszczanie..."
        
        ADD_SYSTEM_EXT_IN_SYSTEM_ROOT "$EXTRACTED_FIRM_DIR"
        FIX_SYSTEM_PATHS "$EXTRACTED_FIRM_DIR"

        cp -aR "$CURRENT"/. "$SYSTEM_ROOT/"
        rm -rf "$CURRENT"
        
        echo "- System partition flattened."
    else
        echo "- System partition już spłaszczony."
    fi
}


FIX_SYSTEM_PATHS() {
    if [ "$#" -ne 1 ]; then
        echo -e "Usage: ${FUNCNAME[0]} <EXTRACTED_FIRM_DIR>"
        return 1
    fi

    local EXTRACTED_FIRM_DIR="$1"
    local SYSTEM_CONFIG_FILE="${EXTRACTED_FIRM_DIR}/config/system_fs_config"
    local SYSTEM_CONTEXTS_FILE="${EXTRACTED_FIRM_DIR}/config/system_file_contexts"

    echo -e "- Adjusting file_contexts and fs_config paths for flattened system..."

    if [ -f "$SYSTEM_CONTEXTS_FILE" ]; then
        sed -i 's|^/system/|/|g' "$SYSTEM_CONTEXTS_FILE"
    fi

    if [ -f "$SYSTEM_CONFIG_FILE" ]; then
        sed -i 's|^system/||g' "$SYSTEM_CONFIG_FILE"
    fi
}
