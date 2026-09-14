"""Show an agent's step-by-step yard placement decisions.

This example is intentionally verbose. It demonstrates the iterative loop an
RL agent would follow: inspect observation, choose an action, apply it, and
interpret reward feedback.
"""

from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from port_sim import PortEnv, default_config


def stack_height(yard: np.ndarray, block: int, bay: int, stack: int) -> int:
    """Count occupied tiers.  Feature index 0 (type) > 0 means occupied."""
    return int(np.sum(yard[block, bay, stack, :, 0] > 0))


def score_action(env: PortEnv, yard: np.ndarray, action: int) -> tuple[float, list[str]]:
    """Score a yard placement using normalised features from the observation."""
    container = env.current_container
    if container is None:
        return 0.0, ["no container waiting"]

    block, bay, stack = env.decode_action(action)
    height = stack_height(yard, block, bay, stack)
    if height >= env.config.tiers:
        return -1_000.0, ["invalid: stack is full"]

    distance = block + bay + stack
    score = 100.0
    reasons = [f"valid stack height={height}", f"distance={distance}"]

    # Compare deadlines using normalised features from the observation.
    blocking_risk = 0
    current_norm_deadline = container.deadline / env.max_deadline
    for tier in range(height):
        below_norm_deadline = float(yard[block, bay, stack, tier, 1])
        if below_norm_deadline > 0 and below_norm_deadline < current_norm_deadline:
            blocking_risk += 1

    urgency = max(0, env.config.max_time - container.deadline)
    score -= 8.0 * blocking_risk
    score -= 1.5 * height
    score -= 0.2 * distance

    if container.deadline <= env.time + 3:
        score -= 3.0 * height
        reasons.append("urgent: prefer shallow stacks")
    else:
        score += 0.5 * height
        reasons.append("not urgent: can use deeper stack")

    if blocking_risk:
        reasons.append(f"blocking risk={blocking_risk}")
    reasons.append(f"urgency_score={urgency}")
    return score, reasons


def choose_action(env: PortEnv, obs: dict[str, np.ndarray]) -> tuple[int, float, list[str]]:
    scored = []
    for action in range(env.action_space.n):
        score, reasons = score_action(env, obs["yard"], action)
        scored.append((score, action, reasons))
    score, action, reasons = max(scored, key=lambda item: item[0])
    return action, score, reasons


def compact_yard(yard: np.ndarray) -> str:
    rows = []
    blocks, bays, stacks, _ = yard.shape
    for block in range(blocks):
        rows.append(f"  block {block}")
        for bay in range(bays):
            stack_values = []
            for stack in range(stacks):
                ids = [int(item) for item in yard[block, bay, stack, :] if int(item) != 0]
                stack_values.append(str(ids or []))
            rows.append(f"    bay {bay}: {stack_values}")
    return "\n".join(rows)


def main() -> None:
    env = PortEnv(default_config())
    obs, info = env.reset(seed=3)
    total_reward = 0.0

    print("iterative heuristic agent trace")
    print("--------------------------------")

    for step in range(env.config.max_time):
        current = env.current_container
        if current is None:
            action = 0
            print(f"\nstep {step} time={env.time}: no container available, advancing time")
        else:
            action, score, reasons = choose_action(env, obs)
            block, bay, stack = env.decode_action(action)
            print(
                f"\nstep {step} time={env.time}: container={current.id} "
                f"type={current.type.name.lower()} deadline={current.deadline} priority={current.priority}"
            )
            print(f"  choose action={action} -> block={block}, bay={bay}, stack={stack}")
            print(f"  heuristic score={score:.2f}; " + "; ".join(reasons))

        obs, reward, terminated, truncated, info = env.step(action)
        total_reward += reward

        print(f"  reward={reward:.2f} total={total_reward:.2f}")
        if info["reward_breakdown"]:
            print(f"  reward_breakdown={info['reward_breakdown']}")
        print("  yard:")
        print(compact_yard(env.yard.grid))

        if terminated or truncated:
            status = "terminated" if terminated else "truncated"
            print(f"\n{status} at time={info['time']} total_reward={total_reward:.2f}")
            break


if __name__ == "__main__":
    main()
