# RL Port Scheduling Container

A modular container port simulation environment for reinforcement learning experiments.

The environment models:

- ship arrivals and departure deadlines
- import, export, and transshipment containers
- a 3D yard: blocks, bays, stacks, tiers
- abstract quay and yard cranes with task durations
- discrete time progression
- yard placement actions for RL agents
- rehandling and delay penalties

## Install

```bash
python3 -m pip install ".[dev]"
```

## Quick Start

```python
from port_sim import PortEnv, default_config

env = PortEnv(default_config())
obs, info = env.reset(seed=7)

done = False
while not done:
    action = env.action_space.sample()
    obs, reward, terminated, truncated, info = env.step(action)
    done = terminated or truncated
```

Run the example:

```bash
python3 examples/random_agent.py
```

Show a step-by-step placement trace:

```bash
python3 examples/heuristic_agent_trace.py
```

Run the browser UI:

```bash
python3 examples/ui_server.py
```

Then open:

```text
http://127.0.0.1:8000
```

The UI includes local Three.js vendor files under `examples/ui/vendor` so the
3D view does not depend on a CDN at runtime.

Run tests:

```bash
pytest
```

## Action Model

An action selects a stack location, encoded as an integer:

```text
action -> (block, bay, stack)
```

The environment places the current container on the lowest available tier in that stack.

## Reward Summary

- `+10` for a valid placement
- `+5` when a ship unloading cycle completes
- `-20` for invalid placement
- `-1` per rehandled blocking container
- `-0.1 * distance` yard distance cost from origin
- `-1` per idle crane when work is pending
- `-2` per container delayed beyond retrieval deadline
