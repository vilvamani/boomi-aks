#!/bin/bash

while [[ $# > 0 ]]
do
  key="$1"
  shift
  case "$key" in
    --resource_group|-rg)
      resource_group="$1"
      shift
      ;;
    --aks_name|-an)
      aks_name="$1"
      shift
      ;;
    --molecule_username)
      molecule_username="$1"
      shift
      ;;
    --molecule_password)
      molecule_password="$1"
      shift
      ;;
    --molecule_account)
      molecule_account="$1"
      shift
      ;;
    --fileshare)
      fileshare="$1"
      shift
      ;;
    --netAppIP)
      netAppIP="$1"
      shift
      ;;
    --help|-help|-h)
      print_usage
      exit 13
      ;;
    *)
      echo "ERROR: Unknown argument '$key' to script '$0'" 1>&2
      exit -1
  esac
done

exec &> /var/log/bastion.log
set -x

#cfn signaling functions
yum install git -y || apt-get install -y git || zypper -n install git

#install kubectl
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
kubectl version --client

rpm --import https://packages.microsoft.com/keys/microsoft.asc

cat <<EOF > /etc/yum.repos.d/azure-cli.repo
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

yum install azure-cli -y

yum install -y nfs-utils

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

#Sign in with a managed identity
az login --identity

az aks get-credentials --resource-group "$resource_group" --name "$aks_name"

mkdir ~/$fileshare

mount -t nfs -o rw,hard,rsize=1048576,wsize=1048576,vers=3,tcp $netAppIP:/$fileshare ~/$fileshare

chmod -R 777 ~/$fileshare

cat >/tmp/secrets.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: boomi-secret
type: Opaque
stringData:
  username: $molecule_username
  password: $molecule_password
  account: $molecule_account
EOF

cat >/tmp/persistentvolume.yaml <<EOF
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: azurefile
spec:
  storageClassName: ""
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  mountOptions:
    - vers=3
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: $netAppIP
    path: /$fileshare
EOF

cat >/tmp/persistentvolumeclam.yaml <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: azurefile
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 100Gi
EOF

whoami

kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/v1.6.0/deploy/infra/deployment-rbac.yaml --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/secrets.yaml --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/persistentvolume.yaml --kubeconfig=/root/.kube/config

kubectl apply -f /tmp/persistentvolumeclam.yaml --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/vilvamani/boomi-aks/main/kubernetes/statefulset.yaml --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/vilvamani/boomi-aks/main/kubernetes/services.yaml --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/vilvamani/boomi-aks/main/kubernetes/hpa.yaml --kubeconfig=/root/.kube/config

kubectl apply -f https://raw.githubusercontent.com/vilvamani/boomi-aks/main/kubernetes/ingress.yaml --kubeconfig=/root/.kube/config

rm /tmp/secrets.yaml
rm /tmp/persistentvolume.yaml
rm /tmp/persistentvolumeclam.yaml
