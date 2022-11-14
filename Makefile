# Build Env Argument, dev will be default env if no specified
ENV ?= dev
ECR_IMAGE=175471962215.dkr.ecr.ap-southeast-1.amazonaws.com/ticket-server-bref
ifeq ($(ENV), dev)
IMAGE_NAME=carro-ticket-server-bref
else
IMAGE_NAME=$(ECR_IMAGE)
endif
CONSOLE_IMAGE_NAME=$(IMAGE_NAME)-console

# Build the docker image
# If no TAG_NAME was specified, latest will be used
build:
	@if [ -z "$(TAG_NAME)" ]; then export TAG_NAME=latest; fi; \
	if [ -z "$(TARGET)" ]; then export TARGET=dev; fi; \
	echo "Building \033[0;32m[$(IMAGE_NAME):$$TAG_NAME]\033[0;39m with \033[0;32m[$$TARGET]\033[0;39m layer"; \
	if [ "$$(uname -m)" = "arm64" ]; then \
		echo "Building linux/arm64/v8 Image"; \
		docker build --target=$$TARGET --platform linux/arm64/v8 -f docker/php-fpm/Dockerfile -t $(IMAGE_NAME):$$TAG_NAME .; \
		docker build --platform linux/arm64/v8 -f docker/php-console/Dockerfile -t $(CONSOLE_IMAGE_NAME):$$TAG_NAME .; \
	else \
		echo "Building linux/x86_64 Image"; \
		docker build --target=$$TARGET -f docker/php-fpm/Dockerfile -t $(IMAGE_NAME):$$TAG_NAME .; \
		docker build -f docker/php-console/Dockerfile -t $(CONSOLE_IMAGE_NAME):$$TAG_NAME .; \
	fi

# Install Local vendor/ by copying from docker image
# vendor will be sync across envs
vendor:
	@if [ ! -d vendor ]; then \
		echo "Copying vendor from docker image...."; \
		TMP=$$(docker create carro-ticket-server-bref); \
		docker cp $$TMP:/var/task/vendor vendor; \
		docker rm $$TMP; \
	fi
	@echo "\033[0;32mSuccess install vendor for Local Development..."

install:
	@make build
	@make vendor

up:
	docker compose up -d --remove-orphans
	@echo "\033[0;32m 👉 Web-server started at http://localhost:8000/";
	@echo "\033[0;32m 👉 Soketi Server started at http://localhost:9601/usage";
	@echo "\033[0;32m 👉 MailHog Inbox started at http://localhost:8001";

ssh:
	docker exec -it carro-ticket-web-php bash

# Follow laravel logs (All Logs)
all-logs:
	docker logs -f carro-ticket-web-php

# Follow laravel logs, latest 1 line
logs:
	@echo "\033[0;32m 👉 Latest 1 line of log is being shown.\033[0;39m"
	@echo "\033[0;32m 👉 make all-logs to show all\033[0;39m"
	docker logs --tail 1 -f carro-ticket-web-php

# Run bash under writeable mode, usually to install new package by composer
composer:
	docker compose -f docker-compose.yml -f docker-compose.composer.yml run --rm composer bash

format_check:
	@./vendor/bin/phpcs --standard=./tests/phpcs.xml -n

format_fix:
	@./vendor/bin/phpcbf --standard=./tests/phpcs.xml

lint:
	docker compose run --rm php bash -c "./vendor/bin/phpcs --standard=./tests/phpcs.xml -n"

lint-fix:
	docker compose -f docker-compose.yml -f docker-compose.composer.yml run --rm composer bash -c "./vendor/bin/phpcbf --standard=./tests/phpcs.xml"

lint-no-docker:
	@./vendor/bin/phpcs --standard=./tests/phpcs.xml -n

lint-fix-no-docker:
	@./vendor/bin/phpcbf --standard=./tests/phpcs.xml

reset:
	rm -f bootstrap/cache/packages.php
	rm -f bootstrap/cache/services.php
	docker compose -f docker-compose.yml -f docker-compose.composer.yml run --rm composer bash -c "php artisan package:discover-modules && php artisan package:discover-modules"

# Generate API docs
gen-docs:
	docker compose -f docker-compose.yml -f docker-compose.composer.yml run --rm composer bash -c "php artisan scribe:generate"

# This command use to build and release for [ staging, qa, production ]
release:
	if [[ "$(STAGE)" != "staging" && "$(STAGE)" != "qa" && "$(STAGE)" != "production" ]]; then echo "Bad Stage"; exit 1; fi
	@make build TARGET=production TAG_NAME=$(STAGE)
	docker push $$IMAGE_NAME
	docker push $$CONSOLE_IMAGE_NAME
	serverless deploy --stage $(STAGE)
