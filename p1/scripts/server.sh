#!/bin/bash

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

function info {
	echo -e "${CYAN}➜ $1${NC}"
}

function success {
	echo -e "${GREEN}✔ $1${NC}"
}

function error {
	echo -e "${RED}✘ $1${NC}"
}

info "Installation de K3s server..."

if curl -sfL https://get.k3s.io | sh -; then
	success "K3s server installé avec succès."
else
	error "Échec de l'installation de K3s server."
	exit 1
fi

info "Extraction du token K3s..."
if sudo cat /var/lib/rancher/k3s/server/node-token >/vagrant/token; then
	success "Token sauvegardé dans /vagrant/token."
else
	error "Échec de la sauvegarde du token."
	exit 1
fi
