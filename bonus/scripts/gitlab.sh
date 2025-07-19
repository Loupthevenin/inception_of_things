#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GITLAB_DOMAIN="gitlab.local"
REGISTRY_DOMAIN="registry.local"
MINIO_DOMAIN="minio.local"
HOSTS_LINE="127.0.0.1 $GITLAB_DOMAIN $REGISTRY_DOMAIN $MINIO_DOMAIN"

GITHUB_REPO="https://github.com/Loupthevenin/iot-ltheveni.git"

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

# Helm
if ! command -v helm &>/dev/null; then
	curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
	bash get_helm.sh
	rm get_helm.sh
	success "Helm installed"
else
	success
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
	--set global.hosts.externalIP=0.0.0.0 \
	--set global.hosts.https=false \
	--timeout 600s
success "GitLab installed in 'gitlab' namespace."

info "Waiting for GitLab Webservice to be ready (this takes a while)..."
kubectl get pods -n gitlab --watch --selector=app=gitlab-webservice &
# On récupère le PID du watch
WATCH_PID=$!

# Attente condition ready
kubectl wait --namespace gitlab --for=condition=available deploy/gitlab-webservice-default --timeout=600s

# Kill le watch dès que prêt
kill $WATCH_PID 2>/dev/null
success "GitLab is ready."

info "Starting port-forward on GitLab (gitlab.local:8889)..."
kubectl port-forward -n gitlab svc/gitlab-webservice-default 8889:8181 >/dev/null 2>&1 &

sleep 2

## Ajouter le repo github a gitlab
info "Authenticating and creating GitLab project..."
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Not Found")
if [ "$GITLAB_PASSWORD" = "Not Found" ]; then
	echo -e "${RED}✘ Could not retrieve GitLab password. Did you install GitLab correctly?${NC}"
	exit 1
fi

if ! command -v jq &>/dev/null; then
	info "Installing jq..."
	sudo apt install -y jq
fi

PRIVATE_TOKEN=$(curl -s --request POST http://localhost:8889/api/v4/session \
	--form "login=root" \
	--form "password=$GITLAB_PASSWORD" | jq -r '.private_token')

REPO_NAME="iot-ltheveni"

curl --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
	--data "name=$REPO_NAME" \
	--data "visibility=public" \
	http://localhost:8889/api/v4/projects

GITLAB_REPO="http://root:$GITLAB_PASSWORD@localhost:8889/root/$REPO_NAME.git"

info "Cloning GitHub repo..."
git clone "$GITHUB_REPO" /tmp/iot
cd /tmp/iot

info "Pushing to GitLab repo..."
git remote set-url origin "$GITLAB_REPO"
git push --mirror
success "Repo pushed to GitLab."
rm -rf /tmp/iot
success "Cleaned up temporary GitHub repo clone."

### Reload confs argocd
kubectl apply -f "$SCRIPT_DIR/../confs/argocd.yaml" -n argocd

# Credentials
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Not Found")
if [ "$GITLAB_PASSWORD" != "Not Found" ]; then
	echo -e "${YELLOW}GitLab available at: http://localhost:8889"
	echo -e "Login: root"
	echo -e "Password: $GITLAB_PASSWORD${NC}"
	success "GitLab credentials retrieved."
else
	echo -e "${RED}✘ Could not retrieve GitLab password. Did you install GitLab correctly?${NC}"
fi
