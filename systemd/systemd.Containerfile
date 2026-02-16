FROM registry.access.redhat.com/ubi10-init:10.1

STOPSIGNAL SIGRTMIN+3

ENV container=oci

USER 0

RUN dnf install -y nginx ;     systemctl enable nginx

ENTRYPOINT ["/sbin/init"]
