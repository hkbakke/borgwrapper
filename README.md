# borgwrapper
Wrapper to simplify backups with borgbackup

# Configuration
By default borgwrapper expects the configuration to be located at `/etc/borgwrapper/config.sh`.
Ensure restrictive permissions on this file as it exposes the passphrase.

    chown root:root config.sh
    chmod 600 config.sh
    
Example cron jobs:
    
    # Run the backup daily
    23 1 * * * /usr/local/sbin/borgwrapper.sh backup
    
    # Verify the backups once a month
    40 17 23 * * /usr/local/sbin/borgwrapper.sh verify

# Usage
## Backup

    borgwrapper.sh backup
## Verify backups

    borgwrapper.sh verify
## Unlock after unclean exit

    borgwrapper.sh unlock
## Run other borg commands
Run in subshell if you do not want the passphrase stored in the current shell even after the commands have exited.

Examples:

    (. /etc/borgwrapper/config.sh; export BORG_PASSPHRASE; borg list "$REPO")
    (. /etc/borgwrapper/config.sh; export BORG_PASSPHRASE; borg mount "$REPO" /mnt)
