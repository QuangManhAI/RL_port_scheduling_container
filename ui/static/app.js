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
  animSpeed: document.querySelector("#animSpeed"),
  cameraButtons: [...document.querySelectorAll(".camera-btn")],
  trainBtn: document.querySelector("#trainBtn"),
  trainStatus: document.querySelector("#trainStatus"),
  progressContainer: document.querySelector("#progressContainer"),
  trainProgress: document.querySelector("#trainProgress"),
  chartContainer: document.querySelector("#chartContainer"),
  trainChart: document.querySelector("#trainChart"),
};

let trainingChart = null;

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
  try {
    state.raw = await requestJson("/api/step", {
      action: state.selectedAction,
      mode: els.modeSelect.value,
    });
    state.port = adaptPortState(state.raw);
    const executedAction = state.port.lastAction !== null ? state.port.lastAction : state.selectedAction;
    state.selectedAction = executedAction;
    render({
      previous,
      action: executedAction,
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
  const animDuration = els.animSpeed ? Number(els.animSpeed.value) : 2500;
  const delay = els.animationToggle.checked
    ? Math.max(Number(els.speedInput.value), animDuration + 50)
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

async function startTraining() {
  els.trainBtn.disabled = true;
  els.trainBtn.textContent = "Training...";
  els.trainStatus.textContent = "Initializing...";
  els.progressContainer.style.display = "block";
  els.chartContainer.style.display = "block";
  els.trainProgress.style.width = "0%";
  
  if (!trainingChart) {
    const ctx = els.trainChart.getContext("2d");
    trainingChart = new Chart(ctx, {
      type: "line",
      data: {
        labels: [],
        datasets: [{
          label: "Mean Reward",
          data: [],
          borderColor: "#3b82f6",
          backgroundColor: "rgba(59, 130, 246, 0.15)",
          borderWidth: 2,
          fill: true,
          tension: 0.3,
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
        },
        scales: {
          x: {
            grid: { color: "rgba(255, 255, 255, 0.05)" },
            ticks: { color: "#94a3b8", font: { family: "Outfit" } },
            title: { display: true, text: "Steps", color: "#94a3b8", font: { family: "Outfit", size: 10 } }
          },
          y: {
            grid: { color: "rgba(255, 255, 255, 0.05)" },
            ticks: { color: "#94a3b8", font: { family: "Outfit" } },
            title: { display: true, text: "Reward", color: "#94a3b8", font: { family: "Outfit", size: 10 } }
          }
        }
      }
    });
  } else {
    trainingChart.data.labels = [];
    trainingChart.data.datasets[0].data = [];
    trainingChart.update();
  }

  await requestJson("/api/train", {});
  pollTrainingStatus();
}

async function pollTrainingStatus() {
  const status = await requestJson("/api/train/status");
  
  if (status.running) {
    const pct = Math.round((status.current_step / status.total_steps) * 100);
    els.trainProgress.style.width = `${pct}%`;
    els.trainStatus.textContent = `Training: ${status.current_step}/${status.total_steps} steps (${pct}%)`;
    
    const labels = status.rewards_history.map(item => item[0]);
    const data = status.rewards_history.map(item => item[1]);
    
    trainingChart.data.labels = labels;
    trainingChart.data.datasets[0].data = data;
    trainingChart.update();
    
    setTimeout(pollTrainingStatus, 500);
  } else {
    els.trainProgress.style.width = "100%";
    els.trainStatus.textContent = "Complete!";
    els.trainBtn.disabled = false;
    els.trainBtn.textContent = "Train Model";
    
    const labels = status.rewards_history.map(item => item[0]);
    const data = status.rewards_history.map(item => item[1]);
    trainingChart.data.labels = labels;
    trainingChart.data.datasets[0].data = data;
    trainingChart.update();
    
    // Automatically switch mode select to RL Agent
    if (els.modeSelect) {
      els.modeSelect.value = "rl";
    }
    
    // Refresh environment to pick up new model
    refresh();
  }
}

function syncSceneOptions() {
  portScene.setOptions({
    labels: els.labelsToggle.checked,
    paths: els.pathsToggle.checked,
    heatmap: els.heatmapToggle.checked,
    animation: els.animationToggle.checked,
    animSpeed: els.animSpeed ? parseInt(els.animSpeed.value) : 1,
  });
}

els.resetBtn.addEventListener("click", reset);
els.stepBtn.addEventListener("click", stepOnce);
els.runBtn.addEventListener("click", () => {
  if (state.running) stopRun();
  else startRun();
});
els.trainBtn.addEventListener("click", startTraining);
els.speedInput.addEventListener("input", () => {
  if (!state.running) return;
  stopRun();
  startRun();
});
[els.labelsToggle, els.pathsToggle, els.heatmapToggle, els.animationToggle, els.animSpeed].forEach((input) => {
  if (input) input.addEventListener("change", syncSceneOptions);
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
