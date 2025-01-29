#!/bin/bash

SUPPORTED_DISTROS="Ubuntu 22.04, Ubuntu 24.04, Linux Mint 21, OpenSUSE Leap 15.6, OpenSUSE Leap 15.5, Fedora 40, Fedora 41, Debian 11, Debian 12, AlmaLinux 8, AlmaLinux 9"

function usage {
    echo -e "Starts $SUPPORTED_DISTROS virtual machines, runs their configured provisionners and shuts them down\n
            -v | --vm-path <VMpath>:\t Start the VM contained in the VMpath, run its configured provisionners and shut it down\n
            -d | --destroy:\t Destroy the VM after being shut down\n
            -h | --help:\t Display help\n"
    exit
}

script_dir="$(dirname "$(readlink -f "$0")")"


LISTPATH_DEFAULT=" \
                    almalinux/8/ \
                    almalinux/9/ \
                    fedora/40/ \
                    fedora/41/ \
                    debian/11/ \
                    debian/12/ \
                    ubuntu/22.04/ \
                    ubuntu/24.04/ \
                    linuxmint/v21/ \
                    opensuse-leap/15.6/ \
                    opensuse-leap/15.5/ \
                    "

LISTPATH=""
DESTROY_AFTER="n"

error_message () {
	echo "Your distribution, $PRETTY_NAME, is not supported. Supported distribution are $SUPPORTED_DISTROS. For more information, please check https://docs.redpesk.bzh/"
}

BRANCH="upstream"

#test arguments
while [[ $# -gt 0 ]]; do
    OPTION="$1"
    case $OPTION in
    -h | --help)
        usage;
    ;;
    -d | --destroy)
        DESTROY_AFTER="y"
        shift 1;
    ;;
    -b | --branch)
        BRANCH="$2"
        shift 2;
    ;;
    -v | --vm-path)
        if [ -z $2 ]; then 
            echo "No parameter for option --vm-path"
            usage
            exit 1
        fi
        LISTPATH="${LISTPATH} $2"
        shift 2;
    ;;
    *)
        usage;
    ;;
    esac
done

if [ -z "${LISTPATH}" ]; then
    LISTPATH="${LISTPATH_DEFAULT}"
fi

#function that runs all VMs from listepath
run_all_test(){   
    for path in ${LISTPATH}; do
        run_one_test "${script_dir}/${path}"
    done
}

run_one_test(){
    cd "$1" || exit
    vagrant up --no-provision
    if [ -n "${BRANCH}" ]; then
        echo "BRANCH=${BRANCH}" > ../../test_SDK_var.sh
        vagrant provision --provision-with test-sdk-script,test-sdk-VAR-script,install-redpesk-sdk
    else
        vagrant provision --provision-with test-sdk-script,install-redpesk-sdk
    fi
    vagrant halt
    if [ "$DESTROY_AFTER" = "y" ]; then
        vagrant destroy -f
    fi
    cd ../..
}

run_all_test