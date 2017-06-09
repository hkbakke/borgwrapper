#!/bin/bash

VERSION="1.0.0"


print_usage () {
    cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] MODE

OPTIONS
    -c CONFIG_FILE
    -V
        Print version and exit.

MODES
    init|backup|verify|unlock|delete-checkpoints|exec
EOF
}

print_version () {
    echo "borgwrapper v${VERSION}"
}

error_handler () {
    local SCRIPT_NAME="$0"
    local LINE="$1"
    local EXIT_CODE="$2"
    >&2 echo "${SCRIPT_NAME}: Error in line ${LINE} (exit code ${EXIT_CODE})"
    exit ${EXIT_CODE}
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
        )
    fi

    ${BORG} create \
        "${BORG_BACKUP_ARGS[@]}" \
        "${BORG_REPO}"::"{hostname}-$(date -u +'%Y%m%dT%H%M%SZ')" \
        "${PATHS[@]}" \
        "${EXCLUDE_CMD[@]}"
}

borg_prune () {
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

borg_delete_checkpoints () {
    ${BORG} list "${BORG_REPO}" \
        | { grep .checkpoint || true; } \
        | cut -d ' ' -f 1 \
        | xargs -I % -n 1 --no-run-if-empty \
        ${BORG} delete "${BORG_REPO}"::%
}

borg_unlock () {
    # Use if borgbackup is not shut down cleanly and complains about lock files
    ${BORG} break-lock "${BORG_REPO}"
}

borg_exec () {
    export BORG_REPO
    ${BORG} "$@"
}

convert_rate () {
    # Convert IN_RATE to bytes
    local IN_RATE=${1}
    local RATE=0
    local B_REGEX="^([0-9]+)$"
    local KIB_REGEX="^([0-9]+)K$"
    local MIB_REGEX="^([0-9]+)M$"
    local GIB_REGEX="^([0-9]+)G$"
    local TIB_REGEX="^([0-9]+)T$"

    if [[ ${IN_RATE} =~ ${TIB_REGEX} ]]; then
        RATE=$(( ${BASH_REMATCH[1]} * 1024**4 ))
    elif [[ ${IN_RATE} =~ ${GIB_REGEX} ]]; then
        RATE=$(( ${BASH_REMATCH[1]} * 1024**3 ))
    elif [[ ${IN_RATE} =~ ${MIB_REGEX} ]]; then
        RATE=$(( ${BASH_REMATCH[1]} * 1024**2 ))
    elif [[ ${IN_RATE} =~ ${KIB_REGEX} ]]; then
        RATE=$(( ${BASH_REMATCH[1]} * 1024 ))
    elif [[ ${IN_RATE} =~ ${B_REGEX} ]]; then
        RATE=${BASH_REMATCH[1]}
    else
        >&2 echo "${IN_RATE} is not a valid rate"
        false
    fi

    echo ${RATE}
}

limit_bw () {
    if ! [[ -x $(command -v pv) ]]; then
        >&2 echo "WARNING: BWLIMIT is enabled, but the utility 'pv' is not available. Continuing without bandwidth limitation."
        return 0
    fi

    export PV_WRAPPER=$(mktemp)
    export RATE_LIMIT=$(convert_rate ${BWLIMIT})
    chmod +x ${PV_WRAPPER}
    echo -e '#!/bin/bash\npv -q -L ${RATE_LIMIT} | "$@"' > ${PV_WRAPPER}
    export BORG_RSH="${PV_WRAPPER} ssh"
    echo "Limiting bandwith to ${RATE_LIMIT} bytes/s"
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

lock_failed () {
    >&2 echo "$0 is already running"
    exit 1
}

exit_clean () {
    [[ -n ${PV_WRAPPER} ]] && rm -f ${PV_WRAPPER}
    [[ -n ${LOCKFILE} ]] && rm -f "${LOCKFILE}"
    trap - ERR INT TERM
    exit $1
}


# Default parameters
CONFIG="/etc/borgwrapper/config.sh"
BORG="/usr/bin/borg"
LOCKDIR="/run/lock/borgwrapper"
PRE_BACKUP_CMD=()
POST_BACKUP_CMD=()
POST_VERIFY_CMD=()
BWLIMIT=0

while getopts ":c:V" OPT; do
    case ${OPT} in
        c)
            CONFIG="${OPTARG}"
            ;;
        V)
            print_version
            exit 0
            ;;
        *)
            print_usage
            exit 1
    esac
done

# Interpret all remaining arguments as mode parameters
shift "$((OPTIND - 1))"
MODE="${1}"


echo "Loading config from ${CONFIG}"
source "${CONFIG}" || exit 1
export BORG_PASSPHRASE

LOCKFILE="${LOCKDIR}/$(echo -n "${BORG_REPO}" | md5sum | cut -d ' ' -f 1).lock"
mkdir -p "${LOCKDIR}"

(
    # Ensure this is the only instance running
    flock -n 9 || lock_failed

    # The error handler trap must be set within the subshell to be effective
    trap 'error_handler ${LINENO} $?' ERR INT TERM
    set -o errtrace -o pipefail

    # Enforce bandwidth limit if set
    [[ -n ${BWLIMIT} ]] && [[ ${BWLIMIT} != "0" ]] && limit_bw

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
    elif [[ ${MODE} == "delete-checkpoints" ]]; then
        borg_delete_checkpoints
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
) 9>"${LOCKFILE}"
