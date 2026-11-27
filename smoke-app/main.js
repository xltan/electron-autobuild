const { app } = require('electron');
const { strictEqual } = require('node:assert');
const { writeFileSync } = require('node:fs');

function loadUndefined() { return void 0; }
function loadNull() { return null; }

app.whenReady().then(() => {
  strictEqual(loadUndefined(), undefined);
  strictEqual(loadNull(), null);
  const marker = process.env.ELECTRON_ENTRY_SMOKE_MARKER;
  if (marker) writeFileSync(marker, 'entry ran');
  app.exit(0);
});
