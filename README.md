# redpesk LocalBuilder installer

This set of two scripts is dedicated to developers.

*install-redpesk-localbuilder.sh* setups a build container on your machine,
this container has all the things you need to perform cross-compilation
for a redpesk embedded target. It can also install other flavours of supported
containers.

*install-redpesk-sdk.sh* installs the redpesk ApplicationFramework build environnement
on your host (ie, the AFB binder, with the needed libraries and header files),
for developers that feel more comfortable with developing in a native development.

```bash
# To configure LXD on your host
./install-redpesk-localbuilder.sh config_host
# To Install the container
./install-redpesk-localbuilder.sh create -c <your_container_name>
```

and follow the instructions.

You will be prompted for your host's root password to perform the installation of LXD

At the end of the script, you will also be asked for an optional host directory that
you want to have to access to within the container.

Depending of your host distribution, you may need to relaunch the script after a reboot or not.

```bash
./install-redpesk-localbuilder.sh clean -c <your_container_name>
```

can be useful when things go bad.

Once the container is created, is is accessible through ssh:

```bash
ssh devel@${container_name}
passwd:*devel*
```

To set the environnement to compile for aarch64, do:

```bash
. /usr/aarch64-linux-gnu/bin/cross-profile-setup-aarch64.sh
```

## Troubleshooting

*Error: TLS certificate*

In case of you encounter follow error message :\
`Error: get "https://download.redpesk.bzh:8443/1.0": tls: failed to verify certificate:x509: certificate has expired or is not yet valid`

Just relaunch installation script with `--clean-remote` option :

```bash
# launch the script
./install-redpesk-localbuilder.sh create -c ${container_name} --clean-remote
```

## Cleans things up

If you want to deletes container and cleans things up, use `clean` action:

```sh
./install-redpesk-localbuilder.sh clean -c ${container_name}
```

