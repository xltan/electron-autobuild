const { app } = require('electron');
const { writeFileSync } = require('node:fs');

app.whenReady().then(() => {
  const marker = process.env.ELECTRON_ENTRY_SMOKE_MARKER;
  if (marker) writeFileSync(marker, 'entry ran');
  app.exit(0);
});
