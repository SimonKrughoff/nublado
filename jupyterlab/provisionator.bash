#!/bin/bash

function setup_user() {
    # All the sudo functions happen in here
    local sudo="/bin/sudo"
    local user_provisioning=""
    local change_staging_id=""
    local write_user_sudoer=""
    id -u ${U_NAME} 2> /dev/null 1>&2
    if [ $? -ne 0 ]; then
	user_provisioning="${sudo} ${PROVDIR}/addlabuser.bash -n ${U_NAME}"
	if [ -n "${EXTERNAL_UID}" ]; then
	    user_provisioning="${user_provisioning} -u ${EXTERNAL_UID}"
	fi
	if [ -n "${EXTERNAL_GROUPS}" ]; then
	    user_provisioning="${user_provisioning} -g ${EXTERNAL_GROUPS}"
	fi
	change_staging_id="${sudo} ${PROVDIR}/changestagingid.bash ${U_NAME}"
	write_user_sudoer="${sudo} ${PROVDIR}/writeusersudoer.bash ${U_NAME}"
	${user_provisioning} || debug_pause
	${change_staging_id} || debug_pause
	${write_user_sudoer} || debug_pause
    fi
}

function forget_extraneous_vars() {
    purge_docker_vars FILESERVER RPCBIND:111,NFS:2049,MOUNTD:20048
}

function purge_docker_vars() {
    local n=$1
    local plist=$2
    local purge="${n}_PORT"
    local portmap=""
    local portname=""
    local portnum=""
    local i=""
    local k=""
    for i in "HOST" "PORT"; do
	purge="${purge} ${n}_SERVICE_${i}"
    done
    for portmap in $(echo ${plist} | tr "," "\n"); do
        portname=$(echo ${portmap} | cut -d ':' -f 1)
	purge="${purge} ${n}_SERVICE_PORT_${portname}"
        portnum=$(echo ${portmap} | cut -d ':' -f 2)
	for prot in "TCP" "UDP"; do
	    k="${n}_PORT_${portnum}_${prot}"
	    purge="${purge} ${k}"
	    for i in "ADDR" "PORT" "PROTO"; do
		purge="${purge} ${k}_${i}"
	    done
	done
    done
    unset ${purge}
}

function debug_pause() {
    if [ -n "${DEBUG}" ]; then
	echo 1>&2 "Previous command failed.  Debug_pause in effect."
	sleep 600
    fi
}

## Begin mainline code. ##
if [ -n "${DEBUG}" ]; then
    set -x
fi
U_NAME="${JUPYTERHUB_USER}"
JLDIR="/opt/lsst/software/jupyterlab"
PROVDIR="${JLDIR}/prov"
PUSER="provisionator"
user_sudo=""

if [ $(id -u) -eq 0 ]; then
    echo 1>&2 "Warning: running as UID 0."
    id ${PUSER} 2>&1 >/dev/null
    rc=$?
    if [ "${rc}" -eq 0 ]; then
	echo 1>&2 "Attempting restart as provisioning user."
	exec /bin/sudo -u ${PUSER} -E \
	     /opt/lsst/software/jupyterlab/provisionator.bash
    fi
fi
if [ -z "${U_NAME}" ]; then
    echo 1>&2 "Warning: no target user name."
fi
if [ -n "${U_NAME}" ]; then
    setup_user
    user_sudo="/bin/sudo -E -u ${U_NAME} "
fi
forget_extraneous_vars
exec ${user_sudo} ${JLDIR}/runlab.sh
