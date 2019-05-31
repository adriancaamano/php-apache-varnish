#!/usr/bin/env bash

includeScriptDir "/opt/docker/bin/service.d/varnish.d/"

rm -f /var/run/varnishd/varnishd.pid

echo " Starting varnishd..."
echo "     listening on: 0.0.0.0:${VARNISH_PORT}"
echo "      config file: ${VARNISH_CONFIG}"
echo "          backend: ${VARNISH_BACKEND_HOST}:${VARNISH_BACKEND_PORT}"
echo "          storage: ${VARNISH_STORAGE}"
echo "    varnishd opts: ${VARNISH_OPTS}"
echo ""

exec /usr/sbin/varnishd -j unix,user=varnish -F \
    -a "0.0.0.0:${VARNISH_PORT}" \
    -f "$VARNISH_CONFIG" \
    -s "$VARNISH_STORAGE" \
    $VARNISH_OPTS