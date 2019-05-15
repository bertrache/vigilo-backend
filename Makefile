ENV:=unittest
UID=$(shell id -u)
GID=$(shell id -g)
WWW_DATA_UID=33
FROM=0.0.2
TO=0.0.3
SHUNIT=2.1.7
SCOPE=montpellier
NOW:=$(shell date +'%Y%m%d%H%M%S')
WAIT:=10

# Database information
BKDATE=NODATE

# Get .env parameters
MYSQL_HOST :=$(shell cat .env_${ENV} | grep MYSQL_HOST | cut -d"=" -f2)
MYSQL_ROOT_PASSWORD :=$(shell cat .env_${ENV} | grep MYSQL_ROOT_PASSWORD | cut -d"=" -f2)
MYSQL_DATABASE :=$(shell cat .env_${ENV} | grep MYSQL_DATABASE | cut -d"=" -f2)
MYSQL_INIT_FILE :=$(shell cat .env_${ENV} | grep MYSQL_INIT_FILE | cut -d"=" -f2)
VOLUME_PATH :=$(shell cat .env_${ENV} | grep VOLUME_PATH | cut -d"=" -f2)
ROOT_APP_DIR :=$(shell cat .env_${ENV} | grep ROOT_APP_DIR | cut -d"=" -f2)

all: help

help:
	@grep "##" Makefile | grep -v "@grep"

shunit2:
	wget https://github.com/kward/shunit2/archive/v${SHUNIT}.tar.gz
	tar -xvzf v${SHUNIT}.tar.gz
	ln -s shunit2-${SHUNIT} shunit2
	rm v${SHUNIT}.tar.gz


init-db: ## Init database with unit tests datas
	docker run --rm -ti -v ${PWD}:/data/ python sh -c "pip install docopt ; python /data/scripts/migrateDatabase.py -f ${FROM} -t ${TO} --test"


backup-db: ## Backup a mysql docker container
	docker run --rm -ti -v ${PWD}/backup/mysql:/dump mysql sh -c 'MYSQL_PWD=${MYSQL_ROOT_PASSWORD} mysqldump -h ${MYSQL_HOST} -u root --single-transaction --skip-lock-tables --column-statistics=0 --databases ${MYSQL_DATABASE} > /dump/dump-${NOW}.sql'


restore-db: ## Restore a mysql docker container
	#docker run --rm -ti -v ${PWD}/mysql/dump:/dump mysql sh -c 'mysql -h ${MYSQL_HOST} -u root --password=${MYSQL_ROOT_PASSWORD} ${MYSQL_DATABASE} < /dump/${DBFILE}'
	cp ${PWD}/backup/mysql/dump-${BKDATE}.sql mysql/${MYSQL_INIT_FILE} 

env: ## copy docker-compose -f docker-compose_${ENV}.yml .env environment
		cp .env_${ENV} .env

show-db:  ## Show database content
	docker-compose -f docker-compose_${ENV}.yml exec db sh -c 'mysql -u root --password=$$MYSQL_ROOT_PASSWORD -e "select obs_id,obs_scope,obs_categorie,obs_address_string,obs_app_version,obs_approved,obs_token from obs_list;" ${MYSQL_DATABASE}'


list-bundle: ## list a bundle backups
	@-ls -alh backup/bundle | grep "bundle-" | sed 's/bundle-//' | sed 's/\.tgz//'


backup-bundle: backup-db ## backup database and image files
	tar -cvzf backup/bundle/bundle-${NOW}.tgz backup/mysql/dump-${NOW}.sql app/caches app/images app/maps


restore-bundle: ## Restore a bundle backup
	test -e app/caches && rm -f app/caches/*
	test -e app/images && rm -f app/images/*
	test -e app/maps && rm -f app/maps/*
	tar -xvzf backup/bundle/bundle-${BKDATE}.tgz
	sudo rsync -avr app/caches app/images app/maps ${VOLUME_PATH}/files/
	sudo chown -R ${WWW_DATA_UID} ${VOLUME_PATH}/files/caches ${VOLUME_PATH}/files/images ${VOLUME_PATH}/files/maps
	cp backup/mysql/dump-${BKDATE}.sql mysql/${MYSQL_INIT_FILE}


debug-db: env init-db
	docker-compose -f docker-compose_${ENV}.yml logs --no-color -f db


unittest: env
	docker-compose -f docker-compose_${ENV}.yml up -d
	docker-compose -f docker-compose_${ENV}.yml exec web phpunit -c phpunit.xml


start: env ## Start a docker compose stack
	@docker-compose -f docker-compose_${ENV}.yml up -d
	@echo "Waiting ${WAIT} sec for stating container and restoring database ..."
	@sleep ${WAIT}
	docker-compose -f docker-compose_${ENV}.yml exec web chown 33:33 /var/www/html
	docker-compose -f docker-compose_${ENV}.yml exec web chmod ug+s /var/www/html


test-webserver: shunit2
	cp scripts/${SCOPE}.sh scripts/config.sh
	scripts/testApp.sh ${ENV} ${SCOPE}


stop: env ## Stop a docker stack
	docker-compose -f docker-compose_${ENV}.yml stop


clean: .env ## Clean some files
	-docker-compose -f docker-compose_${ENV}.yml rm -f
	-test -e /data/docker/jsudd-${ENV} && sudo rm -rf /data/docker/jsudd-${ENV}
	-test -e mysql/${MYSQL_INIT_FILE} && sudo rm -rf mysql/${MYSQL_INIT_FILE}


clean-packages: ## Clean some files
	-$(RM) -r shunit2*
