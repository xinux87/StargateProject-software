from __future__ import annotations

from homeassistant.components.light import (
    ATTR_BRIGHTNESS,
    ATTR_RGB_COLOR,
    ColorMode,
    LightEntity,
)
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
    async_add_entities([StargateLampLight(coordinator, entry)])


class StargateLampLight(CoordinatorEntity, LightEntity):
    _attr_icon = "mdi:led-strip-variant"
    _attr_color_mode = ColorMode.RGB
    _attr_supported_color_modes = {ColorMode.RGB}

    def __init__(self, coordinator: StargateCoordinator, entry: ConfigEntry) -> None:
        super().__init__(coordinator)
        self._entry = entry
        self._attr_unique_id = f"{entry.entry_id}_lamp"
        self._attr_name = f"{entry.title} Lamp"

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
        return bool((self.coordinator.data or {}).get("lamp_mode", False))

    @property
    def brightness(self) -> int | None:
        return (self.coordinator.data or {}).get("lamp_brightness", 255)

    @property
    def rgb_color(self) -> tuple[int, int, int] | None:
        color = (self.coordinator.data or {}).get("lamp_color", [255, 255, 255])
        if isinstance(color, (list, tuple)) and len(color) == 3:
            return tuple(int(c) for c in color)
        return (255, 255, 255)

    async def async_turn_on(self, **kwargs) -> None:
        brightness = kwargs.get(ATTR_BRIGHTNESS)
        rgb_color = kwargs.get(ATTR_RGB_COLOR)
        payload: dict = {}
        if brightness is not None:
            payload["brightness"] = brightness
        if rgb_color is not None:
            payload["color"] = list(rgb_color)
        await self.coordinator.async_post("/do/lamp_on", payload)
        await self.coordinator.async_request_refresh()

    async def async_turn_off(self, **kwargs) -> None:
        await self.coordinator.async_post("/do/lamp_off")
        await self.coordinator.async_request_refresh()
