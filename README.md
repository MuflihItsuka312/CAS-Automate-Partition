# CAS-Automate-Partition

### 🧩 Step-by-Step to Free and Format /dev/vda
1. ✅ Unmount the LVM volume
bash
Copy
Edit
sudo umount /mnt/disk
2. ✅ Deactivate the logical volume
bash
Copy
Edit
sudo lvchange -an /dev/vg_combined/lv_combined
3. ✅ Remove the volume group (if you want to delete it completely)
bash
Copy
Edit
sudo vgremove vg_combined
4. ✅ Remove physical volumes (including /dev/vda1 and /dev/vdb1)
bash
Copy
Edit
sudo pvremove /dev/vda1
sudo pvremove /dev/vdb1
5. ✅ Now format /dev/vda (you may need to wipe partition first)
If /dev/vda1 still exists:

bash
Copy
Edit
sudo wipefs -a /dev/vda1
Then delete it:

bash
Copy
Edit
sudo parted /dev/vda
(parted) rm 1
(parted) quit
Then:

bash
Copy
Edit
sudo mkfs.ext4 -F /dev/vda
Or repartition first if needed:

bash
Copy
Edit
sudo fdisk /dev/vda
