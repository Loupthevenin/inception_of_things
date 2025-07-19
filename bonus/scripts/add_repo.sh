#!/bin/bash
set -e

GITHUB_REPO="https://github.com/Loupthevenin/iot-ltheveni.git"

GITLAB_PASSWORD=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "Not Found")
if [ "$GITLAB_PASSWORD" = "Not Found" ]; then
	echo -e "${RED}✘ Could not retrieve GitLab password. Did you install GitLab correctly?${NC}"
	exit 1
fi

GITLAB_REPO="http://root:$GITLAB_PASSWORD@gitlab.local:8889/root/iot-ltheveni.git"

echo "Cloning GitHub repo..."
git clone "$GITHUB_REPO" /tmp/iot
cd /tmp/iot

echo "Pushing to GitLab repo..."
git remote set-url origin "$GITLAB_REPO"
git push --mirror

echo "Clean up temporary clone..."
rm -rf /tmp/iot

echo "Repo pushed to GitLab."
