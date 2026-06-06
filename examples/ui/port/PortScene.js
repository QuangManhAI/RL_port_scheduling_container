import * as THREE from "../vendor/three.module.js";
import { OrbitControls } from "../vendor/OrbitControls.js";
import { coordsForAction } from "../state/portStateAdapter.js";

const COLORS = {
  water: 0x05131a,
  waterDeep: 0x0a1e29,
  quay: 0x1e262b,
  apron: 0x141a1e,
  lane: 0x0d1114,
  line: 0x3a4b52,
  import: 0x00f0ff,
  export: 0xff003c,
  transshipment: 0xffe600,
  selected: 0xb533ff,
  invalid: 0xef4444,
  empty: 0x2a363f,
  hull: 0x0f171e,
  hullAlt: 0x141d26,
  deck: 0x222d36,
  crane: 0x3b82f6,
  craneDark: 0x1e293b,
  yardCrane: 0x334155,
  agv: 0xf59e0b, // Bright warning orange so trucks are visible
};

const LAYOUT = {
  yardBaseX: 1.8,
  yardBaseZ: 2.2,
  blockGap: 5.3,
  bayGap: 2.0,
  stackGap: 1.34,
  tierHeight: 0.62,
  containerSize: [1.08, 0.56, 0.9],
};

const CAMERA_PRESETS = {
  overview: { pos: [18, 15, 18], target: [3.8, 1.2, 1.2] },
  follow: { pos: [4.5, 7.6, 8.2], target: [1.8, 1.2, -1.2] },
  crane: { pos: [-10.5, 8.4, 4.8], target: [-8.6, 2.8, -2.3] },
  yard: { pos: [8.7, 10.5, 5.1], target: [5.2, 1.0, 0.8] },
  ship: { pos: [3.0, 4.5, -8.0], target: [3.0, 1.5, 0.0] },
};

export class PortScene {
  constructor(root, tooltip, { onSelectAction }) {
    this.root = root;
    this.tooltip = tooltip;
    this.onSelectAction = onSelectAction;
    this.portState = null;
    this.selectedAction = 0;
    this.options = {
      labels: true,
      paths: true,
      heatmap: true,
      animation: true,
    };
    this.cameraMode = "overview";
    this.stackTargets = [];
    this.stackOutlines = [];
    this.dynamicGroup = new THREE.Group();
    this.staticGroup = new THREE.Group();
    this.animatedGroup = new THREE.Group();
    this.raycaster = new THREE.Raycaster();
    this.pointer = new THREE.Vector2();
    this.clock = new THREE.Clock();
    this.transition = null;
    this.init();
  }

  init() {
    this.scene = new THREE.Scene();
    this.scene.background = null; // Let CSS background show
    this.scene.fog = new THREE.FogExp2(0x090c10, 0.015);

    this.camera = new THREE.PerspectiveCamera(42, 1, 0.1, 220);
    this.camera.position.set(...CAMERA_PRESETS.overview.pos);

    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.root.appendChild(this.renderer.domElement);

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.target.set(...CAMERA_PRESETS.overview.target);
    this.controls.maxPolarAngle = Math.PI * 0.49;
    this.controls.minDistance = 9;
    this.controls.maxDistance = 58;

    this.scene.add(this.staticGroup, this.dynamicGroup, this.animatedGroup);
    this.addLighting();
    this.addStaticPort();
    this.renderer.domElement.addEventListener("pointerdown", (event) => this.handlePointerDown(event));
    this.renderer.domElement.addEventListener("pointermove", (event) => this.handlePointerMove(event));
    this.renderer.domElement.addEventListener("pointerleave", () => this.hideTooltip());
    window.addEventListener("resize", () => this.resize());
    this.resize();
    this.animate();
  }

  setOptions(options) {
    this.options = { ...this.options, ...options };
    if (this.portState) this.render(this.portState, this.selectedAction);
  }

  setCamera(mode) {
    this.cameraMode = mode;
    const preset = CAMERA_PRESETS[mode] || CAMERA_PRESETS.overview;
    this.camera.position.set(...preset.pos);
    this.controls.target.set(...preset.target);
    this.controls.update();
  }

  render(portState, selectedAction, transition = null) {
    this.portState = portState;
    this.selectedAction = selectedAction;
    if (transition && this.options.animation && transition.previous?.currentContainer) {
      this.startTransition(transition.previous, portState, selectedAction, transition.container);
      return;
    }
    this.renderCommitted(portState, selectedAction);
  }

  renderCommitted(portState, selectedAction) {
    this.dynamicGroup.clear();
    this.animatedGroup.clear();
    this.transition = null;
    this.stackTargets = [];
    this.stackOutlines = [];
    this.addShips(portState);
    this.addCranes(portState, selectedAction);
    this.addYard(portState, selectedAction);
    this.addAgvFleet(portState);
    if (this.options.paths) this.addPathLines(portState, selectedAction);
  }

  startTransition(previousState, nextState, action, container) {
    this.renderCommitted(previousState, action);
    const targetCoords = coordsForAction(previousState.config, action);
    const path = this.buildContainerPath(previousState, action, container);
    const color = this.containerColor(container?.type);
    
    const movingContainer = this.box([1.08, 0.56, 0.9], path[0], this.material(color));
    const spreader = this.box([1.1, 0.1, 0.8], [path[0][0], path[0][1] + 0.35, path[0][2]], this.material(0xd5dde1, 0.3, 0.5));
    
    // Dynamic cables from spreader to an invisible trolley height
    const cableGroup = new THREE.Group();
    for (let i = 0; i < 4; i++) {
      cableGroup.add(this.box([0.02, 1, 0.02], [0, 0, 0], this.material(COLORS.craneDark)));
    }
    
    // Dynamic trolley that moves with the container
    const trolley = this.box([1.1, 0.45, 0.9], [0, 0, 0], this.material(COLORS.craneDark));

    const agv = this.buildAgv(path[0][0], path[0][2], color);
    agv.visible = false; // Hidden until it reaches the lane

    this.animatedGroup.add(movingContainer, spreader, cableGroup, trolley, agv);
    
    this.transition = {
      start: performance.now(),
      duration: this.options.animSpeed || 2500,
      path,
      action,
      nextState,
      targetBlock: targetCoords.block,
      movingContainer,
      spreader,
      cableGroup,
      trolley,
      agv,
    };

    // Hide static trolleys of active cranes to avoid overlapping with dynamic trolley
    this.dynamicGroup.children.forEach((child) => {
      if (child.userData.staticTrolley) {
        if (child.userData.isYardCrane && child.userData.block === targetCoords.block) {
          child.userData.staticTrolley.visible = false;
        }
        if (!child.userData.isYardCrane && path[0][0] < -1.0) {
          // Quay crane
          child.userData.staticTrolley.visible = false;
        }
      }
    });
  }

  buildContainerPath(portState, action, container) {
    const target = this.stackPosition(portState, action);
    const currentTier = portState.stacks.find((stack) => stack.action === action)?.filled || 0;
    const targetY = 0.72 + currentTier * LAYOUT.tierHeight;
    
    const source = [-9.4, 2.2, -7.5];
    const laneZ = -0.2;
    const laneY = 1.02; // Height on the truck
    const quayHoistY = 3.9; // Safe height below Quay crane trolley
    const yardHoistY = 3.2; // Safe height below Yard crane trolley

    // Orthogonal movement: Up, Across, Down.
    if (container?.type === "export") {
      return [
        [target.x, targetY, target.z],      // 0: in stack
        [target.x, yardHoistY, target.z],   // 1: hoist up
        [target.x, yardHoistY, laneZ],      // 2: yard trolley to lane
        [target.x, laneY, laneZ],           // 3: lower to AGV
        [source[0], laneY, laneZ],          // 4: AGV drive to quay
        [source[0], quayHoistY, laneZ],     // 5: hoist up from AGV
        [source[0], quayHoistY, source[2]], // 6: quay trolley to ship
        [source[0], source[1], source[2]]   // 7: lower to ship
      ];
    }
    
    // Import or Transshipment
    return [
      [source[0], source[1], source[2]],    // 0: on ship
      [source[0], quayHoistY, source[2]],   // 1: hoist up
      [source[0], quayHoistY, laneZ],       // 2: quay trolley to lane
      [source[0], laneY, laneZ],            // 3: lower to AGV
      [target.x, laneY, laneZ],             // 4: AGV drive to yard
      [target.x, yardHoistY, laneZ],        // 5: hoist up from AGV
      [target.x, yardHoistY, target.z],     // 6: yard trolley to stack
      [target.x, targetY, target.z]         // 7: lower into stack
    ];
  }

  animate() {
    requestAnimationFrame(() => this.animate());
    const elapsed = this.clock.getElapsedTime();
    this.updateWater(elapsed);
    this.updateAmbientMotion(elapsed);
    this.updateTransition();
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  updateTransition() {
    if (!this.transition) return;
    // We use a linear progress through the segments for orthogonal movements so it stops cleanly at corners.
    const progress = Math.min(1, (performance.now() - this.transition.start) / this.transition.duration);
    
    const point = samplePath(this.transition.path, progress);
    this.transition.movingContainer.position.set(point[0], point[1], point[2]);
    
    // Spreader sits slightly above container
    const spreaderY = point[1] + 0.35;
    this.transition.spreader.position.set(point[0], spreaderY, point[2]);
    
    // Determine which crane is hoisting based on X position to set top height
    const isQuayPhase = point[0] < -1.0; 
    const hoistTopY = isQuayPhase ? 4.54 : 3.32; // Exact absolute Y coordinates of the crane beams
    
    // Position dynamic trolley
    this.transition.trolley.position.set(point[0], hoistTopY, point[2]);
    
    // Move the Yard Crane's entire gantry along the Z axis to follow the transition
    if (!isQuayPhase) {
      this.dynamicGroup.children.forEach((child) => {
        if (child.userData.isYardCrane && child.userData.block === this.transition.targetBlock) {
          child.position.z = point[2];
        }
      });
    }

    // Dynamic Cables
    const cableLength = Math.max(0.01, hoistTopY - spreaderY);
    const cableCenterY = spreaderY + cableLength / 2;
    
    const offsets = [[-0.3, -0.3], [0.3, -0.3], [-0.3, 0.3], [0.3, 0.3]];
    this.transition.cableGroup.children.forEach((cable, idx) => {
      cable.scale.y = cableLength;
      cable.position.set(point[0] + offsets[idx][0], cableCenterY, point[2] + offsets[idx][1]);
    });

    // AGV logic: AGV moves only during the middle phase (lane travel)
    const onLane = Math.abs(point[2] - (-0.2)) < 0.1 && point[1] < 1.1;
    if (onLane) {
      this.transition.agv.visible = true;
      this.transition.agv.position.set(point[0], 0.46, point[2]);
      this.transition.movingContainer.position.y = 1.02; // Rest firmly on truck
      this.transition.spreader.visible = false;
      this.transition.cableGroup.visible = false;
      this.transition.trolley.visible = false;
    } else {
      this.transition.agv.visible = false;
      this.transition.spreader.visible = true;
      this.transition.cableGroup.visible = true;
      this.transition.trolley.visible = true;
    }

    if (this.cameraMode === "follow") {
      this.controls.target.set(point[0], point[1], point[2]);
    }

    if (progress >= 1) {
      const nextState = this.transition.nextState;
      const action = this.transition.action;
      this.renderCommitted(nextState, action);
    }
  }

  addLighting() {
    this.scene.add(new THREE.HemisphereLight(0xffffff, 0x090c10, 1.2));
    const sun = new THREE.DirectionalLight(0xe0e7ff, 2.5);
    sun.position.set(16, 28, 12);
    sun.castShadow = true;
    sun.shadow.mapSize.set(4096, 4096);
    sun.shadow.camera.left = -50;
    sun.shadow.camera.right = 50;
    sun.shadow.camera.top = 50;
    sun.shadow.camera.bottom = -50;
    sun.shadow.bias = -0.0005;
    this.scene.add(sun);
    
    // Add blueish ambient/point lights for a cyberpunk feel
    const point1 = new THREE.PointLight(0x00f0ff, 15, 40);
    point1.position.set(-15, 5, -5);
    this.scene.add(point1);
    
    const point2 = new THREE.PointLight(0xff003c, 15, 40);
    point2.position.set(15, 5, 5);
    this.scene.add(point2);
  }

  addStaticPort() {
    const water = this.box([92, 0.08, 58], [-19, -0.08, 0], this.material(COLORS.water, 0.1, 0.9));
    water.receiveShadow = true;
    this.staticGroup.add(water);
    this.waterLines = [];
    for (let i = 0; i < 20; i += 1) {
      const line = this.box([13 + (i % 3) * 2, 0.015, 0.035], [-30 + i * 3.2, 0.02, -13 + (i % 7) * 2.4], this.material(0x00f0ff, 0.2, 0.8));
      line.material.transparent = true;
      line.material.opacity = 0.4;
      line.material.emissive = new THREE.Color(0x00f0ff);
      line.material.emissiveIntensity = 0.8;
      this.waterLines.push(line);
      this.staticGroup.add(line);
    }

    this.staticGroup.add(this.box([54, 0.32, 18.5], [8, 0.1, 3.7], this.material(COLORS.quay, 0.92)));
    this.staticGroup.add(this.box([16, 0.38, 18.5], [-15.4, 0.14, 3.7], this.material(COLORS.apron, 0.86)));
    this.staticGroup.add(this.box([36, 0.08, 2.1], [4.5, 0.36, -0.2], this.material(COLORS.lane, 0.82)));
    this.staticGroup.add(this.box([36, 0.09, 0.08], [4.5, 0.43, -1.18], this.material(COLORS.line, 0.6)));
    this.staticGroup.add(this.box([36, 0.09, 0.08], [4.5, 0.43, 0.78], this.material(COLORS.line, 0.6)));

    for (let z = -4.7; z <= 11; z += 3.4) {
      const bollard = new THREE.Mesh(
        new THREE.CylinderGeometry(0.13, 0.17, 0.42, 16),
        this.material(0x344149, 0.6)
      );
      bollard.position.set(-6.8, 0.43, z);
      bollard.castShadow = true;
      this.staticGroup.add(bollard);
    }
  }

  addShips(portState) {
    const berthed = portState.ships.find((ship) => ship.arrived && !ship.departed) || portState.ships[0];
    this.dynamicGroup.add(this.buildShip({
      id: berthed?.id || 1,
      position: [-9.4, -0.1, -7.5],
      scale: 1,
      color: COLORS.hull,
      remaining: berthed?.remaining || 0,
      label: `Ship ${berthed?.id || 1}`,
    }));

    const waiting = portState.ships.find((ship) => !ship.arrived);
    if (waiting) {
      this.dynamicGroup.add(this.buildShip({
        id: waiting.id,
        position: [-9.4, -0.12, -13.0],
        scale: 0.65,
        color: COLORS.hullAlt,
        remaining: waiting.remaining,
        label: `Ship ${waiting.id} (waiting)`,
      }));
    }
  }

  buildShip({ position, scale, color, remaining, label }) {
    const group = new THREE.Group();
    group.position.set(...position);
    group.scale.setScalar(scale);
    group.userData.floatBaseY = position[1];

    const hullMat = this.material(color, 0.62, 0.14);

    // Simple hull - just a long box
    const hullLength = 14;
    const hullHeight = 1.3;
    const hullWidth = 3.0;
    group.add(this.box([hullLength, hullHeight, hullWidth], [0, hullHeight / 2, 0], hullMat));

    // Deck
    group.add(this.box([hullLength + 0.4, 0.08, hullWidth + 0.2], [0, hullHeight + 0.04, 0], this.material(COLORS.deck, 0.76)));

    // Bridge at stern
    group.add(this.box([1.8, 1.8, 2.2], [-5.5, hullHeight + 0.96, 0], this.material(0xe8ebe5, 0.58)));
    group.add(this.box([1.4, 0.35, 2.4], [-5.5, hullHeight + 2.08, 0], this.material(0x2a3640, 0.5)));
    // Funnel
    group.add(this.box([0.45, 0.9, 0.5], [-6.0, hullHeight + 1.7, 0], this.material(0xcc3333, 0.6)));

    // Containers on deck
    for (let i = 0; i < remaining; i += 1) {
      const colorCycle = [COLORS.import, COLORS.export, COLORS.transshipment][i % 3];
      const col = i % 2;
      const row = Math.floor(i / 2) % 6;
      const tier = Math.floor(i / 12);
      const cx = -3.0 + row * 1.15;
      const cy = hullHeight + 0.36 + tier * 0.58;
      const cz = -0.5 + col * 1.0;
      group.add(this.box([1.0, 0.5, 0.8], [cx, cy, cz], this.material(colorCycle, 0.7, 0.06)));
    }

    if (this.options.labels) group.add(this.labelSprite(label, [6, 2.0, -2.0]));
    return group;
  }

  addCranes(portState, selectedAction) {
    portState.cranes.filter((crane) => crane.kind === "quay").forEach((crane, index) => {
      const craneGroup = this.buildQuayCrane(-9.6 + index * 3.6, -2.3, crane);
      this.dynamicGroup.add(craneGroup);
    });

    // Find where the action is happening
    const targetCoords = coordsForAction(portState.config, selectedAction);

    portState.cranes.filter((crane) => crane.kind === "yard").forEach((crane, index) => {
      const block = index % portState.config.blocks;
      const x = LAYOUT.yardBaseX + block * LAYOUT.blockGap + ((portState.config.stacks - 1) * LAYOUT.stackGap) / 2;
      
      // Move the crane exactly to the bay where the action occurs
      const bay = (block === targetCoords.block) ? targetCoords.bay : 0;
      const z = LAYOUT.yardBaseZ + bay * LAYOUT.bayGap;

      const isTargetBlock = (block === targetCoords.block);
      const trolleyWorldX = isTargetBlock ? LAYOUT.yardBaseX + targetCoords.block * LAYOUT.blockGap + targetCoords.stack * LAYOUT.stackGap : x;
      const trolleyLocalX = trolleyWorldX - x;

      const craneGroup = this.buildYardCrane(x, z, crane, trolleyLocalX);
      craneGroup.userData.isYardCrane = true;
      craneGroup.userData.block = block;
      this.dynamicGroup.add(craneGroup);
    });
  }

  buildQuayCrane(x, z, crane) {
    const group = new THREE.Group();
    group.position.set(x, 0.26, z);
    const yellow = this.material(COLORS.crane, 0.56, 0.18);
    const dark = this.material(COLORS.craneDark, 0.62);
    
    // Legs and wheels
    [[-0.78, -0.85], [0.78, -0.85], [-0.78, 0.85], [0.78, 0.85]].forEach(([lx, lz]) => {
      group.add(this.box([0.3, 4.8, 0.3], [lx, 2.4, lz], yellow));
      group.add(this.box([0.5, 0.25, 0.6], [lx, 0.1, lz], dark));
      // Wheels
      const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.12, 0.15, 12), dark);
      wheel.rotation.z = Math.PI / 2;
      wheel.position.set(lx, 0, lz - 0.15);
      const wheel2 = wheel.clone();
      wheel2.position.set(lx, 0, lz + 0.15);
      group.add(wheel, wheel2);
    });

    // Structure
    group.add(this.box([2.5, 0.35, 2.4], [0, 4.72, 0], yellow));
    group.add(this.box([0.35, 0.3, 8.8], [0, 4.65, -3.4], yellow)); // Boom
    group.add(this.box([0.35, 0.3, 3.5], [0, 4.65, 2.65], yellow)); // Back reach
    group.add(this.box([2.2, 0.12, 0.16], [0, 0.18, -1.2], dark));
    group.add(this.box([2.2, 0.12, 0.16], [0, 0.18, 1.2], dark));
    
    const trolleyZ = crane.available ? -0.45 : -3.45;
    group.add(this.box([1.1, 0.45, 0.9], [0, 4.28, trolleyZ], dark)); // Trolley
    
    // Cables and Spreader (The Hook)
    const wireLength = 2.2;
    const wireY = 3.1;
    [[-0.3, -0.3], [0.3, -0.3], [-0.3, 0.3], [0.3, 0.3]].forEach(([wx, wz]) => {
      group.add(this.box([0.02, wireLength, 0.02], [wx, wireY, trolleyZ + wz], dark));
    });

    const spreaderY = wireY - wireLength / 2 - 0.05;
    
    const trolleyGroup = new THREE.Group();
    trolleyGroup.add(this.box([1.1, 0.45, 0.9], [0, 4.28, trolleyZ], dark)); // Static Trolley
    [[-0.3, -0.3], [0.3, -0.3], [-0.3, 0.3], [0.3, 0.3]].forEach(([wx, wz]) => {
      trolleyGroup.add(this.box([0.02, wireLength, 0.02], [wx, wireY, trolleyZ + wz], dark));
    });
    trolleyGroup.add(this.box([1.1, 0.1, 0.8], [0, spreaderY, trolleyZ], this.material(0xd5dde1, 0.3, 0.5)));

    if (!crane.available) {
      trolleyGroup.add(this.box(LAYOUT.containerSize, [0, spreaderY - 0.3, trolleyZ], this.material(COLORS.import)));
    }
    
    group.add(trolleyGroup);
    group.userData.staticTrolley = trolleyGroup;
    
    if (this.options.labels) group.add(this.labelSprite(crane.name, [0, 5.8, 0]));
    return group;
  }

  buildYardCrane(x, z, crane, trolleyX = 0) {
    const group = new THREE.Group();
    group.position.set(x, 0.3, z);
    const steel = this.material(COLORS.yardCrane, 0.44, 0.24);
    const dark = this.material(COLORS.craneDark, 0.62);
    
    // Main top beams
    group.add(this.box([5.6, 0.28, 0.35], [0, 3.3, 0], steel));
    group.add(this.box([5.1, 0.15, 1.2], [0, 3.15, 0], steel)); // cross support
    
    // Legs and Wheels
    [[-2.35, -0.85], [2.35, -0.85], [-2.35, 0.85], [2.35, 0.85]].forEach(([lx, lz]) => {
      group.add(this.box([0.3, 3.35, 0.3], [lx, 1.68, lz], steel)); // Leg
      group.add(this.box([0.5, 0.25, 0.7], [lx, 0.1, lz], dark)); // Wheel base
      const wheel1 = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.15, 0.2, 12), dark);
      wheel1.rotation.z = Math.PI / 2;
      wheel1.position.set(lx, 0, lz - 0.2);
      const wheel2 = wheel1.clone();
      wheel2.position.set(lx, 0, lz + 0.2);
      group.add(wheel1, wheel2);
    });
    
    // Cables (4 thin cables)
    const wireLength = 1.4;
    const wireY = 2.3;
    const spreaderY = wireY - wireLength / 2 - 0.05;

    const trolleyGroup = new THREE.Group();
    trolleyGroup.add(this.box([0.9, 0.36, 0.9], [trolleyX, 3.02, 0], dark)); // Static Trolley
    [[-0.3, -0.3], [0.3, -0.3], [-0.3, 0.3], [0.3, 0.3]].forEach(([wx, wz]) => {
      trolleyGroup.add(this.box([0.02, wireLength, 0.02], [trolleyX + wx, wireY, wz], dark));
    });
    trolleyGroup.add(this.box([1.1, 0.1, 0.8], [trolleyX, spreaderY, 0], this.material(0xd5dde1, 0.3, 0.5)));

    if (!crane.available) {
      trolleyGroup.add(this.box(LAYOUT.containerSize, [trolleyX, spreaderY - 0.3, 0], this.material(COLORS.export)));
    }
    
    group.add(trolleyGroup);
    group.userData.staticTrolley = trolleyGroup;
    
    if (this.options.labels) group.add(this.labelSprite(crane.name, [0, 4.3, 0]));
    return group;
  }

  addYard(portState, selectedAction) {
    const blockLabels = new Set();
    portState.stacks.forEach((stackInfo) => {
      const { x, z } = this.stackPosition(portState, stackInfo.action);
      const selected = stackInfo.action === selectedAction;
      const padColor = stackInfo.full ? COLORS.invalid : selected ? COLORS.selected : COLORS.empty;
      const opacity = this.options.heatmap ? 0.28 + stackInfo.occupancy * 0.58 : selected ? 0.8 : 0.24;
      const pad = this.box(
        [1.18, 0.06, 1.02],
        [x, 0.38, z],
        this.transparentMaterial(padColor, selected ? 0.92 : opacity)
      );
      pad.userData.stackInfo = stackInfo;
      pad.receiveShadow = true;
      this.dynamicGroup.add(pad);
      this.stackTargets.push(pad);

      if (selected) {
        const outline = this.box([1.34, 0.08, 1.18], [x, 0.44, z], this.transparentMaterial(COLORS.selected, 0.45));
        this.dynamicGroup.add(outline);
        this.stackOutlines.push(outline);
      }

      stackInfo.tiers.forEach((tier) => {
        if (!tier.id) return;
        const color = this.containerColor(tier.container?.type);
        const container = this.box(
          LAYOUT.containerSize,
          [x, 0.72 + tier.tier * LAYOUT.tierHeight, z],
          this.material(color)
        );
        this.dynamicGroup.add(container);
        this.dynamicGroup.add(this.edges(container, 0xffffff, 0.28));
      });

      if (this.options.labels && !blockLabels.has(stackInfo.block)) {
        blockLabels.add(stackInfo.block);
        this.dynamicGroup.add(this.labelSprite(`Block ${stackInfo.block}`, [x, 1.8, z + 3.2]));
      }
    });
  }

  addAgvFleet(portState) {
    // Disabled decorative AGVs because they caused confusing visual overlaps
  }

  buildAgv(x, z, loadColor = COLORS.import) {
    const group = new THREE.Group();
    group.position.set(x, 0.46, z);
    group.add(this.box([1.0, 0.28, 0.58], [0, 0, 0], this.material(COLORS.agv, 0.62, 0.08)));
    group.add(this.box([0.78, 0.34, 0.44], [0, 0.34, 0], this.material(loadColor, 0.66, 0.04)));
    [-0.38, 0.38].forEach((wheelX) => {
      [-0.32, 0.32].forEach((wheelZ) => {
        const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.09, 0.08, 12), this.material(0x182327, 0.6));
        wheel.rotation.z = Math.PI / 2;
        wheel.position.set(wheelX, -0.16, wheelZ);
        wheel.castShadow = true;
        group.add(wheel);
      });
    });
    return group;
  }

  addPathLines(portState, selectedAction) {
    const path = this.buildContainerPath(portState, selectedAction, portState.currentContainer || { type: "import" });
    const points = path.map((point) => new THREE.Vector3(point[0], Math.max(0.5, point[1]), point[2]));
    const geometry = new THREE.BufferGeometry().setFromPoints(points);
    const line = new THREE.Line(
      geometry,
      new THREE.LineBasicMaterial({ color: COLORS.selected, transparent: true, opacity: 0.62 })
    );
    this.dynamicGroup.add(line);
  }

  handlePointerDown(event) {
    const hit = this.pickStack(event);
    if (!hit) return;
    this.onSelectAction(hit.object.userData.stackInfo.action);
  }

  handlePointerMove(event) {
    const hit = this.pickStack(event);
    if (!hit) {
      this.hideTooltip();
      return;
    }
    const info = hit.object.userData.stackInfo;
    const types = info.types.length ? info.types.join(", ") : "empty";
    this.tooltip.hidden = false;
    this.tooltip.style.left = `${event.offsetX + 14}px`;
    this.tooltip.style.top = `${event.offsetY + 14}px`;
    this.tooltip.innerHTML = `
      <strong>Block ${info.block} | Bay ${info.bay} | Stack ${info.stack}</strong>
      <span>Occupancy ${info.filled}/${info.capacity}</span>
      <span>Types: ${types}</span>
      <span>Action ${info.action}${info.full ? " | full" : ""}</span>
    `;
  }

  hideTooltip() {
    this.tooltip.hidden = true;
  }

  pickStack(event) {
    if (!this.portState || !this.stackTargets.length) return null;
    const rect = this.renderer.domElement.getBoundingClientRect();
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const hits = this.raycaster.intersectObjects(this.stackTargets, false);
    return hits[0] || null;
  }

  stackPosition(portState, action) {
    const { block, bay, stack } = coordsForAction(portState.config, action);
    return {
      x: LAYOUT.yardBaseX + block * LAYOUT.blockGap + stack * LAYOUT.stackGap,
      z: LAYOUT.yardBaseZ + bay * LAYOUT.bayGap,
    };
  }

  resize() {
    const rect = this.root.getBoundingClientRect();
    this.camera.aspect = rect.width / rect.height;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(rect.width, rect.height, false);
  }

  updateWater(elapsed) {
    this.waterLines?.forEach((line, index) => {
      line.position.x += Math.sin(elapsed + index) * 0.0008;
      line.material.opacity = 0.18 + Math.sin(elapsed * 1.2 + index) * 0.08;
    });
  }

  updateAmbientMotion(elapsed) {
    this.dynamicGroup.children.forEach((child) => {
      if (child.userData.floatBaseY !== undefined) {
        child.position.y = child.userData.floatBaseY + Math.sin(elapsed * 1.4 + child.position.x) * 0.045;
      }
    });
    this.stackOutlines.forEach((mesh, index) => {
      mesh.material.opacity = 0.35 + Math.sin(elapsed * 3.5 + index) * 0.12;
    });
  }

  box(size, position, material) {
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(...size), material);
    mesh.position.set(...position);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    return mesh;
  }

  material(color, roughness = 0.2, metalness = 0.6) {
    return new THREE.MeshStandardMaterial({ color, roughness, metalness });
  }

  transparentMaterial(color, opacity) {
    return new THREE.MeshStandardMaterial({
      color,
      transparent: true,
      opacity,
      roughness: 0.86,
      depthWrite: false,
    });
  }

  containerColor(type) {
    return {
      import: COLORS.import,
      export: COLORS.export,
      transshipment: COLORS.transshipment,
    }[type] || COLORS.import;
  }

  edges(mesh, color, opacity) {
    const edge = new THREE.LineSegments(
      new THREE.EdgesGeometry(mesh.geometry),
      new THREE.LineBasicMaterial({ color, transparent: true, opacity })
    );
    edge.position.copy(mesh.position);
    return edge;
  }

  labelSprite(text, position) {
    const canvas = document.createElement("canvas");
    canvas.width = 256;
    canvas.height = 72;
    const context = canvas.getContext("2d");
    context.fillStyle = "rgba(247, 250, 247, 0.9)";
    roundRect(context, 8, 10, 240, 46, 12);
    context.fill();
    context.fillStyle = "#1d2522";
    context.font = "700 24px system-ui, sans-serif";
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillText(text, 128, 34);
    const texture = new THREE.CanvasTexture(canvas);
    const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: texture, transparent: true }));
    sprite.position.set(...position);
    sprite.scale.set(2.5, 0.7, 1);
    return sprite;
  }
}

function samplePath(path, progress) {
  if (!path.length) return null;
  if (path.length === 1) return path[0];
  
  // Calculate total distance to make the container move at a uniform speed
  let totalDist = 0;
  const dists = [];
  for (let i = 0; i < path.length - 1; i++) {
    const d = Math.hypot(path[i+1][0] - path[i][0], path[i+1][1] - path[i][1], path[i+1][2] - path[i][2]);
    totalDist += d;
    dists.push(d);
  }
  
  const targetDist = progress * totalDist;
  let currentDist = 0;
  
  for (let i = 0; i < dists.length; i++) {
    if (currentDist + dists[i] >= targetDist || i === dists.length - 1) {
      const localProgress = dists[i] > 0 ? (targetDist - currentDist) / dists[i] : 0;
      return lerpPoint(path[i], path[i+1], Math.max(0, Math.min(1, localProgress)));
    }
    currentDist += dists[i];
  }
  return path[path.length - 1];
}

function lerpPoint(a, b, t) {
  return [
    a[0] + (b[0] - a[0]) * t,
    a[1] + (b[1] - a[1]) * t,
    a[2] + (b[2] - a[2]) * t,
  ];
}

function easeInOut(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

function roundRect(context, x, y, width, height, radius) {
  context.beginPath();
  context.moveTo(x + radius, y);
  context.arcTo(x + width, y, x + width, y + height, radius);
  context.arcTo(x + width, y + height, x, y + height, radius);
  context.arcTo(x, y + height, x, y, radius);
  context.arcTo(x, y, x + width, y, radius);
  context.closePath();
}
