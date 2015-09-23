#!/usr/bin/bash
#
# 2015-07-17 zfsbuild.sh by severach for AUR 4
# 2015-08-08 AUR4 -> AUR, added git pull, safer AUR 3.5 update folder
# Adapted from ZFS Builder by graysky
# place this in a user home folder.
# I recommend ~/build/zfspkg/. Do not name the folder 'zfs'.

# 1 to add conflicts=(linux>,linux<) which offers automatic removal on upgrade.
# Manual removal with zfsun.sh is preferred.
_opt_AutoRemove=0
_opt_ZFSPool='sdmdata'
_opt_ZFSbyid='/dev/disk/by-partlabel'
#_opt_ZFSbyid='/dev/disk/by-id'
# '' for manual answer to prompts. --noconfirm to go ahead and do it all.
_opt_AutoInstall='--noconfirm'
_opt_Downgrade=0 # default=0, 1 to be admonished and downgrade to your current kernel (uname -r)

# Multiprocessor compile enabled!
# Huuuuuuge performance improvement. Watch in htop.
# An E3-1245 can peg all 8 processors.
#1  [|||||||||||||||||||||||||96.2%]
#2  [|||||||||||||||||||||||||97.6%]
#3  [|||||||||||||||||||||||||95.7%]
#4  [|||||||||||||||||||||||||96.7%]
#5  [|||||||||||||||||||||||||95.7%]
#6  [|||||||||||||||||||||||||97.1%]
#7  [|||||||||||||||||||||||||98.6%]
#8  [|||||||||||||||||||||||||96.2%]
#Mem[|||                596/31974MB]
#Swp[                         0/0MB]

set -u
set -e

if [ "${_opt_Downgrade}" -ne 0 ]; then
  echo "Warning: You are downgrading zfs which is unsupported"
  sleep 5
  _opt_DownGradeVer="$(uname -r)"        # uname: Version 0.0.0-0
  _opt_DownGradeVer="${_opt_DownGradeVer%-ARCH}" # These disagree when the version isn't 3 numbers like 4.0
  _opt_DownGradePkg="$(pacman -Q linux)" # pacman: Version 0.0-0
  _opt_DownGradePkg="${_opt_DownGradePkg#* }"
  _opt_DownGradePkg="${_opt_DownGradePkg%-ARCH}"
fi

if [ "${EUID}" -eq 0 ]; then
  echo "This script must NOT be run as root"
  sleep 1
  exit 1
fi

for i in 'sudo' 'git'; do
  command -v "${i}" >/dev/null 2>&1 || {
  echo "I require ${i} but it's not installed. Aborting." 1>&2
  exit 1; }
done

cd "$(dirname "$0")"
OPWD="$(pwd)"
for cwpackage in 'spl-utils-git' 'spl-git' 'zfs-utils-git' 'zfs-git'; do
  #cower -dc -f "${cwpackage}"
  if [ -d "${cwpackage}" -a ! -d "${cwpackage}/.git" ]; then
    echo "${cwpackage}: Convert AUR3.5 to AUR4"
    cd "${cwpackage}"
    git clone "https://aur.archlinux.org/${cwpackage}.git/" "${cwpackage}.temp"
    cd "${cwpackage}.temp"
    mv '.git' ..
    cd ..
    rm -rf "${cwpackage}.temp"
    cd ..
  fi
  if [ -d "${cwpackage}" ]; then
    echo "${cwpackage}: Update local copy"
    cd "${cwpackage}"
    git fetch
    git reset --hard 'origin/master'
    git pull # this line was missed in previous versions
  else
    echo "${cwpackage}: Clone to new folder"
    git clone "https://aur.archlinux.org/${cwpackage}.git/"
    cd "${cwpackage}"
  fi
  sed -i -e 's:^\s\+make$:'"& -s -j $(nproc):g" 'PKGBUILD'
  if [ "${_opt_AutoRemove}" -ne 0 ]; then
    sed -i -e 's:^conflicts=(.*$: &\n_kernelversionsmall="`uname -r | cut -d - -f 1`"\nconflicts+=("linux>${_kernelversionsmall}" "linux<${_kernelversionsmall}")\n:g' 'PKGBUILD'
  fi
  if [ "${_opt_Downgrade}" -ne 0 ]; then
    sed -i -e 's:\(_kernel_version_x[0-9]\+_full="\)\(.\+\)\(".*\)$'":\1${_opt_DownGradeVer}\3:g" \
           -e 's:\(_kernel_version_x[0-9]\+="\)\(.\+\)\(".*\)$'":\1${_opt_DownGradePkg}\3:g" 'PKGBUILD' *.install || :
  fi
  # Only found in help files
  if ! makepkg -sCcfi ${_opt_AutoInstall}; then
    cd "${OPWD}"
    break
  fi
  #rm -rf 'zfs' 'spl'
  cd "${OPWD}"
done
which fsck.zfs
if [ "$?" -eq 0 ]; then
  sudo mkinitcpio -p 'linux' # Stores fsck.zfs into the initrd image. I don't know why it would be needed.
fi
#sudo zpool import "${_opt_ZFSPool}" # Don't do this or zpool will mount via /dev/sd?, which you won't like!
set -x
sudo zpool import -d "${_opt_ZFSbyid}" "${_opt_ZFSPool}" # This loads all the modules
set +x
sudo zpool status
sudo -k
sleep 2
