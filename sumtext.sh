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

function NoCtrlChars () {
    (
        export LC_CTYPE=C
        tr -d '[:cntrl:]'
    )
}

function leftTrim () {
    local x="$@"
    local t=""
    while [[ "${t}" != "$x" ]] ; do
        t="${x}"
        x="${x#${x%%[![:space:]]*}}"
    done
    echo "${x}"
}

function rightTrim () {
    local x="$*"
    local t=""
    while [[ "${t}" != "$x" ]] ; do
        t="${x}"
        x="${x%${x##*[![:space:]]}}"
    done
    echo "${x}"
}

function trim () {
    local x=$(rightTrim "$@")
    x=$(leftTrim "$x")
    echo "$x"
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

function showpkg () {
# A flight simulator that focuses on real
	local t="${1##*/}"
	t="${t%%.*}"
	t="# ${t} "
	while [[ ${#t} -lt 39 ]] ; do
		t="#${t}#"
	done
	t="${t:0:39}"
	local b='-'
	while [[ ${#b} -lt 39 ]] ; do
		b="${b}-"
	done
	echo "${t}"
	local d=$(grep -i "Description:" "${1}" 2>/dev/null | cut -d ':' -f 2- )
	local s=$(grep -i "Summary:" "${1}" 2>/dev/null | cut -d ':' -f 2- )
	d=$(trim "${d}" | NoCtrlChars)
	s=$(trim "${s}" | NoCtrlChars)
	[[ "${s}" == "" ]] && s="${d}"

	echo "${d}"
	echo "${b}"
	echo "${s}" | tr "|" "\n"
	echo

}

function changepkg () {
	# [[ "${pkg}" != "ELIZA" ]] && return 0
	local lsm=$(case_match_file "${pkg}/appinfo/${pkg}.LSM")
	if [[ ! -f "${lsm}" ]] ; then
		echo "${pkg}, not found"
		return 0
	fi

	local ods="${description}"
	local x u w n
	while IFS=''; read -r x ; do
		x="${x//[\r\v\f\b\n\]}"
		u=$(upperCase "${x//[[:cntrl:]]}")
		if [[ "${u:0:12}" == 'DESCRIPTION:' ]] ; then
			[[ ${#description} -eq 0 ]] && continue
			n="${x:12}"
			u=$(leftTrim "${n}")
			[[ $(( ${#n} - ${#u} )) -eq 0 ]] && description=" ${description}"
			echo "${x:0:12}${n:0:$(( ${#n} - ${#u} ))}${description}"
			description=
			continue
		elif [[ "${u:0:8}" == 'SUMMARY:' ]] ; then
			[[ ${#summary} -eq 0 ]] && continue
			n="${x:8}"
			u=$(leftTrim "${n}")
			[[ $(( ${#n} - ${#u} )) -eq 0 ]] && summary=" ${summary}"
			echo "${x:0:8}${n:0:$(( ${#n} - ${#u} ))}${summary}"
			summary=
			continue
		elif [[ "${u}" == "END" ]] ; then
			if [[ ${#description} -ne 0 ]] ; then
				echo "Description: ${description}"
			fi
			if [[ ${#summary} -ne 0 ]] ; then
				if [[ ! "${ods}" == "${summary}" ]] ; then
					echo "Summary: ${summary}"
				fi
			fi
		fi
		echo "${x}"
	done< "${lsm}" | crlf >temp-appinfo.lsm
	u=$(diff -i -E -b -B  -t -q "${lsm}" temp-appinfo.lsm)
	if [[ ${#u} -ne 0 ]] ; then
		echo "${pkg}, update LSM metadata"
		mv temp-appinfo.lsm "${lsm}"
		pushd "${lsm%%/*}" >/dev/null
		# fdvcs.sh -cpr -c "Metadata update" || exit $?
		git commit -a -m "Metadata update" || exit $?
		git push || exit $?
		popd >/dev/null
	else
		echo "${pkg}, unchanged"
		rm temp-appinfo.lsm
	fi
}


function changepkgs () {

	pkg=
	description=
	summary=

	local line
	while IFS=''; read -r line ; do
		line="${line//[[:cntrl:]]}"
		if [[ ${#line} -eq 0 ]] ; then
			continue
		elif [[ "${line:0:5}" == "#####" ]] ; then
			if [[ ! "${pkg}" == "" ]] ; then
				changepkg "${pkg}"
			fi
			pkg="${line//[ #]}"
			description=
			summary=
		elif [[ ${#description} -eq 0 ]] ; then
			description="${line}"
		elif [[ "${line:0:5}" == "-----" ]] ; then
			continue
		elif [[ ${#summary} -eq 0 ]] ; then
			summary="${line}"
		else
			summary="${summary}|${line}"
		fi;

	done< "${1}"

}



if [[ "${1}" == "" ]] ; then
	for i in */APPINFO/*.LSM */APPINFO/*.lsm ; do
		[[ ! -f "${i}" ]] && continue
		showpkg "${i}"
	done
elif [[ "${1}" == "-apply" ]] ; then
	if [[ "${2}" == "" ]] || [[ ! -f "${2}" ]]; then
		echo "apply what?"
	else
		changepkgs "${2}"
	fi
else
	echo "usage sumtext.sh: [options]"
	echo
	echo "	[no options] 	output package descriptions and summary to stdout"
	echo
	echo " 	-apply file	update package metadata using sumtext formated file"
	echo

fi