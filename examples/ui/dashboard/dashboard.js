export class Dashboard {
  constructor(elements) {
    this.elements = elements;
  }

  render(portState, selectedAction) {
    this.renderKpis(portState);
    this.renderCurrentDecision(portState, selectedAction);
    this.renderShips(portState);
    this.renderCranes(portState);
    this.renderReward(portState);
    this.renderLog(portState);
  }

  renderKpis(portState) {
    const kpis = [
      ["Time", portState.time],
      ["Total reward", portState.totalReward.toFixed(2)],
      ["Last reward", portState.lastReward.toFixed(2)],
      ["Status", portState.status],
      ["Avg ship wait", `${portState.metrics.avgShipWaitingTime.toFixed(1)} t`],
      ["Crane util.", `${Math.round(portState.metrics.craneUtilization * 100)}%`],
      ["Yard occupancy", `${Math.round(portState.metrics.yardOccupancy * 100)}%`],
      ["Rehandles", portState.metrics.rehandlingCount.toFixed(0)],
    ];
    this.elements.kpiStrip.innerHTML = kpis
      .map(([label, value]) => `<div class="kpi-card"><span>${label}</span><strong>${value}</strong></div>`)
      .join("");
  }

  renderCurrentDecision(portState, selectedAction) {
    const item = portState.currentContainer;
    const selected = portState.stacks.find((stack) => stack.action === selectedAction);
    const selectedText = selected
      ? `Block ${selected.block}, Bay ${selected.bay}, Stack ${selected.stack}`
      : "No stack selected";
    if (!item) {
      this.elements.currentDecision.className = "decision-card muted";
      this.elements.currentDecision.innerHTML = `
        <strong>No container waiting</strong>
        <dl>
          <dt>Selected Action</dt><dd>${selectedAction}</dd>
          <dt>Selected Stack</dt><dd>${selectedText}</dd>
          <dt>Suggested Action</dt><dd>${portState.suggestedAction}</dd>
        </dl>
      `;
      return;
    }

    this.elements.currentDecision.className = "decision-card";
    this.elements.currentDecision.innerHTML = `
      <div class="decision-head">
        <span class="container-dot ${item.type}"></span>
        <strong>#${item.id} ${item.type}</strong>
      </div>
      <dl>
        <dt>Deadline</dt><dd>${item.deadline}</dd>
        <dt>Priority</dt><dd>${item.priority}</dd>
        <dt>Weight</dt><dd>${item.weight}</dd>
        <dt>Selected Action</dt><dd>${selectedAction}</dd>
        <dt>Selected Stack</dt><dd>${selectedText}</dd>
        <dt>Suggested Action</dt><dd>${portState.suggestedAction}</dd>
      </dl>
    `;
  }

  renderShips(portState) {
    this.elements.shipList.innerHTML = "";
    portState.ships.forEach((ship) => {
      const card = document.createElement("div");
      card.className = "ship-card";
      card.innerHTML = `
        <div>
          <strong>Ship ${ship.id}</strong>
          <div class="muted">arrival ${ship.arrivalTime} | departure ${ship.departureTime}</div>
          <div class="progress-track"><i style="width:${ship.containerCount ? (ship.unloadedCount / ship.containerCount) * 100 : 0}%"></i></div>
        </div>
        <div class="ship-meta">
          <span>${ship.remaining} left</span>
          <span class="badge ${ship.status === "departed" || ship.remaining === 0 ? "done" : ship.status}">${ship.status}</span>
        </div>
      `;
      this.elements.shipList.appendChild(card);
    });
  }

  renderCranes(portState) {
    this.elements.craneList.innerHTML = "";
    portState.cranes.forEach((crane) => {
      const card = document.createElement("div");
      card.className = "crane-card";
      const task = crane.task ? `${crane.task.description} #${crane.task.containerId}` : "No active task";
      card.innerHTML = `
        <div>
          <strong>${crane.name}</strong>
          <div class="muted">${crane.kind === "quay" ? "quay crane" : "yard crane"} | ${task}</div>
        </div>
        <span class="badge ${crane.available ? "" : "busy"}">${crane.available ? "idle" : `${crane.remainingTime} left`}</span>
      `;
      this.elements.craneList.appendChild(card);
    });
  }

  renderReward(portState) {
    const entries = Object.entries(portState.rewardBreakdown || {});
    if (!entries.length) {
      this.elements.rewardBreakdown.innerHTML = '<div class="empty-state">No detailed breakdown</div>';
      return;
    }
    const labels = {
      valid_placement: "yard placement reward",
      invalid_placement: "invalid placement penalty",
      ship_complete: "ship completion reward",
      rehandling: "rehandling penalty",
      distance: "distance cost",
      crane_idle: "crane idle penalty",
      delay: "deadline delay penalty",
    };
    this.elements.rewardBreakdown.innerHTML = entries
      .map(([key, value]) => {
        const tone = value < 0 ? "negative" : value > 0 ? "positive" : "";
        return `
          <div class="breakdown-row ${tone}">
            <span>${labels[key] || key}</span>
            <strong>${Number(value).toFixed(2)}</strong>
          </div>
        `;
      })
      .join("");
  }

  renderLog(portState) {
    this.elements.eventLog.innerHTML = "";
    [...portState.eventLog].reverse().forEach((line) => {
      const row = document.createElement("div");
      row.textContent = line;
      this.elements.eventLog.appendChild(row);
    });
    this.elements.eventLog.scrollTop = this.elements.eventLog.scrollHeight;
  }
}
