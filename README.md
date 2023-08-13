# PMIx Docker Compose

> I am convinced this software is evil in all the ways. I am posting for collective brainstorming.

This is an experiment to learn about PMIx with Docker compose. It is based on the [pmix-swarm-toy-box](https://github.com/jjhursey/pmix-swarm-toy-box).
I am hoping to test this in Docker compose, and then to move into Kubernetes (womp womp)

## Understanding Libraries

 - [openpmix](https://github.com/openpmix/openpmix) This is a "Reference Implementation of the Process Management Interface Exascale (PMIx) standard." I found [these docs](https://docs.openpmix.org/en/latest/) helpful - they want to maintain an open, community maintained "standalone library to support application interactions with Resource Managers (RMs)" that is compatible with PM-1 and PM-2. What are those?
 - [PMI-1](https://flux-framework.readthedocs.io/projects/flux-rfc/en/latest/spec_13.html) is the better design, and the [Flux implementation is here](https://github.com/flux-framework/flux-core/tree/master/src/common/libpmi).
 - [Original wire protocol](https://github.com/pmodels/mpich/blob/7c4361e1ee57b6c3f2c65f49a31a963ba9e6e672/src/pmi/src/pmi_wire.c)

In layman's terms, this project (openmpi) wants to ensure that we have APIs (in HPC) for things like MPI to interact with resource managers. This project wants to ensure, for example, that Flux can easily run MPI across nodes. I've heard feedback that the complexity of PMIx is terrible and it's confusing, so that is bad. But it's worth trying out anyway.

## Images

First, build the docker images. These assume we are using ssh.

```bash
docker build -t pmix:latest .
```

## Cluster

To bring up the cluster:

```bash
$ docker compose up -d
```

Ensure they are running:

```bash
$ docker compose ps
```
```console
NAME                IMAGE               COMMAND               SERVICE             CREATED             STATUS              PORTS
node-1              pmix:latest         "/usr/sbin/sshd -D"   node-1              54 seconds ago      Up 53 seconds       22/tcp
node-2              pmix:latest         "/usr/sbin/sshd -D"   node-2              54 seconds ago      Up 53 seconds       22/tcp
```

### Interaction

<details>

<summary>Failed attempts</summary>

Shell into the first node:

```bash
$ docker exec -it -u mpiuser -w /home/mpiuser --env COLUMNS=`tput cols` --env LINES=`tput lines`  node-1 bash
```

Verify your user:

```bash
[mpiuser@node-1 ~]$ whoami
mpiuser
```

Test running something:

```bash
env | grep PRRTE_MCA_prrte_default_hostfile
PRRTE_MCA_prrte_default_hostfile=/opt/hpc/etc/hostfile.txt
```
```bash
$ mpirun -npernode 2 hostname
```

This is the error I'm at:

```console
PRRTE_MCA_prrte_default_hostfile=/opt/hpc/etc/hostfile.txt
[mpiuser@node-1 ~]$ mpirun -npernode 2 hostname
[node-1:00044] mca_base_component_repository_open: unable to open mca_pmix_ext2x: /usr/lib64/openmpi/lib/openmpi/mca_pmix_ext2x.so: undefined symbol: pmix_value_load (ignored)
[node-1:00044] [[39080,0],0] ORTE_ERROR_LOG: Not found in file ess_hnp_module.c at line 320
--------------------------------------------------------------------------
It looks like orte_init failed for some reason; your parallel process is
likely to abort.  There are many reasons that a parallel process can
fail during orte_init; some of which are due to configuration or
environment problems.  This failure appears to be an internal failure;
here's some additional information (which may only be relevant to an
Open MPI developer):

  opal_pmix_base_select failed
  --> Returned value Not found (-13) instead of ORTE_SUCCESS
--------------------------------------------------------------------------
```

I also tried:

```bash
$ mpirun -N 2 --host node-1,node-2 hostname --enable-orterun-prefix-by-default
```

When I updated the Dockerfile to the current, not I get...

```bash
$ mpirun -N 2 --host node-1,node-2 hostname --enable-orterun-prefix-by-default
Segmentation fault (core dumped)
```

Is that progress? lol! Need to keep trying. Ok next build - I can shell in as root:

</details>

Shell into the main node-1

```bash
docker exec -it node-1 bash
```

It runs for one host:

```bash
$ mpirun -npernode 2 -N 2 -allow-run-as-root hostname
```
```console
node-1
node-1
```

And finally more than one!

```bash
mpirun -npernode 2 -N 2 --hostfile /opt/hpc/etc/hostfile.txt -allow-run-as-root hostname
```
```console
node-1
node-1
node-2
node-2
```

OH LAWD.

## License

The original license (also MIT) is [included](.github/LICENSE).

HPCIC DevTools is distributed under the terms of the MIT license.
All new contributions must be made under this license.

See [LICENSE](https://github.com/converged-computing/cloud-select/blob/main/LICENSE),
[COPYRIGHT](https://github.com/converged-computing/cloud-select/blob/main/COPYRIGHT), and
[NOTICE](https://github.com/converged-computing/cloud-select/blob/main/NOTICE) for details.

SPDX-License-Identifier: (MIT)

LLNL-CODE- 842614
