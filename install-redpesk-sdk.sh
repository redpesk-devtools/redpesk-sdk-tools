#!/bin/bash
###########################################################################
# Copyright (C) 2020-2025 IoT.bzh
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

# shellcheck disable=SC1091
shopt -s extglob
source /etc/os-release

SUPPORTED_DISTROS="AlmaLinux 9/10, Fedora 41/42, Debian 11/12, Linux Mint 21/22, Ubuntu 22.04/24.04, OpenSUSE Leap 15.6"

##############################
####### DEFAULT VALUES #######
##############################

OBS_DISTRO_NAME=""
PACKAGE_MANAGER=""

SDK_REPO_FILE_NAME="redpesk-sdk"
SDK_REPO_FILE_PATH=""
SDK_REPO_URL_LIST=""
SDK_REPO_ENABLE=1

CI_REPO_FILE_NAME="redpesk-ci"
CI_REPO_FILE_PATH=""
CI_REPO_URL_LIST=""
CI_REPO_ENABLE=1

SDK_WRITE_CONF=1
CI_WRITE_CONF=1

NO_INSTALL=0
INTERACTIVE=1
INSTALL_RECOMMENDED_PKG=1

REDPESK_OS_VERSION="batz-2.1-update"

LIST_PACKAGE_SDK_RPM="afb-binder afb-binding-devel afb-libhelpers-devel afb-cmake-modules afb-libcontroller-devel afb-ui-devtools afb-test afb-client"
LIST_PACKAGE_SDK_DEB="afb-binder afb-binding-dev afb-libhelpers-dev afb-cmake-modules afb-libcontroller-dev afb-ui-devtools afb-test-bin afb-client"

LIST_PACKAGE_CI_RPM="redpesk-cli"
LIST_PACKAGE_CI_DEB="redpesk-cli"

#########################
####### FUNCTIONS #######
#########################

# redmine #4550: execute sudo with user environment set (example: http_proxy)
function sudo { command sudo -E "$@"; }

usage() {
	echo -e "Redpesk SDK and CI tools installation script
Supported distributions : $SUPPORTED_DISTROS
Usage:
            -k | --sdk:                                only install sdk repo and packages
            -c | --rp-cli:                             only install rp-cli repo and packages
            -r | --sdkrepository <SDK_REPO_URL_LIST>   redpesk sdk repository path
            -i | --cirepository <CI_REPO_URL_LIST>     redpesk ci repository path
            -o | --osversion <os_version>              set the redpesk version value, default:${REDPESK_OS_VERSION}
            -s | --no-install                          only declare repositories, don't install packages
            -n | --no-recommends                       doesn't install recommended packages alongside redpesk packages
            -a | --non-interactive                     non interactive mode
            -h | --help:                               display help"
	exit
}

unsupported_distro_error() {
	echo "Your distribution, $PRETTY_NAME, is not supported. Supported distribution are $SUPPORTED_DISTROS. For more information, please check https://docs.redpesk.bzh/"
}

distro_detection() {
	# Validate distro support + set obs_distro_name + set package manager
	case "$ID" in
	almalinux)
		case "$VERSION_ID" in
		9.*)
			#Add PowerTools needed for the lib-controller
			dnf repolist --enabled | grep -q "powertools" || sudo dnf config-manager --set-enabled crb
			OBS_DISTRO_NAME="AlmaLinux_${VERSION_ID%%.*}"
			;;
		10.*)
			#Add PowerTools needed for the lib-controller
			dnf repolist --enabled | grep -q "powertools" || sudo dnf config-manager --set-enabled crb
			OBS_DISTRO_NAME="AlmaLinux_${VERSION_ID%%.*}"
			;;
		*)
			unsupported_distro_error
			;;
		esac
		PACKAGE_MANAGER="dnf"
		;;
	fedora)
		case "$VERSION_ID" in
		41| 42)
			OBS_DISTRO_NAME="Fedora_\$releasever"
			;;
		*)
			unsupported_distro_error
			;;
		esac
		PACKAGE_MANAGER="dnf"
		;;
	debian)
		case "$VERSION_ID" in
		11 | 12)
			OBS_DISTRO_NAME="Debian_${VERSION_ID}"
			;;
		*)
			unsupported_distro_error
			;;
		esac
		PACKAGE_MANAGER="apt"
		;;
	linuxmint)
		case "$VERSION_ID" in
		21*)
			OBS_DISTRO_NAME="xUbuntu_22.04"
			;;
		22*)
			OBS_DISTRO_NAME="xUbuntu_24.04"
			;;
		*)
			unsupported_distro_error
			;;
		esac
		PACKAGE_MANAGER="apt"
		;;
	ubuntu)
		case "$VERSION_ID" in
		22.04 | 24.04)
			OBS_DISTRO_NAME="xUbuntu_${VERSION_ID}"
			;;
		*)
			unsupported_distro_error
			;;
		esac
		PACKAGE_MANAGER="apt"
		;;
	opensuse-leap)
		case "$VERSION_ID" in
		15.6)
			OBS_DISTRO_NAME="openSUSE_Leap_${VERSION_ID}"
			;;
		*)
			unsupported_distro_error
			;;
		esac
		PACKAGE_MANAGER="zypper"
		;;
	*)
		unsupported_distro_error
		;;
	esac
	echo "Your distribution, $PRETTY_NAME, is supported."

	# Prepare env depending on package manager + set sdk & ci conf file path
	case "$PACKAGE_MANAGER" in
	dnf)
		sudo dnf install -y dnf-plugins-core &>/dev/null
		SDK_REPO_FILE_PATH="/etc/yum.repos.d/${SDK_REPO_FILE_NAME}.repo"
		CI_REPO_FILE_PATH="/etc/yum.repos.d/${CI_REPO_FILE_NAME}.repo"
		;;
	apt)
		sudo apt update &>/dev/null
		sudo apt install -y curl wget gnupg ca-certificates &>/dev/null
		SDK_REPO_FILE_PATH="/etc/apt/sources.list.d/${SDK_REPO_FILE_NAME}.list"
		CI_REPO_FILE_PATH="/etc/apt/sources.list.d/${CI_REPO_FILE_NAME}.list"
		;;
	zypper)
		SDK_REPO_FILE_PATH="/etc/zypp/repos.d/${SDK_REPO_FILE_NAME}.repo"
		CI_REPO_FILE_PATH="/etc/zypp/repos.d/${CI_REPO_FILE_NAME}.repo"
		;;
	esac
}

ask_overwrite_conf() {
	local file_path="$1"
	local var_name="$2"
	local default="y"
	local choice=""

	if [ -f "$file_path" ]; then
		[ $INTERACTIVE -eq 1 ] && read -r -p "The conf file $file_path already exists, update it ? [Y/n] " choice

		# Set to default if no input
		choice="${choice:-$default}"

		case "$choice" in
			[yY]) eval "$var_name=1" ;;
			*)    eval "$var_name=0" ;;
		esac
	fi
}

install_repo_and_packages() {
	local repo_list="$1"
	local file_path="$2"
	local write_conf="$3"
	local prefix="$4"
	local id_repo=""
	local no_recommend_opt=""

	[ $write_conf -eq 1 ] && sudo rm -f "$file_path"

	case "${PACKAGE_MANAGER}" in
	dnf)
		if [ $write_conf -eq 1 ]; then
			for repo in $repo_list; do
				# Retrieve repo name
				id_repo=$(echo "$repo" | awk -F/ '{print $(NF-1)}')
				sudo tee --append "$file_path" >/dev/null <<EOF
[redpesk-$id_repo]
name=redpesk-$id_repo
baseurl=${repo}
enabled=1
gpgcheck=1
gpgkey=${repo}/repodata/repomd.xml.key

EOF
			done
		fi

		sudo dnf clean expire-cache &>/dev/null
		# Manage the "no recommended option" variable
		[ $INSTALL_RECOMMENDED_PKG -eq 0 ] && no_recommend_opt="--setopt=install_weak_deps=False"
		#Install base redpesk packages
		[ $NO_INSTALL -eq 0 ] && eval "sudo dnf install -y ${no_recommend_opt} \${LIST_PACKAGE_${prefix}_RPM}"
		;;
	apt)
		if [ $write_conf -eq 1 ]; then
			sudo mkdir -p /usr/share/keyrings
			for repo in $repo_list; do
				id_repo=$(echo "$repo" | awk -F/ '{print $(NF-1)}')
				local key_path="/usr/share/keyrings/redpesk-${id_repo}.gpg"

				curl -fsSL "${repo}/Release.key" | gpg --dearmor | sudo tee "$key_path" >/dev/null
				echo "deb [signed-by=${key_path}] ${repo} ./" | sudo tee -a "$file_path" >/dev/null
			done
		fi

		sudo apt update &>/dev/null
		# Manage the "no recommended option" variable
		[ $INSTALL_RECOMMENDED_PKG -eq 0 ] && no_recommend_opt="--no-install-recommends"
		#Install base redpesk packages
		[ $NO_INSTALL -eq 0 ] && eval "sudo apt install -y ${no_recommend_opt} \${LIST_PACKAGE_${prefix}_DEB}"
		;;
	zypper)
		#Add redpesk repos
		if [ $write_conf -eq 1 ]; then
			for repo in $repo_list; do
				id_repo=$(echo "$repo" | awk -F/ '{print $(NF-1)}')
				sudo zypper lr | grep -q "redpesk-${id_repo}" && sudo zypper rr "redpesk-${id_repo}"
				sudo zypper ar -f "${repo}" "redpesk-${id_repo}"
				sudo zypper --non-interactive --gpg-auto-import-keys ref
				sudo zypper --non-interactive dup --from "redpesk-${id_repo}"
			done
		fi

		# Manage the "no recommended option" variable
		[ $INSTALL_RECOMMENDED_PKG -eq 0 ] && no_recommend_opt="--no-recommends"
		#Install base redpesk packages
		[ $NO_INSTALL -eq 0 ] && eval "sudo zypper install -y ${no_recommend_opt} \${LIST_PACKAGE_${prefix}_RPM}"
		;;
	esac
}

####################
####### MAIN #######
####################

options=$(getopt -o k,c,r:,i:,o:,s,n,a,h -l sdk,rp-cli,sdkrepository:,cirepository:,osversion:,no-install,no-recommends,non-interactive,help -- "$@")
[ $? != "0" ] && usage

while true; do
	case $1 in
		-k|--sdk)               CI_REPO_ENABLE=0                                    ; shift ;;
		-c|--rp-cli)            SDK_REPO_ENABLE=0                                   ; shift ;;
		-r|--sdkrepository)     shift; SDK_REPO_URL_LIST="$SDK_REPO_URL_LIST $1"    ; shift ;;
		-i|--cirepository)      shift; CI_REPO_URL_LIST="$CI_REPO_URL_LIST $1"      ; shift ;;
		-o|--osversion)         shift; REDPESK_OS_VERSION="$1"                      ; shift ;;
		-s|--no-install)        NO_INSTALL=1                                        ; shift ;;
		-n|--no-recommends)     INSTALL_RECOMMENDED_PKG=0                           ; shift ;;
		-a|--non-interactive)   INTERACTIVE=0                                       ; shift ;;
		-h|--help)                                                                  usage ;;
		*)                                                                          break ;;
	esac
done

# check sudo rights
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

distro_detection

if [ $SDK_REPO_ENABLE -eq 1 ]; then
	echo -e "\nInstalling redpesk SDK repos"
	if [ -z "${SDK_REPO_URL_LIST}" ]; then
		SDK_REPO_URL_LIST="
				https://download.redpesk.bzh/redpesk-lts/${REDPESK_OS_VERSION}/sdk/${OBS_DISTRO_NAME}\
				https://download.redpesk.bzh/redpesk-lts/${REDPESK_OS_VERSION}/sdk-third-party/${OBS_DISTRO_NAME}"
	fi
	ask_overwrite_conf "$SDK_REPO_FILE_PATH" SDK_WRITE_CONF
	install_repo_and_packages "${SDK_REPO_URL_LIST}" "${SDK_REPO_FILE_PATH}" "${SDK_WRITE_CONF}" "SDK"
fi

if [ $CI_REPO_ENABLE -eq 1 ]; then
	echo -e "\nInstalling redpesk CI repos"
	if [ -z "${CI_REPO_URL_LIST}" ]; then
		CI_REPO_URL_LIST="
				https://download.redpesk.bzh/redpesk-ci/armel-update/tools/${OBS_DISTRO_NAME}\
				https://download.redpesk.bzh/redpesk-ci/armel-update/tools-third-party/${OBS_DISTRO_NAME}"
	fi
	ask_overwrite_conf "$CI_REPO_FILE_PATH" CI_WRITE_CONF
	install_repo_and_packages "${CI_REPO_URL_LIST}" "${CI_REPO_FILE_PATH}" "${CI_WRITE_CONF}" "CI"
fi
