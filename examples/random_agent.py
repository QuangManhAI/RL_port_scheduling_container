"""Run PortEnv with random yard placement actions."""

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from port_sim import PortEnv, default_config


def main() -> None:
    env = PortEnv(default_config(), render_mode="ansi")
    obs, info = env.reset(seed=1)
    total_reward = 0.0

    for _ in range(env.config.max_time):
        action = env.action_space.sample()
        obs, reward, terminated, truncated, info = env.step(action)
        total_reward += reward
        if terminated or truncated:
            break

    print(f"finished at time={info['time']} total_reward={total_reward:.2f}")
    print(env.render())


if __name__ == "__main__":
    main()
