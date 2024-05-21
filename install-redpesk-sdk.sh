#!/bin/bash
###########################################################################
# Copyright (C) 2020-2023 IoT.bzh
#
# Authors: Armand Bénéteau <armand.beneteau@iot.bzh>
#          Ronan Le Martret <ronan.lemartret@iot.bzh>
#          Valentin Geffroy <valentin.geffroy@iot.bzh>
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

SUPPORTED_DISTROS="AlmaLinux 8/9, Fedora 39/40, Linux Mint 21.1/21.2/21.3, OpenSUSE Leap 15.4/15.5, Ubuntu 22.04/24.04"

#REDPESK_REPO can be given in command line, if so REDPESK_REPO must be the full path for the distro used.

REDPESK_OS_VERSION_DEFAULT="arz-1.1-update"

REDPESK_OS_VERSION=""

REDPESK_REPO=""
REDPESK_CI_REPO=""

SPIKPACKINST="no"
INTERACTIVE="yes"
INSTALL_RECOMMENDED_PKG="yes"

LIST_PACKAGE_AFB_DEB="afb-binder afb-binding-dev afb-libhelpers-dev afb-cmake-modules afb-libcontroller-dev afb-ui-devtools afb-test-bin afb-client"
LIST_PACKAGE_AFB_RPM="afb-binder afb-binding-devel afb-libhelpers-devel afb-cmake-modules afb-libcontroller-devel afb-ui-devtools afb-test afb-client"

LIST_PACKAGE_RPCLI_DEB="redpesk-cli"
LIST_PACKAGE_RPCLI_RPM="redpesk-cli"

LIST_PACKAGE_DEB="$LIST_PACKAGE_AFB_DEB $LIST_PACKAGE_RPCLI_DEB"
LIST_PACKAGE_RPM="$LIST_PACKAGE_AFB_RPM $LIST_PACKAGE_RPCLI_RPM"

# redmine #4550: execute sudo with user environment set (example: http_proxy)
function sudo { command sudo -E "$@"; }

function help {
	echo -e "Supported distributions : $SUPPORTED_DISTROS
            -c | --rp-cli:                 install rp-cli only
            -k | --sdk:                    install sdk only
            -r | --repository:             redpesk sdk repository path
            -o | --osversion:              set the redpesk version value, default:${REDPESK_OS_VERSION_DEFAULT}
            -i | --cirepository:           redpesk ci repository path
            -h | --help:                   display help
            -s | --skip-packages-install   only declare repositories but don't install any packages
            -a | --non-interactive
            -n | --no-recommends"
	exit
}

error_message() {
	echo "Your distribution, $PRETTY_NAME, is not supported. Supported distribution are $SUPPORTED_DISTROS. For more information, please check https://docs.redpesk.bzh/"
}

echo "Detected distribution: $PRETTY_NAME"

while [[ $# -gt 0 ]]; do
	OPTION="$1"
	case $OPTION in
	-c | --rp-cli)
		# install only rpcli
		LIST_PACKAGE_DEB="$LIST_PACKAGE_RPCLI_DEB"
		LIST_PACKAGE_RPM="$LIST_PACKAGE_RPCLI_RPM"
		;;
    -k | --sdk)
        # install only sdk
        LIST_PACKAGE_DEB="$LIST_PACKAGE_AFB_DEB"
		LIST_PACKAGE_RPM="$LIST_PACKAGE_AFB_RPM"
		;;
	-i | --cirepository)
		if [[ -n $2 ]]; then
			REDPESK_CI_REPO="$REDPESK_CI_REPO $2"
			shift
		else
			printf "command error: a repository was expected\n-r <repository>\n"
			exit
		fi
		;;
	-r | --repository)
		if [[ -n $2 ]]; then
			REDPESK_REPO="$REDPESK_REPO $2"
			shift
		else
			printf "command error: a repository was expected\n-r <repository>\n"
			exit
		fi
		;;
	-o | --osversion)
		if [[ -n $2 ]]; then
			REDPESK_OS_VERSION="$2"
			shift
		else
			printf "command error: a repository was expected\n-r <repository>\n"
			exit
		fi
		;;
	-h | --help)
		help
		;;
	-s | --skip-packages-install)
		SPIKPACKINST="yes"
		;;
	-a | --non-interactive)
		INTERACTIVE="no"
		;;
	-n | --no-recommends)
		INSTALL_RECOMMENDED_PKG="no"
		;;
	*)
		printf " Unknown command\n
		try -h or --help\n "
		exit
		;;
	esac
    shift
done

if [ -z "${REDPESK_OS_VERSION}" ]; then
	REDPESK_OS_VERSION="${REDPESK_OS_VERSION_DEFAULT}"
fi

REDPESK_BASE_REPO_DEFAULT="	https://download.redpesk.bzh/redpesk-lts/${REDPESK_OS_VERSION}/sdk/ \
							https://download.redpesk.bzh/redpesk-lts/${REDPESK_OS_VERSION}/sdk-third-party	"

REDPESK_CI_BASE_REPO_DEFAULT="	https://download.redpesk.bzh/redpesk-ci/armel-update/tools/	\
								https://download.redpesk.bzh/redpesk-ci/armel-update/tools-third-party/	"

REPO_CONF_FILE_NAME="redpesk-sdk"
REPO_CI_CONF_FILE_NAME="redpesk-ci"
REPO_CONF_FILE=""
CI_REPO_CONF_FILE=""

case $ID in
ubuntu | linuxmint)
	REPO_CONF_FILE="/etc/apt/sources.list.d/${REPO_CONF_FILE_NAME}.list"
	CI_REPO_CONF_FILE="/etc/apt/sources.list.d/${REPO_CI_CONF_FILE_NAME}.list"
	;;
opensuse-leap)
	REPO_CONF_FILE="/etc/zypp/repos.d/${REPO_CONF_FILE_NAME}.repo"
	CI_REPO_CONF_FILE="/etc/zypp/repos.d/${REPO_CI_CONF_FILE_NAME}.repo"
	;;
fedora | almalinux)
	REPO_CONF_FILE="/etc/yum.repos.d/${REPO_CONF_FILE_NAME}.repo"
	CI_REPO_CONF_FILE="/etc/yum.repos.d/${REPO_CI_CONF_FILE_NAME}.repo"
	;;
debian)
	REPO_CONF_FILE="/etc/apt/sources.list.d/${REPO_CONF_FILE_NAME}.list"
	CI_REPO_CONF_FILE="/etc/apt/sources.list.d/${REPO_CI_CONF_FILE_NAME}.list"
	;;
*)
	error_message
	;;
esac

WRITE_CONF="yes"
CI_WRITE_CONF="yes"

if [ -f "${REPO_CONF_FILE}" ]; then
	if [ "${INTERACTIVE}" == "yes" ]; then
		read -r -p "The conf file ${REPO_CONF_FILE} already exists and will be destroyed, keep it? [N/y]" choice
	fi
	if [ -z "${choice}" ]; then
		choice="n"
	fi
	if [ "x$choice" != "xn" ] && [ "x$choice" != "xN" ]; then
		WRITE_CONF="no"
	fi
fi

if [ -f "${CI_REPO_CONF_FILE}" ]; then
	if [ "${INTERACTIVE}" == "yes" ]; then
		read -r -p "The conf file ${CI_REPO_CONF_FILE} already exists and will be destroyed, keep it? [N/y]" choice
	fi
	if [ -z "${choice}" ]; then
		choice="n"
	fi
	if [ "x$choice" != "xn" ] && [ "x$choice" != "xN" ]; then
		CI_WRITE_CONF="no"
	fi
fi

function get_obs_distro_name {
	case $ID in
	ubuntu)
		case $VERSION_ID in
		22.04 | 24.04)
			echo "xUbuntu_${VERSION_ID}"
			;;
		*)
			error_message
			;;
		esac
		;;
	opensuse-leap)
		case $VERSION_ID in
		15.4 | 15.5)
			echo "openSUSE_Leap_${VERSION_ID}"
			;;
		*)
			error_message
			;;
		esac
		;;
	fedora)
		case $VERSION_ID in
		39| 40)
			echo "Fedora_${VERSION_ID}"
			;;
		*)
			error_message
			;;
		esac
		;;
	debian)
		case $VERSION_ID in
		11)
			echo "Debian_${VERSION_ID}"
			;;
		*)
			error_message
			;;
		esac
		;;
	almalinux)
		case $VERSION_ID in
		8.*)
			echo "AlmaLinux_8"
			;;
		9.*)
			echo "AlmaLinux_9"
			;;
		*)
			error_message
			;;
		esac
		;;
	linuxmint)
		case $VERSION_ID in
		21| 21.1| 21.2| 21.3)
			echo "xUbuntu_22.04"
			;;
		*)
			error_message
			;;
		esac
		;;
	*)
		error_message
		;;
	esac
}

obs_distro_name=$(get_obs_distro_name)

if [ -z "${REDPESK_REPO}" ]; then
	for repo in ${REDPESK_BASE_REPO_DEFAULT}; do
		REDPESK_REPO="${REDPESK_REPO} ${repo}/${obs_distro_name}"
	done
fi

if [ -z "${REDPESK_CI_REPO}" ]; then
	for repo in ${REDPESK_CI_BASE_REPO_DEFAULT}; do
		REDPESK_CI_REPO="${REDPESK_CI_REPO} ${repo}/${obs_distro_name}"
	done
fi

case $ID in
ubuntu)
	case $VERSION_ID in
	22.04 | 24.04)
		#Add redpesk repos (ca-certificates is here to fix VM CI test)
		sudo apt-get update --yes
		sudo apt-get install -y curl wget add-apt-key gnupg ca-certificates
		ID_REPO=1
		if [ "${WRITE_CONF}" == "yes" ]; then
			sudo rm -fr "${REPO_CONF_FILE}"
			for repo in ${REDPESK_REPO}; do
				#This should be fixed
				wget -O - "${repo}/Release.key" | sudo apt-key add -
				#sudo rm -f  "/etc/apt/trusted.gpg.d/redpesk-sdk-${ID_REPO}.gpg"
				#curl "${repo}/Release.key" | sudo gpg --no-tty --dearmor --output "/etc/apt/trusted.gpg.d/redpesk-sdk-${ID_REPO}.gpg"
				sudo sh -c 'echo "deb  '"${repo}"' ./" >> '"${REPO_CONF_FILE}"
				ID_REPO=$(($ID_REPO + 1))
			done
		fi
		ID_REPO=1
		if [ "${CI_WRITE_CONF}" == "yes" ]; then
			sudo rm -fr "${CI_REPO_CONF_FILE}"
			for repo in ${REDPESK_CI_REPO}; do
				curl "${repo}/Release.key" | sudo gpg --no-tty --dearmor --output "/etc/apt/trusted.gpg.d/redpesk-ci-${ID_REPO}.gpg"
				sudo sh -c 'echo "deb  '"${repo}"' ./" >> '"${CI_REPO_CONF_FILE}"
				ID_REPO=$(($ID_REPO + 1))
			done
		fi

		sudo apt-get update --yes
		# Manage the "no recommended option" variable
		no_recommend_opt=""
		if [ "${INSTALL_RECOMMENDED_PKG}" == "no" ]; then
			no_recommend_opt="--no-install-recommends"
		fi
		#Install base redpesk packages
		if [ "${SPIKPACKINST}" == "no" ]; then
			sudo apt-get install -y ${no_recommend_opt} ${LIST_PACKAGE_DEB}
		fi
		;;
	*)
		error_message
		;;
	esac
	;;
opensuse-leap)
	case $VERSION_ID in
	15.4 | 15.5)
		# Manage the "no recommended option" variable
		no_recommend_opt=""
		if [ "${INSTALL_RECOMMENDED_PKG}" == "no" ]; then
			no_recommend_opt="--no-recommends"
		fi

		ID_REPO=1

		#Add redpesk repos

		if [ "${WRITE_CONF}" == "yes" ]; then
			for repo in ${REDPESK_REPO}; do
				sudo zypper rr "redpesk-sdk-${ID_REPO}"
				sudo zypper ar -f "${repo}" "redpesk-sdk-${ID_REPO}"
				sudo zypper --non-interactive --gpg-auto-import-keys ref
				sudo zypper --non-interactive dup --from "redpesk-sdk-${ID_REPO}"
				ID_REPO=$(($ID_REPO + 1))
			done
		fi

		ID_REPO=1

		if [ "${CI_WRITE_CONF}" == "yes" ]; then
			for repo in ${REDPESK_CI_REPO}; do
				sudo zypper rr "redpesk-ci-${ID_REPO}"
				sudo zypper ar -f "${repo}" "redpesk-ci-${ID_REPO}"
				sudo zypper --non-interactive --gpg-auto-import-keys ref
				sudo zypper --non-interactive dup --from "redpesk-ci-${ID_REPO}"
				ID_REPO=$(($ID_REPO + 1))
			done
		fi

		#Install base redpesk packages
		if [ "${SPIKPACKINST}" == "no" ]; then
			sudo zypper install -y ${no_recommend_opt} ${LIST_PACKAGE_RPM}
		fi
		;;
	*)
		error_message
		;;
	esac
	;;
fedora)
	case $VERSION_ID in
	39| 40)
		#Add redpesk repos
		sudo dnf install -y dnf-plugins-core

		if [ "${WRITE_CONF}" == "yes" ]; then

			sudo rm -fr "${REPO_CONF_FILE} ${CI_REPO_CONF_FILE}"

			ID_REPO=1

			for repo in ${REDPESK_REPO}; do
				sudo tee --append "${REPO_CONF_FILE}" >/dev/null <<EOF
[redpesk-sdk-$ID_REPO]
name=redpesk-sdk-$ID_REPO
baseurl=${repo}
enabled=1
gpgcheck=1
gpgkey=${repo}/repodata/repomd.xml.key

EOF
				ID_REPO=$(($ID_REPO + 1))
			done

			ID_REPO=1

			for repo in ${REDPESK_CI_REPO}; do
				sudo tee --append "${CI_REPO_CONF_FILE}" >/dev/null <<EOF
[redpesk-ci-$ID_REPO]
name=redpesk-ci-$ID_REPO
baseurl=${repo}
enabled=1
gpgcheck=1
gpgkey=${repo}/repodata/repomd.xml.key
EOF
				ID_REPO=$(($ID_REPO + 1))
			done

		fi
		sudo dnf clean expire-cache
		# Manage the "no recommended option" variable
		no_recommend_opt=""
		if [ "${INSTALL_RECOMMENDED_PKG}" == "no" ]; then
			no_recommend_opt="--setopt=install_weak_deps=False"
		fi
		#Install base redpesk packages
		if [ "${SPIKPACKINST}" == "no" ]; then
			sudo dnf install -y ${no_recommend_opt} ${LIST_PACKAGE_RPM}
		fi
		;;
	*)
		error_message
		;;
	esac
	;;
almalinux)
	case $VERSION_ID in
	8.*|9.*)
		#Add redpesk repos
		sudo dnf install -y dnf-plugins-core
		#Add PowerTools needed for the lib-controller
		case $VERSION_ID in
			8.*)
				if ! dnf repolist --enabled | grep -q "powertools"; then
					sudo dnf config-manager --set-enabled powertools
				fi
				;;
			9.*)
				if ! dnf repolist --enabled | grep -q "powertools"; then
					sudo dnf config-manager --set-enabled crb
				fi
				;;
		esac

		if [ "${WRITE_CONF}" == "yes" ]; then

			sudo rm -fr "${REPO_CONF_FILE} ${CI_REPO_CONF_FILE}"

			ID_REPO=1

			for repo in ${REDPESK_REPO}; do
				sudo tee --append "${REPO_CONF_FILE}" >/dev/null <<EOF
[redpesk-sdk-$ID_REPO]
name=redpesk-sdk-$ID_REPO
baseurl=${repo}
enabled=1
gpgcheck=1
gpgkey=${repo}/repodata/repomd.xml.key

EOF
				ID_REPO=$(($ID_REPO + 1))
			done

			ID_REPO=1

			for repo in ${REDPESK_CI_REPO}; do
				sudo tee --append "${CI_REPO_CONF_FILE}" >/dev/null <<EOF
[redpesk-ci-$ID_REPO]
name=redpesk-ci-$ID_REPO
baseurl=${repo}
enabled=1
gpgcheck=1
gpgkey=${repo}/repodata/repomd.xml.key
EOF
				ID_REPO=$(($ID_REPO + 1))
			done

		fi
		sudo dnf clean expire-cache
		# Manage the "no recommended option" variable
		no_recommend_opt=""
		if [ "${INSTALL_RECOMMENDED_PKG}" == "no" ]; then
			no_recommend_opt="--setopt=install_weak_deps=False"
		fi
		#Install base redpesk packages
		if [ "${SPIKPACKINST}" == "no" ]; then
			sudo dnf install -y ${no_recommend_opt} ${LIST_PACKAGE_RPM}
		fi
		;;
	*)
		error_message
		;;
	esac
	;;
debian)
	case $VERSION_ID in
	11)
		#Add redpesk repos (ca-certificates is here to fix VM CI test)
		sudo apt-get update --yes
		sudo apt-get install -y curl wget add-apt-key gnupg ca-certificates
		ID_REPO=1
		if [ "${WRITE_CONF}" == "yes" ]; then
			sudo rm -fr "${REPO_CONF_FILE}"
			for repo in ${REDPESK_REPO}; do
				#This should be fixed
				wget -O - "${repo}/Release.key" | sudo apt-key add -
				#sudo rm -f  "/etc/apt/trusted.gpg.d/redpesk-sdk-${ID_REPO}.gpg"
				#curl  "${repo}/Release.key" | sudo gpg --no-tty --dearmor --output "/etc/apt/trusted.gpg.d/redpesk-sdk-${ID_REPO}.gpg"
				sudo sh -c 'echo "deb  '"${repo}"' ./" >> '"${REPO_CONF_FILE}"
				ID_REPO=$(($ID_REPO + 1))
			done
		fi
		ID_REPO=1
		if [ "${CI_WRITE_CONF}" == "yes" ]; then
			sudo rm -fr "${CI_REPO_CONF_FILE}"
			for repo in ${REDPESK_CI_REPO}; do
				sudo rm -f "/etc/apt/trusted.gpg.d/redpesk-ci-${ID_REPO}.gpg"
				curl "${repo}/Release.key" | sudo gpg --no-tty --dearmor --output "/etc/apt/trusted.gpg.d/redpesk-ci-${ID_REPO}.gpg"
				sudo sh -c 'echo "deb  '"${repo}"' ./" >> '"${CI_REPO_CONF_FILE}"
				ID_REPO=$(($ID_REPO + 1))
			done
		fi

		sudo apt-get update --yes
		# Manage the "no recommended option" variable
		no_recommend_opt=""
		if [ "${INSTALL_RECOMMENDED_PKG}" == "no" ]; then
			no_recommend_opt="--no-install-recommends"
		fi
		#Install base redpesk packages
		if [ "${SPIKPACKINST}" == "no" ]; then
			sudo apt-get install -y ${no_recommend_opt} ${LIST_PACKAGE_DEB}
		fi
		;;
	*)
		error_message
		;;
	esac
	;;
linuxmint)
	case $VERSION_ID in
	21| 21.1| 21.2| 21.3)
		#Add redpesk repos (ca-certificates is here to fix VM CI test)
		sudo apt-get update --yes
		sudo apt-get install -y curl wget add-apt-key gnupg ca-certificates
		ID_REPO=1
		if [ "${WRITE_CONF}" == "yes" ]; then
			sudo rm -fr "${REPO_CONF_FILE}"
			for repo in ${REDPESK_REPO}; do
				#This should be fixed
				wget -O - "${repo}/Release.key" | sudo apt-key add -
				#sudo rm -f  "/etc/apt/trusted.gpg.d/redpesk-sdk-${ID_REPO}.gpg"
				#curl "${repo}/Release.key" | sudo gpg --no-tty --dearmor --output "/etc/apt/trusted.gpg.d/redpesk-sdk-${ID_REPO}.gpg"
				sudo sh -c 'echo "deb  '"${repo}"' ./" >> '"${REPO_CONF_FILE}"
				ID_REPO=$(($ID_REPO + 1))
			done
		fi
		ID_REPO=1
		if [ "${CI_WRITE_CONF}" == "yes" ]; then
			sudo rm -fr "${CI_REPO_CONF_FILE}"
			for repo in ${REDPESK_CI_REPO}; do
				curl "${repo}/Release.key" | sudo gpg --no-tty --dearmor --output "/etc/apt/trusted.gpg.d/redpesk-ci-${ID_REPO}.gpg"
				sudo sh -c 'echo "deb  '"${repo}"' ./" >> '"${CI_REPO_CONF_FILE}"
				ID_REPO=$(($ID_REPO + 1))
			done
		fi

		sudo apt-get update --yes
		# Manage the "no recommended option" variable
		no_recommend_opt=""
		if [ "${INSTALL_RECOMMENDED_PKG}" == "no" ]; then
			no_recommend_opt="--no-install-recommends"
		fi
		#Install base redpesk packages
		if [ "${SPIKPACKINST}" == "no" ]; then
			sudo apt-get install -y ${no_recommend_opt} ${LIST_PACKAGE_DEB}
		fi
		;;
	*)
		error_message
		;;
	esac
	;;
*)
	error_message
	;;
esac
