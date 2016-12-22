#!/bin/bash

MODE="$1"
CONFIG="/etc/borgwrapper/config.sh"


print_usage () {
    echo "Usage: borgwrapper.sh MODE"
    echo ""
    echo "arguments:"
    echo "    MODE          backup|verify|unlock"
}

borg_backup () {
    EXCLUDE_CMD=()

    for EXCLUDE in ${EXCLUDES[@]}; do
        EXCLUDE_CMD+=( --exclude "$EXCLUDE" )
    done

    # Backup all of /home and /var/www except a few
    # excluded directories
    $BORG create --info --stats \
        --compression lz4 \
        --numeric-owner \
        "${REPO}"::"$(hostname)-$(date -u +'%Y%m%dT%H%M%SZ')" \
        ${PATHS[@]} \
        ${EXCLUDE_CMD[@]}
}

borg_prune () {
    # Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
    # archives of THIS machine. --prefix `hostname`- is very important to
    # limit prune's operation to this machine's archives and not apply to
    # other machine's archives also.
    $BORG prune --info --stats --list \
        --prefix "$(hostname)-" \
        --keep-daily=$KEEP_DAILY \
        --keep-weekly=$KEEP_WEEKLY \
        --keep-monthly=$KEEP_MONTHLY \
        --keep-yearly=$KEEP_YEARLY \
        "${REPO}"
}

borg_verify () {
    $BORG check --show-rc "${REPO}"
}

borg_unlock () {
    # Use if borg backup is not shut down cleanly
    $BORG break-lock "${REPO}"
}


source "$CONFIG" || exit 1
export BORG_PASSPHRASE

if [[ $MODE == "backup" ]]; then
    borg_backup
    borg_prune
elif [[ $MODE == "verify" ]]; then
    borg_verify
elif [[ $MODE == "unlock" ]]; then
    borg_unlock
else
    print_usage
fi
