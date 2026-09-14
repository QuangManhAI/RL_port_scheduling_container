"""Container port simulation package."""

from port_sim.config import PortConfig, default_config, medium_config
from port_sim.models import Container, ContainerType, Ship

__all__ = [
    "Container",
    "ContainerType",
    "PortConfig",
    "PortEnv",
    "Ship",
    "default_config",
    "medium_config",
]


def __getattr__(name: str):
    if name == "PortEnv":
        from port_sim.env import PortEnv

        return PortEnv
    raise AttributeError(name)
