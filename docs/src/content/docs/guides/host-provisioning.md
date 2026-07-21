---
title: Host provisioning
description: One-time host setup (reference cloud-init).
---


`outpost` never installs anything on the host - it only manages workspace containers.
This is the one-time host setup it assumes, as a complete `cloud-config` you can
feed to cloud-init directly or template from OpenTofu (the only interpolation is
the Tailscale auth key). Adapt freely; the point is the package/module/firewall
set, not the exact provider.

What the host must end up with:

- **Docker CE + Compose plugin** - the engine `outpost` drives (Compose powers `outpost
  up`/`outpost down`). (`outpost` never installs it.)
- **socat** - the in-container git agent bridge depends on it (`outpost doctor` checks it).
- **Tailscale + Tailscale SSH** - access path (no host keys stored).
- **A firewall that drops all public inbound** - here UFW limited to the tailnet,
  behind the provider firewall.
- The login user is **`dev`, uid 1000** (the forwarded SSH agent is only readable
  in the container when host uid is 1000 - see [git-and-ssh.md](/guides/git-and-ssh/)).

```yaml
#cloud-config
# ${tailscale_authkey} is the only template interpolation. If you add literal
# shell ${...} expansion, double the brace ($${...}) so OpenTofu leaves it alone.
users:
  - name: dev
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    # No ssh_authorized_keys: access is Tailscale SSH (no key stored on the outpost).

disable_root: true
ssh_pwauth: false

package_update: true
package_upgrade: true
packages: [ca-certificates, curl, socat, ufw, unattended-upgrades, fail2ban]

write_files:
  - path: /etc/apt/apt.conf.d/20auto-upgrades
    content: |
      APT::Periodic::Update-Package-Lists "1";
      APT::Periodic::Unattended-Upgrade "1";
  - path: /etc/apt/apt.conf.d/52unattended-reboot
    content: |
      # Always-on agent outpost: do NOT auto-reboot (a 04:30 reboot would kill overnight
      # agents + tmux sessions). Security updates still install; reboot manually when
      # idle (check /var/run/reboot-required), or use Ubuntu Pro Livepatch.
      Unattended-Upgrade::Automatic-Reboot "false";
  - path: /etc/cron.weekly/docker-prune
    permissions: '0755'
    content: |
      #!/bin/sh
      # Reclaim disk on a 24/7 outpost: dangling images + build cache only. Does NOT
      # touch stopped containers, tagged images, or volumes (your data is safe).
      docker image prune   -f >/dev/null 2>&1 || true
      docker builder prune -f >/dev/null 2>&1 || true
  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PubkeyAuthentication yes
      MaxAuthTries 3
      LoginGraceTime 30
      X11Forwarding no
      PermitTunnel no
      AllowUsers dev
      LogLevel VERBOSE
      # Do NOT add 'AllowAgentForwarding no' (Secretive git signing needs it) or
      # 'AllowTcpForwarding no' (editor port forwarding needs it).

runcmd:
  # Docker engine + Compose plugin
  - install -m0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  - chmod a+r /etc/apt/keyrings/docker.asc
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  - usermod -aG docker dev
  # Tailscale + Tailscale SSH (key injected by your provisioner)
  - curl -fsSL https://tailscale.com/install.sh | sh
  - tailscale up --ssh --hostname=dev-box --authkey=${tailscale_authkey}
  # UFW: only loopback + tailnet inbound (defense in depth behind the provider firewall)
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow in on tailscale0
  - ufw allow 41641/udp
  - ufw --force enable
  - systemctl enable --now unattended-upgrades fail2ban
```

After the outpost boots, confirm with `outpost doctor` (it checks the engine, the Compose
plugin, socat, host uid, the forwarded agent, and whether Docker's backing store
is on a `nosuid` mount - which would silently break setuid/file-caps inside
containers). Then follow [Installation](/installation/).
