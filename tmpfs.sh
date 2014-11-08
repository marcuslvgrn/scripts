#!/bin/sh
rsync -av --exclude proc --exclude dev --exclude sys --exclude /mnt/data --exclude /mnt/temp / /mnt/temp
mkdir /mnt/temp/proc
mkdir /mnt/temp/dev
mkdir /mnt/temp/sys
mkdir /mnt/temp/mnt/data
mount --bind /proc /mnt/temp/proc
mount --bind /dev /mnt/temp/dev
mount --bind /sys /mnt/temp/sys
