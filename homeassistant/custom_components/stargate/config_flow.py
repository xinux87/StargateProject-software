from __future__ import annotations

import logging
from typing import Any

import aiohttp
import voluptuous as vol

from homeassistant import config_entries
from homeassistant.components import zeroconf
from homeassistant.data_entry_flow import FlowResult

from .const import DOMAIN, DEFAULT_PORT

_LOGGER = logging.getLogger(__name__)

STEP_USER_DATA_SCHEMA = vol.Schema(
    {
        vol.Required("host", default="stargate.local"): str,
        vol.Required("port", default=DEFAULT_PORT): int,
    }
)


async def _verify_stargate(host: str, port: int) -> dict | None:
    """Return system_info if host is a valid Stargate, else None."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                f"http://{host}:{port}/get/is_alive",
                timeout=aiohttp.ClientTimeout(total=5),
            ) as resp:
                if resp.status != 200:
                    return None
                alive = await resp.json(content_type=None)
                if not alive.get("is_alive"):
                    return None

            async with session.get(
                f"http://{host}:{port}/get/system_info",
                timeout=aiohttp.ClientTimeout(total=5),
            ) as resp:
                return await resp.json(content_type=None)
    except Exception:  # noqa: BLE001
        return None


class StargateConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    VERSION = 1

    def __init__(self) -> None:
        self._host: str = ""
        self._port: int = DEFAULT_PORT
        self._info: dict = {}

    async def async_step_user(
        self, user_input: dict[str, Any] | None = None
    ) -> FlowResult:
        errors: dict[str, str] = {}

        if user_input is not None:
            host = user_input["host"]
            port = user_input["port"]
            info = await _verify_stargate(host, port)
            if info is None:
                errors["base"] = "cannot_connect"
            else:
                unique_id = f"stargate_{host}_{port}"
                await self.async_set_unique_id(unique_id)
                self._abort_if_unique_id_configured()
                return self.async_create_entry(
                    title=info.get("gate_name", "Stargate"),
                    data={"host": host, "port": port},
                )

        return self.async_show_form(
            step_id="user",
            data_schema=STEP_USER_DATA_SCHEMA,
            errors=errors,
        )

    async def async_step_zeroconf(
        self, discovery_info: zeroconf.ZeroconfServiceInfo
    ) -> FlowResult:
        host = discovery_info.host
        port = discovery_info.port or DEFAULT_PORT

        if "stargate" not in discovery_info.hostname.lower():
            return self.async_abort(reason="not_stargate_device")

        info = await _verify_stargate(host, port)
        if info is None:
            return self.async_abort(reason="cannot_connect")

        unique_id = f"stargate_{host}_{port}"
        await self.async_set_unique_id(unique_id)
        self._abort_if_unique_id_configured()

        self._host = host
        self._port = port
        self._info = info

        self.context["title_placeholders"] = {"name": info.get("gate_name", "Stargate")}
        return await self.async_step_zeroconf_confirm()

    async def async_step_zeroconf_confirm(
        self, user_input: dict[str, Any] | None = None
    ) -> FlowResult:
        if user_input is not None:
            return self.async_create_entry(
                title=self._info.get("gate_name", "Stargate"),
                data={"host": self._host, "port": self._port},
            )

        return self.async_show_form(
            step_id="zeroconf_confirm",
            description_placeholders={
                "name": self._info.get("gate_name", "Stargate"),
                "host": self._host,
            },
        )
