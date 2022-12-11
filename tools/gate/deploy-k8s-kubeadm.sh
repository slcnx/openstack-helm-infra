#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

: "${HELM_VERSION:="v3.6.3"}"
: "${KUBE_VERSION:="1.21.5-00"}"
: "${CALICO_VERSION:="v3.20"}"
: "${YQ_VERSION:="v4.6.0"}"

export DEBCONF_NONINTERACTIVE_SEEN=true
export DEBIAN_FRONTEND=noninteractive

sudo swapoff -a

echo "DefaultLimitMEMLOCK=16384" | sudo tee -a /etc/systemd/system.conf
sudo systemctl daemon-reexec

function configure_resolvconf {
  # here with systemd-resolved disabled, we'll have 2 separate resolv.conf
  # 1 - /etc/resolv.conf - to be used for resolution on host

  kube_dns_ip="10.96.0.10"
  # keep all nameservers from both resolv.conf excluding local addresses
  old_ns=$(grep -P --no-filename "^nameserver\s+(?!127\.0\.0\.|${kube_dns_ip})" \
           /etc/resolv.conf /run/systemd/resolve/resolv.conf | sort | uniq)

  # Add kube-dns ip to /etc/resolv.conf for local usage
  sudo bash -c "echo 'nameserver ${kube_dns_ip}' > /etc/resolv.conf"
  if [ -z "${HTTP_PROXY}" ]; then
    sudo bash -c "printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /run/systemd/resolve/resolv.conf"
    sudo bash -c "printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' >> /etc/resolv.conf"
  else
    sudo bash -c "echo \"${old_ns}\" > /run/systemd/resolve/resolv.conf"
    sudo bash -c "echo \"${old_ns}\" >> /etc/resolv.conf"
  fi

  for file in /etc/resolv.conf /run/systemd/resolve/resolv.conf; do
    sudo bash -c "echo 'search svc.cluster.local cluster.local' >> ${file}"
    sudo bash -c "echo 'options ndots:5 timeout:1 attempts:1' >> ${file}"
  done
}

# NOTE: Clean Up hosts file
sudo sed -i '/^127.0.0.1/c\127.0.0.1 localhost localhost.localdomain localhost4localhost4.localdomain4' /etc/hosts
sudo sed -i '/^::1/c\::1 localhost6 localhost6.localdomain6' /etc/hosts

configure_resolvconf

# shellcheck disable=SC1091
. /etc/os-release


# NOTE: Configure docker
docker_resolv="/run/systemd/resolve/resolv.conf"
docker_dns_list="$(awk '/^nameserver/ { printf "%s%s",sep,"\"" $NF "\""; sep=", "} END{print ""}' "${docker_resolv}")"

sudo -E mkdir -p /etc/docker
sudo -E tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "dns": [${docker_dns_list}],
	"data-root": "/nvme_data/others/minikube"
}
EOF

if [ -n "${HTTP_PROXY}" ]; then
  sudo mkdir -p /etc/systemd/system/docker.service.d
  cat <<EOF | sudo -E tee /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF
fi



# 解压直接是二进制文件
# Install YQ
which yq || {
wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64.tar.gz -O - | tar xz && sudo mv yq_linux_amd64 /usr/local/bin/yq
}


which helm || {
# 解压有目录,  --strip-components=1
# Install Helm
TMP_DIR=$(mktemp -d)
sudo -E bash -c \
  "curl -sSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz | tar -zxv --strip-components=1 -C ${TMP_DIR}"
sudo -E mv "${TMP_DIR}"/helm /usr/local/bin/helm
rm -rf "${TMP_DIR}"
}

# Install kubeadm kubectl and kublet
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
#setenforce 0
yum install kubeadm-1.17.17-0 kubectl-1.17.17-0 kubelet-1.17.17-0 -y
systemctl enable kubelet && systemctl start kubelet

# NOTE: Deploy kubernetes using kubeadm. A CNI that supports network policy is
# required for validation; use calico for simplicity.
# install dockerd-cri
kubeadm init --kubernetes-version 1.17.0 --pod-network-cidr=10.10.0.0/16 --service-cidr=10.20.0.0/16  --node-name 192.168.0.35


mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Taing the node so that the pods can be deployed on master nodes.
kubectl taint nodes --all node-role.kubernetes.io/master- || true

curl https://docs.projectcalico.org/"${CALICO_VERSION}"/manifests/calico.yaml -o /tmp/calico.yaml

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/tigera-operator.yaml

wget https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/custom-resources.yaml -O /tmp/custom-resources.yaml
sed -i "s@192.168.0.0/16@10.10.0.0/16@g" /tmp/custom-resources.yaml


# Note: Patch calico daemonset to enable Prometheus metrics and annotations
#tee /tmp/calico-node.yaml << EOF
#spec:
#  template:
#    metadata:
#      annotations:
#        prometheus.io/scrape: "true"
#        prometheus.io/port: "9091"
#    spec:
#      containers:
#        - name: calico-node
#          env:
#            - name: FELIX_PROMETHEUSMETRICSENABLED
#              value: "true"
#            - name: FELIX_PROMETHEUSMETRICSPORT
#              value: "9091"
#            - name: FELIX_IGNORELOOSERPF
#              value: "true"
#EOF
#kubectl -n kube-system patch daemonset calico-node --patch "$(cat /tmp/calico-node.yaml)"

kubectl get pod -A
kubectl -n kube-system get pod -l k8s-app=kube-dns

# NOTE: Wait for dns to be running.
END=$(($(date +%s) + 240))
until kubectl --namespace=kube-system \
        get pods -l k8s-app=kube-dns --no-headers -o name | grep -q "^pod/coredns"; do
  NOW=$(date +%s)
  [ "${NOW}" -gt "${END}" ] && exit 1
  echo "still waiting for dns"
  sleep 10
done
kubectl -n kube-system wait --timeout=240s --for=condition=Ready pods -l k8s-app=kube-dns

# Remove stable repo, if present, to improve build time
helm repo remove stable || true

# Add labels to the core namespaces & nodes
kubectl label --overwrite namespace default name=default
kubectl label --overwrite namespace kube-system name=kube-system
kubectl label --overwrite namespace kube-public name=kube-public
kubectl label nodes --all openstack-control-plane=enabled
kubectl label nodes --all openstack-compute-node=enabled
kubectl label nodes --all openvswitch=enabled
kubectl label nodes --all linuxbridge=enabled
kubectl label nodes --all ceph-mon=enabled
kubectl label nodes --all ceph-osd=enabled
kubectl label nodes --all ceph-mds=enabled
kubectl label nodes --all ceph-rgw=enabled
kubectl label nodes --all ceph-mgr=enabled

for NAMESPACE in ceph openstack osh-infra; do
tee /tmp/${NAMESPACE}-ns.yaml << EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: ${NAMESPACE}
    name: ${NAMESPACE}
  name: ${NAMESPACE}
EOF

kubectl create -f /tmp/${NAMESPACE}-ns.yaml
done
