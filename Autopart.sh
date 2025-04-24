#!/bin/bash

set -euo pipefail

MOUNT_BASE="/mnt/disk"
VG_NAME="vg_combined"
LV_NAME="lv_combined"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

echo "Available Disks:"
DISKS=()
for DISK in $(lsblk -dno NAME | grep -E 'sd|nvme|vd'); do
    echo "[${#DISKS[@]}] /dev/$DISK"
    DISKS+=("/dev/$DISK")
done

if [ ${#DISKS[@]} -eq 0 ]; then
    echo "No disks found. Exiting."
    exit 1
fi

echo ""
read -p "Enter the indexes of disks to use (e.g., 0 1): " -a SELECTED_INDEXES

# Validate indexes
for i in "${SELECTED_INDEXES[@]}"; do
    if ! [[ "$i" =~ ^[0-9]+$ ]] || [ "$i" -ge "${#DISKS[@]}" ]; then
        echo "Invalid index: $i"
        exit 1
    fi
done

SELECTED_DISKS=()
for i in "${SELECTED_INDEXES[@]}"; do
    SELECTED_DISKS+=("${DISKS[$i]}")
done

echo ""
echo "Choose an operation:"
echo "1) Combine existing partitions on selected disks using LVM"
echo "2) Delete all partitions on selected disks, repartition, and format"
read -p "Enter choice [1/2]: " CHOICE

if [[ "$CHOICE" == "1" ]]; then
    echo "Combining existing partitions using LVM..."
    PARTITIONS=()
    for d in "${SELECTED_DISKS[@]}"; do
        # Find all partitions (e.g., /dev/sda1, /dev/sda2, /dev/nvme0n1p1, etc.)
        for part in $(lsblk -ln -o NAME "/dev/$(basename $d)" | grep -v "^$(basename $d)$"); do
            PART="/dev/$part"
            echo "  Adding $PART to LVM"
            pvcreate -y $PART
            PARTITIONS+=("$PART")
        done
    done
    if [ ${#PARTITIONS[@]} -eq 0 ]; then
        echo "No partitions found on selected disks!"
        exit 1
    fi
    vgcreate $VG_NAME "${PARTITIONS[@]}"
    lvcreate -l 100%FREE -n $LV_NAME $VG_NAME
    mkfs.ext4 /dev/$VG_NAME/$LV_NAME

    mkdir -p $MOUNT_BASE
    mount /dev/$VG_NAME/$LV_NAME $MOUNT_BASE

    UUID=$(blkid -s UUID -o value /dev/$VG_NAME/$LV_NAME)
    if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID $MOUNT_BASE ext4 defaults 0 0" >> /etc/fstab
    fi
    echo "Combined volume mounted at $MOUNT_BASE"

elif [[ "$CHOICE" == "2" ]]; then
    echo "WARNING: This will delete ALL partitions on the selected disks!"
    read -p "Are you sure you want to continue? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    read -p "Do you want to combine the new partitions using LVM? [y/N]: " COMBINE
    if [[ "$COMBINE" =~ ^[Yy]$ ]]; then
        echo "Repartitioning and combining disks using LVM..."
        PARTITIONS=()
        for d in "${SELECTED_DISKS[@]}"; do
            echo "  Wiping $d"
            wipefs -a $d &>/dev/null
            sgdisk --zap-all $d &>/dev/null
            sgdisk -o $d &>/dev/null
            sgdisk -n 1:0:0 $d &>/dev/null
            sleep 2
            if [[ $d =~ nvme ]]; then
                PART="${d}p1"
            else
                PART="${d}1"
            fi
            wipefs -a $PART &>/dev/null
            pvcreate -y $PART
            PARTITIONS+=("$PART")
        done
        vgcreate $VG_NAME "${PARTITIONS[@]}"
        lvcreate -l 100%FREE -n $LV_NAME $VG_NAME
        mkfs.ext4 /dev/$VG_NAME/$LV_NAME

        mkdir -p $MOUNT_BASE
        mount /dev/$VG_NAME/$LV_NAME $MOUNT_BASE

        UUID=$(blkid -s UUID -o value /dev/$VG_NAME/$LV_NAME)
        if ! grep -q "$UUID" /etc/fstab; then
            echo "UUID=$UUID $MOUNT_BASE ext4 defaults 0 0" >> /etc/fstab
        fi
        echo "Combined volume mounted at $MOUNT_BASE"
    else
        echo "Repartitioning and formatting disks individually..."
        i=1
        for d in "${SELECTED_DISKS[@]}"; do
            echo "  Wiping $d"
            wipefs -a $d &>/dev/null
            sgdisk --zap-all $d &>/dev/null
            sgdisk -o $d &>/dev/null
            sgdisk -n 1:0:0 $d &>/dev/null
            sleep 2
            if [[ $d =~ nvme ]]; then
                PART="${d}p1"
            else
                PART="${d}1"
            fi
            mkfs.ext4 -q $PART
            MOUNT_POINT="${MOUNT_BASE}${i}"
            mkdir -p $MOUNT_POINT
            mount $PART $MOUNT_POINT
            UUID=$(blkid -s UUID -o value $PART)
            if ! grep -q "$UUID" /etc/fstab; then
                echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 0" >> /etc/fstab
            fi
            echo "$PART mounted at $MOUNT_POINT"
            ((i++))
        done
    fi
else
    echo "Invalid choice."
    exit 1
fi

echo "Done!"
