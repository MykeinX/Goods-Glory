---
tür: karar-günlüğü
durum: aktif
kapsam: Kesinleşmiş ürün, sistem ve belge kararları
kaynaklar:
  - Kullanıcının ana tasarım özeti
  - PROJE.md
  - Taslak_fikir.md
  - docs/01_URUN_VIZYONU.md
  - docs/02_OYUN_TASARIMI.md
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/04_KARARLAR_VE_ACIK_SORULAR.md
  - docs/05_GORSEL_YON_VE_HARITA.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md
  - docs/08_TEST_ARACLARI_VE_LOGBOOK.md
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md
son_güncelleme: 2026-07-18
etiketler: [gdd, gdd/karar]
---

# Karar Günlüğü

Bu günlük yalnızca açıkça kesinleşmiş kararları tutar. Yeni bir öneri, bu dosyaya yazılmadan önce [[02 - Çelişki ve Açık Karar Kaydı]] içinde değerlendirilir.

## K-001 — Modüler Obsidian GDD yapısı

- **Durum:** Kabul edildi
- **Karar:** GDD; küçük, konu odaklı Markdown notlarından, wikilinklerden ve merkezi yönetim kayıtlarından oluşur. Harici Obsidian eklentisi kullanılmaz.
- **Gerekçe:** Tek kanonik kaynak, izlenebilir karar geçmişi ve bağımsız güncellenebilir sistem notları sağlar.
- **Etkilenen notlar:** [[00 - GDD Ana İndeks]] ve 01–08 klasörlerindeki mevcut GDD notları
- **Kaynak:** Kullanıcının ana tasarım özeti
- **Tarih:** 2026-07-17

## K-002 — Kanonik lojistik alan modeli

- **Durum:** Kabul edildi
- **Karar:** Ana model **sözleşme → yük partisi → taşıma aşaması → servis hattı** zinciridir. Sözleşme müşteriye verilen uçtan uca sözü; yük partisi oluşan fiziksel hacmi; taşıma aşaması kapıdan kapıya operasyon adımını; servis hattı ise şirketin düzenli kapasite hizmetini temsil eder.
- **Sonuç:** Bir sözleşme tek araca veya tek rotaya bağlanmaz. Bir servis hattı, uygun olduğunda birden fazla sözleşmenin yük partisini aynı kapasitede birleştirebilir.
- **Etkilenen notlar:** [[03 - Lojistik Ağı/01 - Kanonik Lojistik Nesne Modeli]], [[04 - Sistemler/01 - İşler, Müşteriler ve Sözleşmeler]], [[03 - Lojistik Ağı/04 - Doğrudan ve Aktarmalı Taşıma]], [[04 - Sistemler/02 - Taşıma Hatları ve Konsolidasyon]]
- **Kaynak:** Kullanıcının ana tasarım özeti; `docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md`
- **Tarih:** 2026-07-17

## K-003 — Hibrit simülasyon ve görünürlük

- **Durum:** Kabul edildi
- **Karar:** Erken ölçekte gerçek araç, konum, yük ve operasyon akışı fiziksel olarak görünürdür. Şirket büyüdükçe tekil nesneler kaybolmaz; güvenli ve açıklanabilir biçimde araç havuzu, kapasite, akış ve kümeler olarak toplulaştırılır. Oyuncu gerektiğinde toplulaştırılmış yapının altındaki gerçek varlıklara inebilir.
- **Sınır:** Toplulaştırma; kapasite, konum, yük uyumluluğu, maliyet, SLA veya risk sonuçlarını değiştiren bir kestirme olamaz.
- **Etkilenen notlar:** [[03 - Lojistik Ağı/03 - Kapasite ve Hibrit Simülasyon]], [[04 - Sistemler/02 - Taşıma Hatları ve Konsolidasyon]], [[04 - Sistemler/03 - Araçlar ve Ekipman]], [[06 - UX ve Görsel Tasarım/02 - Dünya Haritası ve Görsel Dil]], [[07 - Teknik Tasarım/02 - Simülasyon Çekirdeği ve Determinizm]]
- **Kaynak:** Kullanıcının ana tasarım özeti; `docs/02_OYUN_TASARIMI.md`; `docs/05_GORSEL_YON_VE_HARITA.md`; `docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md`
- **Tarih:** 2026-07-17

## K-004 — Oyuncu şirketi yönetir

- **Durum:** Kabul edildi
- **Karar:** Oyuncunun rolü araç sürücüsü değil CEO'dur. Büyüme, aynı tekil işlemin daha çok tekrarı yerine daha büyük kapasite, ağ, hizmet seviyesi, risk ve yatırım kararları açar.
- **Etkilenen notlar:** [[01 - Ürün Vizyonu/04 - Oyuncu Fantezisi ve Marka]], [[05 - İlerleme ve İçerik/01 - Şirket Büyüme Aşamaları]]
- **Kaynak:** `Taslak_fikir.md`; `docs/01_URUN_VIZYONU.md`; `docs/02_OYUN_TASARIMI.md`
- **Tarih:** 2026-07-17

## K-005 — Kaynak önceliği

- **Durum:** Kabul edildi
- **Karar:** Çelişkilerde kullanıcının ana tasarım özeti en yüksek ürün önceliğidir. Ardından kabul edilmiş kararlar, çalışan prototip kanıtı, ürün vizyonu, tasarım önerileri ve ham fikirler gelir.
- **Etkilenen notlar:** Tüm GDD
- **Kaynak:** Kullanıcının talimatı; `PROJE.md`
- **Tarih:** 2026-07-17

## K-006 — Uzak şehirde tesis kuruluşu

- **Durum:** Kabul edildi
- **Karar:** Başka bir şehirde şube veya depo kurmak için o şehirde şirket aracının bulunması gerekmez. Kuruluş; para, inşa/kurulum süresi, izinler ve stratejik erişim koşullarıyla sınırlandırılır.
- **Gerekçe:** Boş araç konumlandırmasını zorunlu bir tıklama engeline dönüştürmeden genişleme kararının ekonomik ve zaman riskini korur.
- **Etkilenen notlar:** [[04 - Sistemler/04 - Tesisler]], [[03 - Lojistik Ağı/01 - Kanonik Lojistik Nesne Modeli]]
- **Kaynak:** Ürün sahibi kararı
- **Tarih:** 2026-07-17

## K-007 — Standart sözleşmelerin filo şartı

- **Durum:** Kabul edildi
- **Karar:** Standart sözleşmeler minimum araç sayısı yerine kapasite, sefer sıklığı ve SLA ister. Yalnız açıkça `dedicated fleet` olarak tanımlanan özel sözleşmeler belirli araç sayısı veya ayrılmış filo şartı koyabilir.
- **Gerekçe:** Oyuncunun araç, dış kapasite ve servis hattı bileşimini özgürce optimize etmesini sağlarken özel filo sözleşmelerinin farklılığını korur.
- **Etkilenen notlar:** [[04 - Sistemler/01 - İşler, Müşteriler ve Sözleşmeler]], [[03 - Lojistik Ağı/03 - Kapasite ve Hibrit Simülasyon]]
- **Kaynak:** Ürün sahibi kararı
- **Tarih:** 2026-07-17

## K-008 — Harita sunumu ve kanonik yol ağı

- **Durum:** Kabul edildi
- **Karar:** Yalnızca harita SpriteKit sahnesi olarak SwiftUI içindeki `SKView` üzerinde sunulur; yönetim arayüzleri SwiftUI kalır. Simülasyon ve domain render katmanından bağımsızdır. Harita MapKit/navigasyon altlığı değil, gerçek coğrafi ilişkileri tanınabilir ölçüde koruyan özgün ve stilize 2D oyun haritasıdır.
- **Veri sözleşmesi:** Şehir geçitleri, kavşaklar ve yol geometrileri kararlı kimlikli tek bir kanonik graf oluşturur. Rota bulma, araç konumu ve çizim bu grafı ortak kaynak olarak kullanır. Mevcut 8 şehirlik dilim ilk doğrulama kapsamıdır; 150–200 şehir ve binlerce yol hedefi için veri çevrimdışı üretilip sürümlü paketlenir.
- **Etkilenen notlar:** [[06 - UX ve Görsel Tasarım/02 - Dünya Haritası ve Görsel Dil]], [[07 - Teknik Tasarım/01 - iOS Mimarisi]], [[07 - Teknik Tasarım/03 - Veri Odaklı İçerik]], [[02 - Çelişki ve Açık Karar Kaydı#A-007 — Gerçek veya kurgusal coğrafya verisi]]
- **Kaynak:** Ürün sahibi kararı; native iOS harita temel uygulaması
- **Tarih:** 2026-07-18

## K-009 — Minimal şehir ve ürün/pazar veri sözleşmesi

- **Durum:** Kabul edildi
- **Şehir kararı:** `CityDefinition`; kimlik, coğrafya ve yol bağlantısının yanında pazar/servis alanı nüfusu, demir yolu yük/hava kargo erişim bayrakları ile 1000 tabanlı maliyet ve trafik gecikme endekslerini taşır. Bütün şehirlerin nüfusu aynı coğrafi kapsamla üretilir. Şehir rolü veya tag saklanmaz; ekonomik karakter verilerin birleşiminden ortaya çıkar. Geçici etkiler runtime durumundadır.
- **Ürün/pazar kararı:** `products.json` içindeki simülasyon çözünürlüğündeki ticari ürün kategorileri kararlı `lowercase_snake_case` `ProductID` ile bir kez tanımlanır. Tek bir fiziksel/fiyatlama profili anlamlı değilse kategori bölünür. Ayrı `city_markets.json`, şehir başına arz/talep listelerinde yalnız `ProductID` + `UInt16 weight` tutar; her liste en çok 20 girdidir ve ürün tanımını kopyalamaz.
- **Erişim sözleşmesi:** Doğrulanmış `GameCatalog`, şehir, ürün ve şehir pazarı kimlik indekslerini yüklemede kurar; runtime erişimi O(1)'dir.
- **Etkilenen notlar:** [[05 - İlerleme ve İçerik/02 - Dünya, Şehirler ve Açılımlar]], [[07 - Teknik Tasarım/03 - Veri Odaklı İçerik]]
- **Kaynak:** Ürün sahibi kararı; native veri temeli uygulaması
- **Tarih:** 2026-07-18

#gdd #gdd/karar
