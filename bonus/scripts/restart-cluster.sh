#!/bin/bash

set -e

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

function wait_for_pod_ready() {
	local namespace=$1
	local label_selector=$2
	local timeout=${3:-300}

	info "Waiting for pods in namespace '$namespace' with label '$label_selector' to be ready (timeout: $timeout s)..."
	SECONDS=0
	while true; do
		not_ready=$(kubectl get pods -n "$namespace" -l "$label_selector" -o jsonpath='{.items[?(@.status.phase!="Running")].metadata.name}')
		if [ -z "$not_ready" ]; then
			success "Pods in namespace '$namespace' are ready."
			break
		fi
		if [ $SECONDS -ge "$timeout" ]; then
			echo -e "${RED}✘ Timeout waiting for pods in $namespace with label $label_selector to be ready.${NC}"
			exit 1
		fi
		sleep 5
	done
}

function is_cluster_running() {
	local cluster_name=$1
	k3d cluster list "$cluster_name" -o json 2>/dev/null | jq -e '.[0].serversRunning == .[0].serversCount' >/dev/null
}

pkill -f "kubectl port-forward"

CLUSTER_NAME="iot"

if is_cluster_running "$CLUSTER_NAME"; then
	info "Cluster '$CLUSTER_NAME' is already running."
else
	info "Starting cluster '$CLUSTER_NAME'..."
	k3d cluster start "$CLUSTER_NAME"
	success "Cluster '$CLUSTER_NAME' started."
fi

wait_for_pod_ready gitlab app=gitlab-webservice-default 600
wait_for_pod_ready argocd app.kubernetes.io/name=argocd-server 300
wait_for_pod_ready dev app=wil-playground 300

info "Starting port-forward on Argo CD UI (localhost:8080)..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &

info "Starting port-forward to service 'wil-playground'..."
kubectl port-forward svc/wil-playground -n dev 8888:8888 >/dev/null 2>&1 &

info "Starting port-forward on GitLab (gitlab.local:8889)..."
kubectl port-forward -n gitlab svc/gitlab-webservice-default 8889:8181 >/dev/null 2>&1 &

info "All port-forwards started."

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

# Credentials
info "You can now access Argo CD UI at: http://localhost:8080"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo -e "${YELLOW}Default login: admin"
echo -e "Password: $ARGOCD_PASSWORD${NC}"
