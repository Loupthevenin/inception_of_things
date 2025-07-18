#!/bin/bash

set -e

SCRIPT_DIR=/vagrant/scripts

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

function info {
	echo -e "${CYAN}➜ $1${NC}"
}

function success {
	echo -e "${GREEN}✔ $1${NC}"
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

# Helm
if ! command -v helm &>/dev/null; then
	curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	bash get_helm.sh
	rm get_helm.sh
	success "Helm installed"
else
	success
fi

# Create k3d cluster
CLUSTER_NAME="iot"
if k3d cluster list | grep -q $CLUSTER_NAME; then
	info "Cluster '$CLUSTER_NAME' already exists. Skipping creation."
else
	info "Creating K3D cluster '$CLUSTER_NAME'..."
	k3d cluster create $CLUSTER_NAME
	success "Cluster '$CLUSTER_NAME' created."
fi

# Wait for nodes
info "Waiting for K3D nodes to be ready..."
kubectl wait node --all --for=condition=Ready --timeout=60s || error_exit "Nodes did not become ready."
success "K3D nodes are ready."

# Gitlab
info "Creating 'gitlab' namespace..."
kubectl create namespace gitlab

info "Adding Gitlab Helm repo..."
helm repo add gitlab https://charts.gitlab.io/
helm repo update

info "Installing Gitlab with Helm..."
helm upgrade --install gitlab gitlab/gitlab \
	--namespace gitlab \
	--create-namespace \
	--timeout 20m \
	--set global.hosts.domain=localhost \
	--set global.hosts.externalIP=127.0.0.1 \
	--set global.ingress.configureCertmanager=false \
	--set certmanager.install=false \
	--set certmanager-issuer.email="dev@example.com" \
	--set nginx-ingress.enabled=false
success "GitLab installed in 'gitlab' namespace."

info "Waiting for GitLab Webservice to be ready (this takes a while)..."
kubectl wait --namespace gitlab --for=condition=available deploy/gitlab-webservice-default --timeout=600s
success "GitLab is ready."

info "Starting port-forward on GitLab (localhost:8889)..."
kubectl port-forward -n gitlab svc/gitlab-webservice-default 8889:8181 >/dev/null 2>&1 &

# Install Argo CD
info "Installing Argo CD in 'argocd' namespace..."
kubectl create namespace argocd && kubectl create namespace dev
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
success "Argo CD deployed in 'argocd' namespace."

# Wait for Argo CD to be ready
info "Waiting for Argo CD server to be available..."
kubectl wait --for=condition=available --timeout=180s -n argocd deploy/argocd-server || error_exit "Argo CD server is not ready in time."
success "Argo CD is ready."

info "Starting port-forward on Argo CD UI (localhost:8080)..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
sleep 2

info "Applying Argo CD Application manifest..."
kubectl apply -f "$SCRIPT_DIR/../confs/argocd.yaml" -n argocd
success "Application resource created. Argo CD should start syncing."

# Credentials
info "You can now access Argo CD UI at: http://localhost:8080..."
echo -e "${YELLOW}Default login: admin"
echo -e "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)${NC}"
info "Retrieving GitLab initial root password..."

GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Not Found")
if [ "$GITLAB_PASSWORD" != "Not Found" ]; then
	echo -e "${YELLOW}GitLab available at: http://localhost:8889"
	echo -e "Login: root"
	echo -e "Password: $GITLAB_PASSWORD${NC}"
	success "GitLab credentials retrieved."
else
	echo -e "${RED}✘ Could not retrieve GitLab password. Did you install GitLab correctly?${NC}"
fi

info "Waiting for wil-playground Pod to be Ready..."
kubectl wait --for=condition=ready pod -l app=wil-playground -n dev --timeout=120s || {
	echo -e "${RED}✘ Timeout: wil-playground Pod is not Ready.${NC}"
	kubectl get pods -n dev
	exit 1
}

success "wil-playground Pod is Ready."

#port-forward
info "Starting port-forward to service 'wil-playground'..."
kubectl port-forward svc/wil-playground -n dev 8888:8888

info "Setup complete!"
