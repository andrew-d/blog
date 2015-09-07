USER := andrew
HOST := dunham.io
LOCATION := /var/www/blog/

THEME ?= purehugo


# Should go first to be the default
.PHONY: help
help:
	@echo "Usage: make <command>"
	@echo
	@echo "Commands:"
	@echo "   hugo          Builds the site in public/"
	@echo "   sync          Uploads the site to the server"
	@echo


.PHONY: hugo
hugo:
	hugo --theme=$(THEME)


.PHONY:
sync: hugo
	rsync --itemize-changes -a public/ $(USER)@$(HOST):$(LOCATION)
