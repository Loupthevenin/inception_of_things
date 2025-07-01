# Colors
_GREY   = \033[30m
_RED    = \033[31m
_GREEN  = \033[32m
_YELLOW = \033[33m
_BLUE   = \033[34m
_PURPLE = \033[35m
_CYAN   = \033[36m
_WHITE  = \033[37m
_END    = \033[0m

DIRS = p1 p2 p3 bonus

up_p1:
	@echo -e "→ [p1] Lancement des VMs..."
	cd p1 && vagrant up

status_p1:
	cd p1 && vagrant status

halt_p1:
	@echo -e "-> [p2] Arrêt des VMs..."
	cd p1 && vagrant halt

down_p1:
	@echo -e "→ [p1] Destruction des VMs..."
	cd p1 && vagrant destroy -f

clean: halt_p1 down_p1
	cd p1 && rm -rf .vagrant token

fclean: clean

.PHONY: up_p1 status_p1 halt_p1 down_p1 clean fclean
