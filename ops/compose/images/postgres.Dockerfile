FROM postgres:16.15-bookworm@sha256:bb3e1a57e5407e0a5280b4211980a5e537f4abd234a87014ac979849a78dd825

COPY --chmod=0555 postgres/010-bootstrap-macsad.sh /docker-entrypoint-initdb.d/010-bootstrap-macsad.sh
COPY --chmod=0444 postgres/010-bootstrap-macsad.sql /opt/macsad/bootstrap/010-bootstrap-macsad.sql
COPY --chmod=0555 run-migrations.sh /opt/macsad/run-migrations.sh
COPY --from=database-source --chmod=0444 . /opt/macsad/database
