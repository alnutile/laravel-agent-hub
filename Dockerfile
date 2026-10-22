FROM composer:2 AS composer
FROM php:8.4-apache AS app
RUN apt-get update && apt-get install -y --no-install-recommends libonig-dev libsqlite3-dev libicu-dev unzip \
    && docker-php-ext-install pdo_sqlite mbstring intl pcntl \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
WORKDIR /var/www/html
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --no-interaction --prefer-dist
COPY . .
RUN composer dump-autoload --no-dev --optimize \
    && chown -R www-data:www-data storage bootstrap/cache
COPY ops/apache.conf /etc/apache2/sites-available/000-default.conf
EXPOSE 80
CMD ["apache2-foreground"]
