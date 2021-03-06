#!/bin/bash
{

encryption_passphrase="passwd"
root_password="passwd"
user_password="passed"
hostname="noname"
user_name="ivan"
continent_city="Europe/Belgrade"
swap_size="4"

echo "Updating system clock"
timedatectl set-ntp true
timedatectl set-timezone $continent_city

echo "Creating partition tables"
printf "n\n1\n4096\n+512M\nef00\nw\ny\n" | gdisk /dev/sda
printf "n\n2\n\n\n8e00\nw\ny\n" | gdisk /dev/sda


echo "Setting up cryptographic volume"
printf "%s" "$encryption_passphrase" | cryptsetup -h sha512 -s 512 --use-random --type luks2 luksFormat /dev/sda2
printf "%s" "$encryption_passphrase" | cryptsetup luksOpen /dev/sda2 cryptlvm

echo "Creating physical volume"
pvcreate /dev/mapper/cryptlvm

echo "Creating volume volume"
vgcreate vg0 /dev/mapper/cryptlvm

echo "Creating logical volumes"
lvcreate -L +"$swap_size"GB vg0 -n swap
lvcreate -l +100%FREE vg0 -n root

echo "Setting up / partition"
yes | mkfs.ext4 /dev/vg0/root
mount /dev/vg0/root /mnt

echo "Setting up /boot partition"
yes | mkfs.fat -F32 /dev/sda1
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

echo "Setting up swap"
yes | mkswap /dev/vg0/swap
swapon /dev/vg0/swap


echo "Installing Arch Linux"
yes '' | pacstrap /mnt base base-devel linux linux-lts linux-firmware lvm2 device-mapper e2fsprogs cryptsetup wget man-db man-pages nano vi diffutils

echo "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "Configuring new system"
arch-chroot /mnt /bin/bash <<EOF
echo "Setting system clock"
ln -fs /usr/share/zoneinfo/$continent_city /etc/localtime
hwclock --systohc --localtime

echo "Setting locales"
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
locale-gen

echo "Adding persistent keymap"
echo "KEYMAP=us" > /etc/vconsole.conf

echo "Setting hostname"
echo $hostname > /etc/hostname

echo "Setting root password"
echo -en "$root_password\n$root_password" | passwd

echo "Creating new user"
useradd -m -G wheel -s /bin/bash $user_name
usermod -a -G video $user_name
echo -en "$user_password\n$user_password" | passwd $user_name

echo "Fix pacman: Signature is unknown trust"
rm -Rf /etc/pacman.d/gnupg
pacman-key --init
pacman-key --populate archlinux

echo "Install microcode for Intel processors"
pacman -Syy --noconfirm intel-ucode

echo "Generating initramfs"
sed -i 's/^HOOKS.*/HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt sd-lvm2 filesystems fsck)/' /etc/mkinitcpio.conf
sed -i 's/^MODULES.*/MODULES=(ext4 intel_agp i915)/' /etc/mkinitcpio.conf
mkinitcpio -p linux
mkinitcpio -p linux-lts

echo "Setting up systemd-boot"
bootctl --path=/boot install

mkdir -p /boot/loader/
touch /boot/loader/loader.conf
tee -a /boot/loader/loader.conf << END
default arch
timeout 1
editor 0
END

mkdir -p /boot/loader/entries/
touch /boot/loader/entries/arch.conf
tee -a /boot/loader/entries/arch.conf << END
title ArchLinux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options rd.luks.name=$(blkid -s UUID -o value /dev/sda2)=cryptlvm root=/dev/vg0/root resume=/dev/vg0/swap rd.luks.options=discard i915.fastboot=1 quiet rw
END

touch /boot/loader/entries/archlts.conf
tee -a /boot/loader/entries/archlts.conf << END
title ArchLinux
linux /vmlinuz-linux-lts
initrd /intel-ucode.img
initrd /initramfs-linux-lts.img
options rd.luks.name=$(blkid -s UUID -o value /dev/sda2)=cryptlvm root=/dev/vg0/root resume=/dev/vg0/swap rd.luks.options=discard i915.fastboot=1 quiet rw
END

echo "Setting up Pacman hook for automatic systemd-boot updates"
mkdir -p /etc/pacman.d/hooks/
touch /etc/pacman.d/hooks/systemd-boot.hook
tee -a /etc/pacman.d/hooks/systemd-boot.hook << END
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update
END


echo "Adding user as a sudoer"
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo
EOF

echo "Installing packages"
arch-chroot /mnt /bin/bash <<EOF
# Install header files and scripts for building modules for Linux kernel
pacman -S --noconfirm linux-headers linux-lts-headers

# Install important services
pacman -S --noconfirm acpid ntp cronie avahi nss-mdns dbus cups ufw tlp

# Configure the network
pacman -S --noconfirm dialog dhclient 
pacman -S --noconfirm networkmanager network-manager-applet
pacman -S --noconfirm gnome-keyring libsecret seahorse

# Install command line and ncurses programs
pacman -S --noconfirm sudo nano man-db man-pages texinfo
pacman -S --noconfirm bash-completion
pacman -S --noconfirm tree
pacman -S --noconfirm atool
pacman -S --noconfirm ranger w3m
pacman -S --noconfirm pulseaudio pulseaudio-alsa
pacman -S --noconfirm htop
pacman -S --noconfirm tmux
pacman -S --noconfirm youtube-dl
pacman -S --noconfirm wget curl axel
pacman -S --noconfirm rsync
pacman -S --noconfirm scrot
pacman -S --noconfirm xdotool
pacman -S --noconfirm xclip xsel
pacman -S --noconfirm lshw
pacman -S --noconfirm acpi
pacman -S --noconfirm nmap
pacman -S --noconfirm vim
pacman -S --noconfirm ffmpeg
pacman -S --noconfirm git
pacman -S --noconfirm feh
pacman -S --noconfirm openssh
pacman -S --noconfirm openvpn easy-rsa

# Install xorg and graphics
pacman -S --noconfirm xorg xorg-xinit libva-intel-driver mesa
pacman -S --noconfirm xf86-video-intel xf86-input-synaptics

# Install fonts
pacman -S --noconfirm ttf-droid ttf-ionicons ttf-dejavu noto-fonts

# Install desktop & window manager
pacman -S --noconfirm i3-gaps i3status i3lock dmenu compton

# Install GTK-Theme and Icons
pacman -S --noconfirm arc-gtk-theme hicolor-icon-theme papirus-icon-theme

# Creating user's folders"
pacman -S --noconfirm xdg-user-dirs

# Install graphical programs
pacman -S --noconfirm rxvt-unicode termite
pacman -S --noconfirm rxvt-unicode
pacman -S --noconfirm dunst
pacman -S --noconfirm ghex
pacman -S --noconfirm lxappearance
pacman -S --noconfirm pavucontrol
pacman -S --noconfirm gnome-system-monitor
pacman -S --noconfirm lxrandr
pacman -S --noconfirm firefox
pacman -S --noconfirm gnome-calculator
pacman -S --noconfirm libreoffice-fresh hunspell
pacman -S --noconfirm evince
pacman -S --noconfirm smplayer vlc
pacman -S --noconfirm jdk8-openjdk intellij-idea-community-edition
pacman -S --noconfirm gimp
pacman -S --noconfirm gparted dosfstools ntfs-3g mtools
pacman -S --noconfirm pcmanfm-gtk3 gvfs udisks2 libmtp mtpfs gvfs-mtp
pacman -S --noconfirm file-roller unrar p7zip lrzip
pacman -S --noconfirm gutenprint ghostscript gsfonts
pacman -S --noconfirm system-config-printer gtk3-print-backends simple-scan
pacman -S --noconfirm gpicview
pacman -S --noconfirm transmission-gtk
pacman -S --noconfirm qemu
pacman -S --noconfirm code 
# pacman -S --noconfirm docker
# pacman -S --noconfirm virtualbox virtualbox-host-modules-arch virtualbox-guest-iso

EOF

echo "Enable important services"
arch-chroot /mnt /bin/bash <<EOF

# Enable important services
systemctl enable acpid
systemctl enable ntpd
systemctl enable cronie
systemctl enable avahi-daemon
systemctl enable fstrim.timer
systemctl enable NetworkManager

# Enable TLP
systemctl enable tlp.service
systemctl enable tlp-sleep.service
systemctl mask systemd-rfkill.service
systemctl mask systemd-rfkill.socket

# Enable UFW
systemctl enable ufw
#ufw default deny
#ufw enable
EOF

echo "Copy the setup folder to the new system"
DIR="$(dirname ${BASH_SOURCE[0]})"
cp -R $DIR /mnt/arch-setup 

echo "Copy configuration"
arch-chroot /mnt /bin/bash <<EOF

# Copy all home folder files
cp -R /arch-setup/sysconfig/home/. /home/$user_name/
cp -R /arch-setup/sysconfig/home/. /root/

# Change premissions
chown -R $user_name:$user_name /home/$user_name/
chmod -R 700 /home/$user_name/.bin/
EOF

# Pipe all output into log file
} |& tee -a /root/Arch-Installation.log
mv /root/Arch-Installation.log /mnt/home/$(ls /mnt/home/)/


umount -R /mnt
swapoff -a

echo "ArchLinux is ready. You can reboot now!"