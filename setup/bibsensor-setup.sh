#!/bin/bash

# BiB Raspberry Pi sensor setup script
#
# This is intended for use on a system installed with a Raspbian 'OS Lite'
# image, where the version of Raspbian is 'Bullseye':
#
#   https://www.raspberrypi.org/software/operating-systems/
#
# On first boot / before running this script, the following is expected:
#
# * Create user with username `sensorpi` and set password
# * Log in with as `sensorpi` user
# * Use `sudo -i` to switch to `root` user
# * Set root password with `passwd`
# * Enable ssh:
#     `systemctl enable ssh`
# * May as well force a file system check on next boot:
#     `touch /forcefsck`
# * Then `reboot` the system
# * After reboot, run this script as the `root` user

# Additional post set up steps:
#
# * For SharePoint uploads, the file `/home/sensorpi/.bib-data-archive` should
#   be created, containing details for the SharePoint connection
# * The file `/root/.bib-update` should be created, containing a string which
#   could be used as a passphrase or similar if required
# * `root` and sensorpi` SSH keys should be retrieved and stored

# This script is expected to be located with the associated files in the
# directory `/opt/bibsensor`, with this file being at:
#   `/opt/bibsensor/setup/bibsensor-setup.sh`

# Directory containing this script:
SCRIPT_DIR=$(readlink -f $(dirname ${0}))

# Update all packages on the system:
apt-get -y update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove
apt purge -y $(dpkg -l | awk '/^rc/ { print $2 }')

# Set up / enable the chrony time service:
apt-get -y install chrony
systemctl enable chrony

# Chrony / time server config:
if [ ! -e "/etc/chrony/chrony.conf.install" ] ; then
  \cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.install
  \cp ${SCRIPT_DIR}/setup_files/chrony.conf \
    /etc/chrony/chrony.conf
fi

# Install some possibly useful packages:
apt-get -y install chkconfig vim-nox git screen python3-venv lsof minicom unclutter

# Install some bits which may be needed for sensor code:
apt-get -y install i2c-tools libopenjp2-7 libopenjp2-7-dev libopenjp2-tools \
                   python3-dev python3-rpi.gpio python3-serial python3-smbus \
                   python3-arrow python3-numpy python3-spidev

# Set up vimrc.local file:
if [ ! -e "/etc/vim/vimrc.local" ] ; then
  cp ${SCRIPT_DIR}/setup_files/vimrc.local \
    /etc/vim/vimrc.local
fi

# Set up vimrc for root and sensorpi users:
if [ ! -e "/root/.vimrc" ] ; then
  cp ${SCRIPT_DIR}/setup_files/vimrc \
    /root/.vimrc
fi
if [ ! -e "/home/sensorpi/.vimrc" ] ; then
  cp ${SCRIPT_DIR}/setup_files/vimrc \
    /home/sensorpi/.vimrc
  chown sensorpi:sensorpi /home/sensorpi/.vimrc
fi

# Disable control characters in inputrc:
if [ ! -e "/etc/inputrc.install" ] ; then
  cp /etc/inputrc /etc/inputrc.install
  cat >> /etc/inputrc <<EOF

# Do not print control characters:
set echo-control-characters off
EOF
fi

# Set up bashrc for root and sensorpi users:
if [ ! -e "/root/.bashrc.install" ] ; then
  cp /root/.bashrc /root/.bashrc.install
  \cp ${SCRIPT_DIR}/setup_files/bashrc.root \
    /root/.bashrc
fi
if [ ! -e "/home/sensorpi/.bashrc.install" ] ; then
  cp /home/sensorpi/.bashrc /home/sensorpi/.bashrc.install
  \cp ${SCRIPT_DIR}/setup_files/bashrc.sensorpi \
    /home/sensorpi/.bashrc
  chown sensorpi:sensorpi /home/sensorpi/.bashrc*
fi

# Set up wifi region:
if [ ! -e "/etc/wpa_supplicant/wpa_supplicant.conf.install" ] ; then
  cp /etc/wpa_supplicant/wpa_supplicant.conf \
    /etc/wpa_supplicant/wpa_supplicant.conf.install
  \cp ${SCRIPT_DIR}/setup_files/wpa_supplicant.conf \
    /etc/wpa_supplicant/wpa_supplicant.conf
  chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
  wpa_cli -i "wlan0" set country "GB"
  wpa_cli -i "wlan0" save_config
  rfkill unblock wifi
  for filename in /var/lib/systemd/rfkill/*:wlan ; do
    echo 0 > $filename
  done
fi

# Directories required for bib sensor services:
mkdir -p /etc/bibsensor

# Enable clock setting service:
\rm -f /etc/systemd/system/bib-set-clock.service
\ln -s /opt/bibsensor/etc/systemd/system/bib-set-clock.service \
  /etc/systemd/system/bib-set-clock.service
systemctl daemon-reload
systemctl enable bib-set-clock

# Make sure fake hwclock service is disabled:
systemctl disable fake-hwclock

# Enable hostname setting service:
\rm -f /etc/systemd/system/bib-set-hostname.service
\ln -s /opt/bibsensor/etc/systemd/system/bib-set-hostname.service \
  /etc/systemd/system/bib-set-hostname.service
systemctl daemon-reload
systemctl enable bib-set-hostname

# Enable status LED service:
if [ ! -e "/etc/bibsensor/bibsensor.conf" ] ; then
  ln -s /opt/bibsensor/etc/bibsensor/bibsensor.conf \
    /etc/bibsensor/bibsensor.conf
fi
\rm -f /etc/systemd/system/bib-status-led.service
\ln -s /opt/bibsensor/etc/systemd/system/bib-status-led.service \
  /etc/systemd/system/bib-status-led.service
systemctl daemon-reload
systemctl enable bib-status-led

# Enable a fallback static address for eth0 and disable dhcpcd control of usb0:
if [ ! -e "/etc/dhcpcd.conf.install" ] ; then
  cp /etc/dhcpcd.conf /etc/dhcpcd.conf.install
  cat >> /etc/dhcpcd.conf <<EOF

profile static_eth0
static ip_address=10.3.141.2/24

interface eth0
fallback static_eth0

denyinterfaces usb0
EOF
fi

# Set up interface configuration for usb0:
if [ ! -e "/etc/network/interfaces.d/usb0" ] ; then
  \cp ${SCRIPT_DIR}/setup_files/usb0 \
    /etc/network/interfaces.d/usb0
fi

# Install and enable up dnsmaq:
apt-get -y install dnsmasq
systemctl enable dnsmasq
if [ ! -e "/etc/dnsmasq.d/010_bibsensor.conf" ] ; then
  cp ${SCRIPT_DIR}/setup_files/010_bibsensor.conf \
    /etc/dnsmasq.d/010_bibsensor.conf
fi
if [ ! -e "/etc/dnsmasq.d/050_bibsensor.conf" ] ; then
  cp ${SCRIPT_DIR}/setup_files/050_bibsensor.conf \
    /etc/dnsmasq.d/050_bibsensor.conf
fi

# Install and disable hostapd:
apt-get -y install hostapd
systemctl stop hostapd
systemctl unmask hostapd
systemctl disable hostapd
chkconfig hostapd off

# Install flask:
apt-get -y install python3-flask

# Set up AP services:
if [ ! -e "/etc/bibsensor/bibsensor.conf" ] ; then
  ln -s /opt/bibsensor/etc/bibsensor/bibsensor.conf \
    /etc/bibsensor/bibsensor.conf
fi
\rm -f /etc/systemd/system/bib-ap.service
\ln -s /opt/bibsensor/etc/systemd/system/bib-ap.service \
  /etc/systemd/system/bib-ap.service
\rm -f /etc/systemd/system/bib-ap-web.service
\ln -s /opt/bibsensor/etc/systemd/system/bib-ap-web.service \
  /etc/systemd/system/bib-ap-web.service
systemctl daemon-reload
systemctl enable bib-ap

# Install and enable gpsd service:
apt-get -y install gpsd gpsd-clients
if [ ! -e "/etc/default/gpsd.install" ] ; then
  mv /etc/default/gpsd \
    /etc/default/gpsd.install
  \cp ${SCRIPT_DIR}/setup_files/gpsd \
    /etc/default/gpsd
fi
systemctl enable gpsd

# Set up python virtual environment for sensor logging:
VENV_DIR='/opt/bibsensor/venvs/bib-sensor'
if [ ! -e "${VENV_DIR}" ] ; then
  python3 -m venv ${VENV_DIR}
  . ${VENV_DIR}/bin/activate
  pip install -U pip
  pip install spidev pyserial py-opc-ng sensirion-sps030 gpsd-py3 RPi.GPIO Adafruit-DHT
  deactivate
fi

# Create data directory for bib-sensor service:
mkdir -p /data/bib-sensor
chown sensorpi:sensorpi /data/bib-sensor
# Create link in sensorpi home directory:
if [ ! -e /home/sensorpi/data ] ; then
  ln -s /data/bib-sensor \
    /home/sensorpi/data
fi

# Set up sensor logging services:
if [ ! -e "/etc/bibsensor/bibsensor.conf" ] ; then
  ln -s /opt/bibsensor/etc/bibsensor/bibsensor.conf \
    /etc/bibsensor/bibsensor.conf
fi
\rm -f /etc/systemd/system/bib-sensor.service
\ln -s /opt/bibsensor/etc/systemd/system/bib-sensor.service \
  /etc/systemd/system/bib-sensor.service
systemctl daemon-reload
systemctl enable bib-sensor

# Set up python virtual environment for sensor data archiving:
VENV_DIR='/opt/bibsensor/venvs/bib-data-archive'
if [ ! -e "${VENV_DIR}" ] ; then
  python3 -m venv ${VENV_DIR}
  . ${VENV_DIR}/bin/activate
  pip install -U pip
  pip install 'cryptography<40' Office365-REST-Python-Client
  deactivate
fi

# Create data directory for bib-data-archive service:
mkdir -p /data/archive/bib-sensor
chown sensorpi:sensorpi /data/archive/bib-sensor
# Create link in sensorpi home directory:
if [ ! -e /home/sensorpi/archive ] ; then
  ln -s /data/archive/bib-sensor \
    /home/sensorpi/archive
fi

# Set up sensor logging services:
if [ ! -e "/etc/bibsensor/bibsensor.conf" ] ; then
  ln -s /opt/bibsensor/etc/bibsensor/bibsensor.conf \
    /etc/bibsensor/bibsensor.conf
fi
\rm -f /etc/systemd/system/bib-data-archive.service
\ln -s /opt/bibsensor/etc/systemd/system/bib-data-archive.service \
  /etc/systemd/system/bib-data-archive.service
systemctl daemon-reload
systemctl enable bib-data-archive
# Add cron job to periodically restart service:
\cp /opt/bibsensor/etc/cron.d/bib-data-archive \
  /etc/cron.d/
chown root:root /etc/cron.d/bib-data-archive

# Set up update services:
if [ ! -e "/etc/bibsensor/bibsensor.conf" ] ; then
  ln -s /opt/bibsensor/etc/bibsensor/bibsensor.conf \
    /etc/bibsensor/bibsensor.conf
fi
\rm -f /etc/systemd/system/bib-update.service
\ln -s /opt/bibsensor/etc/systemd/system/bib-update.service \
  /etc/systemd/system/bib-update.service
systemctl daemon-reload
systemctl enable bib-update

# Add sensorpi user to tty group:
groups sensorpi | grep -q ' tty ' >& /dev/null
if [ "${?}" != "0" ] ; then
  usermod -a -G tty sensorpi
fi

# Disable some services:
for service in avahi-daemon bluetooth dbus-org.bluez dbus-org.freedesktop.Avahi \
               hciuart rsync triggerhappy nfs-client.target plymouth
do
  systemctl disable ${service}
done
for service in avahi-daemon bluetooth plymouth rsync triggerhappy
do
  chkconfig ${service} off
done

# Set default hostname:
if [ ! -e "/etc/hosts.install" ] ; then
  cp /etc/hosts /etc/hosts.install
  sed -i 's|raspberrypi|bibsensor-00|g' /etc/hosts
fi
if [ ! -e "/etc/hostname.install" ] ; then
  cp /etc/hostname /etc/hostname.install
  sed -i 's|raspberrypi|bibsensor-00|g' /etc/hostname
fi

# Update /boot/config.txt:
if [ ! -e "/boot/config.txt.install" ] ; then
  cp /boot/config.txt /boot/config.txt.install
  \cp ${SCRIPT_DIR}/setup_files/config.txt \
    /boot/config.txt
fi

# Update /boot/cmdline.txt:
if [ ! -e "/boot/cmdline.txt.install" ] ; then
  cp /boot/cmdline.txt /boot/cmdline.txt.install
  sed -i 's|console=serial[^\ ]\+\ ||g' \
    /boot/cmdline.txt
  sed -i 's|$| fsck.mode=force|g' \
    /boot/cmdline.txt
fi

# Update modules file:
if [ ! -e "/etc/modules.install" ] ; then
  cp /etc/modules /etc/modules.install
  \cp ${SCRIPT_DIR}/setup_files/modules \
    /etc/modules
fi

# Create SSH key for sensorpi user:
if [ ! -e "/home/sensorpi/.ssh/authorized_keys" ] ; then
  mkdir -p /home/sensorpi/.ssh
  ssh-keygen -t rsa -b 4096 -N '' -f /home/sensorpi/.ssh/id_rsa -C 'sensorpi@bibsensor'
  cat /home/sensorpi/.ssh/id_rsa.pub > /home/sensorpi/.ssh/authorized_keys
  chmod 700 /home/sensorpi/.ssh
  chmod 600 /home/sensorpi/.ssh/*
  chown -R sensorpi:sensorpi /home/sensorpi/.ssh
fi

# Create SSH key for root user:
if [ ! -e "/root/.ssh/authorized_keys" ] ; then
  mkdir -p /root/.ssh
  ssh-keygen -t rsa -b 4096 -N '' -f /root/.ssh/id_rsa -C 'root@bibsensor'
  cat /root/.ssh/id_rsa.pub > /root/.ssh/authorized_keys
  cat /root/.ssh/id_rsa.pub >> /home/sensorpi/.ssh/authorized_keys
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/*
fi

# Create SSH config for root user:
if [ ! -e "/root/.ssh/config" ] ; then
  cat > /root/.ssh/config <<EOF
host github.com
  Hostname ssh.github.com
  Port 443
  UserKnownHostsFile = /dev/null
  StrictHostKeyChecking = no
EOF
fi

# Update again:
apt-get -y update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove
apt purge -y $(dpkg -l | awk '/^rc/ { print $2 }')
apt-get -y clean

# Recommend a reboot:
echo "Set up complete, now run 'reboot'"
