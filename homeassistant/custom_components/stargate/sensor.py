from __future__ import annotations

import time

from homeassistant.components.sensor import SensorEntity, SensorDeviceClass
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import UnitOfTime
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
        StargateStateSensor(coordinator, entry),
        StargateLockedChevronsSensor(coordinator, entry),
        StargateConnectedPlanetSensor(coordinator, entry),
        StargateWormholeRemainingSensor(coordinator, entry),
    ])


class _StargateBaseSensor(CoordinatorEntity, SensorEntity):
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


class StargateStateSensor(_StargateBaseSensor):
    _attr_icon = "mdi:gate"

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator, entry)
        self._attr_unique_id = f"{entry.entry_id}_state"
        self._attr_name = f"{entry.title} State"

    @property
    def native_value(self) -> str:
        data = self.coordinator.data or {}
        wormhole = data.get("wormhole_active", False)
        if wormhole:
            return "open"
        buffer = data.get("address_buffer_outgoing") or data.get("address_buffer_incoming") or []
        if buffer:
            return "dialing"
        return "idle"


class StargateLockedChevronsSensor(_StargateBaseSensor):
    _attr_icon = "mdi:chevron-triple-right"

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator, entry)
        self._attr_unique_id = f"{entry.entry_id}_locked_chevrons"
        self._attr_name = f"{entry.title} Locked Chevrons"

    @property
    def native_value(self) -> int:
        data = self.coordinator.data or {}
        outgoing = data.get("locked_chevrons_outgoing", 0)
        incoming = data.get("locked_chevrons_incoming", 0)
        return max(outgoing, incoming)


class StargateConnectedPlanetSensor(_StargateBaseSensor):
    _attr_icon = "mdi:earth"

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator, entry)
        self._attr_unique_id = f"{entry.entry_id}_connected_planet"
        self._attr_name = f"{entry.title} Connected Planet"

    @property
    def native_value(self) -> str | None:
        data = self.coordinator.data or {}
        return data.get("connected_planet") or None


class StargateWormholeRemainingSensor(_StargateBaseSensor):
    _attr_icon = "mdi:timer-outline"
    _attr_device_class = SensorDeviceClass.DURATION
    _attr_native_unit_of_measurement = UnitOfTime.SECONDS

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator, entry)
        self._attr_unique_id = f"{entry.entry_id}_wormhole_remaining"
        self._attr_name = f"{entry.title} Wormhole Remaining"

    @property
    def native_value(self) -> float | None:
        data = self.coordinator.data or {}
        if not data.get("wormhole_active"):
            return None
        remaining = data.get("wormhole_time_till_close")
        if remaining is not None:
            return max(0.0, float(remaining))
        # fallback: calculate from open_time + max_time
        open_time = data.get("wormhole_open_time")
        max_time = data.get("wormhole_max_time")
        if open_time and max_time:
            return max(0.0, open_time + max_time - time.time())
        return None
