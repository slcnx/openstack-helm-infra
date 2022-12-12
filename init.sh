#!/bin/bash
#
#********************************************************************
#Author:                songliangcheng
#QQ:                    2192383945
#Date:                  2022-12-12
#FileName：             init.sh
#URL:                   http://www.magedu.com
#Description：          A test toy
#Copyright (C):        2022 All rights reserved
#********************************************************************
cd ../openstack-helm
./tools/deployment/developer/common/020-setup-client.sh
# ceph, openstack, ingress
./tools/deployment/component/common/ingress.sh
kubectl create ns nfs
./tools/deployment/developer/nfs/040-nfs-provisioner.sh
./tools/deployment/developer/nfs/050-mariadb.sh
./tools/deployment/developer/nfs/060-rabbitmq.sh
./tools/deployment/developer/nfs/070-memcached.sh
./tools/deployment/developer/nfs/080-keystone.sh
./tools/deployment/developer/nfs/090-heat.sh
./tools/deployment/developer/nfs/100-horizon.sh
./tools/deployment/developer/nfs/120-glance.sh
./tools/deployment/developer/nfs/140-openvswitch.sh
./tools/deployment/developer/nfs/150-libvirt.sh
./tools/deployment/developer/nfs/160-compute-kit.sh
./tools/deployment/developer/nfs/170-setup-gateway.sh
export OS_CLOUD=openstack_helm
openstack flavor create --vcpus 2 --ram 2048 --disk 60 m1.nano
echo kubectl edit service/nova-novncproxy -n openstack 将31002转发到6080
