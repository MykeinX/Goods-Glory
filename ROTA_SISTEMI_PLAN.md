# Rota Sistemi — Durum ve Kalan İş Planı

Son güncelleme: 2026-07-19. Bu belge, rota sisteminin tamamlanma durumunu ve
kalan adımları izler. Kod derlenebilir/tutarlı bir ara noktada bırakıldı.

## Alınan tasarım kararları (kullanıcı onaylı)

1. **Tek motor:** Kontrat rotaları ayrı bir sistem değil; kontrata araç atamak,
   otomatik 2 duraklı (`pickupContract` → `deliverContract`) bir rota kurup
   başlatır. Aynı rota kurucuda düzenlenebilir.
2. **"Rotaya ekle" otomatik:** Pazardan bir iş rotaya eklenince al+teslim
   durakları rotanın sonuna eklenir; sıralama sonra düzenlenebilir.
3. **Kontrat yükü bekleme:** Sıradaki sevkiyat çıkmadıysa araç alış durağında
   bekler (`waiting` fazı, sentinel süre; sevkiyat çıkınca uyanır).
4. **Kapanış kuralı:** Rota durdurulunca/araç çıkarılınca araç yeni yük almaz,
   üzerindeki yükleri kalan teslim duraklarına bırakır, boşalınca serbest kalır.
   Alınmamış kontrat sevkiyatları pazara döner (son tarihleri korunur; geçmişse
   tazminat işler). Spot yük iade edilirse ödemesiz iptal olur.
5. **Minimum veri:** Firmalar kayıt verisi üretmez — şehir pazar girdilerinden
   (`city_markets.json`) deterministik türetilir; isimler `firm_names.json`
   havuzundan hash ile seçilir.

## TAMAMLANANLAR

### Firma adres sistemi
- `FirmID`, `Firm`, `FirmRole`, `FirmNamePools` (CatalogDefinitions.swift).
- `firm_names.json` isim havuzu; `GameCatalog.deriveFirms` türetme +
  `firm(_:)`, `firms(in:)`, `supplierFirm/receiverFirm` sorguları.
- `JobOffer`, `ContractOffer`, `ActiveContract`'a `originFirmID` /
  `destinationFirmID` alanları; motor üretimde dolduruyor.

### Rota modeli v2 (GameState.swift)
- `RouteTask`: `travel | pickupShipment | deliverShipment | pickupContract |
  deliverContract`; `RouteStop` (id'li), `Route` (`isRunning`),
  `RouteShipment` (kargo: bekliyor/araçta), `RouteRun` (koşucu durumu:
  traveling/servicing/waiting, bacak alanları, lap guard, wind-down).
- GameState: `routeShipments`, `routeRuns` + yardımcılar (`routeRun(for:)`,
  `cargoLoad(of:)`, `isVehicleIdle(_:)` vb.).
- LogEvent yenilendi: `vehicleAssigned/UnassignedFromRoute`, `routeStarted/
  Stopped`, `routeShipmentDelivered/Skipped` (+ mevcut kontrat olayları).

### Komutlar (GameCommand + SimulationEngine)
- `createRoute, renameRoute, addTravelStop, removeRouteStop, moveRouteStop,
  addJobToRoute, removeJobFromRoute, assignVehicleToRoute,
  unassignVehicleFromRoute, startRoute, stopRoute, deleteRoute`.
- Kural: durak silme/taşıma yalnız durmuş rotada (`routeIsRunning` hatası);
  sona ekleme (travel/iş) çalışırken de serbest.
- Kontrat komutları (`assignVehicleToContract` vb.) rota komutlarına delege.

### Rota koşucusu (SimulationEngine)
- Olay döngüsüne entegre: bacak varışında km + sürüş maliyeti, serviste
  sürücü ücreti, teslimatta gelir + kontrat sayaçları; kapasite kontrolü
  (kargo toplamı araca sığmalı, sığmazsa atla + log/bildirim).
- Bekleme: kontrat yükü yoksa sentinel bekleme, `syncRouteRuns` uyandırır;
  sıfır süreli tur koruması (60 dk park) sonsuz döngüyü engeller.
- Eski `dispatchContractRoutes` / `JobPhase.returning` kaldırıldı; doğrudan
  spot iş akışı (`acceptJob`/`ActiveJob`) değişmedi.
- `estimate(route:vehicleType:state:)` → tur mesafesi/süresi/gelir/maliyet +
  `loopReturnKm` (son durak ≠ ilk durak boş dönüş uyarısı için).

### UI (asgari tutarlılık)
- Harita: koşucudaki araçlar bacak üzerinde hareketli, serviste dolum/boşalım
  animasyonlu; bekleyenler şehir "idle" rozetinde (MapSceneAdapter).
- Fleet: rota kartı yeni modele göre (durum, durak şeridi, araçlar, kontrat
  sayaçları); araç etiketleri: On route / On job / Standby / Idle.
- Jobs: kontrat kartı ve atama sheet'i tek motor üzerinden çalışıyor.
- Testler: kontrat testi koşucu semantiğine taşındı; yeni uçtan uca özel rota
  testi (`customRouteCarriesAnAcceptedJobAroundTheLoop`).
- Kayıt sürümü **7** (eski kayıtlar geçersiz, yeni oyun gerekir).

## KALAN İŞLER (öncelik sırasıyla)

### 1. Rota Kurucu ekranı (prototip 1c — en büyük parça)
Yeni dosya: `Presentation/Routes/RouteBuilderView.swift`.
- Üst yarı: `InteractiveMapView` (CityDetailView'daki mapHeader deseni aynen);
  haritada şehre dokununca "Durak ekle: <şehir>" onayı → `.addTravelStop`.
- Alt panel: numaralı durak listesi ("Şehir — Yük al", alt satırda firma adı
  `catalog.firm(offer.originFirmID)?.name`, tip rozeti GİT/ALIŞ/TESLİM),
  yukarı/aşağı taşı + sil (rota durmuşken), "Adım ekle — haritaya dokun" ipucu.
- ARAÇLAR satırı: atanmış araç çipleri + boştaki araçları ekleme menüsü.
- İstatistik: `session` üzerinden `engine.estimate(route:...)` → MESAFE / SÜRE /
  TAHMİNİ NET; `loopReturnKm > 0` ise uyarı kartı: "Rota burada bitiyor;
  başlangıca X km boş dönüş eklenir".
- Başlat/Durdur butonu (`startRoute/stopRoute`), durmuşken Sil.
- GameSession'a `createRoute() -> RouteID?` yardımcı (perform + `routes.last`).
- FleetView: rota kartına `NavigationLink` → kurucu; "Yeni rota kur" butonu
  aktifleştir (createRoute + aç). VehicleDetailView "Assigned Route" → kurucu.

### 2. Pazardan "Rotaya ekle"
- `OfferDetailView`'a araç seçiminin yanına ikinci yol: rota seçme menüsü →
  `.addJobToRoute(offerID:routeID:)` (çalışan rotaya da eklenebilir).
- Şehir detayındaki (3c) giden yükler listesine de aynı aksiyon eklenebilir.

### 3. Görünürlük cilası
- Jobs → Active sekmesine koşucu satırları: rota adı, mevcut bacak
  "A → B", faz etiketi, ilerleme çubuğu (CompactActiveJobRow benzeri).
- Teklif satırları/detayında firma adresleri göster: "Atlas Industries →
  Adria Market" (JobsView OfferRow + OfferDetailView + kontrat kartları).
- Harita araç popup'ı (MapTabView) koşucu fazlarını göstersin (şu an yalnız
  ActiveJob biliyor; RouteRun için konum/faz metni ekle).
- Kontratı biten rotada kart uyarısı: "Kontrat bitti — rota boş dönüyor".

### 4. Test + kalibrasyon
- Ek testler: bekleme→uyanma (sevkiyat çıkınca), kapasite atlama logu,
  removeJobFromRoute'ta kontrat iadesi/tazminatı, deleteRoute temizliği,
  determinizm (chunk'lı advance koşucuyla — mevcut test rotasız; rota içeren
  senaryo eklenmeli).
- `calibrate.py`'ye rota turu ekonomisi eklenebilir (bacak maliyeti vs iş
  gelirleri; hedef: iyi kurulmuş tur, tek tek spot işlerden ~%10-20 daha iyi).
- Xcode'da tam derleme + test koşusu (bu ortamda Swift yok; ilk derlemede
  küçük hatalar çıkarsa çoğu imza uyuşmazlığıdır).

### 5. İleriye dönük (bu fazın kapsamı dışında, model hazır)
- Tesis/depo durak noktaları: `RouteTask`'a depo görevleri (envanter sistemi
  gerektirir — Tesisler GDD'si).
- Durağa çoklu görev / görev detay ekranı; hazır şablon rotalar.
- Rota bazlı performans göstergeleri (doluluk, boş km — GDD "Taşıma Hatları").
