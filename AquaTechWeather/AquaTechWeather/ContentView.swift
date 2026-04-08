import SwiftUI
import WebKit
import UserNotifications

// MARK: - Tabs

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard      = "Dashboard"
    case maps           = "Maps"
    case marineForecast = "Marine Forecast"
    case settings       = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard:      return "square.grid.2x2.fill"
        case .maps:           return "map.fill"
        case .marineForecast: return "water.waves"
        case .settings:       return "gearshape.fill"
        }
    }

    var cssClass: String {
        switch self {
        case .dashboard:      return "tab-dashboard"
        case .maps:           return "tab-maps"
        case .marineForecast: return "tab-marine-forecast"
        case .settings:       return "tab-settings"
        }
    }

    /// JS to switch tab mode — sets body class + manages panels + scrolls to top
    var navigationJS: String {
        let setClass = "document.body.className=document.body.className.replace(/tab-\\w+/g,'').trim();document.body.classList.add('\(cssClass)');"
        switch self {
        case .dashboard:
            return """
            (function(){
                \(setClass)
                ['windy','map','hourly'].forEach(function(n){
                    var b=document.getElementById(n+'Body');
                    if(b&&b.classList.contains('open'))togglePanel(n);
                });
                window.scrollTo({top:0,behavior:'smooth'});
            })();
            """
        case .maps:
            return """
            (function(){
                \(setClass)
                var wb=document.getElementById('windyBody');
                if(wb&&!wb.classList.contains('open'))togglePanel('windy');
                var mb=document.getElementById('mapBody');
                if(mb&&!mb.classList.contains('open'))togglePanel('map');
                var hb=document.getElementById('hourlyBody');
                if(hb&&hb.classList.contains('open'))togglePanel('hourly');
                window.scrollTo({top:0,behavior:'smooth'});
            })();
            """
        case .marineForecast:
            return """
            (function(){
                \(setClass)
                var hb=document.getElementById('hourlyBody');
                if(hb&&!hb.classList.contains('open'))togglePanel('hourly');
                var wb=document.getElementById('windyBody');
                if(wb&&wb.classList.contains('open'))togglePanel('windy');
                var mb=document.getElementById('mapBody');
                if(mb&&mb.classList.contains('open'))togglePanel('map');
                window.scrollTo({top:0,behavior:'smooth'});
            })();
            """
        case .settings:
            return """
            (function(){
                \(setClass)
                ['windy','map','hourly'].forEach(function(n){
                    var b=document.getElementById(n+'Body');
                    if(b&&b.classList.contains('open'))togglePanel(n);
                });
                // Create settings panel if it doesn't exist yet
                if(!document.getElementById('nativeSettingsPanel')){
                    var sp=document.createElement('div');
                    sp.id='nativeSettingsPanel';
                    var glass='background:rgba(255,255,255,0.12);backdrop-filter:blur(20px);border:1px solid rgba(255,255,255,0.2);border-radius:14px;padding:1.2rem;margin-bottom:1rem;';
                    var secTitle='font-size:0.9rem;font-weight:600;margin-bottom:1rem;opacity:0.6;text-transform:uppercase;letter-spacing:0.08em;';
                    var rowStyle='display:flex;align-items:center;justify-content:space-between;padding:0.7rem 0;';
                    var borderBot='border-bottom:1px solid rgba(255,255,255,0.1);';
                    var label='font-weight:600;font-size:1.05rem;';
                    var sub='font-size:0.85rem;opacity:0.5;margin-top:0.15rem;';
                    var btnOff='padding:0.5rem 1.2rem;border:none;border-radius:10px;background:rgba(255,255,255,0.15);color:white;font-weight:600;font-size:0.95rem;cursor:pointer;';
                    var btnOn='padding:0.5rem 1.2rem;border:none;border-radius:10px;background:linear-gradient(135deg,#4CB848,#6DD468);color:white;font-weight:600;font-size:0.95rem;cursor:pointer;';
                    sp.innerHTML=
                        '<div style="max-width:600px;margin:0 auto;">' +
                        '<h2 style="font-family:DM Sans,sans-serif;font-size:1.6rem;font-weight:700;margin-bottom:1.2rem;">Settings</h2>' +

                        '<div style="'+glass+'">' +
                        '<h3 style="'+secTitle+'">Notifications</h3>' +
                        '<div style="'+rowStyle+borderBot+'">' +
                        '<div><div style="'+label+'">On-Screen Alerts</div><div style="'+sub+'">Show dangerous condition warnings in the app</div></div>' +
                        '<button id="settingsAlertBtn" style="'+btnOff+'">Off</button>' +
                        '</div>' +
                        '</div>' +

                        '<div style="'+glass+'">' +
                        '<h3 style="'+secTitle+'">Reports</h3>' +
                        '<div style="'+rowStyle+borderBot+'">' +
                        '<div><div style="'+label+'">Print Report</div><div style="'+sub+'">Print or save a field conditions report as PDF</div></div>' +
                        '<button id="settingsPrintBtn" style="'+btnOn+'">Print</button>' +
                        '</div>' +
                        '</div>' +

                        '<div style="'+glass+'">' +
                        '<h3 style="'+secTitle+'">About</h3>' +
                        '<div style="font-size:1rem;opacity:0.6;line-height:1.8;">' +
                        'AquaTech Weather v1.5.1<br>AquaTech Eco Consultants<br>Real-time weather, tides, marine forecast & safety alerts' +
                        '</div>' +
                        '</div>' +

                        '</div>';
                    document.querySelector('main').appendChild(sp);

                    // Alert toggle — uses the web app notificationsEnabled flag
                    document.getElementById('settingsAlertBtn').addEventListener('click',function(){
                        notificationsEnabled=!notificationsEnabled;
                        this.textContent=notificationsEnabled?'On':'Off';
                        this.style.cssText=notificationsEnabled?'"+btnOn+"':'"+btnOff+"';
                        // Also sync the hidden header button
                        var nb=document.getElementById('notifyBtn');
                        if(nb){
                            nb.style.background=notificationsEnabled?'linear-gradient(135deg,var(--atec-green),var(--atec-green-light))':'linear-gradient(135deg,var(--atec-blue),var(--atec-blue-light))';
                            nb.innerHTML=notificationsEnabled?'\\ud83d\\udd14 ON':'\\ud83d\\udd14 Alerts';
                        }
                        // Show confirmation banner
                        var banner=document.createElement('div');
                        banner.style.cssText='position:fixed;top:20px;left:50%;transform:translateX(-50%);padding:14px 28px;border-radius:14px;font-size:1.1rem;font-weight:700;color:white;z-index:99999;transition:opacity 0.5s;'+(notificationsEnabled?'background:linear-gradient(135deg,#4CB848,#6DD468);':'background:rgba(255,255,255,0.2);backdrop-filter:blur(10px);');
                        banner.textContent=notificationsEnabled?'\\u2705 Alerts Enabled — You will see on-screen warnings for dangerous conditions':'Alerts Disabled';
                        document.body.appendChild(banner);
                        setTimeout(function(){banner.style.opacity='0';},2500);
                        setTimeout(function(){banner.remove();},3000);
                    });

                    // Print button — uses native print via message handler
                    document.getElementById('settingsPrintBtn').addEventListener('click',function(){
                        document.body.className=document.body.className.replace(/tab-\\w+/g,'').trim();
                        setTimeout(function(){
                            if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.nativePrint){
                                window.webkit.messageHandlers.nativePrint.postMessage('print');
                            }
                        },300);
                        setTimeout(function(){ document.body.classList.add('tab-settings'); },2000);
                    });
                }
                // Sync alert button state on tab switch
                setTimeout(function(){
                    var sb=document.getElementById('settingsAlertBtn');
                    if(sb){
                        sb.textContent=(typeof notificationsEnabled!=='undefined'&&notificationsEnabled)?'On':'Off';
                        sb.style.background=(typeof notificationsEnabled!=='undefined'&&notificationsEnabled)?'linear-gradient(135deg,#4CB848,#6DD468)':'rgba(255,255,255,0.15)';
                    }
                },100);
                window.scrollTo({top:0,behavior:'smooth'});
            })();
            """
        }
    }
}

// MARK: - Main View

struct ContentView: View {
    @State private var selectedTab: AppTab = .dashboard
    @State private var isLoading = true
    @StateObject private var webViewStore = WebViewStore()

    var body: some View {
        ZStack {
            Color(hex: "0d1f2d").ignoresSafeArea()

            VStack(spacing: 0) {
                DashboardWebView(
                    url: URL(string: "https://aquatech-dashboard.onrender.com")!,
                    isLoading: $isLoading,
                    webViewStore: webViewStore
                )
                #if os(macOS)
                .padding(.top, 1)
                #endif

                tabBar
            }
            #if os(iOS)
            .ignoresSafeArea(edges: .top)
            #endif

            if isLoading {
                SplashView()
                    .transition(.opacity)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            webViewStore.runJS(tab.navigationJS)
        }
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted { print("ATEC: Push notifications authorized") }
            }
        }
    }

    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                TabButton(tab: tab, isSelected: selectedTab == tab) {
                    selectedTab = tab
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            ZStack {
                Color(hex: "0a1520").opacity(0.95)
                RoundedRectangle(cornerRadius: 0)
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
            }
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.white.opacity(0.08)),
            alignment: .top
        )
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    #if os(macOS)
    @State private var hovering = false
    #endif

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(hex: "4CB848") : .white.opacity(0.4))
                Text(tab.rawValue)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(hex: "4CB848") : .white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            #if os(macOS)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering && !isSelected ? Color.white.opacity(0.05) : .clear)
            )
            .onHover { hovering = $0 }
            #endif
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Splash

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(hex: "0d1f2d").ignoresSafeArea()
            VStack(spacing: 20) {
                Image("BrandIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                Text("AquaTech Weather")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.5))
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - WebView Store

class WebViewStore: ObservableObject {
    weak var webView: WKWebView?
    func reload() { webView?.reload() }
    func goBack() { webView?.goBack() }
    func runJS(_ js: String) { webView?.evaluateJavaScript(js, completionHandler: nil) }
}

// MARK: - CSS/JS Overrides

enum NativeOverrides {
    static let css: String = """
    /* === Base: hide web chrome === */
    header { display: none !important; }
    .dashboard-title { display: none !important; }
    .dashboard-subtitle { display: none !important; }
    .page-header {
        display: block !important;
        margin-bottom: 0.5rem !important;
        padding-top: 0.3rem !important;
    }
    .page-header > div:first-child { display: none !important; }

    /* Location panel full-width */
    .location-panel {
        width: 100% !important;
        border-radius: 14px !important;
        min-width: unset !important;
        box-sizing: border-box !important;
    }

    .card { border-radius: 14px !important; }
    .panel { border-radius: 14px !important; }
    main { padding: 0.5rem 0.6rem !important; }
    .grid { gap: 0.6rem !important; }

    /* === GLOBAL: boost all text brightness === */
    body {
        font-size: 26px !important;
        color: #ffffff !important;
    }
    /* Force all text to be bright white */
    .card *, .panel *, .grid *, main * {
        color: #ffffff !important;
    }
    /* Labels get a soft white — still very readable */
    .card-title, .conditions-label, .weather-detail-label,
    .tide-label, .sun-label, .panel-sub, .forecast-date,
    .forecast-precip, .tide-next, .location-panel-title,
    .hourly-time, .wind-gust, .alert-detail, .footer {
        color: rgba(255,255,255,0.9) !important;
    }

    /* === MASSIVE readable fonts === */
    .card-title { font-size: 1.6rem !important; font-weight: 700 !important; letter-spacing: 0.03em !important; }
    .card-icon { width: 50px !important; height: 50px !important; font-size: 1.5rem !important; }
    .weather-temp { font-size: 6rem !important; font-weight: 800 !important; }
    .weather-desc { font-size: 1.8rem !important; font-weight: 600 !important; }
    .weather-icon { font-size: 5.5rem !important; }
    .weather-detail-label { font-size: 1.5rem !important; font-weight: 700 !important; letter-spacing: 0.04em !important; }
    .weather-detail-value { font-size: 2.6rem !important; font-weight: 800 !important; }
    .tide-status { font-size: 1.8rem !important; font-weight: 700 !important; }
    .tide-next { font-size: 1.5rem !important; }
    .tide-time { font-size: 2rem !important; font-weight: 800 !important; }
    .tide-height { font-size: 1.6rem !important; font-weight: 700 !important; }
    .tide-label { font-size: 1.3rem !important; }
    .conditions-row { font-size: 2.2rem !important; padding: 0.6rem 0 !important; }
    .conditions-label { font-size: 2rem !important; font-weight: 700 !important; }
    .conditions-value { font-size: 2.2rem !important; font-weight: 800 !important; }
    .conditions-icon { font-size: 1.8rem !important; }
    .conditions-dot { font-size: 1.4rem !important; }
    .forecast-date { font-size: 1.4rem !important; font-weight: 700 !important; }
    .forecast-icon { font-size: 2.4rem !important; }
    .forecast-temps { font-size: 1.7rem !important; font-weight: 700 !important; }
    .forecast-precip { font-size: 1.5rem !important; font-weight: 700 !important; }
    .forecast-high { font-weight: 800 !important; }
    .panel-header h3 { font-size: 1.7rem !important; font-weight: 700 !important; }
    .panel-sub { font-size: 1.3rem !important; }
    .location-panel-title { font-size: 1.3rem !important; font-weight: 700 !important; letter-spacing: 0.05em !important; }
    .location-input { font-size: 1.5rem !important; }
    .location-name { font-size: 2rem !important; font-weight: 800 !important; }
    .location-coords { font-size: 1.2rem !important; }
    .quick-loc { font-size: 1.6rem !important; padding: 0.7rem 1.2rem !important; border-radius: 10px !important; }
    .saved-projects-title { font-size: 1.4rem !important; font-weight: 700 !important; }
    .hourly-time { font-size: 1.4rem !important; }
    .hourly-temp { font-size: 1.7rem !important; font-weight: 800 !important; }
    .hourly-icon { font-size: 2rem !important; }
    .wind-speed { font-size: 3.2rem !important; font-weight: 800 !important; }
    .wind-gust { font-size: 1.6rem !important; }
    .water-temp-value { font-size: 3.2rem !important; font-weight: 800 !important; }
    .sun-time { font-size: 2.2rem !important; font-weight: 800 !important; }
    .sun-label { font-size: 1.4rem !important; }
    .alert-title { font-size: 1.7rem !important; font-weight: 700 !important; }
    .alert-detail { font-size: 1.4rem !important; }
    .footer { font-size: 1.2rem !important; }
    .heat-index-value, .heat-index-label { font-size: 1.8rem !important; font-weight: 700 !important; }
    .search-btn, .location-btn { font-size: 1.4rem !important; }
    select, input { font-size: 1.4rem !important; }

    /* Viewing banner: large and readable with nav arrows */
    .viewing-banner { font-size: 1.6rem !important; font-weight: 700 !important; padding: 0.6rem 0.8rem !important; }
    .viewing-banner .banner-nav { width: 44px !important; height: 44px !important; font-size: 1.6rem !important; }
    .viewing-banner .banner-date { font-size: 1.5rem !important; }

    /* Selected hourly item */
    .hourly-item.selected { border: 2px solid var(--atec-green) !important; background: linear-gradient(135deg, rgba(0,200,150,0.25), rgba(0,150,200,0.15)) !important; box-shadow: 0 0 8px rgba(0,200,150,0.3) !important; }

    /* Export modal must be visible over everything */
    .modal-overlay { z-index: 10000 !important; }
    .modal-overlay.show { display: flex !important; }

    ::-webkit-scrollbar { width: 6px; }
    ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 3px; }
    ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.3); }
    .login-overlay { top: 0 !important; }

    /* === TAB: Dashboard === */
    /* Show: location panel, weather card, conditions card, alerts */
    /* Hide: all panels, tide, forecast-10day, wind, water, sun */
    .tab-dashboard .panel { display: none !important; }
    .tab-dashboard .tide-card { display: none !important; }
    .tab-dashboard .forecast-card { display: none !important; }
    .tab-dashboard .wind-card { display: none !important; }
    .tab-dashboard .water-card { display: none !important; }
    .tab-dashboard .sun-card { display: none !important; }
    .tab-dashboard .viewing-banner { display: flex !important; }

    /* === TAB: Maps === */
    /* Show: windy + radar panels only */
    .tab-maps .page-header { display: none !important; }
    .tab-maps .grid { display: none !important; }
    .tab-maps .viewing-banner { display: flex !important; }
    .tab-maps .panel:has(.hourly-header) { display: none !important; }

    /* === TAB: Marine Forecast === */
    /* Show: viewing banner, 48-hr panel, 10-day forecast, tides, conditions, wind, water, sun, alerts */
    /* Hide: page-header, windy, map, weather card */
    .tab-marine-forecast .page-header { display: none !important; }
    .tab-marine-forecast .panel:has(.windy-header) { display: none !important; }
    .tab-marine-forecast .panel:has(.map-header) { display: none !important; }
    .tab-marine-forecast .weather-card { display: none !important; }

    /* Viewing banner visible on marine forecast tab */
    .tab-marine-forecast .viewing-banner { display: flex !important; }

    /* === TAB: Settings === */
    .tab-settings .page-header { display: none !important; }
    .tab-settings .panel { display: none !important; }
    .tab-settings .grid { display: none !important; }
    .tab-settings .viewing-banner { display: none !important; }
    .tab-settings .safety-alert { display: none !important; }

    /* Settings panel hidden by default, shown on settings tab */
    #nativeSettingsPanel { display: none; padding: 0.5rem 0.6rem; }
    .tab-settings #nativeSettingsPanel { display: block !important; }
    """

    static var js: String {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        // Inject CSS + set initial tab class + fetch 10-day forecast from Open-Meteo
        return """
        (function(){
            var s=document.createElement('style');s.textContent='\(escaped)';document.head.appendChild(s);
            document.body.classList.add('tab-dashboard');

            // 10-Day Forecast from Open-Meteo
            function load10Day(){
                // Get coords from the web app if available, fallback to Tampa
                var lat=window.currentLat||27.9506;
                var lon=window.currentLon||-82.4572;
                var url='https://api.open-meteo.com/v1/forecast?latitude='+lat+'&longitude='+lon
                    +'&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code'
                    +'&temperature_unit=fahrenheit&timezone=America/New_York&forecast_days=10';
                fetch(url).then(function(r){return r.json();}).then(function(data){
                    if(!data.daily)return;
                    var d=data.daily;
                    var days=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
                    var months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                    function wIcon(code){
                        if(code===0)return '☀️';
                        if(code<=2)return '⛅';
                        if(code===3)return '☁️';
                        if(code>=45&&code<=48)return '🌫️';
                        if((code>=51&&code<=57)||(code>=80&&code<=82))return '🌦️';
                        if(code>=61&&code<=67)return '🌧️';
                        if(code>=71&&code<=77)return '❄️';
                        if(code>=95)return '⛈️';
                        return '⛅';
                    }
                    // Find the forecast card
                    var fc=document.querySelector('.forecast-card');
                    if(!fc)return;
                    // Update the title
                    var title=fc.querySelector('.card-title');
                    if(title)title.textContent='10-Day Forecast';
                    // Find or create the forecast body
                    var body=fc.querySelector('.forecast-body')||fc.querySelector('.card-body');
                    if(!body){body=fc;}
                    // Rain % color: white(0%) → yellow(30%) → orange(60%) → red(80%+)
                    function rainColor(pct){
                        if(pct<=15) return 'rgba(255,255,255,0.95)';
                        if(pct<=30) return 'rgb(255,235,120)';
                        if(pct<=50) return 'rgb(255,200,60)';
                        if(pct<=70) return 'rgb(255,140,40)';
                        return 'rgb(255,60,50)';
                    }
                    // Build new forecast rows
                    var html='';
                    for(var i=0;i<d.time.length;i++){
                        var dt=new Date(d.time[i]+'T12:00:00');
                        var dayName=i===0?'Today':days[dt.getDay()];
                        var dateStr=months[dt.getMonth()]+' '+dt.getDate();
                        var hi=Math.round(d.temperature_2m_max[i]);
                        var lo=Math.round(d.temperature_2m_min[i]);
                        var rain=d.precipitation_probability_max[i]||0;
                        var icon=wIcon(d.weather_code[i]);
                        var rc=rainColor(rain);
                        var isSel=i===window.selectedDay;
                        var selStyle=isSel?'background:linear-gradient(135deg,rgba(0,200,150,0.25),rgba(0,150,200,0.15));border-left:4px solid #00C896;box-shadow:0 0 12px rgba(0,200,150,0.3);':'border-left:4px solid transparent;';
                        html+='<div class="forecast-day'+(isSel?' selected':'')+'" onclick="selectDay('+i+')" style="display:flex;align-items:center;justify-content:space-between;padding:12px 8px;cursor:pointer;border-radius:8px;margin:2px 0;transition:all 0.2s ease;'+selStyle+(i<d.time.length-1?'border-bottom:1px solid rgba(255,255,255,0.08);':'')+'">'
                            +'<div style="min-width:70px;"><div class="forecast-date" style="font-weight:700;font-size:1.15rem;">'+dayName+'</div><div style="font-size:0.9rem;opacity:0.7;">'+dateStr+'</div></div>'
                            +'<div style="font-size:2rem;min-width:45px;text-align:center;">'+icon+'</div>'
                            +'<div style="min-width:65px;text-align:center;"><span style="font-size:1.3rem;font-weight:800;color:'+rc+'!important;">💧'+rain+'%</span></div>'
                            +'<div style="min-width:90px;text-align:right;"><span style="font-size:1.3rem;font-weight:800;">'+hi+'°</span><span style="font-size:1.1rem;opacity:0.6;margin-left:6px;">'+lo+'°</span></div>'
                            +'</div>';
                    }
                    // Sync data with web app's weatherData so selectDay() works correctly
                    if(window.weatherData&&window.weatherData.daily){
                        window.weatherData.daily.time=d.time;
                        window.weatherData.daily.temperature_2m_max=d.temperature_2m_max;
                        window.weatherData.daily.temperature_2m_min=d.temperature_2m_min;
                        window.weatherData.daily.precipitation_probability_max=d.precipitation_probability_max;
                        window.weatherData.daily.weather_code=d.weather_code;
                    } else {
                        window.weatherData=data;
                    }
                    // Replace existing forecast rows
                    var existing=fc.querySelectorAll('.forecast-day');
                    existing.forEach(function(el){el.remove();});
                    // Insert after header
                    var header=fc.querySelector('.card-header');
                    if(header){
                        header.insertAdjacentHTML('afterend',html);
                    } else {
                        body.innerHTML=html;
                    }
                }).catch(function(e){console.log('10-day fetch error:',e);});
            }
            // Color-code rain % in the 48-hr hourly forecast too
            function colorize48hr(){
                // Rain color scale: white → yellow → orange → red
                function rainColor(pct){
                    if(pct<=15) return 'rgba(255,255,255,0.95)';
                    if(pct<=30) return 'rgb(255,235,120)';
                    if(pct<=50) return 'rgb(255,200,60)';
                    if(pct<=70) return 'rgb(255,140,40)';
                    return 'rgb(255,60,50)';
                }
                // Target all precip elements in the hourly panel
                document.querySelectorAll('.hourly-precip, .precip-chance, .hourly-rain').forEach(function(el){
                    var txt=el.textContent.replace(/[^0-9]/g,'');
                    var pct=parseInt(txt)||0;
                    el.style.cssText='color:'+rainColor(pct)+'!important;font-weight:700!important;font-size:1.15rem!important;';
                });
                // Also catch any % inside the hourly panel that might use different classes
                var hourlyPanel=document.querySelector('.panel:has(.hourly-header)');
                if(hourlyPanel){
                    hourlyPanel.querySelectorAll('span,div,p').forEach(function(el){
                        var t=el.textContent.trim();
                        if(t.match(/^\\d{1,3}%$/)&&!el.querySelector('*')){
                            var pct=parseInt(t)||0;
                            el.style.cssText='color:'+rainColor(pct)+'!important;font-weight:700!important;font-size:1.15rem!important;';
                        }
                    });
                }
                // Color-code Precip % on dashboard weather card and conditions card
                document.querySelectorAll('.weather-detail-value, .conditions-value').forEach(function(el){
                    var t=el.textContent.trim();
                    if(t.match(/^\\d{1,3}%$/)){
                        var pct=parseInt(t)||0;
                        // Check if label says Precip or Rain
                        var label=el.previousElementSibling||el.parentElement.querySelector('.weather-detail-label, .conditions-label');
                        if(label&&label.textContent.match(/precip|rain|precipitation/i)){
                            el.style.cssText='color:'+rainColor(pct)+'!important;font-weight:800!important;';
                        }
                    }
                });
            }

            // Sync safety alert banners AND NWS alerts into the Alerts card
            function syncAlerts(){
                var alertsCard=document.querySelector('.alerts-card');
                if(!alertsCard)return;
                var body=alertsCard.querySelector('.card-body')||alertsCard;
                var html='';
                var hasAlerts=false;

                // 1. Sync safety-alert banners (wind, heat, lightning)
                var banners=document.querySelectorAll('.safety-alert.show');
                banners.forEach(function(b){
                    hasAlerts=true;
                    var title=b.querySelector('.alert-title');
                    var detail=b.querySelector('.alert-detail');
                    var icon=b.querySelector('.alert-icon');
                    var borderColor='var(--warning)';
                    if(b.classList.contains('heat'))borderColor='var(--danger)';
                    if(b.classList.contains('lightning'))borderColor='#A855F7';
                    if(b.classList.contains('wind'))borderColor='#94A3B8';
                    html+='<div class="alert-item synced" style="border-left-color:'+borderColor+';">'
                        +(icon?icon.textContent+' ':'')+
                        '<strong>'+(title?title.textContent:'Alert')+'</strong><br>'
                        +(detail?detail.textContent:'')
                        +'</div>';
                });

                // 2. Sync NWS alerts from alertsContent (Small Craft Advisory, etc.)
                var nwsItems=document.querySelectorAll('#alertsContent .alert-item:not(.synced)');
                nwsItems.forEach(function(item){
                    hasAlerts=true;
                    html+='<div class="alert-item synced" style="border-left-color:var(--danger);">'+item.innerHTML+'</div>';
                });

                // Hide original alertsContent to avoid showing both originals and synced copies
                var alertsContentEl=document.getElementById('alertsContent');
                if(alertsContentEl)alertsContentEl.style.display=nwsItems.length?'none':'';

                var noAlerts=alertsCard.querySelector('.no-alerts');
                // Remove old synced items
                var existing=alertsCard.querySelectorAll('.alert-item.synced');
                existing.forEach(function(el){el.remove();});

                if(hasAlerts){
                    if(noAlerts)noAlerts.style.display='none';
                    var header=alertsCard.querySelector('.card-header');
                    if(header){
                        var wrapper=document.createElement('div');
                        wrapper.innerHTML=html;
                        wrapper.querySelectorAll('.alert-item').forEach(function(el){
                            header.insertAdjacentElement('afterend',el);
                        });
                    }
                } else {
                    if(noAlerts)noAlerts.style.display='';
                }
            }

            // Hook into selectDay to re-render forecast with updated selected styling
            var origSelectDay=window.selectDay;
            if(typeof origSelectDay==='function'){
                window.selectDay=function(i){
                    origSelectDay(i);
                    setTimeout(load10Day,100);
                };
            }

            // Auto-enable notifications in native app (permissions handled by iOS)
            setTimeout(function(){
                window.notificationsEnabled=true;
                var btn=document.getElementById('notifyBtn');
                if(btn){
                    btn.style.background='linear-gradient(135deg, var(--atec-green), var(--atec-green-light))';
                    btn.innerHTML='🔔 ON';
                }
            },1500);

            // Run after page loads, with a delay to let the web app initialize
            setTimeout(load10Day,2000);
            setTimeout(colorize48hr,2500);
            setTimeout(syncAlerts,3000);
            // Re-run periodically to catch dynamic updates
            setInterval(colorize48hr,5000);
            setInterval(syncAlerts,5000);
            // Also re-run when location changes
            var origFetch=window.fetchWeatherData;
            if(typeof origFetch==='function'){
                window.fetchWeatherData=function(){
                    var result=origFetch.apply(this,arguments);
                    setTimeout(load10Day,3000);
                    setTimeout(colorize48hr,3500);
                    setTimeout(syncAlerts,4000);
                    return result;
                };
            }
        })();
        """
    }
}

// MARK: - WebView (macOS)

#if os(macOS)
struct DashboardWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @ObservedObject var webViewStore: WebViewStore

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let script = WKUserScript(
            source: NativeOverrides.js,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "nativePrint")
        config.userContentController.add(context.coordinator, name: "nativeNotify")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.setValue(false, forKey: "drawsBackground")
        wv.load(URLRequest(url: url))
        DispatchQueue.main.async { webViewStore.webView = wv }
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: DashboardWebView
        init(_ p: DashboardWebView) { parent = p }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "nativePrint" {
                guard let webView = parent.webViewStore.webView else { return }
                let printOp = webView.printOperation(with: NSPrintInfo.shared)
                printOp.showsPrintPanel = true
                printOp.showsProgressPanel = true
                printOp.run()
            }
            if message.name == "nativeNotify", let dict = message.body as? [String: String] {
                let title = dict["title"] ?? "ATEC Weather"
                let body = dict["body"] ?? ""
                let tag = dict["tag"] ?? "atec-alert"
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(identifier: tag, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(NativeOverrides.js, completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.parent.isLoading = false
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
#else

// MARK: - WebView (iOS)

struct DashboardWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @ObservedObject var webViewStore: WebViewStore

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let script = WKUserScript(
            source: NativeOverrides.js,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)
        config.userContentController.add(context.coordinator, name: "nativePrint")
        config.userContentController.add(context.coordinator, name: "nativeNotify")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.bounces = true
        wv.load(URLRequest(url: url))
        DispatchQueue.main.async { webViewStore.webView = wv }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: DashboardWebView
        init(_ p: DashboardWebView) { parent = p }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "nativePrint" {
                guard let webView = parent.webViewStore.webView else { return }
                let printFormatter = webView.viewPrintFormatter()
                let printController = UIPrintInteractionController.shared
                printController.printFormatter = printFormatter
                printController.printInfo = {
                    let info = UIPrintInfo(dictionary: nil)
                    info.jobName = "AquaTech Weather Report"
                    info.outputType = .general
                    return info
                }()
                printController.present(animated: true)
            }
            if message.name == "nativeNotify", let dict = message.body as? [String: String] {
                let title = dict["title"] ?? "ATEC Weather"
                let body = dict["body"] ?? ""
                let tag = dict["tag"] ?? "atec-alert"
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(identifier: tag, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(NativeOverrides.js, completionHandler: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.parent.isLoading = false
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
#endif

// MARK: - Color Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

#Preview {
    ContentView()
}
