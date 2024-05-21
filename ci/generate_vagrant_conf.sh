#!/bin/bash


declare -A listevagrant
listevagrant=(
["./almalinux/8/Vagrantfile"]="almalinux/8"
["./almalinux/9/Vagrantfile"]="almalinux/9"
["./debian/11/Vagrantfile"]="generic/debian11"
["./fedora/39/Vagrantfile"]="fedora/39-cloud-base"
["./fedora/40/Vagrantfile"]="fedora/40-beta-cloud-base"
["./opensuse-leap/15.4/Vagrantfile"]="opensuse/Leap-15.4.x86_64"
["./opensuse-leap/15.5/Vagrantfile"]="alvistack/opensuse-leap-15.5"
["./ubuntu/22.04/Vagrantfile"]="generic/ubuntu2204"
["./ubuntu/24.04/Vagrantfile"]="bento/ubuntu-24.04"
)

rm -fr ubuntu opensuse-leap fedora debian almalinux

for path in "${!listevagrant[@]}"; do
    directory="$(dirname "$path")"
    rm -fr "$path"
    echo -e "\n$directory\n"
    mkdir -p "$directory"
    cd "$directory" || return 
    vagrant init "${listevagrant[$path]}"
    echo "require '../../VagrantCommonConf.rb'" >> Vagrantfile
    cd ../..
done