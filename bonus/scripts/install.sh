#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pkill -f "kubectl port-forward"

function info {
	echo -e "${CYAN}➜ $1${NC}"
}

function success {
	echo -e "${GREEN}✔ $1${NC}"
}

function error_exit {
	echo -e "${RED}✔ $1${NC}"
	exit 1
}

function safe_port_forward {
	local namespace=$1
	local service=$2
	local ports=$3

	info "Starting port-forward to service '$service' in namespace '$namespace'..."
	kubectl port-forward svc/$service -n $namespace $ports >/tmp/portforward-$service.log 2>&1 &
	PF_PID=$!

	# Vérifie que le port est bien ouvert
	ATTEMPTS=0
	until nc -z localhost ${ports%%:*} || [ $ATTEMPTS -ge 10 ]; do
		echo -e "${YELLOW}➜ Waiting for port-forward to be ready... (${ATTEMPTS}/10)${NC}"
		ATTEMPTS=$((ATTEMPTS + 1))
		sleep 2
	done

	if ! nc -z localhost ${ports%%:*}; then
		echo -e "${RED}✘ Port-forward to $service failed. Check /tmp/portforward-$service.log${NC}"
		kill $PF_PID >/dev/null 2>&1 || true
		exit 1
	fi

	success "Port-forward active on http://localhost:${ports%%:*}"
}

# Dependencies
info "Installing required packages..."
sudo apt update -y
sudo apt install -y curl wget git ca-certificates

# Docker
info "Installing Docker..."
if ! command -v docker &>/dev/null; then
	curl -fssL https://get.docker.com | sh
	success "Docker installed successfully."
else
	success "Docker is already installed."
fi

# kubectl
info "Installing kubectl..."
if ! command -v kubectl &>/dev/null; then
	curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
	chmod +x kubectl
	sudo mv kubectl /usr/local/bin
	success "kubectl installed."
else
	success "kubectl is already installed."
fi

# k3d
info "Installing k3d"
if ! command -v k3d &>/dev/null; then
	wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
	success "K3D installed."
else
	success "k3d is already installed."
fi

# Create k3d cluster
CLUSTER_NAME="iot"
if k3d cluster list | grep -q $CLUSTER_NAME; then
	info "Cluster '$CLUSTER_NAME' already exists. Skipping creation."
else
	info "Creating K3D cluster '$CLUSTER_NAME'..."
	k3d cluster create $CLUSTER_NAME \
		--port "80:80@loadbalancer" \
		--port "443:443@loadbalancer"
	success "Cluster '$CLUSTER_NAME' created."
fi

# Wait for nodes
info "Waiting for K3D nodes to be ready..."
kubectl wait node --all --for=condition=Ready --timeout=60s || error_exit "Nodes did not become ready."
success "K3D nodes are ready."

# Install Argo CD
info "Installing Argo CD in 'argocd' namespace..."
kubectl create namespace argocd && kubectl create namespace dev
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
success "Argo CD deployed in 'argocd' namespace."

#Remove endpoint exclusion
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"resource.exclusions":""}}'

kubectl -n argocd rollout restart deployment argocd-server

# Wait for Argo CD to be ready
info "Waiting for Argo CD server to be available..."
kubectl wait --for=condition=available --timeout=180s -n argocd deploy/argocd-server || error_exit "Argo CD server is not ready in time."
success "Argo CD is ready."

info "Starting port-forward on Argo CD UI (localhost:8080)..."
# kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
safe_port_forward argocd argocd-server 8080:443
sleep 2

info "Applying Argo CD Application manifest..."
kubectl apply -f "$SCRIPT_DIR/../confs/argocd.yaml" -n argocd
success "Application resource created. Argo CD should start syncing."

# Credentials
info "You can now access Argo CD UI at: http://localhost:8080..."
echo -e "${YELLOW}Default login: admin"
echo -e "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)${NC}"

info "Waiting for wil-playground Pod to be created by ArgoCD..."
ATTEMPTS=0
until kubectl get pod -l app=wil-playground -n dev 2>/dev/null | grep -q wil-playground || [ $ATTEMPTS -ge 60 ]; do
	echo -e "${YELLOW}➜ Pod not found yet. Waiting... (${ATTEMPTS}/60)${NC}"
	ATTEMPTS=$((ATTEMPTS + 1))
	sleep 5
done

if [ $ATTEMPTS -ge 24 ]; then
	echo -e "${RED}✘ Timeout: Pod was not created after 2 minutes.${NC}"
	kubectl get pods -n dev
	exit 1
fi

info "wil-playground Pod found. Waiting for it to become Ready..."
kubectl wait --for=condition=ready pod -l app=wil-playground -n dev --timeout=120s || {
	echo -e "${RED}✘ Timeout: wil-playground Pod is not Ready.${NC}"
	kubectl get pods -n dev
	exit 1
}

#port-forward
info "Starting port-forward to service 'wil-playground'..."
# kubectl port-forward svc/wil-playground -n dev 8888:8888 >/dev/null 2>&1 &
safe_port_forward dev wil-playground 8888:8888
sleep 2

info "Setup complete!"
