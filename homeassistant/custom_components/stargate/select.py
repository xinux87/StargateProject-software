from __future__ import annotations

import asyncio
import logging

from homeassistant.components.select import SelectEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import StargateCoordinator

_LOGGER = logging.getLogger(__name__)


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator: StargateCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([StargateTargetPlanetSelect(coordinator, entry)])


class StargateTargetPlanetSelect(CoordinatorEntity, SelectEntity):
    _attr_icon = "mdi:earth"

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._entry = entry
        self._attr_unique_id = f"{entry.entry_id}_target_planet"
        self._attr_name = f"{entry.title} Target Planet"

    @property
    def device_info(self):
        return {
            "identifiers": {(DOMAIN, self._entry.entry_id)},
            "name": self._entry.title,
            "manufacturer": "Kristian's Stargate Project",
            "model": self.coordinator.system_info.get("hardware_mode", "Unknown"),
        }

    @property
    def options(self) -> list[str]:
        return [p["name"] for p in self.coordinator.address_book if p.get("name")]

    @property
    def current_option(self) -> str | None:
        return (self.coordinator.data or {}).get("connected_planet") or None

    async def async_select_option(self, option: str) -> None:
        planet = next(
            (p for p in self.coordinator.address_book if p.get("name") == option),
            None,
        )
        if planet is None:
            _LOGGER.warning("Planet %s not found in address book", option)
            return

        address: list[int] = planet.get("address") or planet.get("glyphs") or []
        if not address:
            _LOGGER.warning("No address found for planet %s", option)
            return

        # Abort any current dial first
        await self.coordinator.async_post("/do/clear_outgoing_buffer")
        await asyncio.sleep(0.3)

        # Dial each symbol
        for symbol in address:
            await self.coordinator.async_post("/do/dhd_press", {"symbol": symbol})
            await asyncio.sleep(0.1)

        # Press centre to engage
        await self.coordinator.async_post("/do/dhd_press", {"symbol": 0})
        await self.coordinator.async_request_refresh()
