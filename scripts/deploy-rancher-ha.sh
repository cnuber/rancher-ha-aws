#!/bin/bash

deployment_statuscheck () {
  deployment_status=nope
  while [ "$deployment_status" != "deployment \"$APPNAME\" successfully rolled out" ]
    do
      echo "$APPNAME not ready yet..."
      deployment_status=$(kubectl -n $APPNS rollout status deploy/$APPNAME)
      sleep 10
    done
   echo "$APPNAME is now running"
}

helm_version_check () {
# Ensure at least helm version 2.12.1 is installed (Due to an issue with Helm v2.12.0 and cert-manager)

if (( $(echo "$HELM_VERSION" "2.12.1" | awk '{print ($1 > $2)}') )); then
  echo "minimum helm version found, proceeding..."
else
  echo "please upgrade your helm client to at least 2.12.1 in order to proceed with the Rancher install"
  exit 1
fi
}

tiller_deploy () {

# Create tiller serviceaccount
kubectl -n kube-system get serviceaccount tiller || kubectl -n kube-system create serviceaccount tiller

# Create CRB for tiller serviceaccount
kubectl -n kube-system get clusterrolebinding tiller || kubectl create clusterrolebinding tiller --clusterrole=cluster-admin --serviceaccount=kube-system:tiller

# Initialize tiller on the server
helm init --service-account tiller

# Wait until tiller pod is ready
APPNAME="tiller-deploy" APPNS="kube-system" deployment_statuscheck 
}

rancher_deploy () {
# Add the Rancher helm repository (options are stable and latest)
helm repo add rancher-$RANCHER_REPO https://releases.rancher.com/server-charts/$RANCHER_REPO
helm repo update

# Deploy rancher with specified SSL type (options are rancher, letsencrypt or private)
if [ "$SSL" == "private" ] ; then
  helm upgrade --install --force rancher rancher-$RANCHER_REPO/rancher --namespace cattle-system --set hostname=$RANCHER_HOSTNAME --set ingress.tls.source=secret --set auditLog.level=1
# Create secrets containing private ssl cert/key and ca
  kubectl -n cattle-system get secret tls-rancher-ingress || kubectl -n cattle-system create secret tls tls-rancher-ingress --cert=tls.crt --key=tls.key
  kubectl -n cattle-system get secret tls-ca || kubectl -n cattle-system create secret generic tls-ca --from-file=cacerts.pem
# Wait for Rancher deployment to complete successfully  
  APPNAME="rancher"
  APPNS="cattle-system"
  deployment_statuscheck
elif [ "$SSL" == "letsencrypt" ] ; then
  helm install stable/cert-manager --name cert-manager --namespace kube-system --version v0.5.2
  APPNAME="cert-manager"
  APPNS="kube-system"
  deployment_statuscheck
  helm install rancher-latest/rancher --name rancher --namespace cattle-system --set hostname=$RANCHER_HOSTNAME --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=$LETSENCRYPT_EMAIL
  APPNAME="rancher"
  APPNS="cattle-system"
  deployment_statuscheck
else
  helm install stable/cert-manager --name cert-manager --namespace kube-system --version v0.5.2
  APPNAME="cert-manager"
  APPNS="kube-system"
  deployment_statuscheck
  helm install rancher-latest/rancher --name rancher --namespace cattle-system --set hostname=$RANCHER_HOSTNAME
  APPNAME="rancher"
  APPNS="cattle-system"
  deployment_statuscheck
fi
}

helm_version_check
tiller_deploy
rancher_deploy
