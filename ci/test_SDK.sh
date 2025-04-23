#!/bin/bash
# shellcheck disable=SC1091
source /etc/os-release

set -x

BRANCH="upstream"

source test_SDK_var.sh
#test arguments
while [[ $# -gt 0 ]]; do
    OPTION="$1"
    case $OPTION in
    -b | --branch)
        BRANCH="$2"
        shift 2;
    ;;
    esac
done

declare -A list_distro_name
list_distro_name=(
["/almalinux/8/"]="AlmaLinux_8"
["/almalinux/9/"]="AlmaLinux_9"
["/fedora/40/"]="Fedora_40"
["/fedora/41/"]="Fedora_41"
["/fedora/42/"]="Fedora_42"
["/debian/11/"]="Debian_11"
["/debian/12/"]="Debian_12"
["/ubuntu/22.04/"]="xUbuntu_22.04"
["/ubuntu/24.04/"]="xUbuntu_24.04"
["/linuxmint/21.3/"]="xUbuntu_22.04"
["/opensuse-leap/15.6/"]="openSUSE_Leap_15.6"
["/opensuse-leap/15.5/"]="openSUSE_Leap_15.5"
)

RESULT_DST="/home/vagrant/ci/${ID}_${VERSION_ID}_${BRANCH}_xunit.xml"
LOGFILETEST="/home/vagrant/ci/test_${ID}_${VERSION_ID}_${BRANCH}.log"
mkdir -p "$(dirname "${RESULT_DST}")"

exitval=0

test() {
    #write the tests result in the xunit.xml file
    echo "<testcase classname='VMsdk.${ID}.${VERSION_ID}.${BRANCH}' file='VMsdk.sh' line='$3' name='$2_${ID}.${VERSION_ID}.$1'>" >> "${RESULT_DST}"
    if [ "$1" = "success" ]; then
        echo "</testcase>" >> "${RESULT_DST}"
    elif [ "$1" = "error" ]; then
        echo -e "<error>$4</error>\n</testcase>" >> "${RESULT_DST}"
        exitval=1
    elif [ "$1" = "skipped" ]; then
        echo -e "<skipped> $skip </skipped>\n</testcase>" >> "${RESULT_DST}"
    elif [ "$1" = "failure" ]; then
        echo -e "<failure/>\n</testcase>" >> "${RESULT_DST}"
        exitval=1
    fi
}

sdktest () {
    #install and test the SDK
    (( line=LINENO + 1 ))
    DISTRO_NAME="${list_distro_name[$1]}"
    if [ -z "${DISTRO_NAME}" ]; then
        echo "No DISTRO_NAME for this distribution"
        return 1
    fi
    if [ "${BRANCH}" == "upstream" ]; then
        if ./install-redpesk-sdk.sh ; then
            test "success" "test_native_install" "$line"
        else 
            test "error" "test_native_install" "$line"
        fi
    else
        if ./install-redpesk-sdk.sh -r "http://silo.redpesk.iot/redpesk/private/sdk/obs/${BRANCH}/sdk-third-party/${DISTRO_NAME}/latest/" \
                                    -r "http://silo.redpesk.iot/redpesk/private/sdk/obs/${BRANCH}/sdk/${DISTRO_NAME}/latest/" \
                                    -i "http://silo.redpesk.iot/redpesk/private/tools/obs/master/tools-third-party/${DISTRO_NAME}/latest/" \
                                    -i "http://silo.redpesk.iot/redpesk/private/tools/obs/master/tools/${DISTRO_NAME}/latest/" \
                                    ; then
            test "success" "test_native_install" "$line"
        else 
            test "error" "test_native_install" "$line"
        fi
    fi
    #install helloword-binding and helloword-binding-test
    case ${ID} in
        ubuntu | debian | linuxmint)
            (( line=LINENO + 1 ))
            if sudo apt-get install helloworld-binding-bin helloworld-binding-test ;then
                test "success" "test_helloworld_binding" "$line"
            else
                test "error" "test_helloworld_binding" "$line"
            fi
        ;;
        opensuse-leap)
            (( line=LINENO + 1 ))
            if sudo zypper --no-gpg-checks install -y helloworld-binding helloworld-binding-test; then
                test "success" "test_helloworld_binding" "$line"
            else
                test "error" "test_helloworld_binding" "$line"
            fi
        ;;
        fedora| almalinux)
            (( line=LINENO + 1 ))
            if sudo dnf install -y --nogpgcheck helloworld-binding helloworld-binding-test; then
                test "success" "test_helloworld_binding" "$line"
            else
                test "error" "test_helloworld_binding" "$line"
            fi
        ;;
        *)
            echo "error: distribution not supported"
            return 1
        ;;
    esac
    #test afm-test command
    (( line=LINENO + 1 ))
    echo "Start helloworld-binding test"

    INSTALL_PATH="/usr/redpesk"

    if [ ! -d "${INSTALL_PATH}" ]; then
        #This is the old path
        INSTALL_PATH="/var/local/lib/afm/applications"

        if [ ! -d "${INSTALL_PATH}" ]; then
            test "error" "test_afm-test" "$line" "Installation directory is missing"
            return 1
        fi
    fi

    if sudo afm-test --logfile "${LOGFILETEST}" "${INSTALL_PATH}/helloworld-binding" "${INSTALL_PATH}/helloworld-binding-test" ; then
        test "success" "test_afm-test" "$line"
        #test the afm-test command results
        if [ ! -f "${LOGFILETEST}" ]; then
            test "error" "test_afm-test-result" "$line" "No ${LOGFILETEST} generated"
        elif grep "ERROR:" "${LOGFILETEST}"; then
            error=$(grep "ERROR:" "${LOGFILETEST}" | cut -d">" -f2)
            test "error" "test_afm-test-result" "$line" "$error"
        else
            nofail=$(grep -c "0 failures" "${LOGFILETEST}")
            testskip=$(grep -c "skipped" "${LOGFILETEST}")
            if [ "$nofail" -eq "0" ] || [ "$nofail" -eq "1" ]; then
                test "failure" "test_afm-test-result" "$line"
            else 
                test "success" "test_afm-test-result" "$line"
            fi
            if [ "$testskip" -ne "0" ]; then
                skip=$(grep "skipped" "${LOGFILETEST}" | cut -d"," -f4)
                test "skipped" "test_afm-test-result" "$line"
            fi
        fi
    else 
        test "error" "test_afm-test" "$line"
    fi
}

echo "distribution: $PRETTY_NAME"
#detect the OS and launch the sdktest function
case ${ID} in
    ubuntu | linuxmint)
        sudo sed -i '17inameserver 10.16.2.10\ ' /etc/resolv.conf
        ;;
    debian)
        sudo sed -i '3inameserver 10.16.2.10\ ' /etc/resolv.conf
        ;;
    almalinux)
        VERSION_ID=$(echo ${VERSION_ID} | cut -d"." -f1)
        ;;
esac
echo -e '<?xml version="1.0" encoding="UTF-8"?>\n<testsuites>\n<testsuite>' > "${RESULT_DST}"
sdktest "/${ID}/${VERSION_ID}/"
echo -e '</testsuite>\n</testsuites>' >> "${RESULT_DST}"
exit "$exitval"
