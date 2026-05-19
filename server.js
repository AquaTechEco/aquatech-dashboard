const express = require('express');
const Database = require('better-sqlite3');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const TEAM_PASSWORD = process.env.TEAM_PASSWORD || 'aquatech2024';
const WINDY_API_KEY = process.env.WINDY_API_KEY || '';

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('.'));

// Initialize SQLite database
const db = new Database('./locations.db');

// Create tables if they don't exist
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

// Auth middleware - simple team password check
function checkAuth(req, res, next) {
  const password = req.headers['x-team-password'];
  if (password !== TEAM_PASSWORD) {
    return res.status(401).json({ error: 'Invalid team password' });
  }
  next();
}

// Verify password endpoint
app.post('/api/auth', (req, res) => {
  const { password } = req.body;
  if (password === TEAM_PASSWORD) {
    res.json({ success: true });
  } else {
    res.status(401).json({ error: 'Invalid password' });
  }
});

// Get all project locations
app.get('/api/locations', checkAuth, (req, res) => {
  try {
    const locations = db.prepare('SELECT * FROM project_locations ORDER BY name').all();
    res.json(locations);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Add new location
app.post('/api/locations', checkAuth, (req, res) => {
  try {
    const { name, lat, lon, tide_station, notes } = req.body;
    
    if (!name || lat === undefined || lon === undefined) {
      return res.status(400).json({ error: 'Name, lat, and lon are required' });
    }
    
    const stmt = db.prepare(`
      INSERT INTO project_locations (name, lat, lon, tide_station, notes)
      VALUES (?, ?, ?, ?, ?)
    `);
    
    const result = stmt.run(name, lat, lon, tide_station || null, notes || null);
    
    const newLocation = db.prepare('SELECT * FROM project_locations WHERE id = ?').get(result.lastInsertRowid);
    res.status(201).json(newLocation);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update location
app.put('/api/locations/:id', checkAuth, (req, res) => {
  try {
    const { id } = req.params;
    const { name, lat, lon, tide_station, notes } = req.body;
    
    const stmt = db.prepare(`
      UPDATE project_locations 
      SET name = ?, lat = ?, lon = ?, tide_station = ?, notes = ?, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `);
    
    stmt.run(name, lat, lon, tide_station || null, notes || null, id);
    
    const updated = db.prepare('SELECT * FROM project_locations WHERE id = ?').get(id);
    if (!updated) {
      return res.status(404).json({ error: 'Location not found' });
    }
    res.json(updated);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete location
app.delete('/api/locations/:id', checkAuth, (req, res) => {
  try {
    const { id } = req.params;
    const stmt = db.prepare('DELETE FROM project_locations WHERE id = ?');
    const result = stmt.run(id);
    
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Location not found' });
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Windy Point Forecast proxy — key stays server-side so the whole team shares one.
// Set WINDY_API_KEY in Render env vars. Free key at https://api.windy.com/keys
app.post('/api/windy/point-forecast', async (req, res) => {
  if (!WINDY_API_KEY) {
    return res.status(503).json({ error: 'Windy proxy not configured — set WINDY_API_KEY env var' });
  }
  try {
    const { lat, lon, model, parameters, levels } = req.body || {};
    if (typeof lat !== 'number' || typeof lon !== 'number') {
      return res.status(400).json({ error: 'lat and lon (numbers) required' });
    }
    const payload = {
      lat,
      lon,
      model: model || 'gfs',
      parameters: parameters || ['temp', 'wind', 'gust', 'rh', 'pressure'],
      levels: levels || ['surface'],
      key: WINDY_API_KEY
    };
    const upstream = await fetch('https://api.windy.com/api/point-forecast/v2', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });
    const data = await upstream.json();
    res.status(upstream.status).json(data);
  } catch (err) {
    console.error('Windy proxy error:', err);
    res.status(502).json({ error: 'Windy upstream error', detail: String(err.message || err) });
  }
});

// Serve the main dashboard
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`ATEC Weather Station running on port ${PORT}`);
});
