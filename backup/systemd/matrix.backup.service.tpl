[Unit]
Description=Matrix (Synapse) backup
Wants=network-online.target docker.service
After=network-online.target docker.service

[Service]
Type=oneshot

Group=docker

WorkingDirectory={{ PROJECT_ROOT }}
Environment=PATH=/usr/local/bin:/usr/bin:/bin

ExecStart={{ PROJECT_ROOT }}/backup/backup.sh

StandardOutput=journal
StandardError=journal