#!/bin/bash

[[ "$(uname)" == "Darwin" ]] && MACOS=true || unset MACOS

UPPER_CHARS='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
LOWER_CHARS='abcdefghijklmnopqrstuvwxyz'
SPACE_CHARS=' '

while [[ ${#SPACE_CHARS} -lt 128 ]] ; do
	SPACE_CHARS="${SPACE_CHARS}${SPACE_CHARS}"
done

function crlf () {
    local line
    local rc=$(echo -e "\r")
    while IFS=""; read -r line ; do
        line="${line//${rc}}"
        echo "${line}${rc}"
    done
}

function lowerCase () {
    if [[ ${MACOS} ]] ; then
        # SLower method not using ${variable,,}
        local i c o
        for ((i=0;i<${#1};i++)) ; do
            c="${1:${i}:1}"
            if [[ "${c//[${UPPER_CHARS}]}" != "${c}" ]] ; then
                c="${UPPER_CHARS%%${c}*}"
                c="${LOWER_CHARS:${#c}:1}"
            fi
            o="${o}${c}"
        done
        echo "${o}"
    else
        echo "${1,,}"
    fi
}

function upperCase () {
    if [[ ${MACOS} ]] ; then
        # Slower method not using ${variable^^}
        local i c o
        for ((i=0;i<${#1};i++)) ; do
            c="${1:${i}:1}"
            if [[ "${c//[${LOWER_CHARS}]}" != "${c}" ]] ; then
                c="${LOWER_CHARS%%${c}*}"
                c="${UPPER_CHARS:${#c}:1}"
            fi
            o="${o}${c}"
        done
        echo "${o}"
    else
        echo "${1^^}"
    fi
}

function case_match_file () {
    local i c

    local x="${1%%/*}"
    local u=$(upperCase "${x}")
    local t="${1:$(( ${#x} + 1 ))}"

    for i in "${PWD}"/* ; do
        c=$(upperCase "${i##*/}")
        if [[ "${u}" == "${c}" ]] ; then
            x="${i##*/}"
            break
        fi
    done

    if [[ ${#t} -eq 0 ]] ; then
        echo "${x}"
    elif [[ -d "${x}" ]] ; then
        local hwd="${PWD}"
        cd "${x}"
        echo "${x}/$(case_match_file ${t})"
        cd "${hwd}"
    else
        echo "${x}/${t}"
    fi
}

lsm=$(case_match_file "appinfo/${PWD##*/}.LSM")
grep -iv "^modified-date:\|^changes:\|http://gitlab.com/FDOS/" "${lsm}" | crlf >temp-appinfo.lsm
cat temp-appinfo.lsm
mv temp-appinfo.lsm "${lsm}"
fdvcs.sh -cpr -c "updated LSM"
exit 0