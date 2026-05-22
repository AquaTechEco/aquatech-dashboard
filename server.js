const express = require('express');
const Database = require('better-sqlite3');
const cors = require('cors');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const TEAM_PASSWORD = process.env.TEAM_PASSWORD || 'aquatech2024';
// Xweather (Vaisala NLDN) lightning credentials — set on Render env vars.
// Sign up at https://www.xweather.com/ → developer console → create an app
// to get a Client ID + Client Secret. Lightning data requires the "Lightning"
// add-on or Essentials+ tier. Without these vars the strike endpoint returns
// 503 and the dashboard silently falls back to NWS-only signals.
const XWEATHER_CLIENT_ID = process.env.XWEATHER_CLIENT_ID || '';
const XWEATHER_CLIENT_SECRET = process.env.XWEATHER_CLIENT_SECRET || '';

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

// Lightning strike proxy — Xweather/Vaisala NLDN cloud-to-ground strikes within 50 mi
// of (lat,lon) over the last 5 minutes (the standard tier's data window).
// Credentials stay server-side. Results cached 30s per rounded lat/lon to stay well
// under rate limits (default poll cadence is one call per 30s anyway).
const strikeCache = {};
app.get('/api/lightning/strikes', async (req, res) => {
  if (!XWEATHER_CLIENT_ID || !XWEATHER_CLIENT_SECRET) {
    return res.status(503).json({ error: 'Xweather not configured', detail: 'Set XWEATHER_CLIENT_ID and XWEATHER_CLIENT_SECRET env vars on Render to enable real-strike detection.' });
  }
  const lat = parseFloat(req.query.lat);
  const lon = parseFloat(req.query.lon);
  if (!isFinite(lat) || !isFinite(lon)) {
    return res.status(400).json({ error: 'lat and lon (numbers) required' });
  }
  const cacheKey = lat.toFixed(2) + ',' + lon.toFixed(2);
  const cached = strikeCache[cacheKey];
  if (cached && (Date.now() - cached.ts) < 30000) {
    return res.json(cached.data);
  }
  try {
    const url = 'https://data.api.xweather.com/lightning/closest'
      + '?p=' + encodeURIComponent(lat + ',' + lon)
      + '&radius=50mi'
      + '&filter=cg'           // cloud-to-ground only
      + '&limit=250'
      + '&sort=dt:-1'          // newest first
      + '&format=json'
      + '&client_id=' + encodeURIComponent(XWEATHER_CLIENT_ID)
      + '&client_secret=' + encodeURIComponent(XWEATHER_CLIENT_SECRET);
    const upstream = await fetch(url);
    const data = await upstream.json();
    if (!upstream.ok || data.success === false) {
      const upstreamErr = data && data.error ? data.error : { code: upstream.status, description: 'upstream error' };
      return res.status(502).json({ error: 'Xweather upstream error', detail: upstreamErr });
    }
    const strikes = Array.isArray(data.response) ? data.response : [];
    const within25 = [], within50 = [];
    let nearestMi = null, newestTs = null;
    strikes.forEach(s => {
      const d = s.relativeTo && s.relativeTo.distanceMI;
      const ts = s.ob && s.ob.timestamp;
      if (d != null) {
        if (d <= 25) within25.push(s);
        if (d <= 50) within50.push(s);
        if (nearestMi == null || d < nearestMi) nearestMi = d;
      }
      if (ts != null && (newestTs == null || ts > newestTs)) newestTs = ts;
    });
    const result = {
      count_25mi: within25.length,
      count_50mi: within50.length,
      nearest_mi: nearestMi != null ? Math.round(nearestMi * 10) / 10 : null,
      latest_strike_min_ago: newestTs != null ? Math.max(0, Math.round((Date.now() / 1000 - newestTs) / 60)) : null,
      window_min: 5,
      source: 'Xweather (Vaisala NLDN)'
    };
    strikeCache[cacheKey] = { ts: Date.now(), data: result };
    res.json(result);
  } catch (err) {
    console.error('Xweather lightning error:', err);
    res.status(502).json({ error: 'Xweather request failed', detail: String(err.message || err) });
  }
});

// Serve the main dashboard
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`ATEC Weather Station running on port ${PORT}`);
});
