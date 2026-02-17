
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