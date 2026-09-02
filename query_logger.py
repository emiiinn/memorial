import os
import json
import time
import traceback
from datetime import datetime

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE_JSON = os.path.join(BASE_DIR, "sorgu_loglari.jsonl")
LOG_FILE_TEXT = os.path.join(BASE_DIR, "sorgu_loglari.log")

def log_sorgu(
    soru: str,
    etiket: str = None,
    cevap: str = None,
    hata_asamasi: str = None,
    hata_detayi: str = None,
    sure_sn: float = None,
    ek_bilgi: dict = None
):
    """
    Kullanıcının sorduğu soruyu, verilen yanıtı, hata aşamasını ve detaylarını
    belirgin bir şekilde dosyaya kaydeder.
    """
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    durum = "BAŞARILI" if hata_detayi is None else "HATA"

    log_entry = {
        "zaman": timestamp,
        "durum": durum,
        "sorulan_soru": soru,
        "etiket": etiket or "BELİRSİZ",
        "cevap": cevap,
        "sure_saniye": round(sure_sn, 2) if sure_sn else None,
        "hata_asamasi": hata_asamasi,
        "hata_detayi": hata_detayi,
        "ek_bilgi": ek_bilgi or {}
    }

    # 1. JSON Lines Formatı (Tam Soru Metni İle)
    try:
        with open(LOG_FILE_JSON, "a", encoding="utf-8") as f:
            f.write(json.dumps(log_entry, ensure_ascii=False) + "\n")
            f.flush()
            os.fsync(f.fileno())
    except Exception as e:
        print(f"[LOGGER HATA] JSONL dosyasına yazılamadı: {e}")

    # 2. Okunabilir Metin Formatı (Soru En Üstte Vurgulu Olarak)
    try:
        with open(LOG_FILE_TEXT, "a", encoding="utf-8") as f:
            f.write("=" * 80 + "\n")
            f.write(f"🕒 ZAMAN        : {timestamp}\n")
            f.write(f"❓ SORULAN SORU : \"{soru}\"\n")
            f.write(f"📌 DURUM        : {durum}\n")
            f.write(f"🏷️  ETİKET       : {etiket or 'Belirtilmedi'}\n")
            if sure_sn:
                f.write(f"⏱️  İŞLEM SÜRESİ: {sure_sn:.2f} saniye\n")
            if cevap:
                f.write("-" * 80 + "\n")
                f.write(f"💬 ÜRETİLEN CEVAP:\n{cevap}\n")
            if hata_asamasi:
                f.write("-" * 80 + "\n")
                f.write(f"⚠️ HATA AŞAMASI : {hata_asamasi}\n")
            if hata_detayi:
                f.write(f"❌ HATA DETAYI  :\n{hata_detayi}\n")
            f.write("=" * 80 + "\n\n")
            f.flush()
            os.fsync(f.fileno())
    except Exception as e:
        print(f"[LOGGER HATA] LOG dosyasına yazılamadı: {e}")

    return log_entry
