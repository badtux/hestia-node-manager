#=========================================================================#
# Default Hestia Node Manager Proxy Template (HTTP)                       #
# Template Name: HestiaNode.tpl                                           #
#=========================================================================#

server {
    listen      %ip%:%proxy_port%;
    server_name %domain_idn% %alias_idn%;

    include %home%/%user%/conf/web/%domain%/nginx.forcessl.conf*;

    # Error pages
    location /error/ {
        alias %home%/%user%/web/%domain%/document_errors/;
    }

    # Deny access to hidden files/directories except ACME challenges
    location ~ /\.(?!well-known\/|file) {
        deny all;
        return 404;
    }

    # Fallback definition if backend is used
    location @fallback {
        proxy_pass http://%ip%:%web_port%;
    }

    # Hestia Node Manager reverse proxy include
    include /etc/hestia-node-manager/nginx/%user%_%domain%.conf*;

    # Hestia per-domain custom Nginx directives
    include %home%/%user%/conf/web/%domain%/nginx.conf_*;
}
