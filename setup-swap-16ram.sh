#!/bin/bash
set -euo pipefail

DEV=/dev/nvme0n1p3
UUID=$(blkid -s UUID -o value "$DEV")

# 1. Subvolume @swap no top-level (fora dos snapshots do snapper)
mkdir -p /mnt/btrfs-top
mount -o subvolid=5 "$DEV" /mnt/btrfs-top
[ -d /mnt/btrfs-top/@swap ] || btrfs subvolume create /mnt/btrfs-top/@swap
umount /mnt/btrfs-top
rmdir /mnt/btrfs-top

# 2. Montar em /swap
mkdir -p /swap
grep -q 'subvol=@swap' /etc/fstab || \
  echo "UUID=$UUID /swap btrfs subvol=@swap,noatime 0 0" >> /etc/fstab
systemctl daemon-reload
mountpoint -q /swap || mount /swap

# 3. Swapfile de 32G
[ -f /swap/swapfile ] || btrfs filesystem mkswapfile --size 32g --uuid clear /swap/swapfile
swapon --show=NAME --noheadings | grep -q /swap/swapfile || swapon --priority 10 /swap/swapfile
grep -q '^/swap/swapfile' /etc/fstab || \
  echo '/swap/swapfile none swap defaults,pri=10,nofail 0 0' >> /etc/fstab

# 4. zram = tamanho da RAM (vale no próximo boot)
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF

echo "=== Verificação ==="
btrfs subvolume list / | grep -E '@swap|@home|path @$' || true
snapper -c root get-config | grep SUBVOLUME
findmnt /swap
swapon --show