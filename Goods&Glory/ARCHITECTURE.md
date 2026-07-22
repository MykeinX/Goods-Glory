# Goods & Glory — Kod Mimarisi

Bu belge kod tabanının katman sözleşmesini tanımlar. Tasarım kararlarının kaynağı
`Game Design Documents/` kasasıdır; çelişkide GDD önceliklidir.

> **Not (2026-07-20):** Akış ve hat revizyonu (Faz 0–5) uygulandı; bu belge
> kodun güncel halini anlatır. Revizyonun gerekçesi ve faz kayıtları kökteki
> `AKIS_VE_HAT_REVIZYONU_PLAN.md` içindedir.

## Kod düzeni kuralları

Bu bölüm, bir kez ödenmiş bedellerin tekrar ödenmemesi içindir. Her madde
gerçekten yaşanmış bir sorunun karşılığıdır.

### 1. Dosya boyutu

**~400 satırda bölünür, 700 üst sınırdır.** Sınır estetik değil bakım
kaynaklı: 1000 satırlık dosyada bir değişiklik, dosyanın tamamını okumayı
gerektirir ve gözden kaçan bağlantı üretir. Klasör açmak bölmek değildir —
`Presentation/Fleet/` altında 1000 satırlık tek `FleetView.swift` bulunmak,
bölünmemiş demektir.

**Ne zaman yeni dosya:** yeni bir `struct`/`class`/`enum` yazıyorsan ve
yalnızca tek bir ekranın iç detayı değilse, kendi dosyasına gider. Bir ekranın
alt bileşeni (satır, kart, sheet) ikinci kez kullanıldığı anda kendi dosyasına
taşınır.

### 2. Aynı şeyi iki kere yazma

Bir hesap ya da görsel bileşen ikinci kez yazıldığında, ikisi zamanla ayrışır.
Bu kod tabanında dört kez oldu:

- `RouteCancellationSheet` iki dosyada ayrı ayrı yazılmış, farklı metin ve
  farklı mantıkla ayrışmıştı. İkisi de `private` olduğu için derleyici uyarmadı.
- `accent` 13 dosyada, `cityName` 9 dosyada aynı gövdeyle tekrarlanıyordu.
- Rota görevinin ikonu/rengi/fiili 4 ayrı `switch`teydi; `pickupLane` eklerken
  dördünü de bulmak gerekti (biri unutulsaydı sessizce yanlış ikon çizerdi).
- `firmAddressLine`, `SessionDisplay.addressLine`'ın kopyasıydı.

**Kural:** aynı hesabı ikinci kez yazmak üzereyken dur ve ortak yere taşı.
Ortak yerler: `Domain` (kural/hesap), `Format` (biçimlendirme),
`SessionDisplay` (katalog aramaları), `DesignSystem` (görsel bileşen),
`RouteTaskDisplay` (bir domain tipinin sunum bilgisi).

### 3. Hesap Domain'de, görüntü Presentation'da

Bir sayı birden fazla ekranda gösteriliyorsa onu hesaplayan yer motordur, view
değil. `bottleneck`, `brief`, `coverage`, `estimate`, `RouteStats` bu yüzden
`SimulationEngine+Analysis` içindedir: view'lar okur, hesaplamaz. Bir view'da
`reduce`/`filter` ile iş mantığı yazılıyorsa, yanlış katmandadır.

### 4. Bölerken dikkat edilecek iki şey

**`private` dosya kapsamlıdır.** Bir tip dosyalara bölündüğünde paylaşılan
üyeleri `internal` olur; erişim yine modül içiyle sınırlı, bilinçli bir takas.
Bölünmüş bir tipin üyesini `private` yapmadan önce gerçekten tek dosyada mı
kullanıldığına bak. Aynı şekilde, kendi dosyasına taşınan bir tip artık
`private` olamaz — onu kullanan ekran başka dosyadadır.

**`extension` blokları da taşınır.** `struct`/`enum` sayarak bölerken serbest
`extension View { … }` blokları gözden kaçar; bir kez böyle bir modifier
(`plainListRow`) sessizce kayboldu.

**Durum ana tipte kalır.** Swift'te `extension` stored property içeremez. Bir
tipi bölerken `var x: T` / `var x = …` satırları ana `class`/`struct`'ta kalmalı;
yalnız fonksiyonlar ve computed property'ler extension'a gider. Onları anlatan
küçük yardımcı tipler de durumla birlikte kalsın (`SemanticZoomKey` gibi).

**Bölme sonrası üç kontrol:** her dosyanın süslü parantez dengesi sıfır mı;
kullanılan her sembol hâlâ tanımlı mı; extension'lara stored property düşmüş mü.

Bölme sorumluluk eksenindedir, satır sayısını eşitlemek için değil. `SimulationEngine`
tek bir `struct`tır ama sorumluluklarına göre dosyalara ayrılmıştır:

| Dosya | Sorumluluk |
|---|---|
| `SimulationEngine` | Komut dağıtımı, iş/sözleşme komutları |
| `+Pricing` | Zaman ilerletme, iş fazları, maliyet ve fiyat |
| `+Standing` | Duran maliyetler, süre dolumu, ceza |
| `+Lanes` | Dok birikimi, parti talebi, sevk |
| `+Contracts` | Teklif üretimi, parti takvimi, taahhüt defteri, yaşam döngüsü |
| `+Facilities` | Site ve modüller, fiyat teklifi, inşaat |
| `+Routes` | Rota düzenleme komutları |
| `+RouteRunner` | Rotanın yürütülmesi (yol, servis, bekleme) |
| `+Cargo` | Duraktaki yük: elleçleme, depo, teslim mutabakatı |
| `+Analysis` | Salt okunur UI görünümleri (brief, darboğaz, kapsam, tahmin) |
| `+DebugFormat` | Denge kaydı formatlayıcıları |

Aynı bölme `GameCatalog`, `GameState`, `GameMapScene` ve büyük ekranlar için de
uygulandı. Sunum katmanında ölçüt **tip**tir: her ekran kendi dosyasında, her
yeniden kullanılabilir satır/kart kendi dosyasında.

| Alan | Dosyalar |
|---|---|
| `GameCatalog` | `+Routing`, `+Loading`, `+Derivation`, `+Validation` |
| `GameState` | `Contracts`, `Routes`, `CampaignLog`, `Facility`, `DebugLedger` |
| `GameMapScene` | `+Camera`, `+Terrain`, `+Snapshot`, `MapNodes`, `MapPalette` |
| Operasyon | `JobsView`, `LaneRow`, `ActiveWorkRows`, `ContractMarketList`, `ActiveContractRow`, `ParcelDetailView` |
| Harita | `MapTabView`, `MapChrome`, `MapCityPopup`, `MapVehiclePopup`, `GameNotificationStack` |
| Filo | `FleetView`, `RouteRow`, `VehicleRows`, `VehicleDetailView`, `VehicleShopView` |
| Hat kurucu | `RouteBuilderView`, `+Visits`, `+Planning`, `RouteTaskPicker`, `RouteVehiclePicker`, `RouteCancellationSheet` |

**Not:** Bir tip dosyalara bölündüğünde yardımcı üyeleri `internal` olur —
Swift'te `private` dosya kapsamlıdır. Erişim yine modül içiyle sınırlıdır.

## Ortak sunum yardımcıları (mükerrer kod yasağı)

Aynı hesabı iki yerde yazmak, ikisinin zamanla ayrışması demektir — bu kod
tabanında bir kez oldu: `RouteCancellationSheet` iki dosyada ayrı ayrı yazılmış,
farklı metin ve farklı mantıkla ayrışmıştı. Ortak olan şeyler tek tanımda:

- `SessionDisplay` — `session.accentColor`, `cityName`, `productName`,
  `vehicleCode`, `addressLine`. (Önceden 13 ayrı `accent`, 9 ayrı `cityName`.)
- `RouteTaskDisplay` — bir görevin ikonu, rengi ve fiili. Görevin kendisine ait
  sunum bilgisi; `RouteTask`'a extension olarak durur. (Önceden 4 ayrı switch.)
- `Format` — para, mesafe, kütle, süre, modül adları.
- `DesignSystem` — tema, kart/çip bileşenleri, `ScreenHeader`.

## Katmanlar ve bağımlılık yönü

```
Presentation (SwiftUI + SpriteKit)
    ↓ komut/niyet          ↑ salt okunur durum
Application (GameSession)
    ↓                      ↑
Domain (GameCatalog, GameState, SimulationEngine)  ← hiçbir framework'e bağımlı değil
    ↑
Persistence (SaveRepository)   Resources (JSON kataloglar)
```

- **Domain** (`Domain/`): Saf Swift. SwiftUI, SpriteKit, kayıt teknolojisi ve duvar
  saati bilmez. Aynı katalog + başlangıç durumu + seed + komut dizisi + oyun süresi
  her zaman aynı sonucu üretir (determinizm sözleşmesi).
  - `Core/`: Typed ID'ler (`CatalogID`/`RuntimeID`), kanonik birimler (tam dolar,
    kg, m³, oyun dakikası), `SeededRNG` + kararlı seed türetimi.
  - `Catalog/`: JSON'dan yüklenen salt okunur içerik + doğrulama + yol grafı
    (deterministik Dijkstra). İçerik veride, kurallar kodda.
  - `State/`: `GameState` — kampanyanın tamamı, serileştirilebilir değer tipleri.
  - `Engine/`: `SimulationEngine.apply(command)` ve `advance(by: dakika)`.
    Ara olaylar (faz geçişleri, teklif partileri) kronolojik sırayla işlenir;
    zamanın kaç parçada ilerletildiği sonucu değiştirmez.

- **Application** (`Application/`): `GameSession` (@Observable, @MainActor).
  Gerçek zamanı oyun dakikasına çevirir (1×’te 1 sn = 10 dk; 3× / 6× tam çarpan),
  komutları doğrulatıp
  uygular, kayıt anlarını koordine eder. UI, `GameState`'i asla doğrudan değiştirmez.

- **Persistence** (`Persistence/`): Atomik JSON snapshot (`SaveEnvelope`, sürümlü).
  SwiftData/SQLite kararı GDD gereği prototip ölçümüne ertelendi; arayüz sabit,
  teknoloji değiştirilebilir.

- **Presentation** (`Presentation/`): Yönetim ekranları SwiftUI; yalnızca harita
  SpriteKit sahnesidir.
  - `InteractiveMapView`: SwiftUI içinde bir `SKView` barındırır; pan/zoom,
    dokunma ve seçimi `GameMapScene` yürütür. Sahne oyun verisini
    `MapSceneAdapter`'ın ürettiği salt okunur `MapRenderSnapshot` ile alır.
    SpriteKit simülasyon kuralı veya kalıcı oyun durumu içermez.
  - `MapProjection`: gerçek lat/lon → düz dünya koordinatı (~1 birim = 1 km).
    Simülasyon ekran koordinatı kullanmaz.
  - `DesignSystem`: koyu gece-lojistik teması, kart/buton/çip bileşenleri.

## Veri sözleşmesi (Resources/Catalog)

- Kimlikler kararlı İngilizce `lowercase_snake_case`; asla yeniden kullanılmaz.
- Zaman tamsayı oyun dakikası; kütle `massKg`, hacim `volumeM3`; para tam dolar.
- Çapraz referanslar katalog yüklenirken doğrulanır; bozuk içerik kontrollü
  açılış hatası üretir (sessiz yoksayma yok).
- `CityDefinition` kimlik/coğrafya/yol bağlantısına ek olarak nüfus,
  `hasRailFreightAccess`, `hasAirCargoAccess`, `hasSeaPortAccess`, `costIndex` ve
  `trafficDelayIndex` taban verisini taşır. Nüfus, talep hesabında kullanılacak
  şehir pazar/servis alanını temsil eder; bütün şehirlerde aynı coğrafi kapsam
  uygulanır. İndekslerde 1000 ortak oyun tabanıdır; şehir rolü veya etiketi
  saklanmaz; `CityRole` katalog sözleşmesinde yoktur.
  Erişim bayrakları terminal kapasitesi değil metadata’dır: demir yolu Class I
  yerel yük/intermodal varlığı, hava önemli kargo/express hub rolü, deniz
  derin su kıyı/estuarin veya Great Lakes ticari limanıdır (yalnız nehir mavna
  hub’ları deniz sayılmaz).
- `products.json`, kararlı `lowercase_snake_case` `ProductID` ile ürünün tek
  tanım kaynağıdır. `city_markets.json` ürün tanımını kopyalamadan her katalog
  şehri için statik arz/talep listelerinde `ProductID` + `UInt16 weight` tutar;
  her liste en çok 20 üründür (mevcut ABD diliminde şehir başına 12 arz +
  12 talep). Ağırlıklar seçim eğilimidir; runtime talep kataloğa yazılmaz.
  Profiller `scripts/generate_city_markets.py` ile nüfus ve erişim
  bayraklarından türetilir; `GameCatalog` yüklemede her şehir için pazar
  kaydı, bilinen `ProductID` ve liste üst sınırını doğrular.
- `ProductID`, tek bir SKU değil simülasyon çözünürlüğünde ticareti yapılan yük
  kategorisidir (`cotton`, `consumer_electronics` gibi). Tek bir yoğunluk ve
  sevkiyat aralığı anlamlı değilse kategori daha somut ürünlere
  bölünür; ürün kaydına şehir veya rol bilgisi eklenmez.
- `GameCatalog` şehir, ürün ve şehir pazarı için kimlik sözlüklerini yüklemede
  kurar; runtime sistemleri katalog içeriğine O(1) kimlik erişimiyle ulaşır.
- `road_nodes.json` şehir geçitleri ve kavşakları, `roads.json` ise kararlı yol
  kimliklerini ve `distanceKm` mesafesini tanımlar. Bu kanonik graf yalnız rota
  hesabı içindir; haritada araç/rota çizimi şehir–şehir yaylarla yapılır, yol
  polylines runtime’da yoktur. Yol adı runtime verisi değildir; kaynak adlar
  yalnız çevrimdışı üretimde hatları birleştirmek için kullanılır.
- Harita verisi çevrimdışı ve sürümlü paketlenir. Mevcut dilim ülke namespace'li
  71 şehirdir (ABD + Avrupa + Asya; kıtalar ayrı yol ağlarıdır) ve stratejik
  koridorlar ile bunların gerçek kavşaklarından
  oluşur. Görsel silüetler `map_geography.json` (kara, göl, ülke sınırı)
  üzerinden gelir. Bölgeye özel üretim adımları `scripts/` altında kalır;
  çalışma zamanı veri sözleşmesi yeni ülke ve kıtalar eklenirken değişmez.
- Oyuncuya görünen metinler `Localizable.xcstrings` (en kaynak, tr çeviri)
  üzerinden yerelleşir; katalogdaki `name` alanları İngilizce anahtar olarak
  String Catalog'dan geçer.

### Mevcut ABD şehir metriği snapshot'ı

- `costIndex`, BEA'nın 12 Aralık 2024'te yayımladığı arşivlenmiş
  [2023 metro RPP / All items tablosundaki](https://www.bea.gov/sites/default/files/2024-12/rpp1224.pdf)
  tek ondalıklı değerin ×10 halidir; 1000, 2023 ABD ulusal fiyat düzeyidir.
  Bu değer doğrudan inşaat maliyeti değil, oyun için yerel maliyet vekilidir.
- `trafficDelayIndex`, FHWA
  [FY2026 Q1 Urban Congestion Report](https://ops.fhwa.dot.gov/perf_measurement/ucr/reports/fy2026_q1.pdf)
  içindeki Ekim–Aralık 2025 yoğun-saat Travel Time Index değerinin ×1000
  halidir. Hafta içi sabah/akşam yoğun saat ölçümü statik oyun trafik vekili
  olarak kullanılır; tüm-gün ölçümü değildir. Raporda ayrı satırı bulunmayan
  dengeli harita merkezleri için aynı raporun 1280 ulusal ortalaması kullanılır.
- Demir yolu / hava / deniz bayrakları ayrıntılı rota veya kapasite değil erişim
  metadatasıdır. Demir yolu için Class I yerel yük/intermodal varlığı, hava için
  [FAA all-cargo](https://www.faa.gov/airports/planning_capacity/passenger_allcargo_stats/passenger)
  / ACI-NA kargo hub sınıfı, deniz için derin su kıyı-estuarin veya Great Lakes
  ticari liman (yalnız nehir mavna hub’ı deniz sayılmaz) referans alınır.
- ABD dışı şehirler eklenirken ülkeye özgü endeksler doğrudan bu ABD serisine
  eklenmez; önce ortak global oyun tabanına normalize edilir. Kaynak yayın,
  dönem, coğrafi kapsam ve dönüşüm kuralı bölge dilimi için birlikte pinlenir.

## Mevcut kapsam (temel iskelet)

Ana menü → şirket kuruluşu (kimlik, başlangıç şehri, ilk araç) → oynanış
(harita / filo / işler / tesisler / şirket sekmeleri).

**Akış servisi (Faz 1 — spot pano kaldırıldı):** Talep kalıcıdır: her akışın
çıkış dokunda `GameState.laneAccrualKg` birikir (`LaneConfig.tickMinutes`
olay tiki; debi haftalık salınımlı). Birikim sabır penceresiyle sınırlıdır
(`parcelPatienceMinutes`); böylece servis edilmeyen doklar sınırsız büyümez.
Taşan üretim ayrıca sayılmaz veya loglanmaz. Süresi dolan teklif panosu yoktur; `JobOffer`
yalnız kontrat partisi olarak panoya düşer veya dok talebinde akıştan basılır.
`dispatchVehicleToLane` komutu iki duraklı mekik rota kurar
(`pickupLane` → `deliverAll`): araç dokta bekleyen yükü **kendi sınıfına
göre fiyatlanmış** partiler halinde yükler (maliyet+marj; rekabet marjı
`CityInsight.competitionPercent` üzerinden tek noktadan kırpar), teslim eder,
boş döner ve dok doluncaya dek bekler. Ödeme yalnız dolu gidişi fiyatlar;
boş dönüş oyuncunun optimize edeceği görünür maliyettir.

**Tesisler (Faz 4 — tek site + modüller):** Şehirde tek `Facility` vardır;
yetenekleri `[FacilityModule]` belirler — `office` (sözleşme hakkı + teklif
yuvası + hat primi), `warehouse` (depolama/konsolidasyon), `dock` (elleçleme
hızı). Her modül kendi seviyesi, inşa ve yükseltme saatiyle yaşar. Elleçleme
süresi warehouse × dock çarpanıdır: aynı bütçeyle derin depo ya da hızlı
cross-dock kurulabilir — tesis stratejisi buradan doğar. Komutlar
`installModule` / `upgradeModule` / `removeModule`; HQ ofisi ve dolu depo
sökülemez, son modül gidince site kapanır. Maliyet/süre/gider sabit değil:
`FacilityEconomics` şehir `costIndex`, nüfus ve erişim bayraklarından
`siteFactor` türetir. HQ ofisi kuruluşta ücretsiz gelir ve
`hqLanePremiumPercent` kadar hat primi verir.

**Debug ledger (denge aracı):** `GameState.debug` her nakit hareketini birim
ekonomisiyle (dolu/boş km, $/km, doluluk) tek satırda tutar; Şirket → Balance
Log ekranı özet kırılımı ve panoya kopyalama verir. Yalnız gözlem yapar:
`issueID()` tüketmez, motor kararlarına girmez, determinizmi etkilemez.

**Yük konumu:** `Shipment.location` (`address` / `vehicle` / `warehouse`) yükü
rotadan bağımsızlaştırır; bir parti bir rotayla toplanıp depoda bekleyip başka bir
rotayla teslim edilebilir. `StorageLot` yalnızca sunum katmanı gruplamasıdır
(ürün + nihai hedef + sözleşme); motorda her parti kimliğini korur, böylece
son tarih ve ceza muhasebesi bozulmaz. Depo görevleri: `dropToWarehouse`,
`loadFromWarehouse(lot)`, `deliverAll`.

**Rotalar / hatlar (Faz 2):** Tek motor; rota hiçbir sözleşmeye ait değildir.
Kapsam durak görevlerinden türer (`Route.coveredContractIDs` /
`coveredLaneIDs`). Tek-hedefli kontrata araç atamak
`[pickupContract + aynı-hat pickupLane'ları + deliverAll]` kurar: SLA yükü
önce yüklenir, kalan kapasite dokta bekleyen akış yüküyle dolar (spot
top-off). Kontrat bitince rota kapanmaz — `routeNeedsReview` bilgisi düşer,
hat taban akışla çalışmaya devam eder. `RouteStats` her rotada dolu/boş km,
gelir/gider ve ilk çalışma zamanını biriktirir (koşucu bacak/servis/teslimat
noktalarında yazar); Fleet rota kartı doluluk %, boş km ve $/gün okur.
Fleet → Rota Kurucu ile şehir döngüsü, araç atama, görevler, başlat/durdur;
atanmış araçlar `RouteRun` ile tur atar (bekleme → yükleme → taşıma).

**Sözleşmeler (Faz 3 — akış payı taahhüdü):** Sözleşme talep üretmez.
`ContractDestination` bir `laneID` + `committedShareBps` taşır; teklif şehrin
mevcut akışlarından debiye göre ağırlıklı seçilir ve dönem hacmi
`akış debisi × pay × dönem`dir. İmzalı payın tonajı `accrueLanes` içinde dok
birikiminden düşülür (çift sayım yok) ve kontrat partisi olarak postalanır.
Fiyat akışın spot ücretinden türer: `spot × (1 + contractPremiumPercent)` —
taahhüt primi SLA ve ceza riskinin karşılığıdır. Pay tavanı `companyTier` ile
açılır; bir akışın toplam taahhüdü (imzalı + açık teklif) %100'ü aşamaz.
`multiDrop` aynı şehrin farklı akışlarıdır.

Sözleşmeler dört arketiptir (`laneRecurring`, `bulkPeriodic`, `evergreen`,
`multiDrop`) ve yalnız şubeli şehirlerden üretilir. Teklif sayısı ve marjı şehrin
`CityInsight` pazar/rekabet değerlerinden türetilir — sözleşme kıt değildir,
kıt olan şube yatırımıdır. Arketip ve dönem hacmi tavanı `companyTier` ile açılır.
Her dönem `volumePerCycleKg` araç boyu partilere bölünür; parti son tarihi artık
sevkiyat aralığı değil ayrı `deliveryWindowMinutes`'tır ve imza ile ilk parti
arasında `leadTimeMinutes` hazırlık payı vardır. `ContractCoverage` sözleşmenin
gerçekten taşınıp taşınmadığını yapıdan değil akıştan ölçer.

Mevcut harita dilimi 71 şehri (ABD + Avrupa + Asya) ve ana koridor ağlarını
kapsar; kara/eyalet sınırları ile yollar çevrimdışı üretilmiş gerçek koordinat
geometrileridir.

**Yük akışları (akış revizyonu Faz 0):** `GameCatalog.deriveLanes`,
`city_markets.json` + nüfus + yol mesafelerinden kalıcı firma→firma
`FreightLane` setini deterministik türetir (aynı katalog → aynı akışlar; kayıt
verisi yok). Şehir arz ağırlıkları `scripts/generate_city_markets.py` içindeki
küratörlü `CITY_INDUSTRIES` tablosuyla gerçek ekonomik kimliği taşır (Detroit →
otomotiv, Dhaka → tekstil); K-009 gereği runtime'a şehir rolü/tag yazılmaz.
Debi bütçesi nüfusla ölçeklenir, ürün payları kare-ağırlıkla yoğunlaşır, hedef
seçimi talep × mesafe sönümü iledir; denge değerleri `economy.json > lanes`.
Haftalık debi dalgalanması `FreightLane.ratePerDayKg(week:worldSeed:swingPercent:)`
saf fonksiyonudur. Danışma raporları: `scripts/report_city_markets.py`,
`scripts/report_freight_flows.py` (Swift kanoniktir, Python ayna sadece
kalibrasyon gözü içindir). Faz 1 ile motor akışları tüketir (sınırlı birikim,
`pickupLane`); UI'da Operasyon → hat listesi ve şehir ekranı
akışları gösterir. Haritada standing-demand koridor overlay'i yok — talep
liste/şehir detayında okunur; harita yalnız oyuncunun kendi rotalarını çizer.
Kayıt sürümü 10.

## Bilinçli ertelemeler (GDD'de tanımlı, henüz yok)

- Dinamik pazar: fiyat/talep oynaklığı, oyuncu hacminin arz-talep üzerindeki
  geri beslemesi ve sezonluk şoklar (katalog ağırlıkları hâlâ statik eğilim).
- Sözleşme → yük partisi → taşıma aşaması → servis hattı omurgası
  (şimdilik spot/sözleşme sevkiyatı = tek parti + tek aşama; genişleme noktası
  `ActiveJob`). SLA, gecikme cezası ve itibar henüz bağlı değil.
- Seed'li süre/talep oynaklığı (faz süreleri şimdilik sabit formül).
- Logbook mesajlarının tam veri-odaklı yerelleştirmesi.
- CloudKit senkronizasyonu, migration zinciri, hibrit/toplu simülasyon.
- 150–200 şehir için diğer ülke/kıta dilimleri, bölgesel döşeme/LOD ayrıntıları
  ve binlerce araç için gerçek cihaz performans bütçelerinin kesinleştirilmesi.

## Test stratejisi

`Goods&GloryTests/`: bundled katalog doğrulaması, deterministik yol grafı,
spot settlement, kontrat/rota koşucusu (bekleme→uyanma, kapasite atlama,
silme/iade), bildirim map-focus eşlemesi ve determinizm sözleşmesi (parçalı vs
tek seferlik `advance` → aynı durum; rota koşuculu senaryolar dahil). Yeni
sistem eklerken önce değişmezleri test edin.
