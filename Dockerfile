FROM webdevops/php-apache:alpine-php7

ENV VARNISH_PORT=8080 \
    VARNISH_CONFIG="" \
    VARNISH_STORAGE="malloc,128m" \
    VARNISH_OPTS="" \
    VARNISH_BACKEND_HOST="127.0.0.1" \
    VARNISH_BACKEND_PORT="80"

COPY conf/ /opt/docker/

RUN set -x \
    && apk-install \
        varnish \
    && docker-run-bootstrap \
    && docker-image-cleanup

RUN composer global require hirak/prestissimo

EXPOSE 8080