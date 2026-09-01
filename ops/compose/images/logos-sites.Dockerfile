FROM nginxinc/nginx-unprivileged:1.30.4-alpine3.24@sha256:45ce1e2e699234253d1def7baa96218a5d00b498d1ba0cbb1a17b6bdf73d1351

COPY nginx/sites.conf /etc/nginx/conf.d/default.conf
COPY --from=admin-bundle --chmod=0444 . /usr/share/nginx/html/admin
COPY --from=public-bundle --chmod=0444 . /usr/share/nginx/html/public
