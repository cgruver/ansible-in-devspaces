
```bash
mkdir /sys/fs/cgroup/containers
mkdir /sys/fs/cgroup/init
echo 1 > /sys/fs/cgroup/init/cgroup.procs
echo 2 > /sys/fs/cgroup/init/cgroup.procs
echo 6 > /sys/fs/cgroup/init/cgroup.procs
chown -R user:user /sys/fs/cgroup

su - user

/entrypoint.sh

podman --cgroup-manager cgroupfs run -it --rm --systemd=true --cgroup-parent=/containers --name=systemd registry.access.redhat.com/ubi10-init:10.1
```

```bash
cat << EOF | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: run-as-root
priority: null
allowPrivilegeEscalation: true
allowedCapabilities:
- SETUID
- SETGID
- CHOWN
- SETFCAP
fsGroup:
  type: RunAsAny
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: MustRunAs
  seLinuxOptions:
    type: container_engine_t
supplementalGroups:
  type: RunAsAny
userNamespaceLevel: RequirePodLevel
EOF
```

```bash
cat << EOF | oc apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: systemd
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
            - CHOWN
            - SETFCAP
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
cat << EOF | oc apply -f -
kind: Pod
apiVersion: v1
metadata:
  name: systemd
  annotations:
    io.kubernetes.cri-o.Devices: '/dev/fuse,/dev/net/tun'
    openshift.io/scc: container-run
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
        runAsUser: 1000
        readOnlyRootFilesystem: false
        allowPrivilegeEscalation: true
        procMount: Unmasked
      imagePullPolicy: Always
      image: 'nexus.clg.lab:5002/dev-spaces/systemd-test:latest'
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
MACHINE_TYPE=master

cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.20.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${MACHINE_TYPE}
  name: enable-rw-cgroup-${MACHINE_TYPE}
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

```bash
MACHINE_TYPE=master

cat << EOF | butane | oc apply -f -
variant: openshift
version: 4.20.0
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${MACHINE_TYPE}
  name: selinux-patch-audit-log-${MACHINE_TYPE}
storage:
  files:
  - path: /etc/selinux_patch_audit_log.te
    mode: 0644
    overwrite: true
    contents:
      inline: |
        module selinux_patch_audit_log 1.0;
        require {
                type container_engine_t;
                class netlink_audit_socket nlmsg_relay;
        }
        #============= container_engine_t ==============
        allow container_engine_t self:netlink_audit_socket nlmsg_relay;
systemd:
  units:
  - contents: |
      [Unit]
      Description=Modify SeLinux Type container_engine_t
      DefaultDependencies=no
      After=kubelet.service
      
      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=bash -c "/bin/checkmodule -M -m -o /tmp/selinux_patch_audit_log.mod /etc/selinux_patch_audit_log.te && /bin/semodule_package -o /tmp/selinux_patch_audit_log.pp -m /tmp/selinux_patch_audit_log.mod && /sbin/semodule -i /tmp/selinux_patch_audit_log.pp"
      TimeoutSec=0
      
      [Install]
      WantedBy=multi-user.target
    enabled: true
    name: systemd-selinux-patch-audit-log.service
EOF
```
