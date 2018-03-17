# borgwrapper
Wrapper to simplify backups with borgbackup

# Installation
Put the [script](src/borgwrapper) somewhere practical

    cp borgwrapper /usr/local/bin/borgwrapper
    chown root. /usr/local/bin/borgwrapper
    chmod 750 /usr/local/bin/borgwrapper

# Configuration
By default borgwrapper expects the configuration to be located at `/etc/borgwrapper/config`.
An example configuration file is included in [config.example](src/config.example).
Ensure restrictive permissions on this file as it exposes the passphrase.

    chown root. config
    chmod 600 config

# Scheduling
## systemd
Copy the example systemd [unit files](systemd/) to `/etc/systemd/system/`. Then for each
configuration file in `/etc/borgwrapper/<config_name>` do:

    systemctl enable borgwrapper-backup@<config_name>.timer
    systemctl enable borgwrapper-verify@<config_name>.timer

    systemctl start borgwrapper-backup@<config_name>.timer
    systemctl start borgwrapper-verify@<config_name>.timer

You can view the backup logs with:

    journalctl -xu borgwrapper-backup@<config_name>
    journalctl -xu borgwrapper-verify@<config_name>

If you want to run the tasks manually outside the timers you can just start them like usual
services:

    systemctl start borgwrapper-backup@<config_name>
    systemctl start borgwrapper-verify@<config_name>

## Cron (use only if systemd is not available)

    # Run the backup daily
    23 1 * * * /usr/local/bin/borgwrapper backup

    # Verify the backups once a month
    40 17 23 * * /usr/local/bin/borgwrapper verify

# Borg server preparation
Install borg and then

    adduser --system --group --shell /bin/bash borg
    mkdir /srv/borg
    chown borg. /srv/borg
    chmod 755 /srv/borg
Generate the needed passwordless ssh-keys as root (the user you run the backup as) on the client

    ssh-keygen
Copy the content of the generated public key from `/root/.ssh/<key>.pub` to `/home/borg/.ssh/authorized_keys` on the server, with
some restrictions so it looks something like this:

    command="borg serve --restrict-to-path /srv/borg/<hostname>",no-pty,no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDeCInOLjv0hgzI0u1b/p4yYnCEV5n89HIXF1hrLor+ZQ7lSUii21tpn47Aw8RJJAjfDCwCdQ27MXjpzNelBf4KrlAiN1K3FcnGGIiE3XFNoj4LW7oAjzjFgOKC/ea/hXaCI6E8M/Pn5+MhdNN1ZsWNm/9Zp0+jza+l74DQgOE33XhSBjckUchqtBci7BqoCejy2lVvboFA231mSEpPValcKmG2qaNphAkCgAPjtDOx3V6DGQ8e7jfA2McQYxfju6HlpWPUx/li6VJhRa5huczfJ3J/sdfu123s/lgTW4rG5QNng1vt1FOIZ/TkaEsPt2wzD2Qxdwo70qVts3hrd+r root@client

# Usage
## Initialize backup repo

    borgwrapper init
## Backup

    borgwrapper backup
## Verify backups

    borgwrapper verify
## Run other borg commands
### Wrapped and easy
Use `exec <borg arguments>`. `BORG_REPO` is exported to the environment so use `::` when the repo
argument is required.

Examples:

    borgwrapper exec mount :: /mnt
    borgwrapper exec list
### Borg directly
Run in subshell if you do not want the passphrase stored in the current shell after the command have exited.

Examples:

    (. /etc/borgwrapper/config; export BORG_PASSPHRASE; borg mount "$BORG_REPO" /mnt)
    (. /etc/borgwrapper/config; export BORG_PASSPHRASE; borg list "$BORG_REPO")
