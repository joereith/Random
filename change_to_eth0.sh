#!/bin/bash
set -x

addr1="$1"
gw_addr="$2"
INTERFACE_DIR="/etc/network/interfaces.d"
WHOAMI=$(whoami)
echo "Checking if the script has been executed by root user"
if [ "$WHOAMI" != "root" ]; then
  echo "You're executing the script as $WHOAMI instead of root.. exiting"
  exit 1
fi

echo "Checking if Ubuntu is installed"
if ! grep -q 'Ubuntu' /etc/issue; then
  echo "Ubuntu is not installed"
  exit 1
fi


INTERFACES=$(ip -br a)
if ([[ ! $INTERFACES == *'eth0'*  ]] || [[ ! $INTERFACES == *'eth1'* ]] || ! grep -q 'GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"' /etc/default/grub); then
  # changing intefaces name
  sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/g' /etc/default/grub
  sed -i 's/enp0s3/eth0/g' /etc/netplan/50-cloud-init.yaml
  # changing interface name
  grub-mkconfig -o /boot/grub/grub.cfg

  # name server config
  ln -sf /var/run/systemd/resolve/resolv.conf /etc/resolv.conf
  sed -i 's/#DNS=/DNS=8.8.8.8/' /etc/systemd/resolved.conf
  service systemd-resolved restart

  # interface config
  apt install -y ifupdown net-tools ipcalc
  mkdir -p "$INTERFACE_DIR"
  echo "source-directory $INTERFACE_DIR" > /etc/network/interfaces

  if [ -z "$addr1" ] || [ -z "$gw_addr" ]
  then
    # DHCP allocated interface IP
    echo "auto eth0
    iface eth0 inet dhcp" > "$INTERFACE_DIR"/eth0
  else
    # Statically allocated interface IP
    if ipcalc -c "$addr1" | grep INVALID
    then
      echo "Interface ip is not valid IP"
      exit 1
    fi

    if ipcalc -c "$gw_addr" | grep INVALID
    then
      echo "Upstream Router ip is not valid IP"
      exit 1
    fi

    addr=$(   ipcalc -n "$addr1"  | grep Address | awk '{print $2}')
    netmask=$(ipcalc -n "$addr1"  | grep Netmask | awk '{print $2}')
    gw_addr=$(ipcalc -n "$gw_addr"| grep Address | awk '{print $2}')

    echo "auto eth0
  iface eth0 inet static
  address $addr
  netmask $netmask

  gateway $gw_addr" > "$INTERFACE_DIR"/eth0
  fi


  # get rid of netplan
  systemctl unmask networking
  systemctl enable networking

  apt-get --assume-yes purge nplan netplan.i

else
  echo "Interfaces name are correct, let's check if network and DNS are up"
  while ! nslookup google.com; do
    echo "DNS not reachable"
    sleep 1
  done

  while ! ping -c 1 -W 1 -I eth0 8.8.8.8; do
    echo "Network not ready yet"
    sleep 1
  done
fi

echo "Reboot for changes to take effect!"

