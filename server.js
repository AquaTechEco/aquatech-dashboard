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

// Lightning strike proxy — Xweather/Vaisala NLDN flash data within ~25 mi of (lat,lon)
// over the last 15 minutes. Credentials stay server-side. Results are cached per rounded
// lat/lon so crew at the same site share a single upstream call; the cache TTL stretches
// overnight (Eastern) to cut quota use when nobody's on the water.
const strikeCache = {};
const STRIKE_WINDOW_MIN = 15;   // only count strikes from the last 15 minutes

// Great-circle distance in miles between two lat/lon points (fallback when the API
// response doesn't include a precomputed distance).
function distanceMiles(lat1, lon1, lat2, lon2) {
  const R = 3958.8, toRad = d => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1), dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
// Current hour in US Eastern (DST-safe), used to throttle polling overnight.
function easternHour() {
  return parseInt(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', hour12: false }).format(new Date()), 10);
}

app.get('/api/lightning/strikes', async (req, res) => {
  if (!XWEATHER_CLIENT_ID || !XWEATHER_CLIENT_SECRET) {
    return res.status(503).json({ error: 'Xweather not configured', detail: 'Set XWEATHER_CLIENT_ID and XWEATHER_CLIENT_SECRET env vars on Render to enable real-strike detection.' });
  }
  const lat = parseFloat(req.query.lat);
  const lon = parseFloat(req.query.lon);
  if (!isFinite(lat) || !isFinite(lon)) {
    return res.status(400).json({ error: 'lat and lon (numbers) required' });
  }
  // Daytime (5a–9p ET) = fresh data every 30s; overnight = every 5 min to conserve quota.
  const hour = easternHour();
  const ttl = (hour >= 5 && hour < 21) ? 30000 : 300000;
  const cacheKey = lat.toFixed(2) + ',' + lon.toFixed(2);
  const cached = strikeCache[cacheKey];
  if (cached && (Date.now() - cached.ts) < ttl) {
    return res.json(cached.data);
  }
  try {
    // 40km (~25mi) is the flash endpoint's maximum radius. "closest" sorts nearest-first.
    const url = 'https://data.api.xweather.com/lightning/flash/closest'
      + '?p=' + encodeURIComponent(lat + ',' + lon)
      + '&radius=40km'
      + '&limit=1000'
      + '&format=json'
      + '&client_id=' + encodeURIComponent(XWEATHER_CLIENT_ID)
      + '&client_secret=' + encodeURIComponent(XWEATHER_CLIENT_SECRET);
    const upstream = await fetch(url);
    const data = await upstream.json();
    // warn_no_data = valid request, just no strikes nearby → treat as zero strikes, not an error.
    const noData = data && data.error && data.error.code === 'warn_no_data';
    if (!noData && (!upstream.ok || data.success === false)) {
      const upstreamErr = data && data.error ? data.error : { code: upstream.status, description: 'upstream error' };
      return res.status(502).json({ error: 'Xweather upstream error', detail: upstreamErr });
    }
    const strikes = Array.isArray(data.response) ? data.response : [];
    const nowSec = Date.now() / 1000;
    let count10 = 0, count25 = 0, nearestMi = null, newestTs = null;
    const points = []; // individual strikes within 25mi, for plotting on the map
    strikes.forEach(s => {
      // Prefer the API's relativeTo distance; otherwise derive it from the flash location.
      let d = null;
      if (s.relativeTo) {
        if (s.relativeTo.distanceMI != null) d = s.relativeTo.distanceMI;
        else if (s.relativeTo.distanceKM != null) d = s.relativeTo.distanceKM * 0.621371;
      }
      if (d == null && s.loc && s.loc.lat != null && s.loc.long != null) {
        d = distanceMiles(lat, lon, s.loc.lat, s.loc.long);
      }
      const ts = s.ob && s.ob.timestamp;
      if (ts != null && (nowSec - ts) > STRIKE_WINDOW_MIN * 60) return; // older than our window — skip
      if (d != null) {
        if (d <= 10) count10++;
        if (d <= 25) count25++;
        if (nearestMi == null || d < nearestMi) nearestMi = d;
        if (d <= 25 && s.loc && s.loc.lat != null && s.loc.long != null) {
          points.push({ lat: s.loc.lat, lon: s.loc.long, mi: Math.round(d * 10) / 10, mins: ts != null ? Math.max(0, Math.round((nowSec - ts) / 60)) : null });
        }
      }
      if (ts != null && (newestTs == null || ts > newestTs)) newestTs = ts;
    });
    const result = {
      count_10mi: count10,
      count_25mi: count25,
      nearest_mi: nearestMi != null ? Math.round(nearestMi * 10) / 10 : null,
      latest_strike_min_ago: newestTs != null ? Math.max(0, Math.round((nowSec - newestTs) / 60)) : null,
      window_min: STRIKE_WINDOW_MIN,
      points: points.slice(0, 400),
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
