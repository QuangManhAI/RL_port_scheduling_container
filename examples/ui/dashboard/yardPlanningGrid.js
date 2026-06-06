import { containerTypeColor } from "../state/portStateAdapter.js";

export class YardPlanningGrid {
  constructor(root, onSelectAction) {
    this.root = root;
    this.onSelectAction = onSelectAction;
  }

  render(portState, selectedAction) {
    const { config } = portState;
    this.root.innerHTML = "";
    this.root.style.setProperty("--stack-count", config.stacks);
    this.root.style.setProperty("--tier-count", config.tiers);

    for (let block = 0; block < config.blocks; block += 1) {
      const blockStacks = portState.stacks.filter((stack) => stack.block === block);
      const occupied = blockStacks.reduce((sum, stack) => sum + stack.filled, 0);
      const capacity = blockStacks.reduce((sum, stack) => sum + stack.capacity, 0);
      const blockEl = document.createElement("section");
      blockEl.className = "yard-block-card";
      blockEl.innerHTML = `
        <div class="yard-block-header">
          <div>
            <strong>Block ${block}</strong>
            <span>${config.bays} bays | ${config.stacks} stacks</span>
          </div>
          <div class="occupancy-pill">${occupied}/${capacity}</div>
        </div>
      `;

      for (let bay = 0; bay < config.bays; bay += 1) {
        const bayEl = document.createElement("div");
        bayEl.className = "planning-bay";
        bayEl.innerHTML = `<div class="planning-bay-label">Bay ${bay}</div>`;

        blockStacks
          .filter((stack) => stack.bay === bay)
          .forEach((stackInfo) => {
            bayEl.appendChild(this.renderStack(stackInfo, selectedAction));
          });
        blockEl.appendChild(bayEl);
      }

      this.root.appendChild(blockEl);
    }
  }

  renderStack(stackInfo, selectedAction) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = [
      "planning-stack",
      selectedAction === stackInfo.action ? "selected" : "",
      stackInfo.full ? "full" : "",
    ]
      .filter(Boolean)
      .join(" ");
    button.title = tooltipText(stackInfo);
    button.disabled = stackInfo.full;
    button.addEventListener("click", () => this.onSelectAction(stackInfo.action));

    const tiers = document.createElement("div");
    tiers.className = "planning-tiers";
    [...stackInfo.tiers].reverse().forEach((tier) => {
      const cell = document.createElement("span");
      cell.className = `planning-tier ${tier.id ? "filled" : ""}`;
      if (tier.id) {
        cell.style.background = containerTypeColor(tier.container?.type);
        cell.textContent = tier.id;
      }
      tiers.appendChild(cell);
    });

    const footer = document.createElement("div");
    footer.className = "planning-stack-footer";
    footer.innerHTML = `
      <strong>S${stackInfo.stack}</strong>
      <span>${Math.round(stackInfo.occupancy * 100)}%</span>
    `;

    button.appendChild(tiers);
    button.appendChild(footer);
    return button;
  }
}

function tooltipText(stackInfo) {
  const types = stackInfo.types.length ? stackInfo.types.join(", ") : "empty";
  return `Block ${stackInfo.block}, Bay ${stackInfo.bay}, Stack ${stackInfo.stack}
Occupancy ${stackInfo.filled}/${stackInfo.capacity}
Types: ${types}`;
}
