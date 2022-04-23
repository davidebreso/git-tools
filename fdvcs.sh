#!/bin/bash

# Created 2021 by Jerome Shidel
# Released to Public Domain

# Multi-platform, version control system utility

# Script settings

CONFIG="${HOME}/.fdvcs/settings.cfg"
STAMPDB="${HOME}/.fdvcs/timestamps"
STAMPFILE='.timestamps'

PKGCVSURL="https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/repositories/latest/listing.csv"
GITREPO="git@gitlab.com:FreeDOS"
GITHTTP="https://gitlab.com/FreeDOS"
NLSREPO="https://github.com/shidel/fd-nls.git"

# script auto-configuration stuff

SWD="${PWD}"

unset TESTING QUIET VERBOSE

unset VCSBASE
unset PKGCVS
unset XWD
unset NOAUTOTS NOFOLLOW NOEMPTY NOXMSGS ASSUME_TS HTTPS_MODE

[[ "$(uname)" == "Darwin" ]] && MACOS=true || unset MACOS

if [[ -e "${CONFIG}" ]] ; then
    . "${CONFIG}"
    if [[ $? -ne 0 ]] ; then
        echo "configuration file '${CONFIG}' is corrupt"
        exit 1
    fi
fi

# Help section

function display_help () {
    echo "usage: ${0##*/} [options]"
    echo
    echo "general modifier options (anywhere on the command line):"
    echo
    echo "  -h              show help and exit"
    echo
    echo "  -t              test mode"
    echo "  -q              QUIET mode"
    echo "  -v              verbose mode"
    echo
    echo "  -x              do not automatically restore or preserve timestamps with"
    echo "                  commmit or cloning/checkout"
    echo
    echo "  -nfl            do Not Follow Linked directories (only applies non-VCS,"
    echo "                  like -p, -pa and -sda)"
    echo
    echo "  -ned            Ignore empty directories for -p and -pa (otherwise their"
    echo "                  timestamps can effect higher directories)"
    echo
    echo "repository timestamp functions:"
    echo
    echo "  -s              restore and preserve modified VCS file timestamps"
    echo "  -p              update path/dir trees to newest file timestamp"
    echo "  -pa             like -p, but operates on dir tree not the repository"
    echo
    echo "  -jat            just assume timestamps need adjusted (don't waste time "
    echo "                  hashing). Probably should only use at project checkout."
    echo
    echo "repository functions (automatic timestamp handling, unless -x is used)"
    echo
    echo "  -co (project)   checkout/clone FreeDOS package from the Archive"
    echo "  -coa            checkout/clone all packages from the Archive (takes a while)"
    echo "  -conls          checkout/clone the Language Translations (FD-NLS) project"
    echo
    echo "  -https          use https instead of ssh to checkout/clone projects"
    echo
    echo "  -c (message)    commit and push project changes to the GIT/SVN repository"
    echo
    echo "timestamp database functions: "
    echo
    echo "  (Generally you should avoid the following options. They are strictly based on"
    echo "  file hashing and most do not update or use the VCS timestamp file at all)"
    echo
    echo "  -sdt            restore and preserve using database and timpstamp file"
    echo
    echo "  -sdv            restore and preserve VCS file timestamps (DB only)"
    echo "  -sda            restore and preserve all files timestamps (DB only,"
    echo "                  current dir tree not the VCS repository)"
    echo
    echo "miscellaneous functions:"
    echo
    echo "  -fe (commands)  for each project in the current directory perform commands"
    echo "  -fex (command)  for each project in the current dir perform an external command"
    echo
    echo "  -nls            update the NLS files for a project"
    echo "  -pkg (location) compress the project into a package and store it at location"
    echo
    echo "  -cpr            create a project root director INDEX.md file based on metadata"
    echo
    echo "  -b              commits any changes then creates a new git branch and switches to it"
    echo
    echo "  -crlf           updates files in some directories to CRLF"
    echo
    exit 0
}

function display_seehelp () {
    if [[ ${#*} -eq 0 ]] ; then
        echo "missing options: see ${0##*/} --help"
    else
        echo "invalid option '$*': see ${0##*/} --help"
    fi
    exit 1
}

# generic support functions
# Easier to use external functions like TR, but usually faster to stay in bash

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

function rightPad () {
	if [[ ${3} ]] ; then # TRUE = Also crop at length
		local x="${1}${SPACE_CHARS:0:$(( $2 - ${#1} ))}"
		echo "${x:0:${2}}"
	else
		echo "${1}${SPACE_CHARS:0:$(( $2 - ${#1} ))}"
	fi
}

function leftPad () {
	if [[ ${3} ]] ; then # TRUE = Also crop at length
		local x="${SPACE_CHARS:0:$(( $2 - ${#1} ))}${1}"
		echo "${x:0:${2}}"
	else
		echo "${SPACE_CHARS:0:$(( $2 - ${#1} ))}${1}"
	fi
}

function leftTrim () {
    local x="$@"
    local t=""
    while [[ "${t}" != "${x}" ]] ; do
        t="${x}"
        x="${x#${x%%[![:space:]]*}}"
    done
    echo "${x}"
}

function rightTrim () {
    local x="$*"
    local t=""
    while [[ "${t}" != "${x}" ]] ; do
        t="${x}"
        x="${x%${x##*[![:space:]]}}"
    done
    echo "${x}"
}

function trim () {
    local x=$(rightTrim "${@}")
    x=$(leftTrim "${x}")
    echo "${x}"
}

function epoch_to_date () {
    if [[ ${MACOS} ]] ; then
        # macOS Version
        date -r ${1} +"%C%y%m%d%H%M.%S"
    else
        # Linux Version
        date -d @${1} +"%C%y%m%d%H%M.%S"
    fi
}

function pluralString () {
    if [[ ${1} -eq 1 ]] ; then
      echo "${3}"
    else
      [[ "${2}" == '' ]] && echo "s" || echo "${2}"
    fi
}

function get_csv_field () {
    local idx=$1
    local index=0
    local ret=1
    shift
    local line="$@"
    local flag bit field
    while [[ "${line}" != '' ]] ; do
        (( index++ ))
        flag=
        field=
        # parse next field
        while [[ "${line}" != "" ]]  && [[ ! $flag ]]; do
            if [[ "${line:0:1}" == '"' ]] ; then
                line="${line:1}"
                if [[ "${line:0:1}" == '"' ]] ; then
                    field="${field}\""
                    line="${line:1}"
                fi
                bit="${line%%\"*}"
                line="${line:1}"
            else
                bit="${line%%\,*}"
                [[ "${line:${#bit}}" == ',' ]] && flag=plusone
                line="${line:1}"
                [[ ! $flag ]] && flag=done
            fi
            line="${line:${#bit}}"
            field="${field}${bit}"
            # [[ "${line}" == ',' ]] && [[ "${flag}" == "," ]]  && plusone=yes
        done
        if [[ $idx -eq $index ]] ; then
            echo "$field"
            ret=0
            break;
        fi
    done
    return $ret
}

# vcs generic functions
function set_vcs_base () {
    [[ "${VCSBASE}" != "" ]] && return 0
    [[ "${XWD}" == '' ]] && local b="${SWD}" || local b="${XWD}"
    while [[ "${b}" != '' ]] ; do
        [[ -d "${b}/.git" ]] && break
        [[ -d "${b}/.svn" ]] && break
        b="${b%/*}"
    done
    if [[ "${b}" != '' ]] ; then
        VCSBASE="${b}"
        [[ ${VERBOSE} ]] && echo "VCS root directory is ${VCSBASE}"
    else
        [[ ! ${QUIET} ]] && echo "unable to locate VCS root directory" >&2
        exit 1
    fi
    cd "${VCSBASE}"
    return 0
}

function file_hash () {
    local sha=$(shasum -a 512 "${1}" 2>/dev/null)
    # [[ "${sha}" == '' ]] && sha=$(shasum -a 384 "${1}" 2>/dev/null)
    # [[ "${sha}" == '' ]] && sha=$(shasum -a 256 "${1}" 2>/dev/null)
    # [[ "${sha}" == '' ]] && sha=$(shasum -a 224 "${1}" 2>/dev/null)
    # [[ "${sha}" == '' ]] && sha=$(shasum -a 1 "${1}" 2>/dev/null)
    # [[ "${sha}" == '' ]] && [[ ! ${MACOS} ]] && sha=$(md5sum "${1}" 2>/dev/null)
    # [[ "${sha}" == '' ]] && [[ ${MACOS} ]] && sha=$(md5 "${1}" 2>/dev/null | cut -d '=' -f 2 | tr -d ' ' )
    sha="${sha%% *}"
    if [[ "${sha}" == '' ]] ; then
        echo "unable to hash '${1}'" >&2
        return 1
    fi
    echo "${sha}"
    return 0
}

function file_modified () {
    if [[ ${MACOS} ]] ; then
        stat -f %m "${1}" 2>/dev/null
        return $?
    else
        stat --format %Y "${1}" 2>/dev/null
        return $?
    fi
}

function list_vcs_files () {
    local ret=1
    if [[ -d ".git" ]] ; then
        git ls-files
        ret=$?
    fi
    if [[ -d ".svn" ]] ; then
        svn ls -R | while IFS='' ; read -r line ; do
            [[ -d "${line}" ]] && continue
            echo "${line}"
        done
        ret=$?
    fi
    return ${ret}
}

function list_all_files () {
    local ret=0
    local hwd="${PWD}"
    local i
    for i in * ; do
        if [[ -d "${i}" ]] ; then
            [[ ${NOFOLLOW} ]] && [[ -L "${i}" ]] && continue
            cd "${i}" && list_all_files "${1}${i}/"
            cd "${hwd}"
        elif [[ -f "${i}" ]] ; then
            echo "${1}${i}"
        fi

    done
    return ${ret}
}

function get_file_list () {
    if [[ ${#*} -eq 0 ]] ; then
        list_all_files
        return $?
    fi
    local hwd="${PWD}"
    local ret=0
    while [[ ${#*} -gt 0 ]] && [[ ${ret} -eq 0 ]]; do
        cd "${1}" || ret=$?
        if [[ ${ret} -eq 0 ]] ; then
            list_all_files || ret=$?
        fi
        cd "${hwd}"
        shift
    done
    return ${ret}
}

function save_setting {
    if [[ ! -e "${CONFIG}" ]] ; then
        mkdir -p "${CONFIG%/*}" || exit 1
        echo "# Please note, this settings file is cumulative. Settings are never">"${CONFIG}"
        echo "# removed. They are simple overriden by later settings. This is">>"${CONFIG}"
        echo "# intentional and facilitates the ability to view previous settings.">>"${CONFIG}"
    fi
    echo >>"${CONFIG}"
    echo "# Settings change on $(date)">>"${CONFIG}"
    echo "${1}='${2}'">>"${CONFIG}"
}

# vcs specific functions ------------------------------------------------------

# timestamp functions

function stamper_save () {
    set_vcs_base
    [[ ${ASSUME_TS} ]] && return 0
    if [[ ! ${TESTING} ]]; then
        echo "# Version Control System file timestamp preservation file">"${STAMPFILE}"
        echo "# Timestamps can be saved and restored using the tools/fdvcs.sh utility">>"${STAMPFILE}"
        echo "# which can be found in the 'Package Development Kit' project">>"${STAMPFILE}"
        echo "# https://gitlab.com/FDOS/devel/pkgdevel">>"${STAMPFILE}"
        # echo "# Last updated $(date)">>"${STAMPFILE}"
        echo >>"${STAMPFILE}"
        while IFS=''; read -r line ; do
            [[ "${line}" == "${STAMPFILE}" ]] && continue
            if [[ ! -f "${line}" ]] ; then
                [[ ! ${QUIET} ]] && echo "file not present '${line}'"
                continue
            fi
            fhash=$(file_hash "${line}")
            [[ $? -ne 0 ]] && continue

            fstamp=$(file_modified "${line}")
            [[ ${VERBOSE} ]] && echo "record timestamp for ${line}"
            echo "${fstamp} ${fhash} ${line}">>"${STAMPFILE}"
        done <<< "$(list_vcs_files)"
        [[ -d ".git" ]] && git add "${STAMPFILE}"
        [[ -d ".svn" ]] && svn add "${STAMPFILE}" 2>/dev/null
    else
        [[ ${VERBOSE} ]] && echo "record timestamp for all files"
    fi
}

function stamper () {
    set_vcs_base
    local line fhash fstamp fname thash tstamp
    if [[ -f "${STAMPFILE}" ]] ; then
        while IFS=''; read -r line ; do
            [[ "${line}" == '' ]] && continue
            [[ "${line:0:1}" == '#' ]] && continue
            fstamp="${line%% *}"
            line="${line#* }"
            fhash="${line%% *}"
            fname="${line#* }"
            if [[ ! -f "${fname}" ]] ; then
                [[ ! ${QUIET} ]] && echo "file not present '${fname}'"
                continue
            fi
            tstamp=$(file_modified "${fname}")
            if [[ ${tstamp} -gt ${fstamp} ]] ; then
                if [[ ${ASSUME_TS} ]] ; then
                    fstamp=$(epoch_to_date ${fstamp})
                    [[ ! ${QUIET} ]] && echo "restore timestamp of ${fstamp} for ${fname}"
                    [[ ! ${TESTING} ]] && touch -t ${fstamp} "${fname}"
                else
                    thash=$(file_hash "${fname}")
                    if [[ "${thash}" == "${fhash}" ]] ; then
                        fstamp=$(epoch_to_date ${fstamp})
                        [[ ! ${QUIET} ]] && echo "restore timestamp of ${fstamp} for ${fname}"
                        [[ ! ${TESTING} ]] && touch -t ${fstamp} "${fname}"
                    fi
                fi
            fi
        done < "${STAMPFILE}"
    fi

}

function db_pathname () {
    local count=10
    local out x
    local fname="${1}"
    while [[ ${count} -gt 0 ]] ; do
        [[ "${fname}" == "" ]] && break
        (( count-- ))
        x="${fname:0:2}"
        fname="${fname:2}"
        out="${out}/${x}"
    done
    [[ "${fname}" != "" ]] && out="${out}/${fname}"
    out="${STAMPDB}${out}"
    echo "${out}"
}

function db_lookup () {
    local xf=$(db_pathname "${1}")
    # [[ ! -f "${xf}.txt" ]] && return 1
    [[ ! -f "${xf}.dat" ]] && return 1
    local td=$(< "${xf}.dat")
    echo "${td}"
    return 0
}

function db_update () {
    [[ ${TESTING} ]] && return 0
    local xf=$(db_pathname "${1}")
    if [[ ! -d "${xf%/*}" ]]; then
        mkdir -p "${xf%/*}"
        [[ $? -ne 0 ]] && return 1
    fi
    echo "${2}">"${xf}.dat" || return 1
    return 0
}

function db_verify () {
    local xf=$(db_pathname "${1}")
    # [[ ! -f "${xf}.txt" ]] && return 1
    [[ ! -f "${xf}.dat" ]] && return 1
    return 0
    # not using this stuff bellow anymore
    local tn="${2##*/}"
    local td
    read -r td < "${xf}.txt"
    [[ "${td}" == "${tn}" ]] && return 0
    [[ ! -f "${xf}.alt" ]] && return 1
    while IFS=''; read -r td ; do
        [[ "${td}" == "${tn}" ]] && return 0
    done< "${xf}.alt"
    return 1
}

function stamper_db_proc () {
    if [[ ! -d "${STAMPDB}" ]] ; then
        mkdir -p "${STAMPDB}"
    fi
    if [[ ! -d "${STAMPDB}" ]] ; then
        echo "unable to locate timestamp database '${STAMPDB}'" >&2
        exit 1
    fi;
    [[ "${1}" == "list_vcs_files" ]] && set_vcs_base
    local line fhash fstamp fname thash tstamp
    while IFS=''; read -r line ; do
        [[ "${line}" == "${STAMPFILE}" ]] && continue
        if [[ ! -f "${line}" ]] ; then
            [[ ! ${QUIET} ]] && echo "file not present '${line}'"
            continue
        fi
        fhash=$(file_hash "${line}")
        fstamp=$(file_modified "${line}")
        [[ $? -ne 0 ]] && continue
        db_verify "${fhash}" "${line}"
        if [[ $? -eq 0 ]] ; then
            tstamp=$(db_lookup "${fhash}")
            if [[ ${tstamp} -gt ${fstamp} ]] ; then
                if [[ ! ${QUIET} ]] ; then
                    echo "$(epoch_to_date ${fstamp}) < ${line}"
                fi
                db_update "${fhash}" "${fstamp}"
                continue
            fi
            if [[ ${tstamp} -eq ${fstamp} ]] ; then
                [[ ${VERBOSE} ]] && echo "$(epoch_to_date ${fstamp}) = ${line}"
                continue
            fi
            [[ ! ${QUIET} ]] && echo "$(epoch_to_date ${tstamp}) > ${line}"
            [[ ! ${TESTING} ]] && touch -t "$(epoch_to_date ${tstamp})" "${line}"
        else
            [[ ! ${QUIET} ]] && echo "$(epoch_to_date ${fstamp}) + ${line}"
            db_update "${fhash}" "${fstamp}"

        fi
    done <<< "$(${1})"
}

function stamper_db_vcs () {
   stamper_db_proc list_vcs_files
}

function stamper_db_all () {
   stamper_db_proc list_all_files
}

function stamp_trees () {
    [[ "${1}" != "current" ]] && set_vcs_base
    local hwd="${PWD}"
    local dwd="${hwd}"
    [[ "${dwd}" != '/' ]] && dwd="${dwd}/"
    [[ "${VCSBASE}" != '' ]] && dwd="${dwd:$((${#VCSBASE}+1))}"
    [[ "${dwd}" == '' ]] && dwd='.' # dwd="${hwd}/"

    local first=$(file_modified "${PWD}")
    local latest=0
    local i t
    # echo "## ${first} ${hwd}"
    for i in * ; do
        [[ ! -e "${i}" ]] && continue
        if [[ -d "${i}" ]] ; then
            [[ ${NOFOLLOW} ]] && [[ -L "${i}" ]] && continue
            cd "${i}" && stamp_trees "${1}"
            # echo "??            ${PWD}"
            cd "${hwd}"
            [[ ${RET_TS} -eq 0 ]] && continue
            t=${RET_TS}
        else
            t=$(file_modified "${i}")
        fi
        [[ $? -ne 0 ]] && continue
        [[ ${t} -eq 0 ]] && continue
        [[ ${latest} -gt ${t} ]] && continue
        [[ ${latest} -eq ${t} ]] && continue
        latest=${t}
        # echo "++ ${latest} ${i}"
    done

    RET_TS=${latest}
    if [[ ${latest} -eq 0 ]] ; then
        if [[ ${NOEMPTY} ]] ; then
            [[ ! ${QUIET} ]] && echo "$(epoch_to_date ${first}) ! ${dwd}"
        else
            [[ ! ${QUIET} ]] && echo "$(epoch_to_date ${first}) ^ ${dwd}"
            RET_TS=${first}
        fi
    elif [[ ${first} -ne ${latest} ]] ; then
        if [[ ${first} -lt ${latest} ]] ; then
           [[ ! ${QUIET} ]] && echo "$(epoch_to_date ${latest}) + ${dwd}"
        else
           [[ ! ${QUIET} ]] && echo "$(epoch_to_date ${latest}) - ${dwd}"
        fi
        if [[ ! ${TESTING} ]] ; then
            touch -t "$(epoch_to_date ${latest})" "${hwd}"
            REP_TS=yes
        fi
        # echo ">> ${latest} ${hwd}"
    elif [[ ${VERBOSE} ]] ; then
        echo "$(epoch_to_date ${first}) = ${dwd}"
    fi
    # echo "@@ ${RET_TS} ${hwd}"
}

function stamp_trees_loop () {
    local ITC=0
    REP_TS=yes
    while [[ ${REP_TS} ]] ; do
        (( ITC++ ))
        [[ ! ${QUIET} ]] && echo "pass ${ITC}"
        unset REP_TS
        stamp_trees current
        [[ ! ${QUIET} ]] && [[ ${REP_TS} ]] && echo "--------------"
    done
}

function for_each_project () {
    local i hwd ret opt="${1}"
    shift
    for i in * ; do
        [[ ! -d "${i}" ]] && continue
        [[ ! -d "${i}/.git" ]] && [[ ! -d "${i}/.svn" ]] && continue
        hwd="${PWD}"
        cd "${i}"
        if [[ ${VERBOSE} ]] ; then
            echo "Project: '${i}' ${0##*/} ${@}"
        elif [[ ! ${QUIET} ]] ; then
            echo "Project: '${i}'"
        fi
        unset VCSBASE
        unset PKGCVS
        unset XWD
        SWD="${PWD}"

        if [[ "${opt}" == "internal" ]] ; then
            main "${@}"
        else
            ${@}
        fi
        ret=$?
        cd "${hwd}"
        [[ ${STOPONERR} ]] && [[ ${ret} -ne 0 ]] && return ${ret}
    done
    SWD="${PWD}"
    return 0
}

# Git checkout and cloning

function fetch_package_list () {
    local search=$(lowerCase "${1}")
    if [[ "${PKGCVS}" == '' ]] ; then
        [[ ${VERBOSE} ]] && echo "Attempt to fetch repository package listing file."
        PKGCVS=$(curl -q "${PKGCVSURL}" 2>/dev/null)
        if [[ $? -ne 0 ]] || [[ "${PKGCVS}" == '' ]]; then
            echo "error retrieving package cvs listing file">&2
            exit 1
        fi
    fi
    unset PKGLIST
    local i=0 pkgcnt=0 line x fid ftitle fgroup pident ptitle pgroup
    [[ ${VERBOSE} ]] && echo "Processing cvs package listing file."
    while IFS=''; read -r line ; do
        if [[ ${i} -eq 0 ]] ; then
            while [[ ${#line} -gt 0 ]] ; do
                (( i++))
                x="$(lowerCase ${line%%,*})"
                line="${line:$((${#x} + 1))}"
                case "${x}" in
                    'id')
                        fid=${i}
                        ;;
                    'title')
                        ftitle=${i}
                        ;;
                    'group')
                        fgroup=${i}
                        ;;
                esac
            done
            if [[ "${fid}" == "" ]] ||  [[ "${ftitle}" == "" ]] || [[ "${fgroup}" == "" ]] ; then
                echo "error processing cvs header">&2
                exit 1
            fi
            continue
        fi
        pident=$(get_csv_field ${fid} "${line}")
        [[ "${search}" != '' ]] && [[ "${pident}" != "${search}" ]] && continue
        ptitle=$(get_csv_field ${ftitle} "${line}")
        pgroup=$(get_csv_field ${fgroup} "${line}")
        PKGLIST[${pkgcnt}]="${pident},${pgroup},${ptitle}"
        [[ "${search}" != '' ]] && break
        ((pkgcnt++))
    done <<< "${PKGCVS}"
    return 0
}

function package_to_git () {
    local p="${1}"
    case "${p}" in
        'edit')
            p="edit-freedos"
            ;;
        'tree')
            p="tree-freedos"
            ;;
    esac
    local g="${2}"
    case "${g}" in
        'edit')
            g="editor"
            ;;
        'unix-like' | 'unixlike' )
            g="unix"
            ;;
    esac
    [[ ${HTTPS_MODE} ]] && echo "${GITHTTP}/${g}/${p}.git" || echo "${GITREPO}/${g}/${p}.git"
}

function auto_timestamp () {
    [[ ${NOAUTOTS} ]] && return 0
    if [[ ${TESTING} ]] ; then
        [[ ! ${QUIET} ]] && echo "restore timestamps for '${1}'"
        return 0
    fi
    local hwd="${PWD}"
    local fid="${1}"
    cd "${fid}"
    XWD="${PWD}"
    if [[ -d "${STAMPDB}" ]] && [[ ! -f "${STAMPFILE}" ]] ; then
        [[ ! ${QUIET} ]] && echo "Restore time stamps from database"
        stamper_db
    else
        [[ ! ${QUIET} ]] && echo "Restore time stamps"
        stamper
    fi
    if [[ ! -f "${STAMPFILE}" ]] ; then
        [[ ! ${QUIET} ]] && echo "Create time stamp file"
        stamper_save
        # git commit -m  "Added timestamp file"
        # git push
    fi
    cd "${hwd}"
    unset XWD
}

function fetch_packages () {
    local i line fid fgroup ffail fgit hwd fcnt=0 scnt=0
    for (( i=0;i<${#PKGLIST[*]};i++)) ; do
        line="${PKGLIST[${i}]}"
        fid="${line%%,*}"
        line="${line:$(( 1 + ${#fid} ))}"
        fgroup="${line%%,*}"
        line="${line:$(( 1 + ${#fgroup} ))}"
        if [[ -d "${fid}" ]] ; then
             if [[ ${VERBOSE} ]] ; then
                echo "package (${fgroup}/${fid}) '${line}' is already present"
            else
                [[ ! ${QUIET} ]] && echo "package '${line}' is already present"
            fi
            continue
        fi
        fgit=$(package_to_git "${fid}" "${fgroup}" )
        if [[ ! ${QUIET} ]] ; then
            if [[ ${VERBOSE} ]] ; then
                echo "retrieve (${fgroup}/${fid}) '${line}' from '${fgit}'"
            else
                [[ ! ${QUIET} ]] && echo "retrieve '${line}'"
            fi
        fi
        if [[ ${TESTING} ]] ; then
            [[ ! ${QUIET} ]] && echo "clone '${fgit}' as '${fid}'"
        else
            git clone "${fgit}" "${fid}"
        fi
        if [[ $? -ne 0 ]] ; then
            echo "failed to retrieve '${fgroup}/${fid}' from '${fgit}'" >&2
            ffail[${fcnt}]="${fgroup}/${fid} - ${line}"
            (( fcnt++ ))
            # return 1
            continue
        else
            (( scnt++ ))
        fi
        auto_timestamp "${fid}"
    done
    if [[ ${fcnt} -gt 0 ]] ; then
        echo
        echo "unable to retrieve ${fcnt} package$(pluralString ${fcnt}):">&2
        for (( i=0;i<${#ffail[*]};i++ )) do
            echo "  ${ffail[${i}]}">&2
        done
        echo
        echo "it is possible the package$(pluralString ${fcnt} s\ do \ does) not exist on the repository,">&2
        echo "or that you may not have sufficient permission to access $(pluralString ${fcnt} them it)."
    fi
}

function fetch_nls () {
    [[ ${TESTING} ]] && return 0
    if [[ "${FDNLS_PATH}" != '' ]] && [[ -d "${FDNLS_PATH}" ]] ; then
        local hwd="${PWD}"
        cd "${FDNLS_PATH}" || exit 1
        git pull --ff-only || git pull
        cd "${hwd}"
    else
        git clone "${NLSREPO}" FD-NLS || exit 1
        save_setting FDNLS_PATH "${PWD}/FD-NLS"
    fi
    auto_timestamp "FD-NLS"
}

function commit_git () {
    if [[ ! ${NOAUTOTS} ]] ; then
        local changes=$(git diff --name-only 2>/dev/null| wc -l)
    else
        local changes=0
    fi
    if [[ "${1}" == '' ]] ; then
        git commit -a -m  "General update" || return $?
    else
        git commit -a -m "${1}" || return $?
    fi
    if [[ ${changes} -gt 0 ]] ; then
        stamper
        stamp_trees
        stamper_save
        git commit -m  "Updated timestamps" || return $?
    fi

    git push
    return $?
}

function commit_svn () {
    if [[ ! ${NOAUTOTS} ]] ; then
        stamper
        stamp_trees
        stamper_save
    fi
    local svn_root=$(svn info | grep -i "^Repository Root:" | cut -d ':' -f 2- | cut -c 2-)
    local svn_rev=$(svn info | grep -i "^Revision:" | cut -d ':' -f 2 | cut -c 2-)
    svn commit -m "$*" && svn up || exit 1
    local svn_new=$(svn info | grep -i "^Revision:" | cut -d ':' -f 2 | cut -c 2-)
    if [[ "$svn_new" != "$svn_rev" ]] ; then
        echo "updated \`$svn_root' to revision ${svn_new}."
    else
        echo "no changes to \`$svn_root' since revision ${svn_rev}."
    fi;
    return 0
}

function commit () {
    local hwd="${PWD}"
    set_vcs_base
    [[ -d ".git" ]] && commit_git "${1}"
    [[ -d ".svn" ]] && commit_svn "${1}"
    cd "${hwd}"
    return 0

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

# More package processing functions
function update_nls_appinfo () {
    local p j l c t x aio
    local i line fid ftitle fdesc fsum fkey pident ptitle pdesc psum pkey
    local pkg="${VCSBASE##*/}"
    for p in "${FDNLS_PATH}/packages"/* ; do
        [[ ! -d "${p}" ]] && continue
        l=$(upperCase "${p##*/}")
        for j in "${p}"/* ; do
            [[ ! -d "${j}" ]] && continue
            c=$(upperCase "${j##*/}")
            [[ "${c//UTF}" != "${c}" ]] && continue
            c="${c//CP}"
            i=0
            ptitle=
            psum=
            pkey=
            fid=
            ftitle=
            fdesc=
            fsum=
            fkey=
            while IFS=''; read -r line ; do
                if [[ ${i} -eq 0 ]] ; then
                    while [[ ${#line} -gt 0 ]] ; do
                        (( i++))
                        x="$(lowerCase ${line%%,*})"
                        line="${line:$((${#x} + 1))}"
                        case "${x}" in
                            'id')
                                fid=${i}
                                ;;
                            'title')
                                ftitle=${i}
                                ;;
                            'description')
                                fdesc=${i}
                                ;;
                            'summary')
                                fsum=${i}
                                ;;
                            'keywords')
                                fkey=${i}
                                ;;
                        esac
                    done
                    if [[ "${fid}" == "" ]] || [[ "${fdesc}" == "" ]] ; then
                        echo "error processing cvs header in '${j:$(( ${#FDNLS_PATH} + 10 ))}/listing.csv">&2
                        return 1
                    fi
                    continue
                fi
                pident=$(get_csv_field ${fid} "${line}")
                [[ "${pident}" != "${pkg}" ]] && continue
                line="${line//[[\r\n]]}"
                aio=$(case_match_file "APPINFO/${pkg}.lsm")
                aio=$(case_match_file "${aio%.*}.${l:0:3}")
                if [[ ! ${QUIET} ]] ; then
                    if [[ -f "${aio}" ]] ; then
                        echo "translation ${l} ${c} for '${pkg}' found > '${aio}'"
                    else
                        echo "translation ${l} ${c} for '${pkg}' found + '${aio}'"
                    fi
                fi
                pdesc=$(get_csv_field ${fdesc} "${line}")
                [[ ${ftitle} ]] && ptitle=$(get_csv_field ${ftitle} "${line}")
                [[ ${fsum} ]] && psum=$(get_csv_field ${fsum} "${line}")
                [[ ${fkey} ]] && pkey=$(get_csv_field ${fkey} "${line}")
                if [[ ${VERBOSE} ]] ; then
                    echo "  Language:    ${l}, ${c}"
                    [[ "${ptitle// }" != "" ]] && echo "  Title:       ${ptitle}"
                    echo "  Description: ${pdesc}"
                    [[ "${psum// }" != "" ]] && echo "  Summary:     ${psum}"
                    [[ "${pkey// }" != "" ]] && echo "  Keywords:    ${pkey}"
                fi
                if [[ ! ${TESTING} ]] ; then
                    mkdir -p "APPINFO" || return 1
                    echo "Begin3"|crlf>"${aio}"
                    echo "Language:    ${l}, ${c}"|crlf>>"${aio}"
                    [[ "${ptitle// }" != "" ]] && echo "Title:       ${ptitle}"|crlf>>"${aio}"
                    echo "Description: ${pdesc}"|crlf>>"${aio}"
                    [[ "${psum// }" != "" ]] && echo "Summary:     ${psum}"|crlf>>"${aio}"
                    [[ "${pkey// }" != "" ]] && echo "Keywords:    ${pkey}"|crlf>>"${aio}"
                    echo "End"|crlf>>"${aio}"
                    if [[ -d "${VCSBASE}/.git" ]] ; then
                        git add "${aio}"
                    fi
                    if [[ -d "${VCSBASE}/.svn" ]] ; then
                        svn add "${aio}" 2>/dev/null
                    fi
                        fi
                break
            done < "${j}/listing.csv"
        done
    done

    return 0
}


function update_nls () {
    if [[ "${FDNLS_PATH}" == "" ]] || [[ ! -e "${FDNLS_PATH}" ]] ; then
        echo
        echo "ERROR: Unable to find language translations project."
        echo "Please move to an appropriate directory for it and run:"
        echo
        echo "${0##*/} -conls"
        echo
        return 1
    fi
    set_vcs_base

    update_nls_appinfo || return 1

    if [[ ! -d "${FDNLS_PATH}/${VCSBASE##*/}" ]] ; then
        if [[ ! ${QUIET} ]] ; then
            echo "Project '${VCSBASE##*/}' not found in Language Translations (FD-NLS) project"
        fi
        return 0
    fi

    local fsrc fdst fdste t bfd lfd mfd
    local pkg="$(upperCase ${VCSBASE##*/})"
    case "${pkg}" in
        "FDTUI"|"HTMLHELP"|"PGME")
             [[ ! ${QUIET} ]] && echo "'${pkg}' requires special handling, not supported yet"
             return 0
    esac

    while IFS=""; read -r fsrc ; do
        t=$(upperCase "${fsrc}")
        [[ "${fsrc//.UTF}" != "${fsrc}" ]] && continue
        bfd="${fsrc%%/*}"
        # exclude files in package nls base directory
        [[ "${bfd}" == "${fsrc}" ]] && continue
        if [[ "${bfd}" != "${lfd}" ]] ; then
            lfd="${bfd}"
            mfd=$(case_match_file "${bfd}")
        fi
        fdst="${fsrc#*/}"
        case "$(upperCase ${mfd})" in
            "NLS"|"HELP")
                fdst="${mfd}/${fdst##*/}"
                ;;
            "DOC")
                fdst="${fdst#*/}"
                fdst="${mfd}/${pkg}/${fdst#*/}"
                ;;
            *)
                [[ ! ${QUIET} ]] && echo "'${fsrc}' ? skipped"
                continue
        esac
        case "${pkg}" in
            "BLOCEK")
                fdst="PROGS/${pkg}/${fsrc##*/}"
            ;;
        esac

        fdst="${fdst%/*}/"$(upperCase "${fdst##*/}")

		# skip all multi extension files
        fdste="${fdst##*/}"
        fdste="${fdste//[!.]}"
        [[ ${#fdste} -gt 1 ]] && continue

		# truncate extension to 3 chars
        fdste="${fdst##*.}"
        fdst=$(case_match_file "${fdst%.*}.${fdste:0:3}")

        [[ ! -d "${fdst%/*}" ]] && continue

        if [[ -f "${fdst}" ]] ; then
            [[ ! ${QUIET} ]] && echo "'${fsrc}' > '${fdst}'"
        else
            [[ ! ${QUIET} ]] && echo "'${fsrc}' + '${fdst}'"
        fi
        if [[ ! ${TESTING} ]] ; then
            cp -f "${FDNLS_PATH}/${VCSBASE##*/}/${fsrc}" "${fdst}" || return 1
            if [[ -d "${VCSBASE}/.git" ]] ; then
                git add "${fdst}"
            fi
            if [[ -d "${VCSBASE}/.svn" ]] ; then
                svn add "${fdst}" 2>/dev/null
            fi
        fi
    done <<<"$(get_file_list ${FDNLS_PATH}/${VCSBASE##*/})"
    return 0
}

function lsm_field () {

    local lsm="${1##*/}"
    local field line linex a b ignore

    while IFS=''; read -r line ; do
        line="${line//</&lt;}"
        line="${line//>/&gt;}"
        line="$(trim ${line})"
        linex="$(lowerCase ${line})"
        [[ "${linex}" == "end" ]] && ignore=yes
        if [[ "${ignore}" == 'no' ]] ; then
            a=$"${linex%%:*}"
            b="$(trim ${line:$(( ${#a} + 1 ))})"
            a="$(trim ${a})"
            [[ "${b}" == "" ]] && continue
            [[ "${b}" == "-" ]] && continue
            [[ "${b}" == "?" ]] && continue
            [[ "${a}" != "$2" ]] && continue
            field="$b"
            break
        fi
        [[ "${linex}" == "begin3" ]] && ignore=no
    done< "$1"
    [[ "${field}" == "" ]] && echo "${3}" || echo "${field}"
}

function lsm_to_md () {

   # local minwidth=0
    local lsm="${1##*/}"
    local line linex a b ignore

    echo "## $(upperCase ${lsm})"
    echo
    echo "<table>"

   # while IFS=''; read -r line ; do
   #     line="$(trim ${line})"
   #     linex="$(lowerCase ${line})"
   #     [[ "${linex}" == "end" ]] && ignore=yes
   #     if [[ "${ignore}" == 'no' ]] ; then
   #         a=$"${linex%%:*}"
   #         a="$(trim ${a})"
   #         [[ "${a}" == "modified-date" ]] && continue
   #         [[ "${a}" == "changes" ]] && continue
   #         [[ "${a//defunct}" != "${a}" ]] && continue
   #         [[ ${#a} -gt ${minwidth} ]] && minwidth=${#a}
   #     fi
   #     [[ "${linex}" == "begin3" ]] && ignore=no
   # done< "$1"

    while IFS=''; read -r line ; do
        line="${line//</&lt;}"
        line="${line//>/&gt;}"
        line="$(trim ${line})"
        linex="$(lowerCase ${line})"
        [[ "${linex}" == "end" ]] && ignore=yes
        if [[ "${ignore}" == 'no' ]] ; then
            a=$"${linex%%:*}"
            b="$(trim ${line:$(( ${#a} + 1 ))})"
            a="$(trim ${a})"
            [[ "${b}" == "" ]] && continue
            [[ "${b}" == "-" ]] && continue
            [[ "${b}" == "?" ]] && continue
            [[ "${a}" == "modified-date" ]] && continue
            [[ "${a}" == "changes" ]] && continue
            [[ "${a//defunct}" != "${a}" ]] && continue
            [[ "${a}" == "copying-policy" ]] && [[ "${2}" != '' ]] && b="[${b}](${2})"
            # while [[ ${#a} -lt ${minwidth} ]] ; do a="${a} "; done
            a="${a//-/ }"
            echo "<tr><td>${a// /&nbsp;}</td><td>$b</td></tr>"
        fi
        [[ "${linex}" == "begin3" ]] && ignore=no
    done< "$1"
    echo "</table>"
}

function create_project_readme () {

    set_vcs_base
    local i ix
    local appinfo=$(case_match_file "appinfo")
    local readme=$(case_match_file "readme.md")
    local lsm=$(case_match_file "${appinfo}/${PWD##*/}.LSM")
    local contrib=$(case_match_file "contrib")
    [[ ! -e "${contrib}" ]] && contrib=$(case_match_file "contrib.md")
    [[ ! -e "${contrib}" ]] && contrib=$(case_match_file "contributing.md")
    local licinfo=$(case_match_file "LICENSE")
    [[ ! -e "${licinfo}" ]] && licinfo=

    if [[ -e "${lsm}" ]] ; then
        local title=$(lsm_field "${lsm}" title "${PWD##*/}")
        local info=$(lsm_field "${lsm}" summary "")
        if [[ "${info}" == "" ]] ; then
            local info=$(lsm_field "${lsm}" description "")
        fi;
    else
        local title="${PWD##*/}"
        local info=
    fi

    echo "# ${title}">INDEX.md
    echo >>INDEX.md

    if [[ -e "${readme}" ]] ; then
        cat "${readme}" >>INDEX.md
        echo >>INDEX.md
    else
        if [[ "${info}" != '' ]] ; then
            echo "${info}">>INDEX.md
            echo >>INDEX.md
        fi
    fi
    if [[ -e "${contrib}" ]] ; then
        cat "${contrib}" >>INDEX.md
        echo >>INDEX.md
    else
        echo >>INDEX.md
        echo "## Contributions">>INDEX.md
        echo >>INDEX.md
        echo "NLS specific corrections, updates and submissions should not be ">>INDEX.md
        echo "directly to submitted this project. NLS is maintained at the [FD-NLS](https://github.com/shidel/fd-nls)">>INDEX.md
        echo "project on GitHub. If the project is still actively maintained by it's">>INDEX.md
        echo "developer, it may be beneficial to also submit changes to them directly.">>INDEX.md
        echo >>INDEX.md
    fi

    for i in "${appinfo}/"* ; do
        [[ ! -f "${i}" ]] && continue
        ix=$(upperCase "${i##*.}")
        [[ "${ix}" != "LSM" ]] && continue
        lsm_to_md "${i}" "${licinfo}">>INDEX.md
    done
    [[ -e .git ]] && git add INDEX.md
    [[ -e .svn ]] && svn add INDEX.md
    return 0

}

function package_project () {
    echo "Sorry. I have not got around to doing the package function yet."
    return 1
}

function branch () {
    set_vcs_base
    if [[ -e .svn ]] ; then
        echo "cannot create new branch for subversion repository" >&2
        return 1
    fi
    if [[ ! -e .git ]] ; then
        echo "Creating new branches is only supported for git repositories" >&2
        return 1
    fi
    git checkout -b "${1}" || return $?
    git commit -c "new branch ${1}" || return $?
    git push -u origin "${1}" || return $?
    return 0
}

function crlf_perl () {
    (
        export LC_CTYPE=C
        tr -d '\r' | perl -pe 's/\n/\r\n/'
    )
}

function crlf_file () {
    while [[ ${#*} -gt 1 ]] ; do
        [[ ! -f "${1}" ]] && shift && continue
        local oname="${1}.temp-crlf"
        cat "${1}" | crlf_perl >"${oname}"
        diff "${1}" "${oname}" >/dev/null
        if [[ $? -eq 0 ]] ; then
            rm "${oname}" || return 1

        else
            local fstamp=$(file_modified "${1}")
            fstamp=$(epoch_to_date ${fstamp})
            touch -t ${fstamp} "${oname}"
            echo "${1} + CRLF"
            mv "${oname}" "${1}" || return 1
        fi
        shift
    done
}

function fix_line_endings () {
    set_vcs_base
    crlf_file *.lsm *.LSM || return $?
    crlf_file $(case_match_file "appinfo")/* || return $?
    crlf_file $(case_match_file "Nls")/* || return $?
    return 0
}

# Primary option parser

function main () {
    local opt
    [[ ${#} -eq 0 ]] && display_seehelp
    # Options to process first regardless of position on command line
    for (( opt=1;opt<=${#};opt++ )) ; do
        case "${!opt}" in
            '-h'|'--help')
                display_help
                ;;
            '-t')
                TESTING=true
                ;;
            '-q')
                QUIET=true
                unset VERBOSE
                ;;
            '-v')
                VERBOSE=true
                unset QUIET
                ;;
            '-x')
                NOAUTOTS=true
                ;;
            '-nfl')
                NOFOLLOW=true
                ;;
            '-ned')
                NOEMPTY=true
                ;;
        esac
    done
    if [[ ${VERBOSE} ]] && [[ ! ${NOXMSGS} ]] ; then
        echo "Verbose Mode is On"
        [[ ${TESTING} ]] && echo "Test Mode is On"
        [[ ${NOAUTOTS} ]] && echo "Disable Automatic timestamp file update"
        [[ ${NOFOLLOW} ]] && echo "Do Not Follow Linked Directories"
        [[ ${NOEMPTY} ]] && echo "No Empty Directories"
    fi
    # process command line in order
    while [[ ${#} -gt 0 ]] ; do
        opt="${1}"
        shift
        case "${opt}" in
            '-t'|'-q'|'-v'|'-x'|'-nfl'|'-ned')
                ;;
            '-s')
                stamper
                [[ ! ${NOAUTOTS} ]] && stamp_trees
                stamper_save
                # since we did it manually, turn off auto mode
                NOAUTOTS=true
                ;;
            '-sdt')
                stamper
                stamper_db_vcs
                [[ ! ${NOAUTOTS} ]] && stamp_trees
                stamper_save
                ;;
            '-sdv')
                stamper_db_vcs
                ;;
            '-sda')
                stamper_db_all
                ;;
            '-https')
                HTTPS_MODE=true
                ;;
            '-jat')
                ASSUME_TS=true
                ;;
            '-co')
                opt="${1}"
                shift
                fetch_package_list "${opt}" || exit 1
                fetch_packages || exit 1
                ;;
            '-coa')
                fetch_package_list || exit 1
                fetch_packages || exit 1
                ;;
            '-conls')
                fetch_nls || exit 1
                ;;
            '-c')
                opt="${1}"
                shift
                commit "${opt}" || exit $?
                ;;
            '-n')
                opt="${1}"
                shift
                commit "pre-branch commit ${opt}" || exit $?
                branch "${opt}" || exit $?
                ;;
            '-p')
                stamp_trees vcs
                ;;
            '-pa')
                stamp_trees current
                ;;
            '-par')
                stamp_trees_loop
                ;;
            '-fe')
                NOXMSGS=true
                for_each_project "internal" "${@}"
                exit $?
                ;;
            '-fex')
                NOXMSGS=true
                for_each_project "external" "${@}"
                exit $?
                ;;
            '-nls')
                update_nls || exit $?
                ;;
            '-cpr')
                create_project_readme || exit $?
                ;;
            '-crlf')
                fix_line_endings || exit $?
                ;;
            '-pkg')
                package_project || exit $?
                ;;
            '-b')
                opt="${1}"
                shift
                commit "commit prior to creating branch ${opt}" || exit $?
                git checkout -b "${opt}" || exit $?
                git push origin "${opt}" || exit $?
                ;;
            *)
                display_seehelp ${opt} ${@}
        esac
    done
}

main "${@}"