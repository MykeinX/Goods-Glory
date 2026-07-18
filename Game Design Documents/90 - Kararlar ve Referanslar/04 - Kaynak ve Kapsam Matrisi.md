---
tür: kaynak-kapsam-matrisi
durum: aktif
kapsam: Ana tasarım özetinin 32 bölümü, mevcut kaynaklar ve hedef GDD notları
kaynaklar:
  - Kullanıcının ana tasarım özeti
  - PROJE.md
  - Taslak_fikir.md
  - docs/*.md
son_güncelleme: 2026-07-17
etiketler: [gdd, gdd/kaynak]
---

# Kaynak ve Kapsam Matrisi

Matristeki bölüm sırası ana tasarım özetinin 32 konu alanını GDD bilgi mimarisine taşır. Her wikilink kasada bulunan en yakın gerçek kanonik nota bağlanır.

| No | Ana özet bölümü | Mevcut kaynaklar | Hedef kanonik not |
|---:|---|---|---|
| 1 | Ürün tanımı ve uzun vadeli vizyon | `Taslak_fikir.md`; `docs/01_URUN_VIZYONU.md` | [[01 - Ürün Vizyonu/01 - Oyun Özeti]] |
| 2 | Oyuncu rolü ve CEO fantezisi | `Taslak_fikir.md`; `docs/01_URUN_VIZYONU.md` | [[01 - Ürün Vizyonu/04 - Oyuncu Fantezisi ve Marka]] |
| 3 | Tasarım sütunları ve stratejik gerilim | `docs/01_URUN_VIZYONU.md`; `docs/02_OYUN_TASARIMI.md` | [[01 - Ürün Vizyonu/02 - Tasarım Sütunları]] |
| 4 | Çekirdek oynanış döngüsü | `Taslak_fikir.md`; `docs/02_OYUN_TASARIMI.md` | [[02 - Çekirdek Oynanış/01 - Ana Oynanış Döngüsü]] |
| 5 | Kanonik sözleşme-yük-aşama-hat modeli | Ana tasarım özeti; `docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md` | [[03 - Lojistik Ağı/01 - Kanonik Lojistik Nesne Modeli]] |
| 6 | İlerleme ve değişen yönetim seviyesi | `docs/02_OYUN_TASARIMI.md`; `docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md` | [[05 - İlerleme ve İçerik/01 - Şirket Büyüme Aşamaları]] |
| 7 | Browser prototip kapsamı ve ölçütleri | `docs/03_BROWSER_PROTOTIP_PLANI.md` | [[08 - Sürüm Kapsamı/01 - İlk Sürüm Kapsamı]]; [[08 - Sürüm Kapsamı/02 - Prototip Hipotezleri]] |
| 8 | Şehir ekonomisi, arz, talep ve pazar | `docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md`; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` | [[04 - Sistemler/01 - İşler, Müşteriler ve Sözleşmeler]]; [[05 - İlerleme ve İçerik/02 - Dünya, Şehirler ve Açılımlar]] |
| 9 | Spot, hat ve hizmet sözleşmeleri | `docs/02_OYUN_TASARIMI.md`; `docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md`; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` | [[04 - Sistemler/01 - İşler, Müşteriler ve Sözleşmeler]] |
| 10 | Yük partileri, stok ve kuyruklar | `docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md` | [[03 - Lojistik Ağı/01 - Kanonik Lojistik Nesne Modeli]] |
| 11 | Taşıma aşamaları ve uçtan uca zincir | `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md`; `docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md` | [[03 - Lojistik Ağı/04 - Doğrudan ve Aktarmalı Taşıma]] |
| 12 | Servis hatları, rotalar ve kapasite havuzları | `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md`; `docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md` | [[04 - Sistemler/02 - Taşıma Hatları ve Konsolidasyon]] |
| 13 | Depolar, terminaller, modüller ve uzmanlıklar | `docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md`; `docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md`; `docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md` | [[04 - Sistemler/04 - Tesisler]] |
| 14 | HQ, tesis personeli ve delegasyon | `docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md`; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` | [[04 - Sistemler/07 - Çalışanlar, Yöneticiler ve Otomasyon]] |
| 15 | Filo, araç, dorse ve ekipman | `docs/02_OYUN_TASARIMI.md`; `docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md`; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` | [[04 - Sistemler/03 - Araçlar ve Ekipman]] |
| 16 | Kara, demiryolu, deniz ve hava | `Taslak_fikir.md`; `docs/02_OYUN_TASARIMI.md`; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` | [[04 - Sistemler/05 - Multimodal Taşımacılık]] |
| 17 | Ekonomi, maliyet, marj ve nakit | `Taslak_fikir.md`; `docs/02_OYUN_TASARIMI.md`; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` | [[04 - Sistemler/06 - Ekonomi ve Finans]] |
| 18 | İtibar, müşteri güveni ve rakip baskısı | `Taslak_fikir.md`; `docs/02_OYUN_TASARIMI.md` | [[04 - Sistemler/10 - Şirket Politikaları ve İtibar]]; [[04 - Sistemler/08 - Rakip Şirketler]] |
| 19 | Dünya olayları, riskler ve krizler | `Taslak_fikir.md`; `docs/02_OYUN_TASARIMI.md` | [[04 - Sistemler/09 - Dünya Olayları ve Risk]] |
| 20 | Zaman, takvim ve hızlar | `docs/02_OYUN_TASARIMI.md`; `docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md` | [[02 - Çekirdek Oynanış/03 - Zaman ve Çevrimdışı İlerleme]] |
| 21 | Başarı, başarısızlık, iflas ve oyun sonu | `docs/02_OYUN_TASARIMI.md`; `docs/04_KARARLAR_VE_ACIK_SORULAR.md` | [[02 - Çekirdek Oynanış/04 - Başarı, Kriz ve Başarısızlık]] |
| 22 | Teknoloji, lisans ve kabiliyetler | `Taslak_fikir.md`; `docs/02_OYUN_TASARIMI.md`; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` | [[05 - İlerleme ve İçerik/03 - Yük Türleri ve Özel Operasyonlar]]; [[04 - Sistemler/07 - Çalışanlar, Yöneticiler ve Otomasyon]] |
| 23 | Dünya, gerçek/kurgusal coğrafya ve harita | `Taslak_fikir.md`; `docs/04_KARARLAR_VE_ACIK_SORULAR.md`; `docs/05_GORSEL_YON_VE_HARITA.md` | [[05 - İlerleme ve İçerik/02 - Dünya, Şehirler ve Açılımlar]]; [[06 - UX ve Görsel Tasarım/02 - Dünya Haritası ve Görsel Dil]] |
| 24 | Görsel yön ve semantik yakınlaştırma | `Taslak_fikir.md`; `docs/05_GORSEL_YON_VE_HARITA.md` | [[06 - UX ve Görsel Tasarım/02 - Dünya Haritası ve Görsel Dil]] |
| 25 | Bilgi mimarisi, navigasyon ve ekranlar | `docs/03_BROWSER_PROTOTIP_PLANI.md`; `docs/05_GORSEL_YON_VE_HARITA.md` | [[06 - UX ve Görsel Tasarım/01 - Bilgi Mimarisi ve Ekranlar]] |
| 26 | Kuruluş, öğretim ve ilk oturum | `docs/03_BROWSER_PROTOTIP_PLANI.md`; `docs/04_KARARLAR_VE_ACIK_SORULAR.md` | [[02 - Çekirdek Oynanış/02 - Başlangıç Deneyimi]] |
| 27 | Erişilebilirlik, diller ve global pazar | `Taslak_fikir.md`; `docs/03_BROWSER_PROTOTIP_PLANI.md`; `docs/05_GORSEL_YON_VE_HARITA.md` | [[06 - UX ve Görsel Tasarım/03 - Erişilebilirlik ve Mobil Kullanım]] |
| 28 | Hedef kitle, oturum ve yaş | `Taslak_fikir.md`; `docs/01_URUN_VIZYONU.md`; `docs/04_KARARLAR_VE_ACIK_SORULAR.md` | [[01 - Ürün Vizyonu/03 - Hedef Oyuncu ve Platform]] |
| 29 | İş modeli ve monetizasyon | `Taslak_fikir.md`; `docs/03_BROWSER_PROTOTIP_PLANI.md`; `docs/04_KARARLAR_VE_ACIK_SORULAR.md` | [[08 - Sürüm Kapsamı/03 - Sonraki Sürümler ve Kapsam Dışı]] |
| 30 | Data-driven mimari, simülasyon ve determinizm | `Taslak_fikir.md`; `docs/03_BROWSER_PROTOTIP_PLANI.md`; `docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md` | [[07 - Teknik Tasarım/03 - Veri Odaklı İçerik]]; [[07 - Teknik Tasarım/02 - Simülasyon Çekirdeği ve Determinizm]] |
| 31 | Kayıt/yükleme, Logbook ve test araçları | `docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md`; `docs/08_TEST_ARACLARI_VE_LOGBOOK.md` | [[07 - Teknik Tasarım/04 - Kayıt, iCloud ve Yaşam Döngüsü]]; [[08 - Sürüm Kapsamı/04 - Browser Prototipi Uygulama Notları]] |
| 32 | Native iOS geçişi ve GDD yönetişimi | `PROJE.md`; `Taslak_fikir.md`; `docs/03_BROWSER_PROTOTIP_PLANI.md`; tüm kaynaklar | [[07 - Teknik Tasarım/01 - iOS Mimarisi]]; [[08 - Sürüm Kapsamı/04 - Browser Prototipi Uygulama Notları]]; [[90 - Kararlar ve Referanslar/06 - Belge Yazım ve Statü Standardı]] |

## Kaynak kapsamı

- Taranan kök belgeler: `PROJE.md`, `Taslak_fikir.md`
- Taranan çalışma belgeleri: `docs/01_URUN_VIZYONU.md`–`docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md`
- Yönetim kayıtlarında kaynak metin değiştirilmez; çelişkiler [[02 - Çelişki ve Açık Karar Kaydı]] üzerinden izlenir.

#gdd #gdd/kaynak
