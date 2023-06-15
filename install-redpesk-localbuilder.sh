#!/bin/bash
###########################################################################
# Copyright (C) 2020-2023 IoT.bzh
#
# Authors:   Thierry Bultel <thierry.bultel@iot.bzh>
#            Ronan Le Martret <ronan.lemartret@iot.bzh>
#            Vincent Rubiolo <vincent.rubiolo@iot.bzh>
#            Valentin Lefebvre <valentin.lefebvre@iot.bzh>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###########################################################################

set -e
set -o pipefail
#set -x

function usage {
    printf "Usage: \n\
        %s config_host\t Install and configure LXC/LXD on your host\n\
        %s create -c <container_name>\tcreates container\n\
        %s clean -c <container_name>\tdeletes container and cleans things up\n\
        \n\
        -c|--container-name\t: give the container name\n\
        -t|--container-type\t: container type to install [localbuilder|cloud-publication] (default: ${CONTAINER_TYPE_DEFAULT})\n\
        -i|--container-image\t: image name of the container to use \n\
                                    (default for container-type 'localbuilder': ${CONTAINER_LB_IMAGE_DEFAULT})\n\
                                    (default for container-type 'cloud-publication': ${CONTAINER_CP_IMAGE_DEFAULT})\n\
        -f|--container-file\t: Do not use image from pool but a local *.tar.gz image file\n\
        -s|--lxd-storage-pool\t: give a specific LXD storage pool to use (default: ${STORAGE_POOL_NAME_DEFAULT})\n\
        -r|--remote-name\t: LXD remote name to use (default: ${IMAGE_REMOTE})\n\
        -u|--remote-url\t\t: LXD remote URL to use (default: ${IMAGE_STORE})\n\
        -a|--non-interactive\t: run the script in non-interactive mode\n\
        \n\
        %s --help\t\t\tdisplays this text\n" "$0" "$0" "$0" "$0"
    exit
}

# redmine #4550: execute sudo with user environment set (example: http_proxy)
function sudo { command sudo -E "$@"; }

GREEN="\e[92m"
RED="\e[31m"
BOLD="\e[1m"
NORMAL="\e[0m"

IMAGE_REMOTE="iotbzh"
IMAGE_STORE="download.redpesk.bzh"
IMAGE_STORE_PASSWD="iotbzh"

declare -A SUPPORTED_FEDORA
declare -A SUPPORTED_DEBIAN
declare -A SUPPORTED_UBUNTU
declare -A SUPPORTED_LINUXMINT
declare -A SUPPORTED_OPENSUSE

SUPPORTED_FEDORA["36"]="True"
SUPPORTED_FEDORA["37"]="True"
SUPPORTED_FEDORA["38"]="True"
SUPPORTED_DEBIAN["11"]="True"
SUPPORTED_UBUNTU["20.04"]="True"
SUPPORTED_UBUNTU["22.04"]="True"
SUPPORTED_LINUXMINT["21"]="True"
SUPPORTED_OPENSUSE["15.3"]="True"
SUPPORTED_OPENSUSE["15.4"]="True"
SUPPORTED_OPENSUSE["15.5"]="True"

CONTAINER_USER=devel
#CONTAINER_GRP=devel
CONTAINER_UID=$(id -u)
CONTAINER_GID=$(id -g)

PROFILE_NAME="redpesk"
STORAGE_POOL_NAME=""
STORAGE_POOL_NAME_DEFAULT="default"
CONTAINER_NAME=""
CONTAINER_TYPE=""
CONTAINER_TYPE_DEFAULT="localbuilder"
CONTAINER_IMAGE=""
CONTAINER_FILE=""

CONTAINER_LB_IMAGE_DEFAULT="redpesk-builder/arz-1.0-update"
CONTAINER_CP_IMAGE_DEFAULT="redpesk-cloud-publication"
CONTAINER_DM_IMAGE_DEFAULT="redpesk-demo"
CONTAINER_DB_IMAGE_DEFAULT="redpesk-demo-builder/arz"

# List of supported container types.
declare -A CONTAINER_FLAVOURS
CONTAINER_FLAVOURS=( ["localbuilder"]="${CONTAINER_LB_IMAGE_DEFAULT}" \
                     ["cloud-publication"]="${CONTAINER_CP_IMAGE_DEFAULT}" \
                     ["redpesk-demo"]="${CONTAINER_DM_IMAGE_DEFAULT}" \
                     ["redpesk-demo-builder"]="${CONTAINER_DB_IMAGE_DEFAULT}" )

DEFAULT_CNTNR_DIR=${HOME}/my_rp_builder_dir
INTERACTIVE="yes"

#The Ip of the container will be set after the "launch" of the container
MY_IP_ADD_RESS=""
LXC=""
LXD=""

[[ "$LXC_DEBUG" == "1" ]] && LXC_DEBUG_OPT="--debug" || LXC_DEBUG_OPT=""

# shellcheck disable=SC1091
source /etc/os-release

while [[ $# -gt 0 ]];do
    key="$1"
    case $key in
    -c|--container-name)
        CONTAINER_NAME="$2";
        shift 2;
    ;;
    -t|--container-type)
        CONTAINER_TYPE="$2";
        shift 2;
    ;;
    -i|--container-image)
        CONTAINER_IMAGE="$2";
        shift 2;
    ;;
    -f|--container-file)
        CONTAINER_FILE="$2";
        shift 2;
    ;;
    -s|--lxd-storage-pool)
        STORAGE_POOL_NAME="$2";
        shift 2;
    ;;
    -r|--remote-name)
        IMAGE_REMOTE="$2";
        shift 2;
    ;;
    -u|--remote-url)
        IMAGE_STORE="$2";
        shift 2;
    ;;
    -a|--non-interactive)
        INTERACTIVE="no";
        shift;
    ;;
	-m|--map-user)
		# advanced usage (not documented)
        # -m|--map-user: map the specified user (inside container) to the current user (default: ${CONTAINER_USER})
		CONTAINER_USER="$2";
		shift 2;
	;;
    -h|--help)
        usage;
    ;;
    *)
        if [ -z "${MAIN_CMD}" ]; then
            MAIN_CMD="$key";
        else
            echo -e "${RED}Error${NORMAL}: unknown argument '$key'"
            usage;
        fi
        shift;
    ;;
    esac
done

if [ -z "${CONTAINER_TYPE}" ]; then
    CONTAINER_TYPE="${CONTAINER_TYPE_DEFAULT}"
fi

if [ -n "${CONTAINER_IMAGE}" ]; then
    CONTAINER_FLAVOURS[$CONTAINER_TYPE]="${CONTAINER_IMAGE}"
fi

function get_os_var_version_id() {
    grep ^VERSION_ID= /etc/os-release || grep ^DISTRIB_RELEASE= /etc/lsb-release
}

function error() {
    echo "FAIL: $*" >&2
}

function debug() {
    echo "DEBUG: $*" >&2
}

function check_user {
    if [ "$(id -u)" == "0" ]; then
        echo -e "Some of the installation must not be run as root"
        echo -e "please execute as normal user, you will prompted for root password when needed"
        exit
    fi
}

function check_lxc {
    #Debian Fix: On the first run "/snap/bin" is, perhaps, not in PATH
    PATH="${PATH}:/snap/bin"
    LXC="$(which lxc)" || echo "No lxc on this host"
    if [ -z "${LXC}" ];then
            echo "Error: No LXC installed"
            exit 1
    else
        LXC="sudo ${LXC}"
    fi
}

function check_lxd {
    #Debian Fix: On the first run "/snap/bin" is, perhaps, not in PATH
    PATH="${PATH}:/snap/bin"
    LXD="$(which lxd)" || echo "No lxd on this host"
    if [ -z "${LXD}" ];then
            echo "Error: No LXD installed"
            exit 1
    else
        LXD="sudo ${LXD}"
    fi
}

function check_distribution {
    echo "Detected host distribution: ${ID} version ${VERSION_ID}"
    case ${ID} in
    ubuntu)
        if [[ ! ${SUPPORTED_UBUNTU[${VERSION_ID}]} == "True" ]];then
            echo -e "Unsupported version of distribution: ${ID}"
            exit 1
        fi
        ;;
    linuxmint)
        if [[ ! ${SUPPORTED_LINUXMINT[${VERSION_ID}]} == "True" ]];then
            echo -e "Unsupported version of distribution: ${ID}"
            exit 1
        fi
        ;;
    debian)
        if [[ ! ${SUPPORTED_DEBIAN[${VERSION_ID}]} == "True" ]];then
            echo -e "Unsupported version of distribution: ${ID}"
            exit 1
        fi
        ;;
    fedora)
        if [[ ! ${SUPPORTED_FEDORA[${VERSION_ID}]} == "True" ]];then
            echo -e "Unsupported version of distribution: ${ID}"
            exit 1
        fi
        ;;
    opensuse-leap)
        if [[ ! ${SUPPORTED_OPENSUSE[${VERSION_ID}]} == "True" ]];then
            echo -e "Unsupported version of distribution: ${ID}"
            exit 1
        fi
        ;;
    manjaro)
        ;;
    *)
        echo "${ID} is not a supported distribution, ask IoT.bzh team for support!"
        exit 1
        ;;
    esac
}


function check_container_file {
    if [ ! -z "${CONTAINER_FILE}" ]; then
        #test if the file really exist
        if [ ! -f "${CONTAINER_FILE}" ]; then
            echo "ERROR: can't find file ${CONTAINER_FILE}"
        fi
        CONTAINER_ALIAS=$(basename "${CONTAINER_FILE}" | rev | cut -d"_" -f2- | rev)
        IMAGE_REMOTE="local"

        #Check if the image is already install
        if lxc image list | grep -q "${CONTAINER_ALIAS}" ; then
            lxc image delete "${CONTAINER_ALIAS}"
        fi

        ${LXC} image import "${CONTAINER_FILE}" --alias "${CONTAINER_ALIAS}"

        CONTAINER_FLAVOURS[$CONTAINER_TYPE]="${CONTAINER_ALIAS}"

    fi

}


function check_container_name_and_type {
    if [ -z "${CONTAINER_NAME}" ]; then
        echo -e "${RED}Error${NORMAL}: no container name given"
        echo -e "Please specify a container name (eg: 'redpesk-builder')"
        usage
    fi
    RESULT=$(echo "${CONTAINER_NAME}" | grep -E '^[[:alnum:]][-[:alnum:]]{0,61}[[:alnum:]]$') || RESULT=""
    if [ -z "${RESULT}" ] ; then
        echo -e "${RED}Error${NORMAL}: Invalid instance Name \"${RESULT}\" can only contain alphanumeric and hyphen characters"
        exit 1
    fi

    TYPE_MATCH="0"
    for CTYPE in "${!CONTAINER_FLAVOURS[@]}"; do
        if [[ "$CONTAINER_TYPE" == "$CTYPE" ]]; then
            TYPE_MATCH="1"
        fi
    done
    if [[ "$TYPE_MATCH" == 0 ]]; then
        echo -e "${RED}Error${NORMAL}: invalid container type $CONTAINER_TYPE!"
        echo -e -n "Supported types are: "
        for CTYPE in "${!CONTAINER_FLAVOURS[@]}"; do
            echo -n "$CTYPE "
        done
        echo
        exit 1
    fi
}

function clean_subxid {
    echo "cleaning your /etc/subuid /etc/subgid files"

    sudo sed -i -e "/^${USER}:${CONTAINER_UID}:1/d" -e "/^root:100000:65536/d" -e "/^root:${CONTAINER_UID}:1/d" /etc/subuid
    sudo sed -i -e "/^${USER}:${CONTAINER_GID}:1/d" -e "/^root:100000:65536/d" -e "/^root:${CONTAINER_GID}:1/d" /etc/subgid
}

function clean_hosts {
    echo "cleaning your ${CONTAINER_NAME} in your /etc/hosts file"
    sudo sed -i -e "/${CONTAINER_NAME}$/d" -e "/${CONTAINER_NAME}-${USER}$/d" /etc/hosts
}

function clean_lxc_container {
    echo "Clean Lxc container"
    clean_subxid /dev/null 2>&1
    clean_hosts /dev/null 2>&1
    choice=""
    if ${LXC} list -cn --format csv | grep -q -w "^${CONTAINER_NAME}$" ; then
        if [ "${INTERACTIVE}" == "yes" ]; then
            read -r -p "Container ${CONTAINER_NAME} exists and will be destroyed, are you sure ? [Y/n]" choice
        fi
        if [ -z "${choice}" ]; then
            choice="y"
        fi
        if [ "x$choice" != "xy" ] && [ "x$choice" != "xY" ]; then
            exit
        fi

        echo "Stopping ${CONTAINER_NAME}"
        ${LXC} stop "${CONTAINER_NAME}" --force > /dev/null 2>&1 || echo "Error during container stop phase"
        echo "Deleting ${CONTAINER_NAME}"
        ${LXC} delete "${CONTAINER_NAME}" --force > /dev/null 2>&1
    fi

    # The 'local' remote is non-removeable
    if [[ "${IMAGE_REMOTE}" != "local" ]]; then
        REMOTE_LIST=$(${LXC} remote list )
        if echo "${REMOTE_LIST}" | grep -q "${IMAGE_REMOTE}" ; then
            echo "Remove ${IMAGE_REMOTE} image store"
            ${LXC} remote remove "${IMAGE_REMOTE}" > /dev/null 2>&1
        fi
    fi

    echo "Cleanup done"
}

function config_host_group {
    if ! grep -q -E "^lxd" /etc/group ; then
        sudo groupadd lxd || true
    fi

    if ! id -nG | grep -qw lxd ; then
        sudo usermod -aG lxd "${USER}"
    fi
}

function config_host {
    echo "Config Lxc on the host"
    HAVE_LXC="$(which lxc)" || echo "No lxc on this host"
    HAVE_JQ="$(which jq)" || echo "No jq on this host"
    HAVE_AWK="$(which awk)" || echo "No awk on this host"

    case ${ID} in
    ubuntu)
        sudo apt-get update --yes
        if [ -z "${HAVE_JQ}" ];then
            echo "Installing jq"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes jq
        fi
        if [ -z "${HAVE_LXC}" ];then
            echo "Installing lxd from apt"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes lxd
        fi
        if [ -z "${HAVE_AWK}" ];then
            echo "Installing awk from apt"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes gawk
        fi
        config_host_group
        ;;
    linuxmint)
        sudo apt-get update --yes
        if [ -z "${HAVE_JQ}" ];then
            echo "Installing jq"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes jq
        fi
        if [ -z "${HAVE_LXC}" ];then
            SNAP="$(which snap)" || echo "No snap on this host"
            echo "Installing snap from apt"
            if [ -z "${SNAP}" ]; then
                sudo rm -f /etc/apt/preferences.d/nosnap.pref
                sudo DEBIAN_FRONTEND=noninteractive apt-get update
                sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes snapd
            fi
            echo "Installing lxd from snap"
            sudo snap install core
            sudo snap install lxd
        fi
        if [ -z "${HAVE_AWK}" ];then
            echo "Installing awk from apt"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes gawk
        fi
        config_host_group
        ;;
    debian)
        sudo apt-get update  --yes
        if [ -z "${HAVE_JQ}" ];then
            echo "Installing jq"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes jq
        fi
        if [ -z "${HAVE_LXC}" ];then
            SNAP="$(which snap)" || echo "No snap on this host"
            echo "Installing snap from apt"
            if [ -z "${SNAP}" ]; then
                sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes snapd
            fi
            echo "Installing lxd from snap"
            sudo snap install core
            sudo snap install lxd
        fi
        if [ -z "${HAVE_AWK}" ];then
            echo "Installing awk"
            sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes gawk
        fi
        config_host_group
        ;;
    fedora)
        if [ -z "${HAVE_JQ}" ];then
            echo "Installing jq"
            sudo dnf install --assumeyes jq
        fi
        if [ -z "${HAVE_LXC}" ];then
            # make sure that any previous LXC version are uninstalled
            sudo dnf remove --assumeyes lxc
            # Now install LXD
            sudo dnf copr enable --assumeyes ganto/lxc4
			# NB: package 'attr' is needed because it provides /usr/bin/setfattr, required by lxd
            sudo dnf install --assumeyes attr lxc lxd
            sudo systemctl enable --now lxc lxd

            sudo ln -sf /run/lxd.socket /var/lib/lxd/unix.socket

        fi
        if [ -z "${HAVE_AWK}" ];then
            echo "Installing awk"
            sudo dnf install --assumeyes gawk
        fi
        config_host_group
        ;;
    opensuse-leap)
        sudo zypper ref
        if [ -z "${HAVE_JQ}" ];then
            echo "Installing jq"
            sudo zypper install --no-confirm jq
        fi
        if [ -z "${HAVE_LXC}" ];then
            sudo zypper install --no-confirm lxd attr iptables
            sudo systemctl enable --now lxd
        fi
        if [ -z "${HAVE_AWK}" ];then
            echo "Installing awk"
            sudo zypper install --no-confirm gawk
        fi
        config_host_group
        ;;
    manjaro)
        if [ -z "${HAVE_JQ}" ];then
            echo "Installing jq ..."
            sudo pacman -S jq
        fi
        if [ -z "${HAVE_LXC}" ];then
            echo "Installing lxd ..."
            sudo pacman -S lxd
            sudo systemctl enable lxd
        fi
        if [ -z "${HAVE_AWK}" ];then
            echo "Installing awk ..."
            sudo pacman -S awk
        fi
        config_host_group
        ;;
    *)
        echo "${ID} is not a supported distribution!"
        exit 1
        ;;
    esac

}

function lxd_init {
    cat << EOF | ${LXD} init --preseed
config:
  images.auto_update_interval: "0"
networks:
- config:
    ipv4.address: auto
    ipv6.address: none
  description: ""
  name: lxdbr0
  type: ""
storage_pools:
- config: {}
  description: ""
  name: default
  driver: dir
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      nictype: bridged
      parent: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
cluster: null
EOF


}

function restart_lxd {
    USE_SNAP="false"
    SNAP="$(which snap)" || echo "No snap on this host"

    if [ -n "${SNAP}" ]; then
        LXD_IN_SNAP="$(${SNAP} list | grep lxd)" 2>/dev/null || echo "No snaps application are installed yet. So no lxd"
        if [ -n "${LXD_IN_SNAP}" ]; then
            USE_SNAP="true"
        fi
    fi

    if [ "${USE_SNAP}" == "true" ]; then
        sudo snap restart lxd
    else
        sudo systemctl restart lxd
    fi
    #From time to time DNS resolution fails just after starting the LXD service.
    #Add a sleep prevent dns resolution issue.
    sleep 1;
}

function setup_subgid {
    echo "Allow user ID remapping"

    sudo echo "${USER}:${CONTAINER_UID}:1" | sudo tee -a /etc/subuid > /dev/null
    sudo echo "${USER}:${CONTAINER_GID}:1" | sudo tee -a /etc/subgid > /dev/null

    sudo echo "root:100000:65536" | sudo tee -a /etc/subuid /etc/subgid > /dev/null

    sudo echo "root:${CONTAINER_UID}:1" | sudo tee -a /etc/subuid > /dev/null
    sudo echo "root:${CONTAINER_GID}:1" | sudo tee -a /etc/subgid > /dev/null
}

function setup_remote {
    if [[ "${IMAGE_REMOTE}" == "local" ]]; then
        echo "Skipping adding remote as user targeted the 'local' one"
    else
        echo "Adding the LXD image store '${IMAGE_REMOTE}' from: '${IMAGE_STORE}'"
        ${LXC} remote add ${IMAGE_REMOTE} https://${IMAGE_STORE} --password "$IMAGE_STORE_PASSWD" \
                --accept-certificate
                # --accept-certificate --protocol=simplestreams
    fi
}

function check_image_availability {
    IMAGE_TO_TEST="$1"
    for i in $(${LXC} image list "${IMAGE_REMOTE}": --columns l --format csv); do
        if [ "${i}" == "${IMAGE_TO_TEST}" ]; then
            return 0
        fi
    done

    echo "${IMAGE_TO_TEST} not an image alias, trying as a fingerprint ..."
    for i in $(${LXC} image list "${IMAGE_REMOTE}": --columns f --format csv); do
        if [ "${i}" == "${IMAGE_TO_TEST}" ]; then
            return 0
        fi
    done

    error "Image '${IMAGE_TO_TEST}' is not present in remote server '${IMAGE_REMOTE}'"
    exit 1
}

function setup_profile {
    reuse="false"
    COUNTER=0
    COUNTER_MAX=10
    choice=""
    while [  "${COUNTER}" -lt "${COUNTER_MAX}" ];do
        COUNTER=$(( "${COUNTER}" + 1 ))
        echo "Checking existing profiles ..."
        echo "Try to Check profiles: ${COUNTER}/${COUNTER_MAX}"

        PROFILE_EXIST=$(${LXC} profile list | grep ${PROFILE_NAME} || echo "") #Prevent exit 1 if no match
        if [ -n "${PROFILE_EXIST}" ]; then
            if [ "${INTERACTIVE}" == "yes" ]; then
                read -r -p "A '${PROFILE_NAME}' profile already exists, (R)euse or (C)reate another one ?[Rc]" choice
            fi
            if [ -z "${choice}" ]; then
                choice="R"
            fi

            case $choice in
                R | r)
                    reuse="true"
                    break
                ;;
                C | c)
                    reuse="false"
                    if [ "${INTERACTIVE}" == "no" ]; then
                        exit 1
                    fi
                    read -r -p "Enter the new profile name:" PROFILE_NAME
                    continue
                ;;
                *) echo "bad choice";;
            esac
        else
            break
        fi
    done
    if [ "${COUNTER}" -ge "${COUNTER_MAX}" ]; then
        echo "Error: setup_profile failed.";
        exit 1;
    fi
    if [ "${reuse}" == "true" ]; then
        echo "Reuse '${PROFILE_NAME}' LXD Profile"
    else
        echo "Create a '${PROFILE_NAME}' LXD Profile"
        ${LXC} profile create "${PROFILE_NAME}"
		${LXC} profile set "${PROFILE_NAME}" security.privileged true
		${LXC} profile set "${PROFILE_NAME}" security.nesting true
        if [ "${ID}" == "opensuse-leap" ]; then
            ${LXC} profile set "${PROFILE_NAME}" raw.lxc lxc.apparmor.profile=unconfined
        fi
		${LXC} profile set "${PROFILE_NAME}" security.syscalls.blacklist "keyctl errno 38\nkeyctl_chown errno 38"
		${LXC} profile device add redpesk loop-control unix-char path=/dev/loop-control
    fi
}

function setup_storage_pool {
    declare -i storage_name_is_valid=0
    STORAGE_POOLS_LIST=($(${LXC} storage list -f csv | awk -F, '{print $1}'))
    if [ -z $STORAGE_POOL_NAME ]; then
        STORAGE_POOL_NAME=${STORAGE_POOL_NAME_DEFAULT}
        if [ "${INTERACTIVE}" == "yes" ]; then
            read -r -p "$(echo "Which storage to use in (${STORAGE_POOLS_LIST[@]})") [Default: $STORAGE_POOL_NAME]:" STORAGE_POOL_NAME
        fi
    fi

    for storage in ${STORAGE_POOLS_LIST[@]}; do
        if [ "$STORAGE_POOL_NAME" == "$storage" ]; then
            storage_name_is_valid=1
        fi
    done
    if [ $storage_name_is_valid -eq 0 ]; then
        echo -e "Unknown LXD storage pool $STORAGE_POOL_NAME"
        STORAGE_POOL_NAME=${STORAGE_POOLS_LIST[0]}
    fi
    echo -e "Using LXD storage pool: $STORAGE_POOL_NAME"
}

function setup_init_lxd {
    if ${LXC} network show lxdbr0 | grep -wq ipv4.address; then
        echo -e "LXD network bridge already setup."
        echo -e "You are likely already owning another container."
        echo -e "LXD will not be restarted."
    else
        echo "1st configuration of lxd ..."
        lxd_init
    fi

    case ${ID} in
    fedora|opensuse-leap)

        FIRECMD="$(which firewall-cmd)" || echo "No firewall-cmd on this host"
        if [ -n "${FIRECMD}" ];then
            zone=$(sudo firewall-cmd --get-zone-of-interface=lxdbr0)||zone=none

            if [ "${zone}" != "trusted" ]; then
                sudo firewall-cmd --zone=trusted --change-interface=lxdbr0 --permanent || echo "No firewall-cmd running"
                sudo firewall-cmd --reload || echo "No firewall-cmd running"
            fi
        fi
        ;;
    *)
        ;;
    esac

}

function setup_ssh {
    SSH_DIR="${HOME}/.ssh"
    CONTAINER_SSH_DIR="/home/${CONTAINER_USER}/.ssh"
    KNOWN_HOSTS_FILE="${SSH_DIR}/known_hosts"

    if [ ! -d "${SSH_DIR}" ]; then
        mkdir -p "${SSH_DIR}"
        chmod 0700 "${SSH_DIR}"
    fi

    if [ ! -f "${SSH_DIR}"/id_rsa.pub ]; then
        echo "Generate a ssh public key"
        ssh-keygen -b 2048 -t rsa -f "${SSH_DIR}"/id_rsa -q -N ""
    fi

    echo "Adding our pubkey to authorized_keys"
    ${LXC} config device add "${CONTAINER_NAME}" my_authorized_keys disk source="${SSH_DIR}" path="${CONTAINER_SSH_DIR}"
    test ! -f "${SSH_DIR}/authorized_keys" && touch "${SSH_DIR}/authorized_keys" && chmod 0600 "${SSH_DIR}/authorized_keys"
    grep -v "$(cat "${SSH_DIR}"/id_rsa.pub)" "${SSH_DIR}/authorized_keys" && \
      cat "${SSH_DIR}/id_rsa.pub" >> "${SSH_DIR}/authorized_keys"

    if [ ! -f "${KNOWN_HOSTS_FILE}" ]; then
        touch "${KNOWN_HOSTS_FILE}"
        chmod 600 "${KNOWN_HOSTS_FILE}"
    fi
    #Remove old known host
    ssh-keygen -q -f "${KNOWN_HOSTS_FILE}" -R "${CONTAINER_NAME}" 2> /dev/null
    ssh-keygen -q -f "${KNOWN_HOSTS_FILE}" -R "${MY_IP_ADD_RESS}" 2> /dev/null
    #Add new known host
    ssh-keyscan -H "${CONTAINER_NAME}","${MY_IP_ADD_RESS}" >> "${KNOWN_HOSTS_FILE}" 2>/dev/null
}

function GetDefaultDir () {
    default_name_dir=$1
    default_msg=$2
    local result_name_dir=$3
    local default_cntnr_dir=${DEFAULT_CNTNR_DIR}
    result_value=""

    if [[ ${default_name_dir} == ".ssh" ]];then
        default_cntnr_dir=${HOME}
    fi

    echo -e "Directory: ${BOLD}${GREEN}${default_name_dir}${NORMAL}
Host directory with ${default_msg}.
In container ${BOLD}\${HOME}/${GREEN}${default_name_dir}${NORMAL}
Choose Host directory path, default[${BOLD}${default_cntnr_dir}/${GREEN}${default_name_dir}${NORMAL}]:"
    if [ "${INTERACTIVE}" == "yes" ]; then
        read -r result_value
    fi
    if [ -z "${result_value}" ]; then
        result_value=${default_cntnr_dir}/${default_name_dir}
    fi
    eval "$result_name_dir"="${result_value}"
}

function MapHostDir () {
    var_name=$1
    dir_value=$2
    mkdir -p "${dir_value}"
    ${LXC} config device add "${CONTAINER_NAME}" my_"${var_name}" disk source="${dir_value}" path="/home/${CONTAINER_USER}/${var_name}"
}

function setup_repositories {

    # The cloud publication container does not need any host dir mappings
    if [[ "$CONTAINER_TYPE" == "cloud-publication" ]]; then
        return
    fi

    echo -e "\nYou will have three repositories in your container (gitsources, gitpkgs, and build)
    If you already have directories in your host, they will be mapped, just have to precise the path.
    And if you don't have directories to map, they will be created by default under: ${BOLD}${DEFAULT_CNTNR_DIR}${NORMAL}\n"

    gitsources_msg='applications sources you want to build'
    gitpkgs_msg='gitpkgs (where is the specfile) to map'
    build_msg='build (files generated by rpmbuild) to map'
    ssh_msg='your .ssh directory holding your ssh key and configuration files. This is allows to authenticate you when cloning git repositories and such.'

    var_gitsources_dir=""
    var_gitpkgs_dir=""
    var_build_dir=""
    var_ssh_dir=""

    GetDefaultDir gitsources "${gitsources_msg}" var_gitsources_dir
    GetDefaultDir gitpkgs "${gitpkgs_msg}" var_gitpkgs_dir
    GetDefaultDir rpmbuild "${build_msg}" var_build_dir
    GetDefaultDir .ssh "${ssh_msg}" var_ssh_dir

    MapHostDir gitsources "${var_gitsources_dir}"
    MapHostDir gitpkgs "${var_gitpkgs_dir}"
    MapHostDir rpmbuild "${var_build_dir}"
    MapHostDir ssh "${var_ssh_dir}"

    echo "Mapping of host directories to retrieve your files in the container"

    #We need to have the same id for user inside/outside container
	local olduid=$(${LXC} exec "${CONTAINER_NAME}" -- id -u $CONTAINER_USER)
    ${LXC} exec "${CONTAINER_NAME}" -- sed -i "s/^\($CONTAINER_USER:x:\)${olduid}/\1${CONTAINER_UID}/g" /etc/passwd
    ${LXC} exec "${CONTAINER_NAME}" -- chown -R $CONTAINER_USER /home/$CONTAINER_USER
}


function setup_kvm_device_mapping {
    # If we want that localbuilder could build an image then we will need to
    # map the kvm device with correct permission and owner.

    if [[ "$CONTAINER_TYPE" == "localbuilder" ]]; then
      ${LXC} config device add "${CONTAINER_NAME}" kvm unix-char path=/dev/kvm gid=36 mode=0666
    fi
}

function setup_port_redirections {
    # Certain containers need custom port redirections. We set them up here.

    # Expose port 30003 in the cloud publication container to the outside world
    # on port 21212. Note: both port numbers need to match the systemd service
    # file within the container and the port used by the binder on the target to
    # reach the host, respectively.
    # We also expose the HTTP port itself on host port 21213 as this allows
    # WebSocket communications to the binder itself
    if [[ "$CONTAINER_TYPE" == "cloud-publication" ]]; then
        ${LXC} config device add "${CONTAINER_NAME}" redis-cloud-api proxy \
            listen=tcp:0.0.0.0:21212 connect=tcp:127.0.0.1:30003
        ${LXC} config device add "${CONTAINER_NAME}" redis-cloud-http proxy \
            listen=tcp:0.0.0.0:21213 connect=tcp:127.0.0.1:1234
    elif [[ "$CONTAINER_TYPE" == "redpesk-demo" ]]; then
        ${LXC} config device add "${CONTAINER_NAME}" rpwebui proxy \
            listen=tcp:0.0.0.0:8002 connect=tcp:127.0.0.1:8002
        ${LXC} config device add "${CONTAINER_NAME}" rpdex proxy \
            listen=tcp:0.0.0.0:8003 connect=tcp:127.0.0.1:8003
        ${LXC} config device add "${CONTAINER_NAME}" rpkorneli proxy \
            listen=tcp:0.0.0.0:9000 connect=tcp:127.0.0.1:9000
    fi
}

function setup_container_ip {
    # Wait for ipv4 address to be available
    COUNTER=0
    COUNTER_MAX=10
    while [  "${COUNTER}" -lt "${COUNTER_MAX}" ];do
        echo "Try to get IP: ${COUNTER}/${COUNTER_MAX}"
        COUNTER=$(( "${COUNTER}" + 1 ))
        MY_IP_ADD_RES_TYPE=$(${LXC} ls "${CONTAINER_NAME}" --format json |jq -r '.[0].state.network.eth0.addresses[0].family')

        if [ "$MY_IP_ADD_RES_TYPE" != "inet" ] ; then
            echo 'waiting for IPv4 address'
            sleep 2
            continue
        fi

        MY_IP_ADD_RESS=$(${LXC} ls "${CONTAINER_NAME}" --format json |jq -r '.[0].state.network.eth0.addresses[0].address')

        echo "The container IP found is: ${MY_IP_ADD_RESS}"

        break;
    done
    if [ "${COUNTER}" -ge "${COUNTER_MAX}" ]; then
        echo "Error: setup_container_ip failed.";
        exit 1;
    fi
}

function fix_container {
    echo "Fixes the annoying missing suid bit on ping"
    ${LXC} exec "${CONTAINER_NAME}" chmod +s /usr/bin/ping

    echo "Switches DNSSEC off"
    #Remove all line with DNSSEC from the file /etc/systemd/resolved.conf
    ${LXC} exec "${CONTAINER_NAME}" -- bash -c 'sed -i -e '\''/^DNSSEC/d'\''  /etc/systemd/resolved.conf'
    #Add "DNSSEC=no" At the end of the file /etc/systemd/resolved.conf
    ${LXC} exec "${CONTAINER_NAME}" -- bash -c 'sed -i -e '\''$ aDNSSEC=no'\'' /etc/systemd/resolved.conf'

	echo "Adjust permissions on home directory /home/${CONTAINER_USER}"
    ${LXC} exec "${CONTAINER_NAME}" -- bash -c "chown -R ${CONTAINER_USER} /home/${CONTAINER_USER}"

    ${LXC} config set "${CONTAINER_NAME}" raw.idmap "$(echo -e "uid $(id -u) ${CONTAINER_UID}\ngid $(id -g) ${CONTAINER_GID}")"
}

function setup_hosts {
    echo "Add container IP to your /etc/hosts"
    echo "# Added by install-redpesk-localbuilder.sh" | sudo tee -a /etc/hosts
    echo "${MY_IP_ADD_RESS} ${CONTAINER_NAME}" | sudo tee -a /etc/hosts
}

function lxc_luanch_failed {
    echo "ERROR ${LXC} launch failed"
    exit 1
}

function setup_lxc_container {
    echo "This will install the ${CONTAINER_NAME} container on your machine"

    setup_init_lxd

    setup_subgid

    restart_lxd

    setup_remote

    setup_profile

    setup_storage_pool

    check_image_availability "${CONTAINER_FLAVOURS[$CONTAINER_TYPE]}"

    # Setup the LXC container
    # The command "< /dev/null" is a workaround to avoid issue on running this
    # script using "vagrant provision" (where this fails with: yaml: unmarshal
    # errors)
	# See https://github.com/lxc/lxd/issues/6188#issuecomment-572248426

    IMAGE_SPEC="${IMAGE_REMOTE}:${CONTAINER_FLAVOURS[$CONTAINER_TYPE]}"
    echo "Pulling in container image from $IMAGE_SPEC ..."
    ${LXC} launch "${IMAGE_SPEC}" "${CONTAINER_NAME}" --profile default --profile "${PROFILE_NAME}" --storage "${STORAGE_POOL_NAME}" --verbose $LXC_DEBUG_OPT < /dev/null || lxc_luanch_failed
    echo "Pulling done, setup container ..."
    setup_container_ip

    echo "Container ${CONTAINER_NAME} operational. Remaining few last steps ..."

    fix_container

    setup_ssh

    setup_repositories

    setup_port_redirections

    setup_kvm_device_mapping

    ${LXC} restart "${CONTAINER_NAME}"

    setup_hosts

    sync
    echo -e "Container ${BOLD}${CONTAINER_NAME}${NORMAL} (${MY_IP_ADD_RESS}) successfully created !"
    #"You can log in it with" is a key sentance use in CI do not change it.
    echo -e "You can log in it with '${BOLD}ssh ${CONTAINER_USER}@${CONTAINER_NAME}${NORMAL}'"
}

##########
# check_user
check_distribution

case "${MAIN_CMD}" in
help)
    usage
    ;;
clean)
    check_lxc
    check_lxd
    check_container_name_and_type
    clean_lxc_container
    ;;
config_host)
    config_host
    ;;
create)
    config_host
    check_lxc
    check_lxd
    check_container_file
    check_container_name_and_type
    clean_lxc_container
    setup_lxc_container
    ;;
*)

    if [[ -z "${MAIN_CMD}" ]]; then
        echo -e "${RED}Error${NORMAL}: no action specified! You must provide one."
    else
        echo -e "${RED}Error${NORMAL}: unknown action type '${MAIN_CMD}' !"
    fi
    echo
    usage
    ;;
esac
