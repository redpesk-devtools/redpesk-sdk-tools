# redpesk CI tools installer

This set of two scripts is dedicated to developers.

*install-redpesk-cli.sh*

installs the redpesk command line (rp-cli) on your host.
Full redpesk CLI documentation is available on [https://docs.redpesk.bzh](
https://docs.redpesk.bzh/docs/en/master/redpesk-factory/rp_cli/0_introduction.html) section `redpesk factory / redpesk command line interface`.

*install-redpesk-localbuilder.sh* (**DEPRECATED** script)

setups a build container on your machine. This container has all the things you
need to perform cross-compilation for a redpesk embedded target. It can also install other flavours of supported containers.

> Note that LXC localbuilder container type is now replaced by OCI (docker/podman) container type, please refer to online documentation on [https://docs.redpesk.bzh](https://docs.redpesk.bzh/docs/en/master/redpesk-factory/local_builder/docs/1_installation.html) section `redpesk factory / Local builder`.

