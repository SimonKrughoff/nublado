#!/bin/bash

# Copyright 2015 The Kubernetes Authors.
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

function ensure_dirs()
{
    base="/exports"
    for dir in home project scratch software datasets; do
	d="${base}/${dir}"
	reexport=""
	if ! [ -d "${d}" ]; then
	    mkdir -p ${d}
	    case ${dir} in
		project | scratch)
		    chmod 1777 ${d}
		    ;;
	    esac
	    echo ${dir} > ${d}/README.${dir}
	    reexport="${reexport} ${dir}"
	fi
    done
    if [ -n "${reexport}" ]; then
	exportfs -r
	echo "Exported filesystems changed ${reexport}.  Exiting."
	exit 0 # Really!  Otherwise it never exports.
    fi
}

function start()
{

    unset gid
    # accept "-G gid" option
    while getopts "G:" opt; do
        case ${opt} in
            G) gid=${OPTARG};;
        esac
    done
    shift $(($OPTIND - 1))


    # start rpcbind if it is not started yet
    /usr/sbin/rpcinfo 127.0.0.1 > /dev/null 2>&1; s=$?
    if [ $s -ne 0 ]; then
       echo "Starting rpcbind"
       /usr/sbin/rpcbind -w
    fi

    mount -t nfsd nfds /proc/fs/nfsd

    # -V 3: enable NFSv3
    /usr/sbin/rpc.mountd -N 2 -V 3

    /usr/sbin/exportfs -r
    # -G 10 to reduce grace time to 10 seconds (the lowest allowed)
    /usr/sbin/rpc.nfsd -G 10 -N 2 -V 3
    /usr/sbin/rpc.statd --no-notify
    echo "NFS started"
}

function stop()
{
    echo "Stopping NFS"

    /usr/sbin/rpc.nfsd 0
    /usr/sbin/exportfs -au
    /usr/sbin/exportfs -f

    kill $( pidof rpc.mountd )
    umount /proc/fs/nfsd
    echo > /etc/exports
    exit 0
}


trap stop TERM

ensure_dirs
start "$@"

# Ugly hack to do nothing and wait for SIGTERM
while true; do
    d=$(date)
    echo "NFS Server still running at: ${d}"
    sleep 60
done
