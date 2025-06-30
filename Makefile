part ?= p1

SERVER = ltheveniS
WORKER = ltheveniSW

up:
	@echo "→ [$(part)] Lancement du serveur K3s..."
	cd $(part) && vagrant up $(SERVER)
