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

function error_exit {
	echo -e "${RED}✔ $1${NC}"
	exit 1
}

GITHUB_REPO="https://github.com/Loupthevenin/iot-ltheveni.git"
GITLAB_REPO="http://root:$GITLAB_PASSWORD@gitlab.local:8889/root/iot-ltheveni.git"

## Ajouter le repo github a gitlab
info "Authenticating and creating GitLab project..."
GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Not Found")
if [ "$GITLAB_PASSWORD" = "Not Found" ]; then
	echo -e "${RED}✘ Could not retrieve GitLab password. Did you install GitLab correctly?${NC}"
	exit 1
fi

info "Création d’un Personal Access Token (root) via gitlab-toolbox…"
TOOLBOX_POD=$(kubectl -n gitlab get pod -l app=toolbox -o jsonpath='{.items[0].metadata.name}')
[ -z "$TOOLBOX_POD" ] && fail "Pod toolbox introuvable (attends encore un peu et relance)"

PAT=$(openssl rand -hex 24)

kubectl -n gitlab exec "$TOOLBOX_POD" -- bash -lc "
TOKEN='$PAT' gitlab-rails runner \"
u = User.find_by_username('root');
t = u.personal_access_tokens.find_by(name: 'bootstrap') || u.personal_access_tokens.build(name: 'bootstrap', scopes: [:api, :read_api, :read_repository, :write_repository]);
t.set_token(ENV['TOKEN']);
t.expires_at = 1.year.from_now;
t.save!;
puts 'OK';
\"
" >/dev/null
success "PAT root créé"

REPO_NAME="iot-ltheveni"

info "Création du projet GitLab '$REPO_NAME'..."
curl -s --header "PRIVATE-TOKEN: $PAT" \
	--header "Content-Type: application/json" \
	--data "{\"name\": \"$REPO_NAME\", \"visibility\": \"private\"}" \
	"http://gitlab.local/api/v4/projects" >/dev/null

success "Projet '$REPO_NAME' créé dans GitLab."

info "Clone GitHub → /tmp/iot …"
rm -rf /tmp/iot
git clone "$GITHUB_REPO" /tmp/iot >/dev/null
cd /tmp/iot

GITLAB_REPO="http://root:${PAT}@gitlab.local/root/${REPO_NAME}.git"
info "Push --mirror vers GitLab…"
git remote set-url origin "$GITLAB_REPO"
git push --mirror >/dev/null
cd - >/dev/null
rm -rf /tmp/iot
success "Repo push vers GitLab"
