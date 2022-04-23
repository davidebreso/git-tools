#!/bin/bash

pkg="${@}"
while [[ "${pkg}" != '' ]] ; do
    if [[ -e "${pkg}/APPINFO" ]] ; then
        bbedit "${pkg}/APPINFO" || vi "${pkg}/APPINFO"
    fi;
    echo Enter package name
    read npkg
    if [[ -e "${pkg}/APPINFO" ]] ; then
        cd "${pkg}"
        fdvcs.sh -cpr -s -c "update metadata" &
        cd ..
    fi;
    pkg="${npkg}"
done