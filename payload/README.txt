Docker for Mavericks
====================

A 10.9-compatible Docker toolchain: the docker CLI, Compose, Machine, LazyDocker,
and a pinned boot2docker.iso, plus a background auto-updater. Installed by this
package; the docker daemon itself runs inside a Linux VM.

Installed layout
----------------
  /usr/local/bin/docker            docker CLI
  /usr/local/bin/docker-compose    Compose (also: `docker compose`)
  /usr/local/bin/docker-machine    Machine (creates/controls the VM host)
  /usr/local/bin/lazydocker        terminal UI for Docker
  /usr/local/bin/docked            one-off-container convenience wrapper
  /usr/local/share/mavericks-docker/boot2docker.iso    the VM image

The binaries are self-contained (legacy-support is linked in statically); there is
no dylib to install.

First-time setup
----------------
1. Install VMware Fusion (the VM that runs the Docker daemon on 10.9).

2. Create the Docker host from the bundled image, and wire your shell to it:

   docker-machine create -d vmwarefusion \
     --vmwarefusion-boot2docker-url /usr/local/share/mavericks-docker/boot2docker.iso \
     default \
   && if ! grep -q DOCKER ~/.bash_profile 2>/dev/null; then \
        printf '\neval "$(docker-machine env default)"\n' >> ~/.bash_profile; fi \
   && eval "$(docker-machine env default)"

Everyday commands
-----------------
  docker-machine start | stop | restart | status | ip     control the VM host
  docker build -t NAME DIR                                 build an image
  docker run --rm -it IMAGE CMD                            run a container
  docked IMAGE CMD                                         same, $PWD -> /work/
  lazydocker                                               TUI dashboard
  docker compose up                                        Compose

Updating the VM image
---------------------
boot2docker.iso is the VM's read-only boot CD: `docker-machine create` COPIES it into the
host's own dir (~/.docker/machine/machines/<name>/), and the VM boots that copy every start.
Your images/containers/volumes live on a SEPARATE data disk, not on the iso.

So a package update refreshes /usr/local/share/mavericks-docker/boot2docker.iso, but an EXISTING
host keeps its old copy. After an update the updater OFFERS to roll your host(s) onto the new
image; you can also trigger that anytime:

   mavericks-docker-sync-image        # offers to upgrade any host on an older image

or do it by hand (data disk preserved):

   docker-machine stop default && docker-machine upgrade default && docker-machine start default

(or `docker-machine rm default` and re-create). A brand-new `create` already uses the newest iso.

Notes
-----
- The VM appears in VMware Fusion as "default"; adjust CPU/RAM in its Settings.
- The auto-updater checks daily and offers new releases via Sparkle.
- boot2docker.iso is built from https://github.com/dragonflylee/boot2docker/
