#!/usr/bin/bash

# 2015-07-17 zfs uninstaller by severach for AUR4
# 2016-05-15 Updated for new AUR packages
# Removing ZFS forgets to unmount the pools, which might be desirable if you're
# running ZFS on the root file system.

_opt_ZFSFolder='/home/sdmdata/med6'
_opt_ZFSPool='sdmdata'

if [ "${EUID}" -ne 0 ]; then
  echo 'Must be root, try sudo !!'
  sleep 1
  exit 1
fi

systemctl daemon-reload
systemctl stop 'smbd.service' # Active shares can lock the mount. You might want to stop nfs too.
zpool export "${_opt_ZFSPool}" # zpool import no longer works with drives that were zfs umount
if [ ! -d "${_opt_ZFSFolder}" ]; then
  echo "${_opt_ZFSPool} exported"
  rmmod 'zfs' 'zavl' 'zunicode' 'zpios' 'zcommon' 'znvpair' 'spl' 'splat'
  pacman -Rc 'spl-utils-git' # This works even if some are already removed.
  pacman -Rc 'spl-utils-linux-git' # This works even if some are already removed.
  #pacman -R 'zfs-utils-git' 'spl-git' 'spl-utils-git' 'zfs-git'
else
  echo "ZFS didn't unmount"
fi
systemctl start 'smbd.service'
