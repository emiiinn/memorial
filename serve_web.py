import os
import sys
import http.server
import socketserver
import webbrowser

PORT = 3000
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
WEB_DIR = os.path.join(BASE_DIR, "chatbot_web", "build", "web")

class CustomHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEB_DIR, **kwargs)

    def end_headers(self):
        # CORS headers to avoid any local origin restrictions
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

def run_server():
    if not os.path.exists(WEB_DIR):
        print(f"Hata: Web derleme dizini bulunamadi ({WEB_DIR})")
        print("Lutfen once 'flutter build web' komutunu calistirin.")
        sys.exit(1)

    print("\n" + "=" * 65)
    print(" 🏥 MEMORIAL SAGLIK GRUBU - CHATBOT WEB ARAYUZU")
    print("=" * 65)
    print(f" 🌐 Web Arayüzü Adresi  : http://127.0.0.1:{PORT}")
    print(f" ⚡ FastAPI Backend Adresi: http://127.0.0.1:8000/sor")
    print("=" * 65 + "\n")

    # Automatically open browser
    try:
        webbrowser.open(f"http://127.0.0.1:{PORT}")
    except Exception as e:
        print(f"Tarayici otomatik acilamadi: {e}")

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), CustomHandler) as httpd:
        print(f"Lokal HTTP sunucusu aktif. Kapatmak icin Ctrl+C basiniz.\n")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nSunucu kapatildi.")

if __name__ == "__main__":
    run_server()
