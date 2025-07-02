#!/bin/bash

# Comment out all lines in /etc/apt/sources.list.d/ceph.list
if [ -f /etc/apt/sources.list.d/ceph.list ]; then
    sed -i 's/^/#/' /etc/apt/sources.list.d/ceph.list
fi

# Comment out all lines in /etc/apt/sources.list.d/pve-enterprise.list
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.list
fi

# Create pve-no-subscription.list with new content
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list