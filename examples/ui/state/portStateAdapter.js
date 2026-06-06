const EMPTY_CONFIG = {
  blocks: 0,
  bays: 0,
  stacks: 0,
  tiers: 0,
  actionCount: 0,
  maxTime: 1,
};

export function adaptPortState(raw) {
  const config = { ...EMPTY_CONFIG, ...(raw?.config || {}) };
  const yard = raw?.yard || [];
  const containerIndex = raw?.containerIndex || {};
  const stacks = buildStacks(config, yard, containerIndex);
  const selectedFallback = Number.isInteger(raw?.lastAction) ? raw.lastAction : 0;
  const suggestedAction = suggestAction(config, stacks, raw?.currentContainer, raw?.time || 0);
  const rewardBreakdown = normalizeBreakdown(raw?.rewardBreakdown);
  const cumulativeRewardBreakdown = normalizeBreakdown(raw?.cumulativeRewardBreakdown);
  const metrics = buildMetrics(raw, config, stacks, rewardBreakdown, cumulativeRewardBreakdown);

  return {
    raw,
    time: Number(raw?.time || 0),
    done: Boolean(raw?.done),
    status: raw?.done ? "done" : "running",
    totalReward: Number(raw?.totalReward || 0),
    lastReward: Number(raw?.lastReward || 0),
    lastAction: Number.isInteger(raw?.lastAction) ? raw.lastAction : null,
    selectedFallback,
    config,
    yard,
    stacks,
    currentContainer: raw?.currentContainer || null,
    pendingContainers: raw?.pendingContainers || [],
    ships: (raw?.ships || []).map(normalizeShip),
    cranes: (raw?.cranes || []).map(normalizeCrane),
    rewardBreakdown,
    cumulativeRewardBreakdown,
    containerIndex,
    eventLog: raw?.eventLog || [],
    metrics,
    suggestedAction,
  };
}

export function actionFor(config, block, bay, stack) {
  return block * config.bays * config.stacks + bay * config.stacks + stack;
}

export function coordsForAction(config, action) {
  const safeAction = Math.max(0, Math.min(config.actionCount - 1, Number(action || 0)));
  const stack = safeAction % config.stacks;
  const bay = Math.floor(safeAction / config.stacks) % config.bays;
  const block = Math.floor(safeAction / (config.bays * config.stacks));
  return { block, bay, stack };
}

export function containerTypeColor(type) {
  return {
    import: "#16758c",
    export: "#2f9a70",
    transshipment: "#c57a16",
  }[type] || "#16758c";
}

function buildStacks(config, yard, containerIndex) {
  const stacks = [];
  for (let block = 0; block < config.blocks; block += 1) {
    for (let bay = 0; bay < config.bays; bay += 1) {
      for (let stack = 0; stack < config.stacks; stack += 1) {
        const tiers = [];
        for (let tier = 0; tier < config.tiers; tier += 1) {
          const id = Number(yard?.[block]?.[bay]?.[stack]?.[tier] || 0);
          tiers.push({
            id,
            tier,
            container: id ? containerIndex[String(id)] || null : null,
          });
        }
        const filled = tiers.filter((item) => item.id).length;
        stacks.push({
          action: actionFor(config, block, bay, stack),
          block,
          bay,
          stack,
          label: `B${block}-Y${bay}-S${stack}`,
          tiers,
          filled,
          capacity: config.tiers,
          occupancy: config.tiers ? filled / config.tiers : 0,
          full: filled >= config.tiers,
          types: [...new Set(tiers.filter((item) => item.container).map((item) => item.container.type))],
        });
      }
    }
  }
  return stacks;
}

function suggestAction(config, stacks, container, time) {
  if (!container || !stacks.length) return 0;
  let best = { score: -Infinity, action: 0 };
  stacks.forEach((stackInfo) => {
    if (stackInfo.full) return;
    const blockingRisk = stackInfo.tiers.filter(
      (tier) => tier.container && tier.container.deadline < container.deadline
    ).length;
    const distance = stackInfo.block + stackInfo.bay + stackInfo.stack;
    const urgent = container.deadline <= time + 3;
    const score =
      100 -
      blockingRisk * 10 -
      stackInfo.filled * (urgent ? 4.5 : 1.2) -
      distance * 0.25 -
      stackInfo.occupancy * 2;
    if (score > best.score) {
      best = { score, action: stackInfo.action };
    }
  });
  return best.action;
}

function buildMetrics(raw, config, stacks, rewardBreakdown, cumulativeRewardBreakdown) {
  const slots = config.blocks * config.bays * config.stacks * config.tiers;
  const occupied = stacks.reduce((sum, item) => sum + item.filled, 0);
  const ships = raw?.ships || [];
  const cranes = raw?.cranes || [];
  const busyCranes = cranes.filter((crane) => !crane.available).length;
  const arrivedShips = ships.filter((ship) => ship.arrived && !ship.departed);
  const waitSum = arrivedShips.reduce(
    (sum, ship) => sum + Math.max(0, Number(raw?.time || 0) - Number(ship.arrivalTime || 0)),
    0
  );
  const rehandling = Math.abs(Number(cumulativeRewardBreakdown.rehandling || rewardBreakdown.rehandling || 0));
  return {
    yardOccupancy: slots ? occupied / slots : 0,
    occupiedSlots: occupied,
    totalSlots: slots,
    craneUtilization: cranes.length ? busyCranes / cranes.length : 0,
    busyCranes,
    totalCranes: cranes.length,
    avgShipWaitingTime: arrivedShips.length ? waitSum / arrivedShips.length : 0,
    rehandlingCount: rehandling,
  };
}

function normalizeBreakdown(breakdown) {
  const normalized = {};
  Object.entries(breakdown || {}).forEach(([key, value]) => {
    normalized[key] = Number(value || 0);
  });
  return normalized;
}

function normalizeShip(ship) {
  const status = ship.departed
    ? "departed"
    : ship.arrived && ship.remaining > 0
      ? "berthing"
      : ship.arrived
        ? "arrived"
        : "waiting";
  return { ...ship, status };
}

function normalizeCrane(crane) {
  return {
    ...crane,
    name: `${crane.kind === "quay" ? "Quay" : "Yard"} crane ${crane.id}`,
    status: crane.available ? "idle" : "busy",
  };
}
