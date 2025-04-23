#!/bin/bash

MOUNT_BASE="/mnt/disk"
VG_NAME="vg_combined"
LV_NAME="lv_combined"

echo " Available Disks (no partitions):"
DISKS=()

# List unpartitioned disks
for DISK in $(lsblk -dno NAME | grep -E 'sd|nvme|vd'); do
    if ! lsblk /dev/$DISK | grep -q part; then
        echo "[${#DISKS[@]}] /dev/$DISK"
        DISKS+=("/dev/$DISK")
    fi
done

if [ ${#DISKS[@]} -eq 0 ]; then
    echo " No unpartitioned disks found. Exiting."
    exit 1
fi

echo ""
read -p " Enter the indexes of disks to use (e.g., 0 1): " -a SELECTED_INDEXES

SELECTED_DISKS=()
for i in "${SELECTED_INDEXES[@]}"; do
    SELECTED_DISKS+=("${DISKS[$i]}")
done

echo ""
read -p "Do you want to combine these disks using LVM? [y/N]: " COMBINE

if [[ "$COMBINE" =~ ^[Yy]$ ]]; then
    echo "ombining disks using LVM..."
    for d in "${SELECTED_DISKS[@]}"; do
        echo " - Wiping $d"
        wipefs -a $d
        echo -e "g\nn\n\n\n\nw" | fdisk $d
        sleep 2
        PART="${d}1"
        wipefs -a $PART
        pvcreate $PART
        PARTITIONS+=("$PART")
    done

    vgcreate $VG_NAME "${PARTITIONS[@]}"
    lvcreate -l 100%FREE -n $LV_NAME $VG_NAME
    mkfs.ext4 /dev/$VG_NAME/$LV_NAME

    mkdir -p $MOUNT_BASE
    mount /dev/$VG_NAME/$LV_NAME $MOUNT_BASE

    UUID=$(blkid -s UUID -o value /dev/$VG_NAME/$LV_NAME)
    echo "UUID=$UUID $MOUNT_BASE ext4 defaults 0 0" >> /etc/fstab

    echo "Combined volume mounted at $MOUNT_BASE"

else
    echo "formatting and mounting disks individually..."
    i=1
    for d in "${SELECTED_DISKS[@]}"; do
        echo " - Wiping $d"
        wipefs -a $d
        echo -e "g\nn\n\n\n\nw" | fdisk $d
        sleep 2
        PART="${d}1"
        mkfs.ext4 $PART
        MOUNT_POINT="${MOUNT_BASE}${i}"
        mkdir -p $MOUNT_POINT
        mount $PART $MOUNT_POINT
        UUID=$(blkid -s UUID -o value $PART)
        echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 0" >> /etc/fstab
        echo "$PART mounted at $MOUNT_POINT"
        ((i++))
    done
fi

echo "Done!"