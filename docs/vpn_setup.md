# VPN Setup Guide

All torrent traffic in the Media Center is routed through an encrypted VPN tunnel using [Gluetun](https://github.com/qdm12/gluetun). **Your ISP cannot see what you are downloading or uploading.**

## How It Works

```
Internet <--encrypted--> [Gluetun VPN Tunnel] <--local--> [Transmission]
                              |
                         Firewall rules
                         block ALL traffic
                         outside the tunnel
```

**Transmission has no direct internet access.** It uses `network_mode: "service:gluetun"`, which means it shares Gluetun's network stack. All packets from Transmission must pass through the VPN tunnel — there is no other route.

## Kill Switch (Automatic)

The kill switch is enforced at **three levels**:

1. **Docker Network Isolation:** Transmission has no network interface of its own. It physically shares Gluetun's network namespace. If Gluetun has no VPN connection, Transmission has no connection at all.

2. **Gluetun Firewall:** Gluetun runs iptables rules that block all outbound traffic except through the VPN tunnel. Even if the VPN disconnects momentarily, packets are dropped — not leaked.

3. **Health Check Dependency:** Transmission's `depends_on` requires Gluetun to be `service_healthy`. If Gluetun's health check fails (VPN is down), Docker will not start Transmission. If Gluetun becomes unhealthy while running, Transmission loses all network access instantly.

**Result:** If the VPN stops, torrents stop. No exceptions, no leaks.

## Setup

### 1. Choose a VPN Provider

We recommend **Mullvad** (€5/mo, no email, no logs, WireGuard). Other supported providers include NordVPN, ProtonVPN, Surfshark, and [50+ more](https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers).

### 2. Configure `.env`

Edit your `.env` file with your VPN credentials:

**For WireGuard with custom endpoint (recommended):**

Use `custom` provider to specify the exact server from your downloaded config file.
This avoids auto-selected server ports that may be blocked by your ISP or NAT.

```env
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=<your private key from .conf file>
WIREGUARD_ADDRESSES=<your address, e.g. 10.x.x.x/32>
WIREGUARD_PUBLIC_KEY=<server public key from [Peer] section>
WIREGUARD_ENDPOINT_IP=<server IP from [Peer] Endpoint>
WIREGUARD_ENDPOINT_PORT=<port from [Peer] Endpoint, e.g. 3046>
```

> **Important:** The **private key** is only available in the `.conf` file you download
> when generating the key. The Mullvad website only shows your **public key** —
> do not confuse the two!

**For OpenVPN:**
```env
VPN_SERVICE_PROVIDER=nordvpn
VPN_TYPE=openvpn
OPENVPN_USER=<your username>
OPENVPN_PASSWORD=<your password>
```

**Optional — Server Selection:**
```env
VPN_SERVER_COUNTRIES=Switzerland
VPN_SERVER_CITIES=Zurich
```

### 3. Start the Stack

```bash
./start.sh full
```

The start script will warn you if VPN credentials are missing and ask for confirmation before proceeding without protection.

## Firewall Settings

These are configured in `.env` and control Gluetun's built-in firewall:

| Variable | Default | Purpose |
|---|---|---|
| `FIREWALL_VPN_INPUT_PORTS` | `51413` | Ports open on the VPN interface (torrent peer connections) |
| `FIREWALL_INPUT_PORTS` | `9091` | Ports open on the local network (Transmission WebUI) |
| `FIREWALL_OUTBOUND_SUBNETS` | `172.16.0.0/12` | Local Docker subnets allowed (so Radarr/Sonarr can reach Transmission) |

## Verifying the VPN is Active

Check Gluetun's logs:
```bash
docker logs gluetun
```

You should see:
```
INFO [wireguard] Connecting to <server>...
INFO [wireguard] Connected!
INFO [healthcheck] healthy!
```

Verify your public IP through the tunnel:
```bash
docker exec gluetun wget -qO- https://ipinfo.io/ip
```

This should show the VPN server's IP, **not** your real IP.

## Troubleshooting

| Problem | Solution |
|---|---|
| Transmission won't start | Check `docker logs gluetun` — VPN must be healthy first |
| Gluetun keeps restarting | Verify credentials in `.env` are correct |
| Slow speeds | Try `VPN_TYPE=wireguard` (faster than OpenVPN) or a closer server |
| Can't reach Transmission WebUI | Ensure `FIREWALL_INPUT_PORTS=9091` is set |
| Radarr/Sonarr can't connect | Ensure `FIREWALL_OUTBOUND_SUBNETS` includes your Docker subnet |
