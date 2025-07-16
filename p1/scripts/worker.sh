#!/bin/bash

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SERVER_IP="192.168.56.110"
WORKER_IP="192.168.56.111"
TOKEN_FILE="/vagrant/token"

function info {
	echo -e "${CYAN}➜ $1${NC}"
}

function success {
	echo -e "${GREEN}✔ $1${NC}"
}

function warning {
	echo -e "${YELLOW}⚠ $1${NC}"
}

function error {
	echo -e "${RED}✘ $1${NC}"
}

info "Setup"
apt install -y net-tools

info "⏳ Attente du token K3s dans ${TOKEN_FILE}..."
while [ ! -s "${TOKEN_FILE}" ]; do
	sleep 2
done

TOKEN=$(cat ${TOKEN_FILE})
success "Token récupéré : ${TOKEN}"

info "Vérification de la connectivité au serveur K3s ${SERVER_IP}:6443..."
until nc -z "${SERVER_IP}" 6443; do
	warning "Le serveur n'est pas encore accessible, nouvelle tentative dans 2s..."
	sleep 2
done
success "Serveur K3s accessible."

info "Installation de K3s agent..."
if curl -sfL https://get.k3s.io | K3S_URL="https://${SERVER_IP}:6443" K3S_TOKEN="${TOKEN}" sh -s - --node-ip="${WORKER_IP}"; then
	success "K3s agent installé avec succès."
else
	error "Échec de l'installation de K3s agent."
	exit 1
fi
