---
tür: açık-karar-kaydı
durum: aktif
kapsam: Kaynak çelişkileri, eksik ürün kararları ve doğrulama ihtiyaçları
kaynaklar:
  - Kullanıcının ana tasarım özeti
  - PROJE.md
  - Taslak_fikir.md
  - docs/*.md
son_güncelleme: 2026-07-18
etiketler: [gdd, gdd/acik-karar]
---

# Çelişki ve Açık Karar Kaydı

Bu kayıt karar üretmez. Her madde, ürün sahibi onayı veya tanımlı prototip kanıtı gelene kadar açık kalır.

## A-001 — Uzak şehirde tesis kurmak için araç şartı

- **Kaynak:** `docs/04_KARARLAR_VE_ACIK_SORULAR.md`, D-021 araç isterken D-027 araç gerekmediğini söyler.
- **Etki:** Genişleme maliyeti, oyuncunun önceden konumlandırma ihtiyacı ve tesis kurulum akışı farklılaşır.
- **Karar:** Hedef şehirde şirket aracı aranmaz. Kuruluş; para, süre, izin ve stratejik erişim koşullarıyla yapılır.
- **Durum:** Karara bağlandı — [[01 - Karar Günlüğü#K-006 — Uzak şehirde tesis kuruluşu]]

## A-002 — Deponun tek veya ikinci uzmanlığı

- **Kaynak:** `docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md` ve `docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md` seviye 2'de tek dal tanımlar; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` olgun tesiste ikinci yan rol önermektedir.
- **Etki:** Tesis çeşitliliği, geri dönüş maliyeti, ağ esnekliği ve veri modeli etkilenir.
- **Öneri:** İlk uzmanlık kalıcı ana rol; ikinci rolün geç oyun modülü mü, tam uzmanlık mı olduğu denge prototipiyle sınansın.
- **Durum:** Açık

## A-003 — Standart sözleşmede araç sayısı mı kapasite/SLA mı?

- **Kaynak:** `docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md` sürekli şehir sözleşmesinde minimum araç sayısı kullanır; D-032 ve `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` hacim, sıklık, kapasite ve SLA'yı esas alır.
- **Etki:** Filo çeşitliliği, kapasite havuzları, dış kaynak kullanımı ve oyuncu özgürlüğü değişir.
- **Karar:** Standart sözleşmeler kapasite, sefer sıklığı ve SLA ister. Yalnız `dedicated fleet` sözleşmeleri açık araç sayısı veya ayrılmış filo şartı koyabilir.
- **Durum:** Karara bağlandı — [[01 - Karar Günlüğü#K-007 — Standart sözleşmelerin filo şartı]]

## A-004 — Devam eden ve sabit süreli sözleşmelerin birlikte kullanımı

- **Kaynak:** `docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md` çoğunlukla devam eden hatlar ve ayrı süreli fırsatlar önerir; `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md` sürelerin şirket aşamasıyla uzamasını da tanımlar.
- **Etki:** Portföy riski, yenileme, rota kapanışı, gelir öngörülebilirliği ve içerik üretimi etkilenir.
- **Öneri:** İki ticari türün kesin oranı, aynı rota planında karıştırılma kuralı ve yenileme davranışı oynanabilir testle belirlenmeli.
- **Durum:** Açık

## A-005 — Ağır araç için ticari saha

- **Kaynak:** D-027, `docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md` ve `docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md`; depo, HQ kiralık alanı ve üçüncü taraf ticari saha seçenekleri tam bağlanmamıştır.
- **Etki:** Ağır filoya geçiş, sabit gider, şehirde fiziksel varlık ve depo değer önerisi değişir.
- **Öneri:** Ticari sahanın ayrı tesis mi, kiralık kapasite sözleşmesi mi olduğu; sınırları ve depo karşısındaki maliyeti kararlaştırılmalı.
- **Durum:** Açık

## A-006 — Büyük ölçekte toplulaştırma ayrıntısı

- **Kaynak:** Kullanıcının ana tasarım özeti; `docs/02_OYUN_TASARIMI.md`; `docs/05_GORSEL_YON_VE_HARITA.md`; `docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md`.
- **Etki:** Simülasyon doğruluğu, performans, kayıt boyutu, görsel temsil ve hata açıklanabilirliği etkilenir.
- **Öneri:** Toplulaştırma eşiği, korunan değişmezler, detay seviyesine iniş ve deterministik ayrıştırma kuralları teknik prototiple doğrulansın.
- **Durum:** Açık

## A-007 — Gerçek veya kurgusal coğrafya verisi

- **Kaynak:** `Taslak_fikir.md` gerçek dünyadan ilham alan yaklaşımı; S-005 kurgusal test bölgesini; `docs/05_GORSEL_YON_VE_HARITA.md` çalışan prototipte yaklaşık 140 gerçek ticaret şehri ve dünya omurgasını anlatır.
- **Etki:** Marka tonu, veri lisansı, denge özgürlüğü, yerelleştirme ve oyuncu beklentisi etkilenir.
- **Karar:** Gerçek şehir konumlarını, bölgesel ilişkileri ve ana koridorları tanınabilir ölçüde koruyan özgün, stilize 2D oyun coğrafyası kullanılacaktır. Canlı MapKit/navigasyon haritası kullanılmaz. Kanonik yol grafı çevrimdışı üretilir, sürümlenir ve veri kaynağı/lisans kökeniyle birlikte izlenir.
- **Durum:** Karara bağlandı — [[01 - Karar Günlüğü#K-008 — Harita sunumu ve kanonik yol ağı]]

## A-008 — Başarısızlık, iflas ve geri dönüş

- **Kaynak:** `docs/02_OYUN_TASARIMI.md` toparlanabilir başarısızlık önerir; S-004 tam iflası açık bırakır; kısa testte nakit iflası son koşulu önerilir.
- **Etki:** Zorluk, oyuncu kaybı, kredi/yatırımcı sistemleri ve kampanya sonu belirlenir.
- **Öneri:** Prototip için test sonu ile nihai kampanyadaki şirket tasfiyesi ayrıştırılarak üç geri dönüş seviyesi kullanıcı testine sunulsun.
- **Durum:** Açık

## A-009 — Native kayıt teknolojisi: SwiftData veya SQLite

- **Kaynak:** `docs/08_TEST_ARACLARI_VE_LOGBOOK.md` browser için D1 ve iOS için `Codable` kayıt modeli tanımlar; native kalıcılık teknolojisini kesinleştirmez.
- **Etki:** Şema geçişleri, performans, sorgulama, test altyapısı, CloudKit olasılığı ve bakım maliyeti etkilenir.
- **Öneri:** Kayıt boyutu ve sorgu desenleri ölçülmeden seçim yapılmasın; SwiftData ile doğrudan SQLite katmanı küçük spike'larla karşılaştırılsın.
- **Durum:** Açık

## A-010 — Monetizasyon modeli

- **Kaynak:** `Taslak_fikir.md` ücretsiz temel oyun, premium yükseltme, kozmetik ve üyelik önerir; D-005 bunların çelişen ürün davranışları olduğunu belirtip prototipten erteler.
- **Etki:** Oturum, çevrimdışı ilerleme, içerik temposu, ekonomi adaleti ve mağaza kapsamı değişir.
- **Öneri:** Çekirdek retention verisi sonrası premium, demo + tek satın alma ve adil ücretsiz modeller ayrı ürün senaryoları olarak değerlendirilmelidir.
- **Durum:** Açık

## A-011 — Yaş derecelendirmesi ve hedef kitle

- **Kaynak:** `Taslak_fikir.md` 18+ der; `docs/01_URUN_VIZYONU.md` ve D-007 yaş yerine motivasyon temelli hedeflemeyi önerir.
- **Etki:** Mağaza konumlandırması, içerik tonu, pazarlama ve ebeveyn kontrolleri etkilenir.
- **Öneri:** Hedef oyuncu profili ile resmi mağaza yaş derecesi ayrı tanımlansın; içerik tamamlanınca derecelendirme anketi uygulanmalı.
- **Durum:** Açık

## A-012 — Zaman hızları (ürün kilidi)

- **Kaynak:** Eski metinlerde 1 sn = 5 dk + 8× / tasarım özetinde 5× çakışması vardı.
- **Karar (2026-07-19):** Ürün temposu **0× / 1× / 3× / 6×**; taban **1 gerçek saniye = 10 oyun dakikası**; 3× = 30 dk/sn, 6× = 60 dk/sn. Kod: `SimulationSpeed` (`GameSession.swift`).
- **Etki:** UI etiketleri çarpanla uyumlu; harita hareketi aynı tick’e bağlı.
- **Durum:** Karara bağlandı

## Özet

- **Açık karar:** 8
- **Karara bağlanan:** 4
- **Son inceleme:** 2026-07-19

#gdd #gdd/acik-karar
