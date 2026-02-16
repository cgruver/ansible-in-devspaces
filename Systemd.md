
```bash
cat << EOF | oc apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: run-as-root
  annotations:
    io.kubernetes.cri-o.Devices: '/dev/fuse,/dev/net/tun'
    openshift.io/scc: run-as-root
    io.kubernetes.cri-o.cgroup2-mount-hierarchy-rw: 'true'
spec:
  hostUsers: false
  restartPolicy: Always
  containers:
    - resources:
        limits:
          cpu: "1"
          memory: 2Gi
        requests:
          cpu: 100m
          memory: 256Mi
      name: run-as-root
      securityContext:
        capabilities:
          add:
            - SETGID
            - SETUID
          drop:
            - ALL
        runAsUser: 0
        readOnlyRootFilesystem: false
        allowPrivilegeEscalation: true
        procMount: Unmasked
      imagePullPolicy: Always
      image: 'nexus.clg.lab:5002/dev-spaces/systemd-test:latest'
      env:
      - name: HOME
        value: /home/root
      volumeMounts:
        - name: home
          mountPath: /home
  volumes:
    - name: home
      emptyDir: {}
EOF
```

```bash
cat << EOF > systemd.Containerfile
FROM registry.access.redhat.com/ubi10-init:10.1

STOPSIGNAL SIGRTMIN+3

ENV container=oci

USER 0

RUN dnf install -y nginx ; \
    systemctl enable nginx

ENTRYPOINT ["/sbin/init"]
EOF
```

podman run -it --tmpfs /tmp --tmpfs /run --tmpfs /var/log/journal --tmpfs /sys/fs/cgroup --systemd=false --rm --name=systemd-test localhost/systemd:test

## Debugging -

```bash
podman create -it --systemd=always --name=systemd registry.access.redhat.com/ubi10-init:10.1 sh

podman start --attach systemd
```

podman --cgroup-manager=cgroupfs run podman run -it --rm --systemd=true --name=systemd registry.access.redhat.com/ubi10-init:10.1

podman create -it --rm --systemd=always --name=systemd --security-opt=unmask=ALL --cgroups=disabled registry.access.redhat.com/ubi10-init:10.1 sh

podman run --annotation=run.oci.delegate-cgroup=/init -it --rm --systemd=true --name=systemd registry.access.redhat.com/ubi10-init:10.1

```bash
cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.20.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: enable-rw-cgroup
storage:
  files:
  - path: /etc/crio/crio.conf.d/99-cic-systemd
    mode: 0644
    overwrite: true
    contents:
      inline: |
        [crio.runtime.runtimes.crun]
        runtime_root = "/run/crun"
        allowed_annotations = [
          "io.containers.trace-syscall",
          "io.kubernetes.cri-o.Devices",
          "io.kubernetes.cri-o.LinkLogs",
          "io.kubernetes.cri-o.cgroup2-mount-hierarchy-rw",
        ]

EOF
```