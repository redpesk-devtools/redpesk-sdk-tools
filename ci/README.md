# Vagrant CI

This directory contains the infrastructure used to regression test the installer
script using Vagrant. This allows to easily setup multiple virtual machine test
environments to validate the script.

Below are instructions to run the full set of tests or to develop the script in
this environment.

## How to setup your Vagrant CI

### Host setup

You will need to install Vagrant from https://www.vagrantup.com/ as well as
VirtualBox (used as a Vagrant provider).

This setup has been tested with Vagrant 2.2.14 and VirtualBox 6.1.16 on Fedora
33.

### Select your OS

```bash
OS=ubuntu_22.04
OS=ubuntu_24.04

OS=debian_11
OS=debian_12

OS=opensuse_15.6
OS=opensuse_15.5

OS=fedora_40
OS=fedora_41
OS=fedora_42
```

### Quick test/regression testing

For a quick test or to run the tests, just do:

```bash
cd ${OS_FAMILY}/${OS}
vagrant up
```

This will create a virtual machine, configure it with the `install-redpesk-localbuilder.sh` script and run the
associated tests.

### Init your Vagrant virtual machine

```bash
cd ${OS_FAMILY}/${OS}
vagrant up --no-provision
#Save your initial state via a VM snapshot
vagrant snapshot save ${OS}
```

### Execute your test

In one command line execute your test

```bash
vagrant provision
```

### Clean up your mess

This will reset all your changes and restore the VM to a clean state, before any
configuration was done.

```bash
vagrant snapshot restore ${OS}
vagrant halt
```

The VM will still be there if needed, bring it up w/ `vagrant up` again.

### Debug your Vagrant CI

You can easily debug your Vagrant CI with the command:

```bash
vagrant ssh
```

This logs you into the VM as the `vagrant` user, which has passwordless sudo rights.

### Clean everything

```bash
vagrant destroy
```

At this point, the VM is gone and can be recreated with `vagrant up`.
