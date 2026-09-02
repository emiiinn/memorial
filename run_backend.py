import os
import sys
import json
import time
import traceback
import uvicorn
from query_logger import log_sorgu

print("=" * 65)
print(" MEMORIAL RAG + SQL FASTAPI BACKEND")
print("=" * 65)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
NOTEBOOK_PATH = os.path.join(BASE_DIR, "query.ipynb")

if not os.path.exists(NOTEBOOK_PATH):
    print(f"Hata: {NOTEBOOK_PATH} dosyasi bulunamadi.")
    sys.exit(1)

print("query.ipynb modulleri ve veritabani baglantilari yukleniyor...")
with open(NOTEBOOK_PATH, "r", encoding="utf-8") as f:
    nb = json.load(f)

global_scope = {"__name__": "__main__"}

for idx, cell in enumerate(nb.get("cells", [])):
    if cell.get("cell_type") == "code":
        source_code = "".join(cell.get("source", []))
        if "uvicorn.run(app" in source_code and "threading.Thread" in source_code:
            lines = [l for l in source_code.splitlines() if "threading.Thread" not in l and ".start()" not in l]
            source_code = "\n".join(lines)
        try:
            exec(source_code, global_scope)
        except Exception as e:
            print(f"  [Hucre {idx}] Yuklenirken mesaj: {type(e).__name__} - {e}")

def format_sql_cevap(cevap_raw):
    if cevap_raw is None:
        return None
    if isinstance(cevap_raw, str):
        return cevap_raw
    if isinstance(cevap_raw, (int, float, bool)):
        return str(cevap_raw)
    if isinstance(cevap_raw, list):
        if len(cevap_raw) == 0:
            return "Sorgu sonucunda herhangi bir kayit bulunamadi."
        if all(isinstance(item, dict) for item in cevap_raw):
            formatted_lines = []
            for i, row in enumerate(cevap_raw, 1):
                row_str = " | ".join(f"{k}: {v}" for k, v in row.items())
                formatted_lines.append(f"{i}. {row_str}")
            return "\n".join(formatted_lines)
        return "\n".join(f"- {item}" for item in cevap_raw)
    if isinstance(cevap_raw, dict):
        return "\n".join(f"{k}: {v}" for k, v in cevap_raw.items())
    return str(cevap_raw)

def sor_with_logging(soru: str):
    t0 = time.time()
    etiket = None
    hata_asamasi = None
    hata_detayi = None
    cevap = None

    try:
        try:
            hata_asamasi = "ROUTER (Yonlendirme Asamasi)"
            route_func = global_scope.get("route")
            if not route_func:
                raise NameError("'route' fonksiyonu notebook'ta bulunamadi.")
            d = route_func(soru, ayrinti=True)
            etiket = d.get("etiket")
            print(f"[LOGGED ROUTER] {etiket} ({d.get('kaynak')}, {d.get('sure', 0):.2f}s)")
        except Exception as e:
            hata_detayi = f"{type(e).__name__}: {e}\n{traceback.format_exc()}"
            log_sorgu(soru=soru, etiket=etiket, hata_asamasi=hata_asamasi, hata_detayi=hata_detayi, sure_sn=time.time()-t0)
            raise e

        if etiket == "SQL":
            hata_asamasi = "SQL_AGENT (Veritabani Sorgulama Asamasi)"
            sql_func = global_scope.get("sql_cevapla")
            raw_cevap = sql_func(soru)
            cevap = format_sql_cevap(raw_cevap)
        elif etiket == "RAG":
            hata_asamasi = "RAG_SEARCH (Vektor Veritabani & LLM Asamasi)"
            answer_func = global_scope.get("answer_question")
            raw_cevap, flag = answer_func(soru)
            if flag:
                print(f"[FLAG: {flag}]")
            cevap = format_sql_cevap(raw_cevap)
        else:
            hata_asamasi = "DIGER (Desteklenmeyen Kategori Asamasi)"
            cevap = "Bu soru icin herhangi bir yanit kategorisi eslesmedi."

        sure_sn = time.time() - t0
        log_sorgu(soru=soru, etiket=etiket, cevap=str(cevap), sure_sn=sure_sn)
        return etiket, cevap

    except Exception as e:
        sure_sn = time.time() - t0
        if not hata_detayi:
            hata_detayi = f"{type(e).__name__}: {e}\n{traceback.format_exc()}"
        log_sorgu(soru=soru, etiket=etiket, hata_asamasi=hata_asamasi, hata_detayi=hata_detayi, sure_sn=sure_sn)
        raise e

if "app" in global_scope:
    app = global_scope["app"]
    
    from pydantic import BaseModel
    class SoruModel(BaseModel):
        soru: str

    @app.post("/sor")
    def sor_api_logged(istek: SoruModel):
        try:
            etiket, cevap = sor_with_logging(istek.soru)
            return {"etiket": etiket, "cevap": cevap, "hata": None}
        except Exception as e:
            return {"etiket": None, "cevap": None, "hata": f"{type(e).__name__}: {e}"}

    print("\nDetayli Loglama ve SQL Yanit Formatlama Aktif.")
    print("Sunucu dinleniyor: http://127.0.0.1:8000/sor\n")
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")
else:
    print("Hata: 'app' (FastAPI nesnesi) bulunamadi.")
