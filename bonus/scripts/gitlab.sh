#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GITLAB_DOMAIN="gitlab.local"
HOSTS_LINE="127.0.0.1 $GITLAB_DOMAIN"

GITHUB_REPO="https://github.com/Loupthevenin/iot-ltheveni.git"
REPO_NAME="iot-ltheveni"

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
function warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
function fail() {
	echo -e "${RED}✘ $1${NC}"
	exit 1
}

# Helm
if ! command -v helm &>/dev/null; then
	curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	bash get_helm.sh
	rm get_helm.sh
	success "Helm installed"
else
	success "Helm is already installed."
fi

# Gitlab
info "Creating 'gitlab' namespace..."
kubectl create namespace gitlab

# Vérifie si les domaines sont déjà présents
if ! grep -q "$GITLAB_DOMAIN" /etc/hosts; then
	echo "$HOSTS_LINE" | sudo tee -a /etc/hosts >/dev/null
	echo "✅ Domaines ajoutés à /etc/hosts : $HOSTS_LINE"
else
	echo "ℹ️ Entrées déjà présentes dans /etc/hosts."
fi

info "Adding Gitlab Helm repo..."
helm repo add gitlab https://charts.gitlab.io/
helm repo update

info "Installing Gitlab with Helm..."
helm upgrade --install gitlab gitlab/gitlab \
	--namespace gitlab \
	-f https://gitlab.com/gitlab-org/charts/gitlab/raw/master/examples/values-minikube-minimum.yaml \
	--set global.hosts.domain=local \
	--set global.hosts.https=false \
	--timeout 30m
success "GitLab installed in 'gitlab' namespace."

info "Waiting for GitLab Webservice to be ready (this takes a while)..."
while true; do
	not_ready=$(kubectl get pods -n gitlab --no-headers 2>/dev/null | grep -Ev 'Running|Completed' || true)

	if [ -z "$not_ready" ]; then
		success "All GitLab pods are ready."
		break
	else
		clear
		echo -e "${YELLOW}Waiting for GitLab pods to be ready...${NC}"
		kubectl get pods -n gitlab
		sleep 5
	fi
done
success "GitLab is ready."

info "Creating GitLab Ingress..."
kubectl apply -f "$SCRIPT_DIR/../confs/gitlab-ingress.yaml"
success "Ingress appliqué"

info "Setting up port-forward for GitLab Webservice on localhost:8181..."
kubectl -n gitlab port-forward svc/gitlab-webservice-default 8181:80 >/dev/null 2>&1 &
PF_PID=$!
success "Port-forward lancé (PID=$PF_PID) → http://gitlab.local"

# Attente que le port soit bien accessible
info "Attente que Gitlab  Webservice soit disponible via le port-forward..."
for i in {1..30}; do
	if curl -s http://gitlab.local/users/sign_in >/dev/null; then
		success "Gitlab Webservice est accessible"
		break
	else
		sleep 1
	fi
done

GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Not Found")

# Credentials
echo
echo -e "${YELLOW}GitLab:  ${NC}http://gitlab.local"
echo -e "${YELLOW}Login:   ${NC}root"
echo -e "${YELLOW}Password:${NC} $GITLAB_PASSWORD"
echo -e "${YELLOW}PAT:     ${NC} $PAT (scopes: api, read_repository, write_repository)"
echo
success "Installation bonus GitLab terminée"
