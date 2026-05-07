from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant

from .const import DOMAIN
from .coordinator import StargateCoordinator

PLATFORMS = ["binary_sensor", "sensor", "button", "number", "select", "switch"]


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    coordinator = StargateCoordinator(
        hass,
        host=entry.data["host"],
        port=entry.data["port"],
    )
    await coordinator.async_setup()
    await coordinator.async_config_entry_first_refresh()

    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = coordinator
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    unload_ok = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unload_ok:
        coordinator: StargateCoordinator = hass.data[DOMAIN].pop(entry.entry_id)
        if coordinator._session and not coordinator._session.closed:
            await coordinator._session.close()
    return unload_ok
