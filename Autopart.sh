#!/bin/bash

VG_NAME="vg_dynamic"
LV_NAME="lv_combined"
MOUNT_POINT="/mnt/combined"

list_disks() {
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -w disk | nl
}

get_disk_paths() {
    lsblk -d -o NAME,TYPE | grep -w disk | awk '{print "/dev/" $1}'
}

select_disks() {
    mapfile -t DISKS < <(get_disk_paths)

    echo "Enter the disk numbers to combine (e.g., 1 2 4):"
    read -rp "> " SELECTION

    SELECTED_DISKS=()
    for index in $SELECTION; do
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#DISKS[@]} )); then
            SELECTED_DISKS+=("${DISKS[$((index - 1))]}")
        else
            echo "❌ Invalid selection: $index"
            exit 1
        fi
    done
}

combine_disks() {
    echo "🧹 Wiping selected disks..."
    for disk in "${SELECTED_DISKS[@]}"; do
        umount "${disk}1" 2>/dev/null || true
        wipefs -a "$disk"
        sgdisk --zap-all "$disk"
    done

    echo "🧱 Creating physical volumes..."
    pvcreate "${SELECTED_DISKS[@]}"

    echo "🔗 Creating volume group '$VG_NAME'..."
    vgcreate "$VG_NAME" "${SELECTED_DISKS[@]}"

    echo "📦 Creating logical volume '$LV_NAME'..."
    lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME"

    echo "🧾 Formatting logical volume..."
    mkfs.ext4 "/dev/$VG_NAME/$LV_NAME"

    echo "📁 Mounting to $MOUNT_POINT..."
    mkdir -p "$MOUNT_POINT"
    mount "/dev/$VG_NAME/$LV_NAME" "$MOUNT_POINT"

    echo "/dev/$VG_NAME/$LV_NAME $MOUNT_POINT ext4 defaults 0 0" >> /etc/fstab

    echo "✅ LVM combined and mounted at $MOUNT_POINT"
}

separate_disks() {
    echo "⚠️ This will destroy the LVM volume and all data."

    read -rp "Type 'yes' to continue: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi

    umount "$MOUNT_POINT" 2>/dev/null || true
    sed -i "\|/dev/$VG_NAME/$LV_NAME|d" /etc/fstab

    lvremove -y "/dev/$VG_NAME/$LV_NAME"
    vgremove -y "$VG_NAME"

    PHYSICAL_DISKS=$(pvs --noheadings -o pv_name)

    for disk in $PHYSICAL_DISKS; do
        pvremove -y "$disk"
        wipefs -a "$disk"
        parted -s "$disk" mklabel gpt mkpart primary ext4 0% 100%
        mkfs.ext4 "${disk}1"
        echo "Disk $disk reset and formatted as ext4"
    done
}

# --- MAIN ---

case "$1" in
    combine)
        list_disks
        select_disks
        combine_disks
        ;;
    separate)
        separate_disks
        ;;
    *)
        echo "Usage: $0 {combine|separate}"
        ;;
esac
