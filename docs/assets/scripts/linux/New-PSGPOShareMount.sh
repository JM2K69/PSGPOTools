#!/usr/bin/env bash
# Mounts a share of HGPM on a Linux console of Tier 0: the central backups of the GPOs, which HGPM
# reads and writes as a folder. Kerberos, multiuser: each account of the computer reaches the share
# with its own ticket (kinit), the server checks its rights; HGPM finds the mount in /proc/mounts
# from Backup.Path (\\server\gpo-backups).
#
#   sudo ./New-PSGPOShareMount.sh //files.contoso.com/gpo-backups                 # /mnt/gpo-backups
#   sudo ./New-PSGPOShareMount.sh //files.contoso.com/gpo-backups /mnt/gpo-backups --fstab
#
# --fstab also adds it to /etc/fstab with x-systemd.automount: from then on it mounts itself when a
# console of Tier 0 first reaches it, after a restart too (HGPM finds it in /etc/fstab). Needs
# cifs-utils and keyutils
# (Debian/Ubuntu: apt install cifs-utils keyutils; RHEL/Fedora: dnf install cifs-utils keyutils),
# and the Kerberos ticket of the account that runs sudo (kinit), to mount.
#
# https://jm2k69.github.io/PSGPOTools/en/features/backup-history/
set -euo pipefail

source="${1:?Usage: sudo $0 //server/share [mount point] [--fstab]}"
target="${2:-/mnt/$(basename "$source")}"
fstab="${3:-}"
if [ "$target" = "--fstab" ]; then target="/mnt/$(basename "$source")"; fstab="--fstab"; fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Run it as root: sudo $0 $*" >&2
    exit 1
fi
if ! command -v mount.cifs > /dev/null; then
    echo "mount.cifs is missing: apt install cifs-utils keyutils (or dnf install cifs-utils keyutils)." >&2
    exit 1
fi

# The ticket of the account that runs sudo mounts the share; then each account uses its own.
owner="${SUDO_UID:-0}"
options="sec=krb5,multiuser,cruid=$owner,noperm,_netdev,nofail"

mkdir -p "$target"
if mountpoint -q "$target"; then
    echo "$target is already mounted: kept."
else
    mount -t cifs "$source" "$target" -o "$options"
    echo "$source mounted on $target."
fi

if [ "$fstab" = "--fstab" ]; then
    if grep -q "^$source[[:space:]]" /etc/fstab; then
        echo "$source is already in /etc/fstab: kept."
    else
        cp /etc/fstab "/etc/fstab.$(date +%Y%m%d-%H%M%S).bak"
        # Mounted when it is first reached, unmounted after 10 minutes without use.
        echo "$source $target cifs $options,x-systemd.automount,x-systemd.idle-timeout=600 0 0" >> /etc/fstab
        systemctl daemon-reload
        echo "$source added to /etc/fstab: it mounts itself when it is reached."
    fi
fi
