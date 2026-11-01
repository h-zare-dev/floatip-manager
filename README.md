# floatip-manager

**Lightweight, persistent floating IPv4 management for Netplan-based Linux servers.**

`floatip-manager` is a small Bash utility that adds and removes secondary IPv4 addresses on a Linux network interface. It keeps its own Netplan file separate from the server's existing primary-IP/DHCP configuration and avoids a full network reconfiguration during normal address changes.

> **Important:** This tool manages IPv4 addresses **inside the guest operating system**. Your hosting provider must already route or assign those addresses to your server. It does not create, purchase, move, or attach floating IPs in a provider control panel or API.

## Features

- Add or remove one or multiple floating IPv4 addresses.
- Replace the managed address list or clear it entirely.
- Persist managed addresses across reboot and `systemd-networkd` restart.
- Automatically select the interface used by the IPv4 default route (for example `eth0`, `ens3`, or `enp1s0`).
- Keep managed floating-IP configuration in a dedicated Netplan file.
- Adopt an already-active `/32` address into persistent management without issuing a duplicate `ip addr add`.
- Change only managed `/32` addresses during normal operations; do not run `netplan apply` or `networkctl reload` for every add/delete.
- No dependency on a port-forwarding manager, Docker, or any cloud-provider API.

## Compatibility and scope

| Environment | Support |
| --- | --- |
| Ubuntu Server 24.04 / 26.04 using Netplan + `systemd-networkd` | Intended environment |
| Other Ubuntu releases using the same network stack | May work; verify on the actual host |
| Debian with Netplan already installed **and used** with `systemd-networkd` | May work; verify first |
| Debian using `ifupdown`, `/etc/network/interfaces`, or another network manager | Not supported by this installer |
| Provider-side NAT / router-mapped floating public IPs | Not applicable |
| IPv6 addresses or non-`/32` IPv4 secondary addresses | Not supported |

A typical use case is a Hetzner Cloud server with additional public Floating IPv4 addresses routed directly to its VM. Other providers can work if their network configuration requires assigning the public IPv4 inside the VM.

**Requirements:** Linux, Bash, `curl` for the installer, `ip` (iproute2), Netplan, an active `systemd-networkd`-based configuration, and root privileges for management commands. The installer checks for `curl`, `bash`, `ip`, and `netplan`; it does **not** install or switch your network stack. It does not automatically prove which backend manages your interface.

Before installing on an unfamiliar machine, inspect the network setup:

```bash
ip -4 route show default
ls -la /etc/netplan/
sudo netplan get
systemctl is-active systemd-networkd
```

## Installation

### Stable v1.0.1 (recommended)

Download both the installer and the executable from the **same release tag**:

```bash
curl -fsSL https://raw.githubusercontent.com/h-zare-dev/floatip-manager/v1.0.1/install.sh | sudo env FLOATIP_REF=v1.0.1 bash
```

Check the installed version:

```bash
floatip --version
```

Expected output:

```text
1.0.1
```

Release notes: [v1.0.1](https://github.com/h-zare-dev/floatip-manager/releases/tag/v1.0.1).

The installer puts the executable at `/usr/local/sbin/floatip`. **Installation alone does not add, remove, or reconfigure any network addresses.** Re-running the installer replaces the executable without deleting your managed Netplan configuration.

> Review remote shell scripts before piping them into `sudo bash`, especially on production servers. Using the release-tag URL avoids unintentionally tracking new commits on `main`.

### Latest main branch (development)

```bash
curl -fsSL https://raw.githubusercontent.com/h-zare-dev/floatip-manager/main/install.sh | sudo bash
```

This installs the latest `main` version, which may differ from the latest tagged release.

### Install from a cloned repository

For a **local installation of the exact checked-out file**, without downloading the executable a second time:

```bash
git clone https://github.com/h-zare-dev/floatip-manager.git
cd floatip-manager
git checkout v1.0.1
sudo install -m 0755 floatip /usr/local/sbin/floatip
```

Running `sudo bash install.sh` from a clone is also possible, but that installer downloads the executable from the selected remote ref. Its default is `main`; use `sudo env FLOATIP_REF=v1.0.1 bash install.sh` to select the stable release.

## Quick start

You can use `add` immediately on a fresh installation. **You do not need to run `set` first.**

```bash
# Add one or several public IPv4 addresses already assigned/routed by your provider
sudo floatip add 95.216.178.75 65.109.254.122

# Show persistent managed addresses and their current on-interface status
sudo floatip show

# Remove just one managed address
sudo floatip del 95.216.178.75
```

Example `show` output:

```text
Interface: eth0
Floating IPs:
  95.216.178.75   active
  65.109.254.122  active
```

`show` reads the address list from `/etc/netplan/60-floating-ip.yaml` and checks those addresses against the detected interface. **It does not list all IP addresses configured on the machine.** An address manually added with `ip addr add` can be active even if `floatip show` says `none`.

## Commands

| Command | Action |
| --- | --- |
| `sudo floatip show` | Show managed addresses and their live status |
| `sudo floatip add IP [IP ...]` | Add addresses without replacing existing managed addresses |
| `sudo floatip del IP [IP ...]` | Remove specified managed addresses |
| `sudo floatip delete IP [IP ...]` | Alias for `del` |
| `sudo floatip remove IP [IP ...]` | Alias for `del` |
| `sudo floatip set IP [IP ...]` | Make the managed list exactly match the supplied addresses |
| `sudo floatip clear` | Remove every address managed by this tool |
| `floatip --version` | Show installed version |

### Add

```bash
sudo floatip add 95.216.178.75
sudo floatip add 95.216.178.75 65.109.254.122
```

On the first successful add, the managed Netplan file is created automatically. If a requested `/32` address is already active on the selected interface, the tool can adopt it into its configuration rather than trying to add it again. If the address exists with a different prefix, the tool rejects that mismatch rather than changing the prefix automatically.

### Delete

```bash
sudo floatip del 95.216.178.75
sudo floatip del 95.216.178.75 65.109.254.122
```

Only addresses that are already listed in the tool's managed file can be deleted with `del`. Removing an address that is currently serving traffic can immediately interrupt those connections.

### Replace the managed list

```bash
sudo floatip set 95.216.178.75 65.109.254.122
```

`set` replaces the entire **managed** address list. The script adds missing addresses first, then removes previously managed addresses omitted from the new list. Unchanged addresses are not intentionally removed and re-added.

### Clear

```bash
sudo floatip clear
```

This removes all addresses managed by the tool and removes its dedicated Netplan file. It does **not** flush the interface or delete every address on the server.

## How persistence works

The tool owns exactly this configuration file:

```text
/etc/netplan/60-floating-ip.yaml
```

For example, after adding two addresses to `eth0`:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 95.216.178.75/32
        - 65.109.254.122/32
```

Existing primary address and DHCP settings stay in the provider's existing Netplan configuration, commonly:

```text
/etc/netplan/50-cloud-init.yaml
```

On a conventional Netplan system, matching `eth0` definitions are merged into the effective configuration. For example, the resulting interface can have both `dhcp4: true` and the floating addresses above.

During normal `add` / `del` / `set` operations, the tool:

1. Updates only its managed YAML file.
2. Runs `netplan generate` to validate the configuration and generate backend files.
3. Changes the necessary live IPv4 `/32` addresses using `ip addr add` or `ip addr del`.

**It intentionally does not run `netplan apply` or `networkctl reload` on every change.** Reloading the network while the script also changes addresses can race with `ip addr add`, and a full interface reconfiguration can briefly interrupt production connections.

On reboot or a `systemd-networkd` restart, the generated Netplan/networkd configuration should restore managed addresses when this interface is actually managed by `systemd-networkd`. Always verify this behavior on the specific server before relying on it in production.

## Interface detection

By default, the tool uses the interface associated with the IPv4 default route, for example `eth0`, `ens3`, `ens18`, or `enp1s0`. It falls back to a route lookup to `1.1.1.1` if necessary.

For an unusual multi-interface host, choose the interface explicitly:

```bash
sudo env FLOATIP_IFACE=ens3 floatip show
sudo env FLOATIP_IFACE=ens3 floatip add 203.0.113.10
```

**Caution:** `floatip-manager` uses a single managed Netplan file and is designed for one selected interface at a time. If the default-route interface changes, or you change `FLOATIP_IFACE` after already managing addresses, review the existing YAML before running another modifying command. The tool does not automatically migrate configuration between network interfaces.

## Check and troubleshoot

### Inspect configuration and live addresses

```bash
sudo floatip show
ip -4 -o addr show
ip -4 route show default
sudo netplan get
sudo cat /etc/netplan/60-floating-ip.yaml
```

The file may not exist on a fresh installation or after `clear`.

If `floatip show` reports `MISSING`, inspect whether the requested IP is actually assigned to the correct interface and check the Netplan/systemd-networkd configuration. Do not assume that the provider has routed the address merely because it appears in the guest.

### Check that persistence survives a networkd restart

Perform this test only during a maintenance window, preferably from your **primary-IP SSH connection with the provider console available**. Restarting the network service can cause a temporary loss of connectivity.

```bash
sudo netplan get
sudo systemctl restart systemd-networkd
sleep 5
sudo floatip show
ip -4 addr show
```

Addresses should return without running `floatip set` again. If they do not, collect diagnostics before manually adding them:

```bash
sudo netplan get
ip -4 -o addr show
journalctl -u systemd-networkd --since "-10 min" --no-pager
```

### `Address already assigned`

In older versions, `networkctl reload` could race with a separate `ip addr add` operation, resulting in `Address already assigned`. Version `v1.0.1` removes that automatic reload step and checks whether an address is already active before adding it.

```bash
floatip --version
ip -4 -o addr show
sudo floatip show
```

If an address is already active with the expected `/32` prefix but not managed by the tool, running `sudo floatip add ADDRESS` with `v1.0.1` can register it persistently without a duplicate add. If the failure persists, inspect the runtime addresses and generated configuration instead of deleting the primary IP or flushing the interface.

### Important limitations

- The tool does not change your provider's IP allocation, routing, firewall rules, or NAT configuration.
- It does not integrate with or require `iptables-forward-manager`, Docker, or another application.
- `add` and `set` refuse the IPv4 currently selected as the default-route source address. This is not a complete safeguard against future changes in which the primary address is reassigned; inspect the managed file before `del` / `clear` on a server whose addressing has changed.
- The tool validates the Netplan configuration, but it does not perform a complete end-to-end reachability test.
- It assumes this managed Netplan file is owned by `floatip-manager`; do not hand-edit it into a different schema while continuing to use the commands.

## Uninstall

To remove **only the command**, keeping current IP configuration intact:

```bash
sudo rm -f /usr/local/sbin/floatip
```

This intentionally leaves `/etc/netplan/60-floating-ip.yaml` in place.

To remove all **managed IPs first** and then uninstall:

```bash
sudo floatip clear
sudo rm -f /usr/local/sbin/floatip
```

**Warning:** `clear` removes addresses immediately and can disconnect active users or SSH sessions using those addresses.

## License

[MIT](LICENSE)
