from __future__ import annotations

from homeassistant.components.binary_sensor import BinarySensorEntity
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
        StargateWormholeActiveSensor(coordinator, entry),
        StargateDialingSensor(coordinator, entry),
    ])


class _StargateBaseBinarySensor(CoordinatorEntity, BinarySensorEntity):
    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._entry = entry

    @property
    def device_info(self):
        return {
            "identifiers": {(DOMAIN, self._entry.entry_id)},
            "name": self._entry.title,
            "manufacturer": "Kristian's Stargate Project",
            "model": self.coordinator.system_info.get("hardware_mode", "Unknown"),
        }


class StargateWormholeActiveSensor(_StargateBaseBinarySensor):
    _attr_icon = "mdi:gate"

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator, entry)
        self._attr_unique_id = f"{entry.entry_id}_wormhole_active"
        self._attr_name = f"{entry.title} Wormhole Active"

    @property
    def is_on(self) -> bool:
        return bool(self.coordinator.data.get("wormhole_active", False))


class StargateDialingSensor(_StargateBaseBinarySensor):
    _attr_icon = "mdi:rotate-360"

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator, entry)
        self._attr_unique_id = f"{entry.entry_id}_dialing"
        self._attr_name = f"{entry.title} Dialing"

    @property
    def is_on(self) -> bool:
        data = self.coordinator.data or {}
        buffer = data.get("address_buffer_outgoing") or data.get("address_buffer_incoming") or []
        wormhole = data.get("wormhole_active", False)
        return bool(buffer) and not wormhole
