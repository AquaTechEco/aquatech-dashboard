# ATEC Weather Station

Real-time weather, tides & safety alerts dashboard for field teams.

## Features

- 🌀 **Windy Map** - Wind, radar, thunder, temp, waves layers
- 🗺️ **Interactive Map** - RainViewer radar overlay with animation
- 📈 **48-Hour Forecast** - Temperature & precipitation chart
- 🌡️ **Heat Index** - Real-time calculation with danger alerts
- ⚡ **Lightning Warnings** - Thunderstorm detection with 30-30 rule
- 💨 **Wind Alerts** - Notifications when gusts exceed 20 mph
- 🔔 **Push Notifications** - Alerts for heat, lightning, and wind
- 📍 **Project Locations** - Save and manage job sites
- 🌊 **Tide Predictions** - NOAA tide data
- 📄 **PDF Export** - Field report generation

## Deployment on Render.com

### 1. Push to GitHub
```bash
git init
git add .
git commit -m "ATEC Weather Station"
git remote add origin YOUR_REPO_URL
git push -u origin main
```

### 2. Create Web Service on Render
- Connect your GitHub repo
- Build Command: `npm install`
- Start Command: `node server.js`

### 3. Add Environment Variable
- `TEAM_PASSWORD` = `!6169Aqua!`

### 4. Add Disk Storage
- Mount Path: `/opt/render/project/src`
- Size: 1 GB

### 5. Deploy!

## Team Password
`!6169Aqua!`

## Alert Thresholds
- **Heat Index**: Warning at 103°F+
- **Wind Gusts**: Alert at 20+ mph
- **Lightning**: Thunderstorm weather codes (95, 96, 99)

## Data Sources
- Open-Meteo (weather forecasts)
- NOAA (tides, water temp, alerts)
- RainViewer (radar)
- Windy (wind visualization)
