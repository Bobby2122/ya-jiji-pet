const sprite = document.querySelector('#sprite');
const loading = document.querySelector('#loading');
const banner = document.querySelector('#banner');
const modal = document.querySelector('#modal');
const modalTitle = document.querySelector('#modal-title');
const modalContent = document.querySelector('#modal-content');
const modalClose = document.querySelector('#modal-close');
const hitCanvas = document.createElement('canvas');
const hitContext = hitCanvas.getContext('2d', { willReadFrequently: true });

const frameUrls = {
  'adult-idle': '../assets/sprites/adult-idle.png',
  'adult-blink': '../assets/sprites/adult-blink.png',
  'adult-tilt': '../assets/sprites/adult-tilt.png',
  'adult-walk-a': '../assets/sprites/adult-walk-a.png',
  'adult-walk-b': '../assets/sprites/adult-walk-b.png',
  'adult-sleep': '../assets/sprites/adult-sleep.png',
  'egg-intact-v2': '../assets/sprites/egg-intact-v2.png',
  'egg-cracked-v2': '../assets/sprites/egg-cracked-v2.png',
  'egg-peek-v2': '../assets/sprites/egg-peek-v2.png',
  'egg-hatched-v2': '../assets/sprites/egg-hatched-v2.png'
};

let appState;
let currentFrame = '';
let currentSkin = '';
let previewing = false;
let walking = false;
let bannerTimer;
let dragStart;
let dragged = false;
let pendingDragPoint;
let dragAnimationFrame;
let blinkTimer;
let actionTimer;
let renderTicket = 0;
const recolorCache = new Map();
const sourceCache = new Map();
let warmedWalkSkin = '';
let hitPixels;
let hitWidth = 0;
let hitHeight = 0;
let hitSource = '';

function rebuildSpriteHitMap() {
  if (!sprite.complete || !sprite.naturalWidth || !sprite.naturalHeight) return;
  hitCanvas.width = sprite.naturalWidth;
  hitCanvas.height = sprite.naturalHeight;
  hitContext.clearRect(0, 0, hitCanvas.width, hitCanvas.height);
  hitContext.drawImage(sprite, 0, 0);
  hitPixels = hitContext.getImageData(0, 0, hitCanvas.width, hitCanvas.height).data;
  hitWidth = hitCanvas.width;
  hitHeight = hitCanvas.height;
  hitSource = sprite.currentSrc || sprite.src;
}

function hitsVisibleSprite(event) {
  const source = sprite.currentSrc || sprite.src;
  if (!hitPixels || hitSource !== source) rebuildSpriteHitMap();
  if (!hitPixels || !hitWidth || !hitHeight) return false;

  const rect = sprite.getBoundingClientRect();
  const scale = Math.min(rect.width / hitWidth, rect.height / hitHeight);
  const drawnWidth = hitWidth * scale;
  const drawnHeight = hitHeight * scale;
  const left = rect.left + (rect.width - drawnWidth) / 2;
  const top = rect.top + (rect.height - drawnHeight) / 2;
  const imageX = Math.floor((event.clientX - left) / scale);
  const imageY = Math.floor((event.clientY - top) / scale);
  if (imageX < 0 || imageY < 0 || imageX >= hitWidth || imageY >= hitHeight) return false;

  return hitPixels[(imageY * hitWidth + imageX) * 4 + 3] >= 24;
}

function skinById(id) {
  return appState?.skins.find((skin) => skin.id === id) || appState?.skins[0];
}

function hexRgb(hex) {
  const value = Number.parseInt(hex.slice(1), 16);
  return [(value >> 16) / 255, ((value >> 8) & 255) / 255, (value & 255) / 255];
}

function hsv(r, g, b) {
  const maximum = Math.max(r, g, b);
  const minimum = Math.min(r, g, b);
  const delta = maximum - minimum;
  let hue = 0;
  if (delta > 0.0001) {
    if (maximum === r) hue = 60 * (((g - b) / delta) % 6);
    else if (maximum === g) hue = 60 * ((b - r) / delta + 2);
    else hue = 60 * ((r - g) / delta + 4);
  }
  if (hue < 0) hue += 360;
  return { hue, saturation: maximum === 0 ? 0 : delta / maximum, value: maximum };
}

function prismColor(x, y, width, height) {
  const colors = [
    [0.91, 0.70, 0.79], [0.95, 0.86, 0.68],
    [0.70, 0.86, 0.80], [0.73, 0.72, 0.90], [0.91, 0.70, 0.79]
  ];
  const phase = (x / Math.max(width, 1) * 0.55) + (y / Math.max(height, 1) * 0.45);
  const scaled = phase * (colors.length - 1);
  const index = Math.min(colors.length - 2, Math.max(0, Math.floor(scaled)));
  const amount = scaled - index;
  return colors[index].map((value, channel) => value + (colors[index + 1][channel] - value) * amount);
}

function loadSource(frame) {
  if (sourceCache.has(frame)) return sourceCache.get(frame);
  const promise = new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = reject;
    image.src = frameUrls[frame];
  });
  sourceCache.set(frame, promise);
  return promise;
}

async function renderedUrl(frame, skinId) {
  const cacheKey = `${frame}|${skinId}`;
  if (recolorCache.has(cacheKey)) return recolorCache.get(cacheKey);
  if (skinId === 'classic' || frame === 'egg-intact-v2' || frame === 'egg-cracked-v2') {
    return frameUrls[frame];
  }

  const source = await loadSource(frame);
  const canvas = document.createElement('canvas');
  canvas.width = source.naturalWidth;
  canvas.height = source.naturalHeight;
  const context = canvas.getContext('2d', { willReadFrequently: true });
  context.drawImage(source, 0, 0);
  const imageData = context.getImageData(0, 0, canvas.width, canvas.height);
  const data = imageData.data;
  const skin = skinById(skinId);

  for (let y = 0; y < canvas.height; y += 1) {
    for (let x = 0; x < canvas.width; x += 1) {
      const offset = (y * canvas.width + x) * 4;
      if (data[offset + 3] < 5) continue;
      const red = data[offset] / 255;
      const green = data[offset + 1] / 255;
      const blue = data[offset + 2] / 255;
      const color = hsv(red, green, blue);
      let target;
      let reference = 0.72;

      if (color.saturation > 0.25 && color.hue >= 32 && color.hue <= 68 && color.value > 0.42) {
        const belly = green / Math.max(red, 0.01) > 0.76 && y > canvas.height / 3;
        target = skin.prism && !belly ? prismColor(x, y, canvas.width, canvas.height) : hexRgb(belly ? skin.belly : skin.body);
        reference = belly ? 0.84 : 0.71;
      } else if (color.saturation > 0.28 && (color.hue <= 31 || color.hue >= 345) && color.value > 0.38) {
        if (y > canvas.height * 0.76) {
          target = hexRgb(skin.feet);
          reference = 0.48;
        } else if (blue / Math.max(red, 0.01) > 0.39) {
          target = hexRgb(skin.cheeks);
          reference = 0.68;
        } else {
          target = hexRgb(skin.beak);
          reference = 0.63;
        }
      }

      if (!target) continue;
      const luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
      const shade = Math.max(0.38, Math.min(1.32, luminance / reference));
      data[offset] = Math.max(0, Math.min(255, target[0] * shade * 255));
      data[offset + 1] = Math.max(0, Math.min(255, target[1] * shade * 255));
      data[offset + 2] = Math.max(0, Math.min(255, target[2] * shade * 255));
    }
  }

  context.putImageData(imageData, 0, 0);
  const url = canvas.toDataURL('image/png');
  recolorCache.set(cacheKey, url);
  return url;
}

async function setFrame(frame, skinId = appState?.activeSkinId, mirrored = false, force = false) {
  if (!frameUrls[frame] || !skinId) return;
  if (!force && frame === currentFrame && skinId === currentSkin) {
    sprite.classList.toggle('mirror', mirrored);
    return;
  }
  const ticket = ++renderTicket;
  try {
    const url = await renderedUrl(frame, skinId);
    if (ticket !== renderTicket) return;
    sprite.src = url;
    sprite.classList.toggle('mirror', mirrored);
    currentFrame = frame;
    currentSkin = skinId;
    loading.classList.add('hidden');
  } catch (error) {
    console.error('Unable to render pet frame:', frame, error);
  }
}

function prewarmWalkFrames(skinId) {
  if (!skinId || warmedWalkSkin === skinId) return;
  warmedWalkSkin = skinId;
  Promise.all([
    renderedUrl('adult-walk-a', skinId),
    renderedUrl('adult-walk-b', skinId)
  ]).catch((error) => console.error('Unable to prewarm walk frames:', error));
}

function normalFrame() {
  if (!appState || previewing) return;
  if (appState.displayMode === 'egg' && !appState.hatchedToday) {
    setFrame(appState.eggFrame, appState.eggSkinId);
  } else {
    setFrame('adult-idle', appState.activeSkinId);
  }
}

function animateClass(name) {
  sprite.classList.remove(name);
  void sprite.offsetWidth;
  sprite.classList.add(name);
  setTimeout(() => sprite.classList.remove(name), 950);
}

function showBanner(text, duration = 7000) {
  clearTimeout(bannerTimer);
  banner.textContent = text;
  banner.classList.remove('hidden');
  bannerTimer = setTimeout(() => banner.classList.add('hidden'), duration);
}

function scheduleBlink() {
  clearTimeout(blinkTimer);
  blinkTimer = setTimeout(async () => {
    if (!previewing && !walking && appState && (appState.hatchedToday || appState.displayMode === 'pet')) {
      await setFrame('adult-blink', appState.activeSkinId, false, true);
      setTimeout(normalFrame, 160);
    }
    scheduleBlink();
  }, 3200 + Math.random() * 4300);
}

function scheduleAction() {
  clearTimeout(actionTimer);
  actionTimer = setTimeout(async () => {
    if (!previewing && !walking && appState && (appState.hatchedToday || appState.displayMode === 'pet')) {
      await setFrame('adult-tilt', appState.activeSkinId, false, true);
      setTimeout(normalFrame, 900);
    }
    scheduleAction();
  }, 12_000 + Math.random() * 12_000);
}

async function previewSkin(skinId) {
  previewing = true;
  await setFrame('adult-idle', skinId, false, true);
  animateClass('bounce');
  const skin = skinById(skinId);
  showBanner(`${skin.name} · ${skin.rarity}`, 3500);
  setTimeout(() => { previewing = false; normalFrame(); }, 4000);
}

function previewHatch(skinId = appState?.eggSkinId) {
  previewing = true;
  const frames = ['egg-intact-v2', 'egg-cracked-v2', 'egg-peek-v2', 'egg-hatched-v2'];
  frames.forEach((frame, index) => setTimeout(() => {
    setFrame(frame, skinId, false, true);
    if (index === frames.length - 1) animateClass('hatch');
  }, index * 850));
  setTimeout(() => { previewing = false; normalFrame(); }, 4300);
}

function formatDate(iso) {
  return new Intl.DateTimeFormat('zh-CN', { month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(iso));
}

async function openCollection() {
  modalTitle.textContent = `我的鸭吉吉 · ${appState.collection.length}`;
  modalContent.replaceChildren();
  if (!appState.collection.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = '第一颗蛋还在努力孵化，17:00 再来看看吧。';
    modalContent.append(empty);
  }
  for (const pet of [...appState.collection].reverse()) {
    const skin = skinById(pet.skinId);
    const card = document.createElement('button');
    card.className = `card${pet.id === appState.selectedPetId ? ' selected' : ''}`;
    card.type = 'button';
    const image = document.createElement('img');
    image.alt = skin.name;
    image.src = await renderedUrl('adult-idle', skin.id);
    const text = document.createElement('span');
    const strong = document.createElement('strong');
    strong.textContent = skin.name;
    const small = document.createElement('small');
    small.textContent = `${skin.rarity} · ${formatDate(pet.hatchedAt)} 孵化`;
    text.append(strong, small);
    const check = document.createElement('span');
    check.className = 'check';
    check.textContent = pet.id === appState.selectedPetId ? '使用中' : '选择';
    card.append(image, text, check);
    card.addEventListener('click', () => {
      window.duckPet.selectPet(pet.id);
      closeModal();
      showBanner(`换成 ${skin.name} 陪你啦`, 3500);
    });
    modalContent.append(card);
  }
  modal.classList.remove('hidden');
}

async function openDex() {
  modalTitle.textContent = '异色图鉴';
  modalContent.replaceChildren();
  for (const skin of appState.skins) {
    const card = document.createElement('button');
    card.className = 'card';
    card.type = 'button';
    const image = document.createElement('img');
    image.alt = skin.name;
    image.src = await renderedUrl('adult-idle', skin.id);
    const text = document.createElement('span');
    const strong = document.createElement('strong');
    strong.textContent = `${skin.name} · ${skin.chance}`;
    const small = document.createElement('small');
    small.textContent = skin.rarity;
    const swatches = document.createElement('span');
    swatches.className = 'swatches';
    [skin.body, skin.belly, skin.beak].forEach((color) => {
      const swatch = document.createElement('i');
      swatch.className = 'swatch';
      swatch.style.background = color;
      swatches.append(swatch);
    });
    text.append(strong, small, swatches);
    const found = appState.collection.some((pet) => pet.skinId === skin.id);
    const status = document.createElement('span');
    status.className = 'check';
    status.textContent = found ? '已发现' : '未发现';
    card.append(image, text, status);
    card.addEventListener('click', () => { closeModal(); previewSkin(skin.id); });
    modalContent.append(card);
  }
  modal.classList.remove('hidden');
}

function closeModal() {
  modal.classList.add('hidden');
}

sprite.addEventListener('contextmenu', (event) => {
  event.preventDefault();
  if (!hitsVisibleSprite(event)) return;
  window.duckPet.showMenu();
});

sprite.addEventListener('pointerdown', (event) => {
  if (event.button !== 0 || !hitsVisibleSprite(event)) return;
  dragStart = { x: event.screenX, y: event.screenY };
  dragged = false;
  pendingDragPoint = undefined;
  sprite.style.visibility = 'visible';
  sprite.setPointerCapture(event.pointerId);
  window.duckPet.dragStart();
});

sprite.addEventListener('pointermove', (event) => {
  if (!dragStart) sprite.classList.toggle('pixel-hit', hitsVisibleSprite(event));
  if (!dragStart || !(event.buttons & 1)) return;
  const point = { x: event.screenX, y: event.screenY };
  if (Math.abs(point.x - dragStart.x) + Math.abs(point.y - dragStart.y) > 4) dragged = true;
  pendingDragPoint = point;
  if (!dragAnimationFrame) {
    dragAnimationFrame = requestAnimationFrame(() => {
      dragAnimationFrame = undefined;
      if (pendingDragPoint) window.duckPet.dragMove();
      pendingDragPoint = undefined;
    });
  }
});

function finishDrag(allowClick) {
  if (!dragStart) return;
  if (dragAnimationFrame) cancelAnimationFrame(dragAnimationFrame);
  dragAnimationFrame = undefined;
  if (pendingDragPoint) window.duckPet.dragMove();
  pendingDragPoint = undefined;
  window.duckPet.dragEnd();
  dragStart = undefined;
  if (!dragged && allowClick) {
    animateClass('bounce');
    if (appState?.hatchedToday || appState?.displayMode === 'pet') {
      setFrame('adult-tilt', appState.activeSkinId, false, true);
      setTimeout(normalFrame, 650);
    }
  } else {
    walking = false;
    normalFrame();
  }
}

sprite.addEventListener('pointerup', () => {
  finishDrag(true);
});

sprite.addEventListener('pointercancel', () => finishDrag(false));
sprite.addEventListener('lostpointercapture', () => finishDrag(false));
sprite.addEventListener('pointerleave', () => {
  if (!dragStart) sprite.classList.remove('pixel-hit');
});
sprite.addEventListener('load', rebuildSpriteHitMap);

banner.addEventListener('click', () => banner.classList.add('hidden'));
modalClose.addEventListener('click', closeModal);
modal.addEventListener('pointerdown', (event) => { if (event.target === modal) closeModal(); });

window.duckPet.onState((nextState) => {
  appState = nextState;
  if (appState.hatchedToday || appState.displayMode === 'pet') prewarmWalkFrames(appState.activeSkinId);
  if (!previewing && !walking) normalFrame();
});

window.duckPet.onMotion((motion) => {
  if (!appState || previewing || (appState.displayMode === 'egg' && !appState.hatchedToday)) return;
  walking = motion.walking;
  if (motion.walking) {
    setFrame(motion.walkFrame ? 'adult-walk-a' : 'adult-walk-b', appState.activeSkinId, motion.direction > 0);
  } else if (motion.idleFor > 180_000) {
    setFrame('adult-sleep', appState.activeSkinId);
  } else if (currentFrame.startsWith('adult-walk') || currentFrame === 'adult-sleep') {
    normalFrame();
  }
});

window.duckPet.onHatch(({ skin }) => {
  previewing = true;
  setFrame('egg-hatched-v2', skin.id, false, true);
  animateClass('hatch');
  showBanner(`孵化成功：${skin.name} · ${skin.rarity}！`, 7000);
  setTimeout(() => { previewing = false; normalFrame(); }, 3800);
});

window.duckPet.onBanner(({ text, duration }) => showBanner(text, duration));
window.duckPet.onModal((kind) => kind === 'collection' ? openCollection() : openDex());
window.duckPet.onPreviewSkin(previewSkin);
window.duckPet.onPreviewHatch(() => previewHatch());

scheduleBlink();
scheduleAction();
window.duckPet.ready();
