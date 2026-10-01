# floatip-manager

A small Bash utility for managing persistent secondary / floating IPv4 addresses on **Netplan-based Linux servers**.

It keeps floating IP configuration separate from the server's primary IP configuration, auto-detects the primary IPv4 interface, and provides simple `add`, `del`, `set`, `show`, and `clear` commands.

## Important scope

This tool is intended for providers/network setups where the floating or secondary public IP must be configured **inside the guest OS** on the server interface (for example, Hetzner Cloud Floating IPs).

It is **not** intended for cloud floating-IP products that are implemented only by provider-side NAT/router mapping and do not require the public IP to be bound inside the VM.

## Requirements

- Linux
- Bash
- `ip` from iproute2
- Netplan
- A Netplan/systemd-networkd based network setup
- root privileges for changes

Typical target systems are Ubuntu Server 24.04/26.04. Debian also works if the server is already using Netplan; the installer does not install or replace the system's network stack.

## One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/h-zare-dev/floatip-manager/main/install.sh | sudo bash
```

The installer places the command at:

```text
/usr/local/sbin/floatip
```

It does **not** add or remove any IP addresses during installation.

## Install from a cloned folder

```bash
git clone https://github.com/h-zare-dev/floatip-manager.git
cd floatip-manager
sudo bash install.sh
```

Or install the script directly from the cloned repository:

```bash
sudo install -m 0755 floatip /usr/local/sbin/floatip
```

## Usage

### Show managed floating IPs

```bash
sudo floatip show
```

Example:

```text
Interface: eth0
Floating IPs:
  95.216.178.75   active
  65.109.254.122  active
```

### Add one or more floating IPs

No previous `set` command is required. On a fresh server, the first `add` command creates the persistent Netplan file automatically.

```bash
sudo floatip add 95.216.178.75
```

Multiple addresses can be added at once:

```bash
sudo floatip add 95.216.178.75 65.109.254.122
```

If an address is already active on the interface but was added manually, `floatip add` adopts it into the persistent configuration without adding a duplicate address.

### Delete one or more floating IPs

```bash
sudo floatip del 95.216.178.75
```

Multiple addresses:

```bash
sudo floatip del 95.216.178.75 65.109.254.122
```

`delete` and `remove` are aliases for `del`.

### Replace the complete managed list

```bash
sudo floatip set 95.216.178.75 65.109.254.122
```

`set` treats the supplied addresses as the complete desired floating-IP list. Addresses that remain in the list are not removed/re-added unnecessarily.

### Remove all managed floating IPs

```bash
sudo floatip clear
```

## How persistence works

The tool stores only the floating IPs it manages in:

```text
/etc/netplan/60-floating-ip.yaml
```

The server's existing primary/DHCP configuration remains in its original Netplan file, such as:

```text
/etc/netplan/50-cloud-init.yaml
```

For example, the resulting Netplan configuration may effectively contain:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      addresses:
        - 95.216.178.75/32
        - 65.109.254.122/32
```

The tool runs `netplan generate` to validate and generate persistent backend configuration. Runtime IP changes are applied only to the managed floating addresses, avoiding an unnecessary full `netplan apply` on every add/delete operation.

After a reboot or `systemd-networkd` restart, Netplan/systemd-networkd can restore the configured floating addresses from the persistent file.

## Interface auto-detection

The interface is detected from the IPv4 default route, so names such as these are supported automatically:

```text
eth0
ens3
ens18
enp1s0
```

For unusual multi-NIC systems, override detection for one command:

```bash
sudo env FLOATIP_IFACE=ens3 floatip show
sudo env FLOATIP_IFACE=ens3 floatip add 203.0.113.10
```

## Safety behavior

- Does not modify the server's existing primary-IP Netplan file.
- Refuses invalid IPv4 addresses.
- Refuses to manage the IPv4 address currently selected as the server's primary/default-route source address.
- Only removes IPs already managed in `60-floating-ip.yaml`.
- Adds new addresses before removing obsolete managed addresses when replacing a list.
- Validates Netplan configuration before changing runtime addresses.
- Restores the previous managed Netplan file if validation fails.
- Does not install Netplan on systems that do not already use it.

## Check persistence manually

First inspect the current addresses:

```bash
ip -4 addr show
sudo floatip show
```

On a server where a short network interruption is acceptable, you can test a real networkd restart without rebooting:

```bash
sudo systemctl restart systemd-networkd
sleep 5
sudo floatip show
```

The managed addresses should return automatically without running `floatip set` or `floatip add` again.

## Configuration file

Example generated file:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 95.216.178.75/32
        - 65.109.254.122/32
```

Do not mix the primary IP into this file. The primary IP should remain managed by the server/provider's existing network configuration.

## Uninstall

Remove only the command:

```bash
sudo rm -f /usr/local/sbin/floatip
```

This intentionally leaves `/etc/netplan/60-floating-ip.yaml` untouched so uninstalling the command does not unexpectedly remove live network addresses.

If you want to remove the managed floating IPs first:

```bash
sudo floatip clear
sudo rm -f /usr/local/sbin/floatip
```

## Notes

Changing network configuration always carries some risk on remote servers. Keep your provider console available when testing networking changes, especially on multi-interface or customized network setups.
