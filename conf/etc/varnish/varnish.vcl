vcl 4.0;

# Default backend definition. Set this to point to your content server.
backend default {
    .host = "<VARNISH_BACKEND_HOST>";
    .port = "<VARNISH_BACKEND_PORT>";
}

sub vcl_hit {
    set req.http.x-cache = "HIT";
}

sub vcl_miss {
    set req.http.x-cache = "MISS";
}

sub vcl_pass {
    set req.http.x-cache = "PASS";
}

sub vcl_pipe {
    set req.http.x-cache = "PIPE";
}

sub vcl_synth {
    set resp.http.x-cache = "SYNTH";
}

sub vcl_recv {
    unset req.http.x-cache;
# Only deal with "normal" types
    if (req.method != "GET" &&
            req.method != "HEAD" &&
            req.method != "PUT" &&
            req.method != "POST" &&
            req.method != "TRACE" &&
            req.method != "OPTIONS" &&
            req.method != "PATCH" &&
            req.method != "DELETE") {
        /* Non-RFC2616 or CONNECT which is weird. */
        return (pass);
    }
# Only cache GET or HEAD requests. This makes sure the POST requests are always passed.
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }
# Some generic URL manipulation, useful for all templates that follow
# First remove the Google Analytics added parameters, useless for our backend
    if (req.url ~ "(\?|&)(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=") {
        set req.url = regsuball(req.url, "&(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "");
        set req.url = regsuball(req.url, "\?(utm_source|utm_medium|utm_campaign|utm_content|gclid|cx|ie|cof|siteurl)=([A-z0-9_\-\.%25]+)", "?");
        set req.url = regsub(req.url, "\?$", "");
    }

# Strip a trailing ? if it exists
    if (req.url ~ "\?$") {
        set req.url = regsub(req.url, "\?$", "");
    }

# Strip hash, server doesn't need it.
    if (req.url ~ "\#") {
        set req.url = regsub(req.url, "\#.*$", "");
    }

    if (req.http.Accept-Encoding) {
# Do no compress compressed files...
        if (req.url ~ "\.(jpg|png|gif|woff2|gz|tgz|bz2|tbz)$") {
            unset req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            unset req.http.Accept-Encoding;
        }
    }
# Remove the "has_js" cookie
    set req.http.Cookie = regsuball(req.http.Cookie, "has_js=[^;]+(; )?", "");

# Remove any Google Analytics based cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__utm.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_ga=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "_gat=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmctr=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmcmd.=[^;]+(; )?", "");
    set req.http.Cookie = regsuball(req.http.Cookie, "utmccn.=[^;]+(; )?", "");

# Remove DoubleClick offensive cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__gads=[^;]+(; )?", "");

# Remove the Quant Capital cookies (added by some plugin, all __qca)
    set req.http.Cookie = regsuball(req.http.Cookie, "__qc.=[^;]+(; )?", "");

# Remove the AddThis cookies
    set req.http.Cookie = regsuball(req.http.Cookie, "__atuv.=[^;]+(; )?", "");

# Remove a ";" prefix in the cookie if present
    set req.http.Cookie = regsuball(req.http.Cookie, "^;\s*", "");

# Are there cookies left with only spaces or that are empty?
    if (req.http.cookie ~ "^\s*$") {
        unset req.http.cookie;
    }
# Allow Let's Encrypt
    if (req.url ~ "^\/.well-known/acme-challenge/") {
        return (pass);
    }
# Do not cache if request backend
    if (req.url ~ "admin-dev") {
        return (pass);
    }
# Do not cache checkout or customer pages ( PHP version )
    if (req.url ~ "(cart|order|addresses|order-detail|order-confirmation|order-return).php") {
        return (pass);
    }
# Do not cache checkout or customer pages ( friendly urls )
    if (req.url ~ "(carrito|pedido|mi-cuenta|datos-personales|direccion|direcciones||historial-compra|facturas-abono|contactenos)") {
        return (pass);
    }
    if (req.url ~ "^[^?]*\.(css|js|jpg|png|gif|woff|woff2)(\?.*)?$") {
        unset req.http.Cookie;
    }
    if (req.http.Authorization || req.http.Authenticate)
    {
        return (pass);
    }
    return (hash);
}

sub vcl_backend_response {
# Avoid Header Expires in the past
    if (beresp.ttl > 0s && (bereq.method == "GET" || bereq.method == "HEAD")) {
        unset beresp.http.set-cookie;
        unset beresp.http.Expires;
        set beresp.ttl = 24h;
        unset beresp.http.Cache-Control;
# Set new Cache-Control headers for browsers to store cache for 7 days
        set beresp.http.Cache-Control = "public, max-age=604800";
        set beresp.http.magicmarker = "1";
        set beresp.http.cachable = "1";
        if (bereq.url !~ "\.(css|js|jpg|png|gif|woff|woff2|html|htm|gz)(\?|$)") {
            set beresp.http.Pragma = "no-cache";
            set beresp.http.Expires = "-1";
            set beresp.http.Cache-Control = "no-store, no-cache, must-revalidate, max-age=0";
            set beresp.grace = 1m;
        }
        return(deliver);
    }
# Sometimes, a 301 or 302 redirect formed via Apache's mod_rewrite can mess with the HTTP port that is being passed along.
# This often happens with simple rewrite rules in a scenario where Varnish runs on :80 and Apache on :8080 on the same box.
# A redirect can then often redirect the end-user to a URL on :8080, where it should be :80.
# This may need finetuning on your setup.
#
# To prevent accidental replace, we only filter the 301/302 redirects for now.
    if (beresp.status == 301 || beresp.status == 302) {
        set beresp.http.Location = regsub(beresp.http.Location, ":[0-9]+", "");
    }

# Don't cache 50x responses
    if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504) {
        return (abandon);
    }

# Allow stale content, in case the backend goes down.
# make Varnish keep all objects for 1 hour beyond their TTL
    set beresp.grace = 1h;

    return (deliver);
}

sub vcl_deliver {
    if (obj.uncacheable) {
        set req.http.x-cache = req.http.x-cache + " UNCACHEABLE" ;
    } else {
        set req.http.x-cache = req.http.x-cache + " CACHED" ;
    }
# Response with cache result
    set resp.http.x-cache = req.http.x-cache;
# Remove some headers: PHP version
    unset resp.http.X-Powered-By;
# Remove some headers: Apache version & OS
    unset resp.http.Server;
# Remove some heanders: Varnish
    unset resp.http.Via;
}

