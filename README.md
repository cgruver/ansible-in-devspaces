
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

```bash
cat << EOF | oc apply -f -
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: dev-workspace-run-as-root
  labels:
    app.kubernetes.io/part-of: che.eclipse.org
rules:
  - verbs:
      - get
      - update
      - use
    apiGroups:
      - security.openshift.io
    resources:
      - securitycontextconstraints
    resourceNames:
      - nested-podman-run-as-root
EOF
```

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
    disableContainerBuildCapabilities: true
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
    user:
      clusterRoles:
      - dev-workspace-run-as-root
  gitServices: {}
  networking: {}   
EOF
```

```bash
cat << EOF | oc apply -f -
apiVersion: controller.devfile.io/v1alpha1
kind: DevWorkspaceOperatorConfig
metadata:
  name: devworkspace-operator-config
  namespace: openshift-operators
config:
  workspace:
    hostUsers: false
    podAnnotations:
      io.kubernetes.cri-o.Devices: "/dev/fuse,/dev/net/tun"
      io.kubernetes.cri-o.cgroup2-mount-hierarchy-rw: 'true'
      openshift.io/scc: nested-podman-run-as-root
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
EOF
```

