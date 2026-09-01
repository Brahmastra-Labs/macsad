FROM ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

COPY --from=logos-runtime --chmod=0555 largo /usr/local/bin/largo
COPY --from=gateway-source --chmod=0444 . /opt/macsad/gateway

WORKDIR /opt/macsad/gateway
USER 65532:65532
ENTRYPOINT ["/usr/local/bin/largo"]
CMD ["serve"]
