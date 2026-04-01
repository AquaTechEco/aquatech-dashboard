const { app, BrowserWindow, shell, Menu } = require('electron');
const path = require('path');

let mainWindow;
let server;

function startServer() {
  return new Promise((resolve, reject) => {
    try {
      // Start the Express server
      const express = require('express');
      const Database = require('better-sqlite3');
      const cors = require('cors');

      const webapp = express();
      const PORT = 3847; // Use a specific port for the desktop app
      const TEAM_PASSWORD = process.env.TEAM_PASSWORD || 'aquatech2024';

      webapp.use(cors());
      webapp.use(express.json());
      webapp.use(express.static(path.join(__dirname, 'public')));

      // Initialize SQLite database (store in user data directory)
      const userDataPath = app.getPath('userData');
      const dbPath = path.join(userDataPath, 'locations.db');
      const db = new Database(dbPath);

      db.exec(`
        CREATE TABLE IF NOT EXISTS project_locations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          lat REAL NOT NULL,
          lon REAL NOT NULL,
          tide_station TEXT,
          notes TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      `);

      function checkAuth(req, res, next) {
        const password = req.headers['x-team-password'];
        if (password !== TEAM_PASSWORD) {
          return res.status(401).json({ error: 'Invalid team password' });
        }
        next();
      }

      webapp.post('/api/auth', (req, res) => {
        const { password } = req.body;
        if (password === TEAM_PASSWORD) {
          res.json({ success: true });
        } else {
          res.status(401).json({ error: 'Invalid password' });
        }
      });

      webapp.get('/api/locations', checkAuth, (req, res) => {
        try {
          const locations = db.prepare('SELECT * FROM project_locations ORDER BY name').all();
          res.json(locations);
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });

      webapp.post('/api/locations', checkAuth, (req, res) => {
        try {
          const { name, lat, lon, tide_station, notes } = req.body;
          if (!name || lat === undefined || lon === undefined) {
            return res.status(400).json({ error: 'Name, lat, and lon are required' });
          }
          const stmt = db.prepare('INSERT INTO project_locations (name, lat, lon, tide_station, notes) VALUES (?, ?, ?, ?, ?)');
          const result = stmt.run(name, lat, lon, tide_station || null, notes || null);
          const newLocation = db.prepare('SELECT * FROM project_locations WHERE id = ?').get(result.lastInsertRowid);
          res.status(201).json(newLocation);
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });

      webapp.put('/api/locations/:id', checkAuth, (req, res) => {
        try {
          const { id } = req.params;
          const { name, lat, lon, tide_station, notes } = req.body;
          const stmt = db.prepare('UPDATE project_locations SET name = ?, lat = ?, lon = ?, tide_station = ?, notes = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?');
          stmt.run(name, lat, lon, tide_station || null, notes || null, id);
          const updated = db.prepare('SELECT * FROM project_locations WHERE id = ?').get(id);
          if (!updated) return res.status(404).json({ error: 'Location not found' });
          res.json(updated);
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });

      webapp.delete('/api/locations/:id', checkAuth, (req, res) => {
        try {
          const { id } = req.params;
          const result = db.prepare('DELETE FROM project_locations WHERE id = ?').run(id);
          if (result.changes === 0) return res.status(404).json({ error: 'Location not found' });
          res.json({ success: true });
        } catch (err) {
          res.status(500).json({ error: err.message });
        }
      });

      webapp.get('/', (req, res) => {
        res.sendFile(path.join(__dirname, 'public', 'index.html'));
      });

      server = webapp.listen(PORT, () => {
        console.log(`ATEC Weather running on port ${PORT}`);
        resolve(PORT);
      });

      server.on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
          // Port taken, try another
          server = webapp.listen(0, () => {
            const assignedPort = server.address().port;
            console.log(`ATEC Weather running on port ${assignedPort}`);
            resolve(assignedPort);
          });
        } else {
          reject(err);
        }
      });
    } catch (err) {
      reject(err);
    }
  });
}

function createWindow(port) {
  mainWindow = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 800,
    minHeight: 600,
    icon: path.join(__dirname, 'icons', 'AquaTech_Weather.icns'),
    title: 'AquaTech Weather',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 15, y: 15 },
    backgroundColor: '#1a5276',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
    show: false,
  });

  mainWindow.loadURL(`http://localhost:${port}`);

  // Show window once content is ready (no white flash)
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });

  // Open external links in the default browser
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// macOS app menu
function createMenu() {
  const template = [
    {
      label: 'AquaTech Weather',
      submenu: [
        { label: 'About AquaTech Weather', role: 'about' },
        { type: 'separator' },
        { label: 'Hide', accelerator: 'CmdOrCtrl+H', role: 'hide' },
        { label: 'Hide Others', accelerator: 'CmdOrCtrl+Shift+H', role: 'hideOthers' },
        { type: 'separator' },
        { label: 'Quit', accelerator: 'CmdOrCtrl+Q', role: 'quit' },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        { type: 'separator' },
        { role: 'front' },
      ],
    },
  ];

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

app.whenReady().then(async () => {
  createMenu();
  const port = await startServer();
  createWindow(port);

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow(port);
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('before-quit', () => {
  if (server) server.close();
});
