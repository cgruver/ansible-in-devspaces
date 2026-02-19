# Experimental project for enabling systemd containers in OpenShift Dev Spaces

__Note:__ The manifests for creating the container image used in this workspace are located in the `root-workspace-image` directory.

## Apply the following MachineConfig to enable RW cgroups

```bash
# For Control-Plane nodes -
# MACHINE_TYPE=master

# For Compute Nodes -
# MACHINE_TYPE=worker

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

## Create an SCC to allow workspaces to run as root mapped to a user namespace

```bash
cat << EOF | oc apply -f -
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: nested-podman-run-as-root
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

## Install OpenShift Dev Spaces

```bash
cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: devspaces
  namespace: openshift-operators
spec:
  channel: stable 
  installPlanApproval: Automatic
  name: devspaces 
  source: redhat-operators 
  sourceNamespace: openshift-marketplace 
EOF
```

Create the Dev Spaces cluster

```bash
cat << EOF | oc apply -f -
apiVersion: v1                      
kind: Namespace                 
metadata:
  name: devspaces
---           
apiVersion: org.eclipse.che/v2 
kind: CheCluster   
metadata:              
  name: devspaces  
  namespace: devspaces
spec:                         
  components:                  
    cheServer:      
      debug: false
      logLevel: INFO
    metrics:                
      enable: true
    pluginRegistry:
      openVSXURL: https://open-vsx.org
    devfileRegistry:
      disableInternalRegistry: true 
  containerRegistry: {}      
  devEnvironments:       
    startTimeoutSeconds: 600
    secondsOfRunBeforeIdling: -1
    maxNumberOfWorkspacesPerUser: -1
    maxNumberOfRunningWorkspacesPerUser: 5
    disableContainerRunCapabilities: false
    security:
      podSecurityContext:
        fsGroup: 0
        runAsNonRoot: false
        runAsUser: 0
    containerRunConfiguration:
      openShiftSecurityContextConstraint: nested-podman-run-as-root
      containerSecurityContext:
        allowPrivilegeEscalation: true
        procMount: Unmasked
        runAsUser: 0
        runAsNonRoot: false
        fsGroup: 0
        capabilities:
          add:
          - SETGID
          - SETUID
          - CHOWN
          - SETFCAP
      workspacesPodAnnotations:
        io.kubernetes.cri-o.Devices: "/dev/fuse,/dev/net/tun"
        io.kubernetes.cri-o.cgroup2-mount-hierarchy-rw: 'true'
    defaultComponents:
    - name: dev-tools
      container:
        image: quay.io/cgruver0/che/dev-tools:latest
        memoryLimit: 6Gi
        mountSources: true
    defaultEditor: che-incubator/che-code/latest
    defaultNamespace:
      autoProvision: true
      template: <username>-devspaces
    secondsOfInactivityBeforeIdling: 1800
    storage:
      pvcStrategy: per-workspace
  gitServices: {}
  networking: {}   
EOF
```

## Create a workspace from this repo

## Run a container with systemd

```bash
podman run -d --name=systemd registry.access.redhat.com/ubi10-init:10.1
```

## Build and run a container that enables Nginx with systemd

```bash
podman build -t systemd:nginx ./systemd-test-image

podman run -d -p 8080:80 --name=nginx systemd:nginx
```
