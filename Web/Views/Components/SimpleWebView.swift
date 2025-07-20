import SwiftUI
import WebKit

struct SimpleWebView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

struct SimpleWebViewTest: View {
    var body: some View {
        VStack {
            Text("Simple WebView Test")
                .padding()
            
            SimpleWebView(url: URL(string: "https://www.google.com")!)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    SimpleWebViewTest()
        .frame(width: 800, height: 600)
}