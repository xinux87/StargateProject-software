from __future__ import annotations

import logging
from datetime import timedelta

import aiohttp
from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

_LOGGER = logging.getLogger(__name__)

SCAN_INTERVAL = timedelta(seconds=2)


class StargateCoordinator(DataUpdateCoordinator):
    def __init__(self, hass: HomeAssistant, host: str, port: int) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name="Stargate",
            update_interval=SCAN_INTERVAL,
        )
        self.host = host
        self.port = port
        self.base_url = f"http://{host}:{port}"
        self.system_info: dict = {}
        self.address_book: list[dict] = []
        self._session: aiohttp.ClientSession | None = None

    def _get_session(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession()
        return self._session

    async def async_get(self, path: str) -> dict:
        session = self._get_session()
        async with session.get(
            f"{self.base_url}{path}",
            timeout=aiohttp.ClientTimeout(total=5),
        ) as resp:
            resp.raise_for_status()
            return await resp.json(content_type=None)

    async def async_post(self, path: str, data: dict | None = None) -> dict:
        session = self._get_session()
        async with session.post(
            f"{self.base_url}{path}",
            json=data or {},
            timeout=aiohttp.ClientTimeout(total=10),
        ) as resp:
            resp.raise_for_status()
            return await resp.json(content_type=None)

    async def async_setup(self) -> None:
        self.system_info = await self.async_get("/get/system_info")
        raw = await self.async_get("/get/address_book?type=all")
        book: dict = raw.get("address_book", {})
        self.address_book = [
            {"name": entry.get("name", key), "address": entry.get("gate_address", [])}
            for key, entry in book.items()
            if entry.get("gate_address")
        ]

    async def _async_update_data(self) -> dict:
        try:
            dialing = await self.async_get("/get/dialing_status")
            sysinfo = await self.async_get("/get/system_info")
            dialing["audio_volume"] = sysinfo.get("audio_volume", 50)
            return dialing
        except aiohttp.ClientError as err:
            raise UpdateFailed(f"Error communicating with Stargate: {err}") from err
