#!/bin/bash

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

NODE_IP="192.168.56.110"

function info {
	echo -e "${CYAN}➜ $1${NC}"
}

function success {
	echo -e "${GREEN}✔ $1${NC}"
}

function error {
	echo -e "${RED}✘ $1${NC}"
}

info "Setup"
apt install -y net-tools

info "Installation de K3s server..."
if curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-ip=${NODE_IP}" sh -; then
	success "K3s server installé avec succès."
else
	error "Échec de l'installation de K3s server."
	exit 1
fi

info "Attente de la disponibilité de l'API Kubernetes..."
until kubectl get nodes &>/dev/null; do
	echo -n "."
	sleep 2
done
success "API Kubernetes disponible."

info "Création des ConfigMaps HTML personnalisés..."

kubectl create configmap app1-html --from-file=index.html=/vagrant/scripts/indexApp1.html --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap app2-html --from-file=index.html=/vagrant/scripts/indexApp2.html --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap app3-html --from-file=index.html=/vagrant/scripts/indexApp3.html --dry-run=client -o yaml | kubectl apply -f -

success "ConfigMaps appliqués."

kubectl apply -f /vagrant/confs/
success "Manifests Kubernetes appliqués."

info "Attente état ready des 3 applications..."

TIMEOUT=120
INTERVAL=5
ELAPSED=0

while true; do
	READY_COUNT=$(kubectl get pods -n default --field-selector=status.phase=Running --no-headers | grep -c "1/1")

	if [ "$READY_COUNT" -ge 3 ]; then
		success "Les 3 applications sont prêtes."
		break
	fi

	if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
		error "Timeout atteint : certaines applications ne sont pas prêtes."
		kubectl get pods -n default
		exit 1
	fi

	echo -n "."
	sleep "$INTERVAL"
	ELAPSED=$((ELAPSED + INTERVAL))
done