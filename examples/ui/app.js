import { requestJson } from "./state/api.js";
import { adaptPortState } from "./state/portStateAdapter.js";
import { Dashboard } from "./dashboard/dashboard.js";
import { YardPlanningGrid } from "./dashboard/yardPlanningGrid.js";
import { PortScene } from "./port/PortScene.js";

const state = {
  raw: null,
  port: null,
  selectedAction: 0,
  running: false,
  stepping: false,
  timer: null,
};

const els = {
  kpiStrip: document.querySelector("#kpiStrip"),
  yardView: document.querySelector("#yardView"),
  scene3d: document.querySelector("#scene3d"),
  sceneTooltip: document.querySelector("#sceneTooltip"),
  currentDecision: document.querySelector("#currentDecision"),
  shipList: document.querySelector("#shipList"),
  craneList: document.querySelector("#craneList"),
  rewardBreakdown: document.querySelector("#rewardBreakdown"),
  eventLog: document.querySelector("#eventLog"),
  resetBtn: document.querySelector("#resetBtn"),
  stepBtn: document.querySelector("#stepBtn"),
  runBtn: document.querySelector("#runBtn"),
  modeSelect: document.querySelector("#modeSelect"),
  speedInput: document.querySelector("#speedInput"),
  labelsToggle: document.querySelector("#labelsToggle"),
  pathsToggle: document.querySelector("#pathsToggle"),
  heatmapToggle: document.querySelector("#heatmapToggle"),
  animationToggle: document.querySelector("#animationToggle"),
  cameraButtons: [...document.querySelectorAll(".camera-btn")],
};

const dashboard = new Dashboard(els);
const planningGrid = new YardPlanningGrid(els.yardView, selectAction);
const portScene = new PortScene(els.scene3d, els.sceneTooltip, { onSelectAction: selectAction });

function selectAction(action) {
  state.selectedAction = action;
  render();
}

function render(transition = null) {
  if (!state.port) return;
  dashboard.render(state.port, state.selectedAction);
  planningGrid.render(state.port, state.selectedAction);
  portScene.render(state.port, state.selectedAction, transition);
}

async function refresh() {
  state.raw = await requestJson("/api/state");
  state.port = adaptPortState(state.raw);
  state.selectedAction = state.port.selectedFallback || state.port.suggestedAction || 0;
  render();
}

async function reset() {
  stopRun();
  state.raw = await requestJson("/api/reset", { seed: 1 });
  state.port = adaptPortState(state.raw);
  state.selectedAction = state.port.suggestedAction || 0;
  render();
}

async function stepOnce() {
  if (state.stepping) return;
  state.stepping = true;
  const previous = state.port;
  const selectedBeforeStep = state.selectedAction;
  try {
    state.raw = await requestJson("/api/step", {
      action: state.selectedAction,
      mode: els.modeSelect.value,
    });
    state.port = adaptPortState(state.raw);
    if (state.port.lastAction !== null) {
      state.selectedAction = state.port.lastAction;
    }
    render({
      previous,
      action: selectedBeforeStep,
      container: previous?.currentContainer || null,
    });
    if (state.port.done) stopRun();
  } finally {
    state.stepping = false;
  }
}

function startRun() {
  state.running = true;
  els.runBtn.textContent = "Pause";
  scheduleNextRunStep();
}

async function scheduleNextRunStep() {
  if (!state.running) return;
  await stepOnce();
  if (!state.running || state.port?.done) return;
  const delay = els.animationToggle.checked
    ? Math.max(Number(els.speedInput.value), 1550)
    : Number(els.speedInput.value);
  state.timer = window.setTimeout(scheduleNextRunStep, delay);
}

function stopRun() {
  state.running = false;
  els.runBtn.textContent = "Run";
  if (state.timer) {
    window.clearTimeout(state.timer);
    state.timer = null;
  }
}

function syncSceneOptions() {
  portScene.setOptions({
    labels: els.labelsToggle.checked,
    paths: els.pathsToggle.checked,
    heatmap: els.heatmapToggle.checked,
    animation: els.animationToggle.checked,
  });
}

els.resetBtn.addEventListener("click", reset);
els.stepBtn.addEventListener("click", stepOnce);
els.runBtn.addEventListener("click", () => {
  if (state.running) stopRun();
  else startRun();
});
els.speedInput.addEventListener("input", () => {
  if (!state.running) return;
  stopRun();
  startRun();
});
[els.labelsToggle, els.pathsToggle, els.heatmapToggle, els.animationToggle].forEach((input) => {
  input.addEventListener("change", syncSceneOptions);
});
els.cameraButtons.forEach((button) => {
  button.addEventListener("click", () => {
    els.cameraButtons.forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    portScene.setCamera(button.dataset.camera);
  });
});

syncSceneOptions();
refresh().catch((error) => {
  document.body.innerHTML = `<pre class="startup-error">${error.message}</pre>`;
});
