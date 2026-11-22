# The math factory image: the pinned LOGOS toolchain (`largo`) and the compiled factory, nothing else.
#
# One image serves every role (the factory's LOGOS source under /opt/macsad/factory, run by `largo`) — `factory coordinator`, `verifier`, `worker`, `local`, `ingest` — chosen
# by the command. A contributor's worker needs no Lean and no database: statements arrive as LOGOS
# documents from the coordinator, proofs are LOGOS, and the LOGOS kernel inside `largo` checks them.
#
# Build the binaries first with `ops/factory/build.sh` (it pins them in bin/toolchain.receipt.json).
# Ubuntu 24.04 matches the glibc the binaries are linked against on the build host.
FROM ubuntu:24.04@sha256:9c7f200c07e3d4a03e7249d2c16bf66a51120fb876aa2242cf31451412543289

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tini \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 10001 macsad \
 && useradd --system --uid 10001 --gid macsad --home-dir /var/lib/macsad --create-home --shell /usr/sbin/nologin macsad

COPY bin/largo /usr/local/bin/largo
COPY factory-entry.sh /usr/local/bin/factory
COPY bin/factory /opt/macsad/factory
COPY bin/toolchain.receipt.json /opt/macsad/toolchain.receipt.json
RUN chmod 0755 /usr/local/bin/largo /usr/local/bin/factory \
 && chmod -R a-w,a+rX /opt/macsad \
 && chown -R macsad:macsad /var/lib/macsad

ENV MACSAD_LARGO=/usr/local/bin/largo \
    HOME=/var/lib/macsad \
    MACSAD_WORK=/var/lib/macsad/work \
    MACSAD_RESULTS_DIR=/var/lib/macsad/results \
    LOGOS_HOST=0.0.0.0 \
    PORT=8080

USER macsad:macsad
WORKDIR /var/lib/macsad
VOLUME ["/var/lib/macsad"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/factory"]
CMD ["worker"]
