const { app, BrowserWindow, Menu, ipcMain, screen } = require('electron');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const WINDOW = { width: 234, height: 261 };
const DAY_START_HOUR = 6;
const HATCH_HOUR = 17;
const DINNER_START_MINUTE = 15;
const DINNER_END_HOUR = 19;

const SKINS = [
  { id: 'classic', name: '暖阳原色', rarity: '普通', chance: '16.7%', weight: 1, body: '#f5b91f', belly: '#f8dc58', beak: '#ed7e61', feet: '#b95338', cheeks: '#ee8b8c' },
  { id: 'strawberry', name: '草莓奶', rarity: '少见', chance: '16.7%', weight: 1, body: '#eab9b4', belly: '#f4e5c8', beak: '#d87982', feet: '#8c514a', cheeks: '#e96573' },
  { id: 'mint', name: '薄荷汽水', rarity: '少见', chance: '16.7%', weight: 1, body: '#a9cfc0', belly: '#d5e7d7', beak: '#e99b7c', feet: '#438f8c', cheeks: '#e99572' },
  { id: 'lavender', name: '薰衣草梦', rarity: '少见', chance: '16.7%', weight: 1, body: '#b9a9ce', belly: '#ded5e6', beak: '#976584', feet: '#60425e', cheeks: '#dd7e9d' },
  { id: 'midnight', name: '星夜', rarity: '稀有', chance: '16.7%', weight: 1, body: '#26345d', belly: '#4e5c88', beak: '#d8a548', feet: '#403354', cheeks: '#d5a341' },
  { id: 'prism', name: '虹彩', rarity: '超稀有', chance: '16.7%', weight: 1, body: '#e8b9ca', belly: '#e7e8c7', beak: '#df7f78', feet: '#a85970', cheeks: '#e7798b', prism: true }
];

let petWindow;
let state;
let statePath;
let hatchTimer;
let scheduleTimer;
let motionTimer;
let dragState;
let lastPetActivity = Date.now();
let walkFrame = false;
let lastWalkFrameAt = 0;

function localDayKey(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function effectiveDayKey(date) {
  const effective = new Date(date);
  if (effective.getHours() < DAY_START_HOUR) effective.setDate(effective.getDate() - 1);
  return localDayKey(effective);
}

function hatchDateFor(key) {
  const [year, month, day] = key.split('-').map(Number);
  return new Date(year, month - 1, day, HATCH_HOUR, 0, 0, 0);
}

function randomSkin() {
  const totalWeight = SKINS.reduce((sum, skin) => sum + skin.weight, 0);
  let roll = Math.random() * totalWeight;
  for (const skin of SKINS) {
    roll -= skin.weight;
    if (roll < 0) return skin;
  }
  return SKINS[0];
}

function defaultState() {
  const now = new Date();
  return {
    cycleDate: localDayKey(now),
    eggStartedAt: now.toISOString(),
    eggSkinId: randomSkin().id,
    hatchedToday: false,
    collection: [],
    selectedPetId: null,
    displayMode: 'egg',
    dinnerReminderEnabled: true,
    dinnerReminderShownDate: null
  };
}

function loadState() {
  statePath = path.join(app.getPath('userData'), 'duck-state.json');
  try {
    const saved = JSON.parse(fs.readFileSync(statePath, 'utf8'));
    state = { ...defaultState(), ...saved };
    if (!Array.isArray(state.collection)) state.collection = [];
  } catch {
    state = defaultState();
    saveState();
  }
}

function saveState() {
  if (!statePath || !state) return;
  fs.mkdirSync(path.dirname(statePath), { recursive: true });
  const temporary = `${statePath}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(state, null, 2));
  fs.renameSync(temporary, statePath);
}

function skinById(id) {
  return SKINS.find((skin) => skin.id === id) || SKINS[0];
}

function selectedPet() {
  return state.collection.find((pet) => pet.id === state.selectedPetId) || state.collection.at(-1) || null;
}

function activeSkinId() {
  if (state.displayMode === 'egg' && !state.hatchedToday) return state.eggSkinId;
  return selectedPet()?.skinId || state.eggSkinId;
}

function eggProgress(now = new Date()) {
  if (state.hatchedToday) return 1;
  const started = new Date(state.eggStartedAt);
  const end = hatchDateFor(state.cycleDate);
  if (end <= started) return now >= started ? 1 : 0;
  return Math.max(0, Math.min(1, (now - started) / (end - started)));
}

function eggFrame(now = new Date()) {
  const progress = eggProgress(now);
  if (progress < 0.48) return 'egg-intact-v2';
  if (progress < 0.82) return 'egg-cracked-v2';
  return 'egg-peek-v2';
}

function publicState() {
  const pet = selectedPet();
  const progress = eggProgress();
  return {
    ...state,
    activeSkinId: activeSkinId(),
    selectedPet: pet,
    eggProgress: progress,
    eggFrame: eggFrame(),
    progressText: state.hatchedToday ? '今天已经孵化完成' : `孵化进度 ${Math.round(progress * 100)}% · 17:00 出壳`,
    loginAtStartup: loginItemSettings().openAtLogin,
    skins: SKINS
  };
}

function loginExecutablePath() {
  return process.env.PORTABLE_EXECUTABLE_FILE || process.execPath;
}

function loginItemSettings() {
  if (process.platform === 'win32') {
    return app.getLoginItemSettings({ path: loginExecutablePath() });
  }
  return app.getLoginItemSettings();
}

function setLoginAtStartup(enabled) {
  const settings = { openAtLogin: enabled };
  if (process.platform === 'win32') settings.path = loginExecutablePath();
  app.setLoginItemSettings(settings);
}

function send(channel, payload) {
  if (petWindow && !petWindow.isDestroyed() && petWindow.webContents) {
    petWindow.webContents.send(channel, payload);
  }
}

function publishState() {
  send('state:update', publicState());
}

function ensureCurrentCycle(now = new Date()) {
  const expected = state.cycleDate ? effectiveDayKey(now) : localDayKey(now);
  if (state.cycleDate === expected) return false;
  state.cycleDate = expected;
  state.eggStartedAt = now.toISOString();
  state.eggSkinId = randomSkin().id;
  state.hatchedToday = false;
  state.displayMode = 'egg';
  state.dinnerReminderShownDate = null;
  saveState();
  publishState();
  return true;
}

function shouldShowDinnerReminder(now) {
  if (!state.dinnerReminderEnabled) return false;
  const day = localDayKey(now);
  if (state.dinnerReminderShownDate === day) return false;
  const minutes = now.getHours() * 60 + now.getMinutes();
  return minutes >= HATCH_HOUR * 60 + DINNER_START_MINUTE && now.getHours() < DINNER_END_HOUR;
}

function performHatch() {
  hatchTimer = undefined;
  if (state.hatchedToday) return;
  const pet = {
    id: crypto.randomUUID(),
    skinId: state.eggSkinId,
    hatchedAt: new Date().toISOString()
  };
  state.collection.push(pet);
  state.selectedPetId = pet.id;
  state.hatchedToday = true;
  state.displayMode = 'pet';
  saveState();
  publishState();
  const skin = skinById(pet.skinId);
  send('pet:hatch', { pet, skin });
}

function checkSchedule() {
  const now = new Date();
  if (ensureCurrentCycle(now)) {
    if (hatchTimer) clearTimeout(hatchTimer);
    hatchTimer = undefined;
  }
  if (!state.hatchedToday && now >= hatchDateFor(state.cycleDate) && !hatchTimer) {
    hatchTimer = setTimeout(performHatch, 2500);
  }
  if (shouldShowDinnerReminder(now)) {
    state.dinnerReminderShownDate = localDayKey(now);
    saveState();
    send('ui:banner', { text: '🍚 记得吃晚饭，忙完这一小段就去吧', duration: 9000 });
  }
  publishState();
}

function createWindow() {
  petWindow = new BrowserWindow({
    width: WINDOW.width,
    height: WINDOW.height,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    alwaysOnTop: true,
    resizable: false,
    maximizable: false,
    minimizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    hasShadow: false,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });

  petWindow.setAlwaysOnTop(true, 'floating');
  petWindow.setMenuBarVisibility(false);
  const workArea = screen.getPrimaryDisplay().workArea;
  petWindow.setPosition(workArea.x + workArea.width - WINDOW.width - 24, workArea.y + workArea.height - WINDOW.height - 12);
  petWindow.loadFile(path.join(__dirname, 'index.html'));
  petWindow.once('ready-to-show', () => {
    petWindow.showInactive();
    publishState();
    setTimeout(checkSchedule, 900);
  });

  petWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  petWindow.webContents.on('will-navigate', (event) => event.preventDefault());
  petWindow.on('closed', () => { petWindow = undefined; });
}

function showContextMenu() {
  const skinItems = SKINS.map((skin) => ({
    label: `${skin.name} · ${skin.chance}`,
    click: () => send('ui:preview-skin', skin.id)
  }));
  const menu = Menu.buildFromTemplate([
    { label: publicState().progressText, enabled: false },
    { type: 'separator' },
    { label: `我的鸭吉吉（${state.collection.length}）`, click: () => send('ui:modal', 'collection') },
    { label: '异色图鉴', click: () => send('ui:modal', 'dex') },
    { label: '预览异色外观', submenu: skinItems },
    { label: '预览孵化动画', click: () => send('ui:preview-hatch') },
    { type: 'separator' },
    {
      label: '晚饭提醒（每天最多一次）',
      type: 'checkbox',
      checked: state.dinnerReminderEnabled,
      click: (item) => {
        state.dinnerReminderEnabled = item.checked;
        saveState();
        publishState();
      }
    },
    {
      label: '开机自动启动',
      type: 'checkbox',
      checked: loginItemSettings().openAtLogin,
      click: (item) => {
        setLoginAtStartup(item.checked);
        publishState();
      }
    },
    { type: 'separator' },
    { label: '退出鸭吉吉', role: 'quit' }
  ]);
  menu.popup({ window: petWindow });
}

function startIdleTracking() {
  motionTimer = setInterval(() => {
    if (!petWindow || petWindow.isDestroyed() || dragState) return;
    send('pet:motion', {
      walking: false,
      direction: 1,
      walkFrame,
      idleFor: Date.now() - lastPetActivity
    });
  }, 1000);
}

function installIpc() {
  ipcMain.on('app:ready', publishState);
  ipcMain.on('menu:show', showContextMenu);
  ipcMain.on('pet:drag-start', (_event, point) => {
    if (!petWindow) return;
    lastPetActivity = Date.now();
    dragState = { point, lastPoint: point, bounds: petWindow.getBounds(), direction: 1 };
  });
  ipcMain.on('pet:drag-move', (_event, point) => {
    if (!petWindow || !dragState) return;
    const stepX = point.x - dragState.lastPoint.x;
    const moved = Math.abs(point.x - dragState.point.x) + Math.abs(point.y - dragState.point.y) > 4;
    if (Math.abs(stepX) > 0.5) dragState.direction = stepX > 0 ? 1 : -1;
    dragState.lastPoint = point;
    lastPetActivity = Date.now();
    const display = screen.getDisplayNearestPoint(point).workArea;
    const proposedX = dragState.bounds.x + point.x - dragState.point.x;
    const proposedY = dragState.bounds.y + point.y - dragState.point.y;
    const nextX = Math.max(display.x, Math.min(display.x + display.width - WINDOW.width, proposedX));
    const nextY = Math.max(display.y, Math.min(display.y + display.height - WINDOW.height, proposedY));
    petWindow.setPosition(Math.round(nextX), Math.round(nextY), false);
    if (moved && (state.hatchedToday || state.displayMode === 'pet')) {
      if (Date.now() - lastWalkFrameAt > 160) {
        walkFrame = !walkFrame;
        lastWalkFrameAt = Date.now();
      }
      send('pet:motion', {
        walking: true,
        direction: dragState.direction,
        walkFrame,
        idleFor: 0
      });
    }
  });
  ipcMain.on('pet:drag-end', () => {
    const direction = dragState?.direction || 1;
    dragState = undefined;
    lastPetActivity = Date.now();
    send('pet:motion', { walking: false, direction, walkFrame, idleFor: 0 });
  });
  ipcMain.on('collection:select', (_event, id) => {
    if (!state.collection.some((pet) => pet.id === id)) return;
    state.selectedPetId = id;
    state.displayMode = 'pet';
    saveState();
    publishState();
  });
}

app.whenReady().then(() => {
  loadState();
  installIpc();
  createWindow();
  startIdleTracking();
  scheduleTimer = setInterval(checkSchedule, 30_000);
});

app.on('window-all-closed', () => app.quit());
app.on('before-quit', () => {
  clearInterval(scheduleTimer);
  clearInterval(motionTimer);
  clearTimeout(hatchTimer);
});
