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

    if [[ -z ${BORG_BACKUP_ARGS[@]} ]]; then
        BORG_BACKUP_ARGS=(
            --info
            --stats
            --list
            --filter AME
            --compression lz4
            --numeric-owner
        )
    fi

    ${BORG} create \
        "${BORG_BACKUP_ARGS[@]}" \
        "${BORG_REPO}"::"{hostname}-$(date -u +'%Y%m%dT%H%M%SZ')" \
        "${PATHS[@]}" \
        "${EXCLUDE_CMD[@]}"
}

borg_prune () {
    # Use --prefix to limit pruning to this hostname's archives only, just in
    # case you for some reason use the same repository for several hosts (not
    # recommended)

    if [[ -z ${BORG_PRUNE_ARGS[@]} ]]; then
        BORG_PRUNE_ARGS=(
            --info
            --stats
            --list
        )
    fi

    ${BORG} prune \
        "${BORG_PRUNE_ARGS[@]}" \
        --prefix "{hostname}-" \
        --keep-daily=${KEEP_DAILY} \
        --keep-weekly=${KEEP_WEEKLY} \
        --keep-monthly=${KEEP_MONTHLY} \
        --keep-yearly=${KEEP_YEARLY} \
        "${BORG_REPO}"
}

borg_verify () {
    if [[ -z ${BORG_CHECK_ARGS[@]} ]]; then
        BORG_CHECK_ARGS=(
            --info
        )
    fi

    ${BORG} check "${BORG_CHECK_ARGS[@]}" "${BORG_REPO}"
}

borg_unlock () {
    # Use if borgbackup is not shut down cleanly and complains about lock files
    ${BORG} break-lock "${BORG_REPO}"
}

borg_exec () {
    export BORG_REPO
    ${BORG} "$@"
}

pre_backup_cmd () {
    [[ -n ${PRE_BACKUP_CMD} ]] || return 0
    echo "Running pre backup command: ${PRE_BACKUP_CMD[@]}"
    "${PRE_BACKUP_CMD[@]}"
}

post_backup_cmd () {
    [[ -n ${POST_BACKUP_CMD} ]] || return 0
    echo "Running post backup command: ${POST_BACKUP_CMD[@]}"
    "${POST_BACKUP_CMD[@]}"
}

post_verify_cmd () {
    [[ -n ${POST_VERIFY_CMD} ]] || return 0
    echo "Running post verify command: ${POST_VERIFY_CMD[@]}"
    "${POST_VERIFY_CMD[@]}"
}

exit_backup () {
    post_backup_cmd
    exit_clean $1
}

exit_verify () {
    post_verify_cmd
    exit_clean $1
}

exit_clean () {
    trap - ERR INT TERM
    exit $1
}


trap 'error_handler ${LINENO} $?' ERR INT TERM
set -o errtrace -o pipefail

# Default options
CONFIG="/etc/borgwrapper/config.sh"
LOCKFILE="/var/lock/borgwrapper.lock"
BORG="/usr/bin/borg"
PRE_BACKUP_CMD=()
POST_BACKUP_CMD=()
POST_VERIFY_CMD=()

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

# Ensure this is the only instance of borgwrapper running
[[ "${FLOCKER}" != "$0" ]] && exec env FLOCKER="$0" flock -en "${LOCKFILE}" "$0" "$@" || true

if [[ ${MODE} == "init" ]]; then
    borg_init
elif [[ ${MODE} == "backup" ]]; then
    trap 'exit_backup $?' ERR INT TERM
    pre_backup_cmd
    borg_backup
    borg_prune
    exit_backup 0
elif [[ ${MODE} == "verify" ]]; then
    trap 'exit_verify $?' ERR INT TERM
    borg_verify
    exit_verify 0
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

exit_clean 0
