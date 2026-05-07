from __future__ import annotations

from homeassistant.components.switch import SwitchEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import StargateCoordinator


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator: StargateCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities([StargateSilenceModeSwitch(coordinator, entry)])


class StargateSilenceModeSwitch(CoordinatorEntity, SwitchEntity):
    _attr_icon = "mdi:volume-off"

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._entry = entry
        self._attr_unique_id = f"{entry.entry_id}_silence_mode"
        self._attr_name = f"{entry.title} Silence Mode"

    @property
    def device_info(self):
        return {
            "identifiers": {(DOMAIN, self._entry.entry_id)},
            "name": self._entry.title,
            "manufacturer": "Kristian's Stargate Project",
            "model": self.coordinator.system_info.get("hardware_mode", "Unknown"),
        }

    @property
    def is_on(self) -> bool:
        return bool((self.coordinator.data or {}).get("silence_mode", False))

    async def async_turn_on(self, **kwargs) -> None:
        if not self.is_on:
            await self.coordinator.async_post("/do/toggle_silence_mode")
            await self.coordinator.async_request_refresh()

    async def async_turn_off(self, **kwargs) -> None:
        if self.is_on:
            await self.coordinator.async_post("/do/toggle_silence_mode")
            await self.coordinator.async_request_refresh()
