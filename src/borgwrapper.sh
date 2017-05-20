#!/bin/bash

error_handler () {
    local SCRIPT_NAME="$0"
    local LINE="$1"
    local EXIT_CODE="$2"
    echo "${SCRIPT_NAME}: Error in line ${LINE} (exit code ${EXIT_CODE})"
    exit ${EXIT_CODE}
}

print_usage () {
    cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] MODE

OPTIONS
    -c CONFIG_FILE

MODES
    init|backup|verify|unlock|exec
EOF
}

borg_init () {
    ${BORG} init "${BORG_REPO}"
}

borg_backup () {
    EXCLUDE_CMD=()

    for EXCLUDE in "${EXCLUDES[@]}"; do
        EXCLUDE_CMD+=( --exclude "${EXCLUDE}" )
    done

    ${BORG} create --info --stats --list --filter AME \
        --compression lz4 \
        --numeric-owner \
        "${BORG_REPO}"::"{hostname}-$(date -u +'%Y%m%dT%H%M%SZ')" \
        "${PATHS[@]}" \
        "${EXCLUDE_CMD[@]}"
}

borg_prune () {
    # Use --prefix to limit pruning to this hostname's archives only, just in
    # case you for some reason use the same repository for several hosts (not
    # recommended)
    ${BORG} prune --info --stats --list \
        --prefix "{hostname}-" \
        --keep-daily=${KEEP_DAILY} \
        --keep-weekly=${KEEP_WEEKLY} \
        --keep-monthly=${KEEP_MONTHLY} \
        --keep-yearly=${KEEP_YEARLY} \
        "${BORG_REPO}"
}

borg_verify () {
    ${BORG} check --info "${BORG_REPO}"
}

borg_unlock () {
    # Use if borgbackup is not shut down cleanly and complains about lock files
    ${BORG} break-lock "${BORG_REPO}"
}

borg_exec () {
    export BORG_REPO
    ${BORG} "$@"
}


trap 'error_handler ${LINENO} $?' ERR INT TERM
set -o errtrace -o pipefail


# Default parameters
CONFIG="/etc/borgwrapper/config.sh"

while getopts ":c:" OPT; do
    case ${OPT} in
        c)
            CONFIG="${OPTARG}"
            ;;
        *)
            print_usage
            exit 1
    esac
done

# Interpret all remaining arguments as mode parameters
shift "$((OPTIND - 1))"
MODE="${1}"

source "${CONFIG}" || exit 1
export BORG_PASSPHRASE

if [[ ${MODE} == "init" ]]; then
    borg_init
elif [[ ${MODE} == "backup" ]]; then
    borg_backup
    borg_prune
elif [[ ${MODE} == "verify" ]]; then
    borg_verify
elif [[ ${MODE} == "unlock" ]]; then
    borg_unlock
elif [[ ${MODE} == "exec" ]]; then
    if [[ $# -le 1 ]]; then
        >&2 echo "ERROR: No borg arguments given"
        exit 1
    fi

    shift
    borg_exec "$@"
else
    print_usage
    exit 1
fi


trap - ERR INT TERM
