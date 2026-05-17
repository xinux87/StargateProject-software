import socket
import subprocess
from pathlib import Path
from typing import Any


class WiFiManager:

    def __init__(self, log: Any) -> None:
        self.log = log

    def _run(self, args: list[str], timeout: int = 10) -> subprocess.CompletedProcess:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)

    def scan_networks(self) -> dict:
        try:
            result = self._run(
                ['nmcli', '-t', '-f', 'SSID,SIGNAL,SECURITY,IN-USE', 'dev', 'wifi', 'list', '--rescan', 'yes'],
                timeout=20,
            )
        except FileNotFoundError:
            return {'status': 'error', 'message': 'nmcli not found'}
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'message': 'scan timed out'}

        if result.returncode != 0:
            self.log.log(f'WiFiManager.scan_networks error: {result.stderr.strip()}')
            return {'status': 'error', 'message': result.stderr.strip()}

        networks: list[dict] = []
        seen: set[str] = set()

        for line in result.stdout.splitlines():
            # nmcli -t escapes colons inside field values as \:
            # Split on unescaped colons only
            parts = _split_nmcli_line(line, 4)
            if parts is None:
                continue

            ssid, signal_raw, security, in_use = parts
            ssid = ssid.strip()
            if not ssid or ssid in seen:
                continue
            seen.add(ssid)

            try:
                signal = int(signal_raw.strip())
            except ValueError:
                signal = 0

            networks.append({
                'ssid': ssid,
                'signal': signal,
                'security': security.strip(),
                'connected': in_use.strip() == '*',
            })

        networks.sort(key=lambda n: n['signal'], reverse=True)
        return {'status': 'ok', 'data': networks}

    def connect(self, ssid: str, password: str = '') -> dict:
        if not ssid:
            return {'status': 'error', 'message': 'SSID must not be empty'}

        args = ['nmcli', 'dev', 'wifi', 'connect', ssid]
        if password:
            args += ['password', password]

        try:
            result = self._run(args, timeout=30)
        except FileNotFoundError:
            return {'status': 'error', 'message': 'nmcli not found'}
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'message': 'connect timed out'}

        if result.returncode != 0:
            msg = result.stderr.strip() or result.stdout.strip()
            self.log.log(f'WiFiManager.connect error: {msg}')
            return {'status': 'error', 'message': msg}

        return {'status': 'ok', 'data': {'message': result.stdout.strip()}}

    def disconnect(self) -> dict:
        try:
            result = self._run(['nmcli', 'dev', 'disconnect', 'wlan0'])
        except FileNotFoundError:
            return {'status': 'error', 'message': 'nmcli not found'}
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'message': 'disconnect timed out'}

        if result.returncode != 0:
            msg = result.stderr.strip()
            self.log.log(f'WiFiManager.disconnect error: {msg}')
            return {'status': 'error', 'message': msg}

        return {'status': 'ok', 'data': {'message': result.stdout.strip()}}

    def get_status(self) -> dict:
        try:
            con_result = self._run(
                ['nmcli', '-t', '-f', 'NAME,TYPE,STATE,IP4.ADDRESS', 'con', 'show', '--active']
            )
        except FileNotFoundError:
            return {'status': 'error', 'message': 'nmcli not found'}
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'message': 'status timed out'}

        if con_result.returncode != 0:
            msg = con_result.stderr.strip()
            self.log.log(f'WiFiManager.get_status error: {msg}')
            return {'status': 'error', 'message': msg}

        ssid = ''
        ip = ''
        connected = False

        # Each active connection may span multiple output lines (one per field).
        # nmcli -t groups multiline entries; NAME appears first, IP4.ADDRESS may follow.
        # Collect all lines then associate them by block.
        lines = con_result.stdout.splitlines()
        blocks: list[dict[str, str]] = []
        current: dict[str, str] = {}

        for line in lines:
            parts = _split_nmcli_line(line, 4)
            if parts is None:
                # Fallback: try splitting on first colon for IP4.ADDRESS continuation lines
                if ':' in line:
                    key, _, val = line.partition(':')
                    current[key.strip()] = val.strip()
                continue

            name, con_type, state, ip4 = (p.strip() for p in parts)

            if con_type == '802-11-wireless':
                if current:
                    blocks.append(current)
                current = {'NAME': name, 'TYPE': con_type, 'STATE': state, 'IP4.ADDRESS': ip4}
            elif current and not con_type:
                # continuation line with IP4.ADDRESS
                current['IP4.ADDRESS'] = name  # name field holds the value in -t mode

        if current:
            blocks.append(current)

        for block in blocks:
            if block.get('TYPE') == '802-11-wireless':
                connected = block.get('STATE') == 'activated'
                ssid = block.get('NAME', '')
                ip_with_prefix = block.get('IP4.ADDRESS', '')
                # Strip CIDR notation (e.g. 192.168.1.5/24 → 192.168.1.5)
                ip = ip_with_prefix.split('/')[0] if ip_with_prefix else ''
                break

        signal = 0
        if connected:
            try:
                sig_result = self._run(['nmcli', '-t', '-f', 'SIGNAL', 'dev', 'wifi', 'list'])
                if sig_result.returncode == 0:
                    first_line = sig_result.stdout.splitlines()[0] if sig_result.stdout.strip() else ''
                    signal = int(first_line.strip()) if first_line.strip().isdigit() else 0
            except (FileNotFoundError, subprocess.TimeoutExpired, IndexError, ValueError):
                pass

        return {
            'status': 'ok',
            'data': {
                'connected': connected,
                'ssid': ssid,
                'ip': ip,
                'signal': signal,
            },
        }

    def get_saved_networks(self) -> dict:
        try:
            result = self._run(['nmcli', '-t', '-f', 'NAME,TYPE', 'con', 'show'])
        except FileNotFoundError:
            return {'status': 'error', 'message': 'nmcli not found'}
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'message': 'timed out'}

        if result.returncode != 0:
            msg = result.stderr.strip()
            self.log.log(f'WiFiManager.get_saved_networks error: {msg}')
            return {'status': 'error', 'message': msg}

        networks: list[dict] = []
        for line in result.stdout.splitlines():
            parts = _split_nmcli_line(line, 2)
            if parts is None:
                continue
            name, con_type = (p.strip() for p in parts)
            if con_type == '802-11-wireless' and name:
                networks.append({'ssid': name})

        return {'status': 'ok', 'data': networks}

    def forget_network(self, ssid: str) -> dict:
        if not ssid:
            return {'status': 'error', 'message': 'SSID must not be empty'}

        try:
            result = self._run(['nmcli', 'con', 'delete', 'id', ssid])
        except FileNotFoundError:
            return {'status': 'error', 'message': 'nmcli not found'}
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'message': 'timed out'}

        if result.returncode != 0:
            msg = result.stderr.strip()
            self.log.log(f'WiFiManager.forget_network error: {msg}')
            return {'status': 'error', 'message': msg}

        return {'status': 'ok', 'data': {'message': result.stdout.strip()}}

    def set_hostname(self, hostname: str) -> dict:
        if not hostname:
            return {'status': 'error', 'message': 'hostname must not be empty'}

        # RFC 1123: allow alphanumeric and hyphens, no leading/trailing hyphens
        import re
        if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$', hostname):
            return {'status': 'error', 'message': 'invalid hostname format'}

        try:
            result = subprocess.run(
                ['hostnamectl', 'set-hostname', hostname],
                capture_output=True, text=True, timeout=10,
            )
        except FileNotFoundError:
            return {'status': 'error', 'message': 'hostnamectl not found'}
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'message': 'timed out'}

        if result.returncode != 0:
            msg = result.stderr.strip()
            self.log.log(f'WiFiManager.set_hostname hostnamectl error: {msg}')
            return {'status': 'error', 'message': msg}

        try:
            hosts_path = Path('/etc/hosts')
            original = hosts_path.read_text(encoding='utf-8')
            lines = []
            old_hostname = socket.gethostname()
            for line in original.splitlines():
                # Replace only the short hostname token on loopback lines
                if line.startswith('127.0.1.1'):
                    parts = line.split()
                    parts = [hostname if p == old_hostname else p for p in parts]
                    lines.append(' '.join(parts))
                else:
                    lines.append(line)
            hosts_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        except OSError as exc:
            self.log.log(f'WiFiManager.set_hostname /etc/hosts update failed: {exc}')
            return {'status': 'error', 'message': f'/etc/hosts update failed: {exc}'}

        return {'status': 'ok', 'data': {'hostname': hostname}}

    def get_hostname(self) -> dict:
        return {'status': 'ok', 'data': {'hostname': socket.gethostname()}}


def _split_nmcli_line(line: str, expected_parts: int) -> list[str] | None:
    """Split a nmcli -t output line on unescaped colons.

    nmcli escapes literal colons inside values as \\:, so we must not split on those.
    Returns a list of exactly `expected_parts` strings, or None if the split yields
    a different count.
    """
    parts: list[str] = []
    current: list[str] = []
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == '\\' and i + 1 < len(line) and line[i + 1] == ':':
            current.append(':')
            i += 2
        elif ch == ':':
            parts.append(''.join(current))
            current = []
            i += 1
        else:
            current.append(ch)
            i += 1
    parts.append(''.join(current))

    if len(parts) != expected_parts:
        return None
    return parts
