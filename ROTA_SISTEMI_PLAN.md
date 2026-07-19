# Rota Sistemi — Durum Planı

Son güncelleme: 2026-07-19. Bu belge **kodun gerçek durumunu** yansıtır;
eski “ara nokta / kurucu yapılacak” notları geçersizdir.

## Alınan tasarım kararları (kullanıcı onaylı)

1. **Tek motor:** Kontrat rotaları ayrı bir sistem değil; kontrata araç atamak,
   otomatik 2 duraklı (`pickupContract` → `deliverContract`) bir rota kurup
   başlatır. Aynı rota kurucuda düzenlenebilir.
2. **"Rotaya ekle" otomatik:** Bir iş rotaya eklenince al+teslim durakları
   rotanın sonuna eklenir; sıralama sonra düzenlenebilir. Motor komutu
   (`addJobToRoute`) hazır; Jobs/CityDetail UI girişi hâlâ eksik.
3. **Kontrat yükü bekleme:** Sıradaki sevkiyat çıkmadıysa araç alış durağında
   bekler (`waiting` fazı, sentinel süre; sevkiyat çıkınca uyanır).
4. **Kapanış kuralı:** Rota durdurulunca/araç çıkarılınca araç yeni yük almaz,
   üzerindeki yükleri kalan teslim duraklarına bırakır, boşalınca serbest kalır.
   Alınmamış kontrat sevkiyatları pazara döner (son tarihleri korunur; geçmişse
   tazminat işler). Spot yük iade edilirse ödemesiz iptal olur.
5. **Minimum veri:** Firmalar kayıt verisi üretmez — şehir pazar girdilerinden
   (`city_markets.json`) deterministik türetilir; isimler `firm_names.json`
   havuzundan hash ile seçilir.

## Tamamlananlar

### Firma adres sistemi
- `FirmID`, `Firm`, `FirmRole`, `FirmNamePools` (CatalogDefinitions.swift).
- `firm_names.json` isim havuzu; `GameCatalog.deriveFirms` türetme +
  `firm(_:)`, `firms(in:)`, `supplierFirm/receiverFirm` sorguları.
- `JobOffer`, `ContractOffer`, `ActiveContract`'a `originFirmID` /
  `destinationFirmID` alanları; motor üretimde dolduruyor.
- Jobs / CityDetail teklif satırlarında firma adları gösteriliyor.

### Rota modeli v2 + motor
- `RouteTask`: `travel | pickupShipment | deliverShipment | pickupContract |
  deliverContract`; `RouteStop`, `Route`, `RouteShipment`, `RouteRun`.
- Komutlar: `createRoute`, `renameRoute`, `addTravelStop`, `removeRouteStop`,
  `moveRouteStop`, `addJobToRoute`, `removeJobFromRoute`,
  `assignVehicleToRoute`, `unassignVehicleFromRoute`, `startRoute`,
  `stopRoute`, `deleteRoute` (+ kontrat ataması rota komutlarına delege).
- Koşucu: bacak maliyeti, servis ücreti, teslimat geliri, kapasite atlama
  logu, kontrat bekleme→uyanma, wind-down kapanış.
- `estimate(route:…)` → tur mesafe/süre/gelir/maliyet + `loopReturnKm`.
- Kayıt sürümü **7**.

### Rota Kurucu UI (`Presentation/Routes/RouteBuilderView.swift`)
Canlı ve Fleet üzerinden açılıyor:
- Fleet: “Yeni rota” → `GameSession.createRoute()` + kurucu;
  rota kartı / araç detayı “Assigned Route” → aynı ekran.
- Üst yarı: `InteractiveMapView` + rota önizlemesi; şehre dokununca durak ekleme.
- Alt panel: şehir ziyaretleri, kontrat görev seçici (`RouteTaskPicker`),
  araç atama, mesafe / süre / tahmini net, Başlat / Durdur / Sil.
- Motor testleri: bekleme→uyanma, kapasite skip, `removeJobFromRoute`
  iade/tazminat, `deleteRoute` temizliği, koşuculu chunked determinizm,
  özel rota + spot turu (`customRouteCarriesAnAcceptedJobAroundTheLoop` vb.).

### Görünürlük (çoğu hazır)
- Harita: koşucu araçları bacak üzerinde; serviste dolum/boşalım; idle rozeti.
- Harita araç popup’ı: `RouteRun` fazları (On route / Loading / Waiting…).
- Jobs → Active: `CompactRouteRunRow` (rota adı, bacak, faz, ilerleme).
- Fleet rota kartı: “Contract ended — route is running empty.” uyarısı.

## Kalan işler (öncelik sırasıyla)

### 1. Pazardan / şehirden “Rotaya ekle” UI
Motor hazır; eksik olan giriş noktaları:
- `OfferDetailView`: araç kabulünün yanında rota seç → `addJobToRoute`.
- (İsteğe bağlı) CityDetail giden yük listesine aynı aksiyon.
- Rota kurucudaki şehir iş seçici bugün yalnız **kontrat** görevlerini listeler;
  spot sevkiyat ekleme hâlâ Jobs/Fleet tarafına bağlı.

### 2. Kurucu cilası
- `loopReturnKm > 0` iken açık uyarı: “Rota burada bitiyor; başlangıca X km
  boş dönüş eklenir” (`RouteEstimate.loopReturnKm` hesaplanıyor, UI’da yok).
- İsim düzenleme / boş dönüş davranışının oyuncu dilinde netleştirilmesi.

### 3. Ekonomi kalibrasyonu (rota + spot birlikte)
- `scripts/calibrate_spot_offers.py` spot odaklı; rota turu ekonomisi
  (bacak maliyeti vs iş gelirleri) henüz yok.
- Hedef önerisi: iyi kurulmuş tur, tek tek spot işlerden ~%10–20 daha iyi net.

### 4. İleriye dönük (model hazır, kapsam dışı)
- Tesis/depo durak noktaları (`RouteTask` + envanter; Tesisler GDD’si).
- Durağa çoklu görev detay ekranı; hazır şablon rotalar.
- Rota performans göstergeleri (doluluk, boş km — GDD “Taşıma Hatları”).
