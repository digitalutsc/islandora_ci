#!/bin/bash
echo "Setup database for Drupal"
mysql -h 127.0.0.1 -P 3306 -u root -e "CREATE USER 'drupal'@'%' IDENTIFIED BY 'drupal'; GRANT ALL PRIVILEGES ON drupal.* To 'drupal'@'%'; FLUSH ALL PRIVILEGES;"

echo "Install utilities needed for testing"
mkdir /opt/utils
cd /opt/utils
if [ -z "$COMPOSER_PATH" ]; then
  composer require drupal/coder 8.3.13 # 8.3.14 breaks, see https://www.drupal.org/project/coder/issues/3262291 
  composer require sebastian/phpcpd ^6
else
  php -dmemory_limit=-1 $COMPOSER_PATH require drupal/coder 8.3.13 # 8.3.14 breaks, see https://www.drupal.org/project/coder/issues/3262291 
  php -dmemory_limit=-1 $COMPOSER_PATH require sebastian/phpcpd ^6
fi
sudo ln -s /opt/utils/vendor/bin/phpcs /usr/bin/phpcs
sudo ln -s /opt/utils/vendor/bin/phpcpd /usr/bin/phpcpd
phpenv rehash
phpcs --config-set installed_paths /opt/utils/vendor/drupal/coder/coder_sniffer

echo "Composer install drupal site"
if [ -z "$DRUPAL_VERSION" ]; then
   # Just fail if we don't set a version
   echo "DRUPAL_VERSION is not set, exiting"
   exit 1
fi
cd /opt
composer create-project drupal/recommended-project:$DRUPAL_VERSION drupal
cd drupal
if [ -z "$COMPOSER_PATH" ]; then
  composer install
else
  php -dmemory_limit=-1 $COMPOSER_PATH install
fi

composer require "drupal/core-dev:$DRUPAL_VERSION"
DRUPAL_MAJOR=$(echo "$DRUPAL_VERSION" | cut -d. -f1)
if [ $DRUPAL_MAJOR -ge 9 ]; then
  # XXX: 9.4.x-dev installs phpunit 8... but then we expect to have to install 
  # the phpspec/prophecy-phpunit:^2 thing, which only works with phpunit 9.
  composer require -W phpunit/phpunit:^9
  composer require phpspec/prophecy-phpunit:^2 drush/drush
elif [ $DRUPAL_MAJOR -eq 8 ]; then
  composer require drush/drush:^10
elif [ $DRUPAL_MAJOR -eq 7 ]; then
  composer require drush/drush:^8
else
  echo "Unmapped major version of Drupal: $DRUPAL_MAJOR"
  exit 1
fi

echo "Setup Drush"
sudo ln -s /opt/drupal/vendor/bin/drush /usr/bin/drush
phpenv rehash

echo "Drush setup drupal site"
cd web
drush si --db-url=mysql://drupal:drupal@127.0.0.1:3306/drupal --yes
drush runserver 127.0.0.1:8282 &
until curl -s 127.0.0.1:8282; do true; done > /dev/null
echo "Enable simpletest module"
drush --uri=127.0.0.1:8282 en -y simpletest

# Install pdfjs
cd /opt/drupal
if [ -z "$COMPOSER_PATH" ]; then
  composer require "zaporylie/composer-drupal-optimizations:^1.0" "drupal/pdf:1.x-dev"
else
  php -dmemory_limit=-1 $COMPOSER_PATH require "zaporylie/composer-drupal-optimizations:^1.0" "drupal/pdf:1.x-dev"
fi

cd web
mkdir libraries
cd libraries
wget "https://github.com/mozilla/pdf.js/releases/download/v2.0.943/pdfjs-2.0.943-dist.zip"
mkdir pdf.js
unzip pdfjs-2.0.943-dist.zip -d pdf.js
rm pdfjs-2.0.943-dist.zip

cd ..
drush -y en pdf
