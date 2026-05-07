from __future__ import annotations

from homeassistant.components.button import ButtonEntity
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
    async_add_entities([
        StargateButton(coordinator, entry, "Wormhole Open",    "mdi:gate-open",  "/do/wormhole_on"),
        StargateButton(coordinator, entry, "Wormhole Close",   "mdi:gate",       "/do/wormhole_off"),
        StargateButton(coordinator, entry, "Simulate Incoming","mdi:download",   "/do/simulate_incoming"),
        StargateButton(coordinator, entry, "Abort Dial",       "mdi:cancel",     "/do/clear_outgoing_buffer"),
    ])


class StargateButton(CoordinatorEntity, ButtonEntity):
    def __init__(
        self,
        coordinator: StargateCoordinator,
        entry: ConfigEntry,
        label: str,
        icon: str,
        endpoint: str,
    ) -> None:
        super().__init__(coordinator)
        self._entry = entry
        self._endpoint = endpoint
        self._attr_icon = icon
        slug = label.lower().replace(" ", "_")
        self._attr_unique_id = f"{entry.entry_id}_{slug}"
        self._attr_name = f"{entry.title} {label}"

    @property
    def device_info(self):
        return {
            "identifiers": {(DOMAIN, self._entry.entry_id)},
            "name": self._entry.title,
            "manufacturer": "Kristian's Stargate Project",
            "model": self.coordinator.system_info.get("hardware_mode", "Unknown"),
        }

    async def async_press(self) -> None:
        await self.coordinator.async_post(self._endpoint)
        await self.coordinator.async_request_refresh()
