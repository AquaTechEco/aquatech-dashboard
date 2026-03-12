import SwiftUI
import WebKit

struct ContentView: View {
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            WebView(url: URL(string: "https://aquatech-dashboard.onrender.com")!, isLoading: $isLoading)
                .ignoresSafeArea()
            
            if isLoading {
                LoadingView()
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1a5276"), Color(hex: "2e86ab"), Color(hex: "48b8a0")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                
                Text("AquaTech Weather")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
                
                Text("Loading dashboard...")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - WebView

#if os(macOS)
struct WebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let css = """
            /* Replace logo with weather icon brand */
            .logo-img { display: none !important; }
            .header-content::before { content: none; }

            /* Restyle header — gradient instead of white block */
            header {
                background: linear-gradient(135deg, #1a5276, #2e86ab) !important;
                border-bottom: none !important;
                padding: 0.5rem 1rem !important;
            }
            .current-time {
                color: white !important;
                -webkit-text-fill-color: white !important;
                background: none !important;
            }
            .header-date { color: rgba(255,255,255,0.8) !important; }

            /* Hide ATEC Weather Station title */
            .dashboard-title { display: none !important; }
            .dashboard-subtitle { display: none !important; }
            .page-header { justify-content: flex-end !important; margin-bottom: 0.6rem !important; }

            /* Soften corners */
            .card { border-radius: 16px !important; }
            .panel { border-radius: 16px !important; }
            .location-panel { border-radius: 16px !important; }

            /* Tighter spacing */
            main { padding: 0.6rem !important; }
            """

            let brandJS = """
            (function() {
                var logo = document.querySelector('.logo-img');
                if (logo) {
                    var brand = document.createElement('div');
                    brand.style.display = 'flex';
                    brand.style.alignItems = 'center';
                    brand.style.gap = '0.5rem';
                    brand.innerHTML = '<span style="font-size:1.8rem;">⛅</span><span style="font-family:DM Sans,sans-serif;font-weight:700;font-size:1.1rem;color:white;letter-spacing:0.02em;">AquaTech Weather</span>';
                    logo.parentNode.replaceChild(brand, logo);
                }
            })();
            """

            let injectCSS = "var style = document.createElement('style'); style.textContent = `\(css)`; document.head.appendChild(style);"

            webView.evaluateJavaScript(injectCSS, completionHandler: nil)
            webView.evaluateJavaScript(brandJS, completionHandler: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
#else
struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.load(URLRequest(url: url))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let css = """
            .logo-img { display: none !important; }
            header {
                background: linear-gradient(135deg, #1a5276, #2e86ab) !important;
                border-bottom: none !important;
                padding: 0.5rem 1rem !important;
            }
            .current-time {
                color: white !important;
                -webkit-text-fill-color: white !important;
                background: none !important;
            }
            .header-date { color: rgba(255,255,255,0.8) !important; }
            .dashboard-title { display: none !important; }
            .dashboard-subtitle { display: none !important; }
            .page-header { justify-content: flex-end !important; margin-bottom: 0.6rem !important; }
            .card { border-radius: 16px !important; }
            .panel { border-radius: 16px !important; }
            .location-panel { border-radius: 16px !important; }
            main { padding: 0.6rem !important; }
            """

            let brandJS = """
            (function() {
                var logo = document.querySelector('.logo-img');
                if (logo) {
                    var brand = document.createElement('div');
                    brand.style.display = 'flex';
                    brand.style.alignItems = 'center';
                    brand.style.gap = '0.5rem';
                    brand.innerHTML = '<span style="font-size:1.8rem;">⛅</span><span style="font-family:DM Sans,sans-serif;font-weight:700;font-size:1.1rem;color:white;letter-spacing:0.02em;">AquaTech Weather</span>';
                    logo.parentNode.replaceChild(brand, logo);
                }
            })();
            """

            let injectCSS = "var style = document.createElement('style'); style.textContent = `\(css)`; document.head.appendChild(style);"

            webView.evaluateJavaScript(injectCSS, completionHandler: nil)
            webView.evaluateJavaScript(brandJS, completionHandler: nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
#endif

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
}
