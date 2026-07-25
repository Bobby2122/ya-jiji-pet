const { contextBridge, ipcRenderer } = require('electron');

function subscribe(channel, callback) {
  const listener = (_event, payload) => callback(payload);
  ipcRenderer.on(channel, listener);
  return () => ipcRenderer.removeListener(channel, listener);
}

contextBridge.exposeInMainWorld('duckPet', {
  ready: () => ipcRenderer.send('app:ready'),
  showMenu: () => ipcRenderer.send('menu:show'),
  dragStart: () => ipcRenderer.send('pet:drag-start'),
  dragMove: () => ipcRenderer.send('pet:drag-move'),
  dragEnd: () => ipcRenderer.send('pet:drag-end'),
  selectPet: (id) => ipcRenderer.send('collection:select', id),
  onState: (callback) => subscribe('state:update', callback),
  onMotion: (callback) => subscribe('pet:motion', callback),
  onHatch: (callback) => subscribe('pet:hatch', callback),
  onBanner: (callback) => subscribe('ui:banner', callback),
  onModal: (callback) => subscribe('ui:modal', callback),
  onPreviewSkin: (callback) => subscribe('ui:preview-skin', callback),
  onPreviewHatch: (callback) => subscribe('ui:preview-hatch', callback)
});
