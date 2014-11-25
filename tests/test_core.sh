#!/bin/bash
# To test this module you need to run it inside a Archlinux system. Also, the following packages needs to be installed:
# bash
# pacman
# arch-install-scripts
# proot
# coreutils
# grep
# sudo
# gawk

source "$(dirname $0)/utils.sh"
CURRPWD=$PWD
JUJU_HOME=""

function set_up(){
    cd $CURRPWD
    JUJU_HOME=$(TMPDIR=/tmp mktemp -d -t jujuhome.XXXXXXXXXX)
    source "$(dirname $0)/../lib/core.sh"
    ORIGIN_WD=$(TMPDIR=/tmp mktemp -d -t jujuowd.XXXXXXXXXX)
    cd $ORIGIN_WD
    JUJU_TEMPDIR=$(TMPDIR=/tmp mktemp -d -t jujutemp.XXXXXXXXXX)

    trap - QUIT EXIT ABRT KILL TERM INT
    trap "rm -rf ${JUJU_HOME}; rm -rf ${ORIGIN_WD}; rm -rf ${JUJU_TEMPDIR}" EXIT QUIT ABRT KILL TERM INT
}


function tear_down(){
    rm -rf $JUJU_HOME
    rm -rf $ORIGIN_WD
    rm -rf $JUJU_TEMPDIR
    trap - QUIT EXIT ABRT KILL TERM INT
}

function test_is_juju_installed(){
    is_juju_installed
    is_equal $? 1 || return 1
    touch $JUJU_HOME/just_file
    is_juju_installed
    is_equal $? 0 || return 1
}


function test_setup_juju(){
    wget_mock(){
        # Proof that the setup is happening
        # inside $JUJU_TEMPDIR
        local cwd=${PWD#${JUJU_TEMPDIR}}
        local parent_dir=${PWD%${cwd}}
        is_equal $JUJU_TEMPDIR ${parent_dir} || return 1
        touch file
        tar -czvf juju-${ARCH}.tar.gz file
    }
    WGET=wget_mock
    setup_juju 1> /dev/null
    [ -e $JUJU_HOME/file ] || return 1
    [ -e $JUJU_HOME/run/lock ] || return 1

    export -f setup_juju
    JUJU_ENV=1 bash -ic "setup_juju" &> /dev/null
    is_equal $? 1 || return 1
}


function test_setup_from_file_juju(){
    touch file
    tar -czvf juju-${ARCH}.tar.gz file 1> /dev/null
    setup_from_file_juju juju-${ARCH}.tar.gz 1> /dev/null
    [ -e $JUJU_HOME/file ] || return 1
    [ -e $JUJU_HOME/run/lock ] || return 1

    export -f setup_from_file_juju
    bash -ic "setup_from_file_juju noexist.tar.gz" &> /dev/null
    is_equal $? 1 || return 1

    export -f setup_from_file_juju
    JUJU_ENV=1 bash -ic "setup_from_file_juju" &> /dev/null
    is_equal $? 1 || return 1
}


function test_run_juju_as_root(){
    install_mini_juju
    CHROOT="sudo $CHROOT"
    SH="type -t type"
    local output=$(run_juju_as_root)
    is_equal $output "builtin" || return 1
    local output=$(run_juju_as_root pwd)
    is_equal $output "/" || return 1
    run_juju_as_root "[ -e /run/lock ]"
    is_equal $? 0 || return 1
    [ -e $JUJU_HOME/${HOME} ] || return 1

    export -f run_juju_as_root
    JUJU_ENV=1 bash -ic "run_juju_as_root" &> /dev/null
    is_equal $? 1 || return 1
}

function test_run_juju_as_user(){
    install_mini_juju
    local output=$(run_juju_as_user "" "mkdir -v /newdir2")
    is_equal "$output" "/usr/bin/mkdir: created directory '/newdir2'" || return 1
    [ -e $JUJU_HOME/newdir2 ]
    is_equal $? 0 || return 1

    SH="mkdir -v /newdir"
    local output=$(run_juju_as_user "")
    is_equal "$output" "/usr/bin/mkdir: created directory '/newdir'" || return 1
    [ -e $JUJU_HOME/newdir ]
    is_equal $? 0 || return 1
}

function test_run_juju_as_user_proot_args(){
    install_mini_juju
    run_juju_as_user "--help" "" 1> /dev/null
    is_equal $? 0 || return 1
    run_juju_as_user "--helps" "" &> /dev/null
    is_equal $? 1 || return 1

    mkdir $JUJU_TEMPDIR/newdir
    touch $JUJU_TEMPDIR/newdir/newfile
    run_juju_as_user "-b $JUJU_TEMPDIR/newdir:/newdir" "ls -l /newdir/newfile" 1> /dev/null
    is_equal $? 0 || return 1
}

function test_run_juju_as_user_seccomp(){
    install_mini_juju
    local output=$(run_juju_as_user "" "env" | grep "PROOT_NO_SECCOMP")
    is_equal $output "" || return 1

    TRUE="/usr/bin/false"
    local output=$(run_juju_as_user "" "env" | grep "PROOT_NO_SECCOMP")
    is_equal $output "PROOT_NO_SECCOMP=1" || return 1
}

function test_run_juju_as_fakeroot(){
    install_mini_juju
    local output=$(run_juju_as_fakeroot "" "id" | awk '{print $1}')
    is_equal "$output" "uid=0" || return 1
}

function test_delete_juju(){
    install_mini_juju
    echo "N" | delete_juju 1> /dev/null
    is_juju_installed
    is_equal $? 0 || return 1
    echo "Y" | delete_juju 1> /dev/null
    is_juju_installed
    is_equal $? 1 || return 1

    export -f delete_juju
    JUJU_ENV=1 bash -ic "delete_juju" &> /dev/null
    is_equal $? 1 || return 1
}


for func in $(declare -F | grep test_ | awk '{print $3}' | xargs)
do
    set_up
    $func && echo -e "${func}...\033[1;32mOK\033[0m" || echo -e "${func}...\033[1;31mFAIL\033[0m"
    tear_down
done
