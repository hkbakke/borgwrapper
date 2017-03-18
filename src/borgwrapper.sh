#!/bin/bash

MODE="${1}"
CONFIG="/etc/borgwrapper/config.sh"


print_usage () {
    echo "Usage: borgwrapper.sh MODE"
    echo ""
    echo "arguments:"
    echo "    MODE          backup|verify|unlock"
}

borg_init () {
    ${BORG} init "${BORG_REPO}"
}

borg_backup () {
    EXCLUDE_CMD=()

    for EXCLUDE in "${EXCLUDES[@]}"; do
        EXCLUDE_CMD+=( --exclude "${EXCLUDE}" )
    done

    ${BORG} create --info --stats \
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
        echo "ERROR: No borg arguments given"
        exit 1
    fi

    shift
    borg_exec "$@"
else
    print_usage
fi
