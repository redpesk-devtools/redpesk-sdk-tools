#!/bin/bash


declare -A listevagrant
listevagrant=(["./debian/10/Vagrantfile"]="generic/debian10"
["./fedora/33/Vagrantfile"]="generic/fedora33"
["./fedora/34/Vagrantfile"]="generic/fedora34"
["./opensuse-leap/15.2/Vagrantfile"]="opensuse/Leap-15.2.x86_64"
["./opensuse-leap/15.3/Vagrantfile"]="opensuse/Leap-15.3.x86_64"
["./ubuntu/18.04/Vagrantfile"]="generic/ubuntu2004"
["./ubuntu/20.04/Vagrantfile"]="generic/ubuntu2004"
["./ubuntu/21.04/Vagrantfile"]="generic/ubuntu2010"
)

rm -fr ubuntu opensuse-leap fedora debian

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