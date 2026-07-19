# Tesis, Depo ve Sözleşme Sistemi — Tasarım ve Uygulama Planı

Son güncelleme: 2026-07-19. Statü: **onaylandı — uygulanıyor**.

Bu belge kullanıcının 2026-07-19 tarihli 5 maddelik yönergesini kanonik kabul eder.
Çelişki durumunda bu belge GDD ve `ROTA_SISTEMI_PLAN.md` üzerindedir; onaydan sonra
GDD `04 - Tesisler` ve `04 - İşler, Müşteriler ve Sözleşmeler` bu belgeye göre güncellenir.

---

## 0. Onaylanan kararlar

| Konu | Karar |
|---|---|
| Depo envanteri | Hibrit: ürün + hedef bazlı **lot** görünümü |
| Şube zorunluluğu | Yalnız sözleşme; **HQ otomatik şube**; spot işler serbest |
| Sözleşme arketipleri | Dönemsel hat, yüksek hacimli toplu, süresiz, çok noktalı dağıtım (4'ü de) |
| Çalışma şekli | Tüm fazlar tek blokta ilerletilir |
| Bilgi mimarisi | **İşler sekmesi → "Operasyon"**: Aktif · Sözleşmeler · Pazar. Tesisler sekmesi yerinde kalır |
| Sözleşme bolluğu | Teklif **sayısı ve getirisi** şehrin statik verisinden (pazar büyüklüğü, rekabet, nüfus, costIndex) türetilir; oyuncu sözleşme aramakta zorlanmaz |
| Tesis maliyeti | `costIndex` × nüfus ölçeği + erişim primi; her şehirde farklı |

### 0.1 Açık varsayımlar (aksi söylenmezse böyle kodlanır)

1. **Şube şartı yalnız origin'de.** Sözleşme teklifi, yükün *alındığı* şehirde şube
   varsa üretilir/imzalanabilir. Varış şehrinde şube aranmaz — aksi halde erken oyunda
   iki şube parası olmadan hiç sözleşme alınamaz. *(Çok noktalı dağıtımda da yalnız
   kaynak şehir şart.)*
2. **Depo şube gerektirmez, ayrı yapıdır.** Aynı şehirde ikisi birden kurulabilir;
   biri diğerinin önkoşulu değildir. (GDD: "Depo kuruluşun zorunlu ilk adımı değildir.")
3. **HQ buff'ı kârlılıkta, küçük ve tek yerde.** HQ şehrinden çıkan veya HQ şehrine
   giren yükün ödemesine sabit bir yüzde eklenir (`hqLanePremiumPercent`, öneri **%5**).
   Maliyet tarafına dokunulmaz; tek bir formül noktası, kalibrasyonu kolay.
4. **Mevcut kayıtlar taşınmaz.** Kayıt sürümü 7 → 8; `SaveRepository` sürüm uyuşmazlığında
   bugünkü davranışı korur (yeni kampanya). Prototip aşamasında migration zinciri yazılmaz.

### 0.2 "Lot" kararının teknik rafinesi — dikkat

Seçilen hibrit lot modelini **iki katmana ayırmayı öneriyorum**, çünkü saf lot
(kütleleri birleştirip sevkiyat kimliğini yok etmek) sözleşme muhasebesini bozar:
teslim tarihi, ceza ve "kaç parti tamamlandı" sayacı kütleye bölünemez.

- **Motor katmanı — kimlik korunur.** Her sevkiyat `Shipment` olarak kimliğiyle yaşar;
  yalnızca *konumu* değişir (adres / araç / depo).
- **Sunum katmanı — lot.** UI, depodaki sevkiyatları `(ürün, nihai hedef, sözleşme)`
  anahtarına göre **tek satırda** toplar: *"Chicago → 120 t Elektronik · Kontrat #4 ·
  en yakın son tarih 2g 4sa"*. Kullanıcı lot seçer; motor o lottan **son tarihi en yakın**
  sevkiyatları kapasite dolana kadar alır.

Kullanıcıya görünen deneyim istenen lot deneyimidir; muhasebe tam kalır. Bu rafineye
itirazın varsa Faz 0 başlamadan söyle — sonrasında değiştirmek pahalı.

---

## 1. Veri modeli

### 1.1 Tesisler

```swift
enum FacilityKind: String, Codable, Sendable {
    case branch      // şube: sözleşme hakkı, yerel ticari temsil. Yük depolamaz.
    case warehouse   // depo: yük kabul/bekletme/sevk, konsolidasyon.
}

struct Facility: Codable, Identifiable, Sendable {
    let id: FacilityID              // yeni RuntimeID
    let cityID: CityID
    let kind: FacilityKind
    var level: Int                  // 1...3
    /// HQ şubesi kuruluşta otomatik yaratılır, satılamaz/yıkılamaz.
    let isHeadquarters: Bool
    let foundedAt: GameTime
    /// İnşaat bitiş zamanı. Bu zamana kadar tesis kapasitesiz ve haksızdır.
    var operationalAt: GameTime
    /// Seviye yükseltmesi sürüyorsa hedef seviye + bitiş zamanı.
    var upgradingTo: Int?
    var upgradeEndsAt: GameTime?
}
```

`GameState`'e: `var facilities: [Facility]`.

Türetilmiş sorgular (`GameState` uzantısı, hepsi saf):
`branch(in:)`, `warehouse(in:)`, `hasOperationalBranch(in:)`, `storageCapacity(of:)`.

### 1.2 Tesis dengesi (economy.json'a taşınacak, kod sabiti değil)

Ölçek referansı: kuruluş maliyeti ≈ 40 × `costIndex` (≈ $40–56k), semi-trailer $95k,
başlangıç nakdi $75k. Tesisler bilinçli olarak **orta oyun yatırımı**dır; erken oyunda
HQ şubesi tek sözleşme kapısıdır.

**Maliyet formülü — şehre göre değişir (sabit değer yok):**

```
siteFactor(city) = (costIndex / 1000)          // BEA bölgesel fiyat düzeyi
                 × (0.75 + 0.65 × popNorm)      // arazi kıtlığı: büyük metro pahalı
                 × (1 + 0.04 × accessFlagCount) // liman/demiryolu/hava primi
```

`popNorm`, `CityInsight`'taki mevcut nüfus normalizasyonudur (0…1) — yeni katalog
alanı gerekmez. Çarpan bandı yaklaşık **0,60× – 1,85×**: Memphis'te seviye 1 depo
~$165k iken New York'ta ~$480k. Günlük gider aynı `siteFactor` ile ölçeklenir.

| Yapı | Sv | Taban inşa | İnşa süresi | Taban günlük gider | Kapasite / etki |
|---|---|---|---|---|---|
| Şube | 1 | $85.000 | 3 gün | $260 | Şehirde sözleşme hakkı; teklif yuvası tabanı |
| Şube | 2 | $190.000 | 5 gün | $520 | +%50 yuva; toplu/süresiz arketip açılır |
| Şube | 3 | $420.000 | 8 gün | $1.050 | +%100 yuva; çok noktalı arketip; +%3 hat primi |
| Depo | 1 | $260.000 | 5 gün | $700 | 400 t / 1.600 m³ · 2 kapı |
| Depo | 2 | $580.000 | 8 gün | $1.550 | 1.200 t / 4.800 m³ · 4 kapı |
| Depo | 3 | $1.250.000 | 12 gün | $3.200 | 3.500 t / 14.000 m³ · 8 kapı · –%25 elleçleme süresi |

İnşa süresi de `siteFactor` ile hafifçe ölçeklenir (pahalı/kalabalık şehirde izin ve
inşaat daha uzun): `süre × (0.85 + 0.3 × popNorm)`.

Bunlar **ilk kalibrasyon tahminleridir**; Faz 4'te `scripts/` ile ölçülecek. Gerçekçilik
çapası: ABD'de sınıf-A dağıtım deposu inşası ~$100–160/m²; 10.000 m²'lik tesis ≈ $1,2M.
Seviye 3 deposu bu ölçekte, seviye 1 ise küçük bir cross-dock tesisidir.

**Kapı (dock) modeli:** Faz 2'de kuyruk simülasyonu yok. Kapı sayısı yalnızca *eşzamanlı
servis* sınırıdır: kapasiteyi aşan araç `waiting` fazında bekler. GDD'nin tam kuyruk
kümesi (cross-dock, geciken yük, ayrılmış kapasite) bilinçli olarak ertelenir.

### 1.3 Yük konumu — çok aşamalı taşımanın temeli

Bugünkü `RouteShipment` bir rotaya *bağlı*. Depo üzerinden aktarma, yükün rota sınırını
aşmasını gerektirir. Bu yüzden tip yeniden adlandırılır ve konum açık hale getirilir:

```swift
enum CargoLocation: Codable, Hashable, Sendable {
    case address(CityID)        // alış adresinde bekliyor
    case vehicle(VehicleID)     // araçta
    case warehouse(FacilityID)  // depoda
}

struct Shipment: Codable, Identifiable, Sendable {
    let id: JobID
    let offer: JobOffer          // adresler, ürün, kütle, ödeme, son tarih
    var location: CargoLocation
    /// Şu an bu yükü taşımayı üstlenen rota. nil = depoda/adreste serbest bekliyor.
    var assignedRouteID: RouteID?
}
```

`GameState.routeShipments` → `shipments`. `RouteShipment` tipi kaldırılır; mevcut
`routeShipments(of:)`, `cargoLoad(of:)` sorguları `location`/`assignedRouteID` üzerinden
yeniden yazılır (davranış aynı kalır, sadece kaynak alan değişir).

**Lot görünümü (sunum):**

```swift
struct StorageLot: Identifiable {          // türetilmiş, Codable değil, kaydedilmez
    let key: LotKey                        // (productID, destinationCityID, contractID?)
    let facilityID: FacilityID
    let shipmentIDs: [JobID]               // son tarihe göre sıralı
    let massKg: Int, volumeM3: Double
    let earliestDeadline: GameTime?
    let pendingPayout: Money
}
```

### 1.4 Rota görevleri

```swift
enum RouteTask {
    case travel
    case pickupShipment(JobID)
    case deliverShipment(JobID)
    case pickupContract(ContractID)
    case deliverContract(ContractID)
    // YENİ
    case dropToWarehouse(FacilityID)     // araçtaki, bu şehirde depolanabilir tüm yükü indir
    case loadFromWarehouse(LotKey)       // seçilen lottan kapasite dolana dek yükle
    case deliverAll                      // bu şehirde teslim edilebilecek her yükü boşalt
}
```

`deliverAll`, hub-and-spoke dağıtımın anahtarıdır: dağıtım aracı depodan karışık lot
yükler, sırayla şehirleri gezer, her durakta oraya ait olanı bırakır. Kullanıcının
"100 aracımla batıdaki yükleri toplayıp en büyük depoma gönderip oradan dağıtayım"
senaryosu tam olarak şu üç görevle kurulur:
`pickupContract → dropToWarehouse` (toplama rotaları) + `loadFromWarehouse → deliverAll…`
(dağıtım rotaları).

### 1.5 Sözleşmeler

```swift
enum ContractArchetype: String, Codable, Sendable {
    case laneRecurring   // her N günde bir M ton, A → B
    case bulkPeriodic    // dönemsel yüksek hacim; tek araca sığmaz, parçalara bölünür
    case evergreen       // bitiş tarihi yok; güvenli kapatmaya kadar sürer
    case multiDrop       // tek kaynak → birden çok hedef, paylara bölünmüş hacim
}

struct ContractDestination: Codable, Hashable, Sendable {
    let cityID: CityID
    let firmID: FirmID?
    let shareBps: Int        // dönem hacminin on binde payı; toplam 10.000
}
```

`ContractOffer` / `ActiveContract`'a eklenenler:

| Alan | Anlam | Neden |
|---|---|---|
| `archetype` | arketip | UI rozeti + motor davranışı |
| `destinations: [ContractDestination]` | tek elemanlı = klasik hat | multiDrop tek modelle çözülür |
| `volumePerCycleKg` | dönem başına toplam hacim | bulk'ta tek araca sığmaz |
| `parcelMassKg` | bir sevkiyat partisinin kütlesi (referans araç kapasitesi) | hacim / parça sayısı |
| `leadTimeMinutes` | imzadan **ilk** partiye hazırlık süresi | oyuncuya lojistik kurma şansı |
| `deliveryWindowMinutes` | parti postalandıktan sonra teslim penceresi | **bugünkü hatanın kaynağı** |
| `endsAt: GameTime?` | nil = evergreen | süresiz sözleşme |
| `cancellationRequestedAt: GameTime?` | güvenli kapatma | GDD yaşam döngüsü adım 7 |

**Bugünkü hata:** parti son tarihi `shipmentIntervalMinutes` ile eşitlenmiş
(`expiresAt = clock + interval`). Yani "her gün 1 parti" sözleşmesinde partiyi 24 saat
içinde teslim etmek zorundasın — 800 km'lik hatta imkânsız. `deliveryWindowMinutes`
bunu ayırır; öneri: `max(1.5 × tek yön süre + elleçleme, 0.75 × interval)`.

### 1.6 Şirket ölçeği ve teklif kalibrasyonu

Saf, deterministik türetme (`GameState` → tier); rastgelelik yok:

```
tier 1: araç ≤ 3
tier 2: araç 4–10          veya  teslim edilmiş iş ≥ 40
tier 3: araç 11–30         ve   operasyonel depo ≥ 1
tier 4: araç > 30          ve   seviye ≥ 2 depo ≥ 1
```

| Tier | Açılan arketipler | Dönem hacmi tavanı |
|---|---|---|
| 1 | laneRecurring | 1 × referans araç kapasitesi |
| 2 | + evergreen | 3 × |
| 3 | + bulkPeriodic | 12 × |
| 4 | + multiDrop | 40 × |

Böylece oyun başında 500 t'lik teklif hiç üretilmez; end-game'e emekle gidilir.

**Teklif sayısı ise tier'a değil şehre bağlıdır** — oyuncu sözleşme aramakla
uğraşmamalı. Şubeli bir şehirde eş zamanlı açık teklif:

```
slots(city, branchLevel) = round( (3 + 6 × marketSizePercent) × levelFactor )
levelFactor = [1: 1.0, 2: 1.5, 3: 2.0]
```

`marketSizePercent` `CityInsight`'tan gelir (nüfus normalizasyonu). Sonuç: orta metroda
(Las Vegas) sv1 şubede ~5, büyük metroda (New York) sv3 şubede ~18 açık seçenek.
Teklifler günde bir tazelenir; kabul edilmeyen süresi dolar, yerine yenisi gelir.
**Sözleşme, spot işin kıtlık ekonomisine tabi değildir** — kıt olan şube yatırımıdır.

**Getiri de şehir verisinden türer.** `contractMarginPercent` sabit değil, şehre göre:

```
margin = base × (1 + 0.35 × marketSizePercent) × (1 − 0.30 × competitionPercent)
```

Büyük pazar daha yüksek hacim ve daha iyi marj sunar; yüksek rekabet marjı kırpar.
`competitionPercent` bugün `CityInsight`'ta zaten hesaplanıyor (nüfus + costIndex);
rakip şirketler geldiğinde bu tek nokta değişir, formül aynı kalır.

---

## 2. Motor davranışı

### 2.1 Yeni komutlar

```swift
case buildFacility(kind: FacilityKind, cityID: CityID)
case upgradeFacility(FacilityID)
case demolishFacility(FacilityID)          // HQ hariç; iade yok, depo boş olmalı
case addWarehouseTaskToRoute(routeID:, visitStopID:, task: RouteTask)
case cancelContract(ContractID)            // güvenli kapatma
```

Yeni hata durumları: `facilityAlreadyExists`, `facilityNotOperational`,
`branchRequired`, `warehouseNotEmpty`, `storageCapacityExceeded`.

### 2.2 Sözleşme yaşam döngüsü (revize)

1. **Üretim** — teklif yalnız `hasOperationalBranch(in: origin)` olan şehirlerde;
   arketip ve hacim `companyTier` ile sınırlı; hedefler `city_markets` talebinden seçilir.
2. **İmza** — `nextShipmentAt = clock + leadTimeMinutes`. İlk parti hemen postalanmaz;
   UI kabul ekranında "ilk yük X saat sonra hazır" yazar (GDD "kabul öncesi değerlendirme").
3. **Parti üretimi** — dönem geldiğinde `volumePerCycleKg`, `parcelMassKg`'a bölünüp
   N adet `Shipment` üretilir (multiDrop'ta `shareBps` oranında hedeflere dağıtılır).
   Her partinin son tarihi `clock + deliveryWindowMinutes`.
4. **Taşıma** — partiler rota görevleriyle taşınır; depo aktarması serbesttir. Ödeme
   yalnız **nihai hedef adresine** teslimde ödenir; depoya bırakmak gelir yaratmaz.
5. **Gecikme** — son tarih geçen parti `contractPenaltyPercent` cezası keser ve
   `shipmentsMissed`'i artırır. Yük yok olmaz; geç de olsa teslim edilebilir (ödeme
   yapılır, ceza geri alınmaz).
6. **Bitiş / kapatma** — süreli sözleşme `endsAt`'te kapanır; evergreen `cancelContract`
   ile güvenli kapanır: yeni parti üretilmez, mevcut partiler teslim edilir, hepsi
   çözülünce sözleşme arşive gider.

### 2.3 Kapsam (coverage) — "araç atanmadı" uyarısının doğru hâli

**Kök neden (doğrulandı).** `JobsView.swift:635` sözleşmenin rotasını
`state.route(forContract:)` ile arıyor; bu sorgu yalnız `route.contractID == id` olan,
yani "araç ata" düğmesiyle **otomatik yaratılmış** rotayı bulur. Oyuncu yükü kendi
kurduğu rotayla (`pickupContract` görevi ekleyerek) taşıyorsa o rotanın `contractID`'si
`nil`'dir, sorgu boş döner ve kırmızı "No vehicle assigned" uyarısı çıkar — yük yolda
olsa bile. Uyarı yapısal bir kontrol; oysa ölçülmesi gereken akış. Yerine motorda salt
okunur bir değerlendirme:

```swift
enum ContractCoverage { case covered, partial(carriedPercent: Double), uncovered }
```

Ölçüt yapı değil **akış**tır: son dönemde üretilen partilerin kaçı zamanında teslim
edildi / şu an bir araçta veya bir depoda ilerliyor. Yeni sözleşmede henüz veri yokken
"kapsam bilinmiyor — ilk parti X saat sonra" gösterilir, uyarı değil bilgi olarak.

### 2.4 Determinizm

Yeni sistemlerin tamamı mevcut sözleşmeye uyar: tesis inşaatı ve yükseltmesi zaman
damgalı olay olarak `advance` içindeki kronolojik olay kuyruğuna girer; depo yükleme
seçimi (son tarih, sonra `JobID`) tam sıralıdır; tier türetmesi saf fonksiyondur.
Parçalı `advance` = tek seferlik `advance` testi yeni senaryolarla genişletilir.

---

## 3. UI / UX

### 3.1 Harita — kalabalık yapmadan bilgi

Şehir düğümü bugün: işaret + ad + boştaki araç rozeti. Eklenecek **iki** öge:

1. **Tesis şeridi** (işaretin altında, 8 px): sahip olunan yapıların mini ikonları —
   şube `building.2.fill`, depo `shippingbox.fill`. En fazla 2 ikon; marka rengiyle
   doldurulur. Zoom-out'ta işaretle birlikte küçülür.
2. **Aksiyon rozeti** (adın sağında, mevcut filo rozetinin yanında): o şehirde
   *oyuncunun ilgilenmesi gereken* sözleşme yükü sayısı. Renk = aciliyet:
   sarı (>%50 pencere kaldı) → turuncu (<%50) → kırmızı (<%15 veya gecikmiş).
   Yalnız sayı gösterilir; ayrıntı şehir ekranındadır.

Filo rozeti + aksiyon rozeti aynı satırda en fazla iki daire — mevcut `labelRow`
yerleşimi bunu kaldırıyor. Zoom-out'ta önce ad, sonra filo rozeti sönümlenir;
**aksiyon rozeti en son sönümlenir** çünkü kaçırılmaması gereken bilgi odur.

### 3.2 Şehir ekranı (`CityDetailView`) — sözleşme yönetiminin merkezi

Mevcut bölümlerin (pazar/rekabet, giden yük, yapılar, araçlar) arasına:

- **"Bu şehirde bekleyen yük"** — sözleşme partileri: ürün, kütle, hedef, kalan süre
  çubuğu, sözleşme adı. Satıra dokunma → "Rotaya ekle" / "Araç ata".
- **"Depo"** (varsa) — doluluk çubuğu (kütle + hacim ayrı), lot listesi, lot satırında
  "Rotaya ekle". Depo yoksa "Depo kur" kartı, maliyet ve süreyle.
- **"Şube"** (varsa) — bu şehirdeki açık sözleşme teklifleri + imzalı sözleşmeler,
  kapsam durumu rozetiyle. Şube yoksa: *"Bu şehirden sözleşme almak için şube gerekir"*
  + maliyet + "Şube kur".

### 3.3 Tesisler sekmesi

Bugünkü görsel kabuk gerçek listeye dönüşür: şehir bazlı gruplanmış tesis kartları
(seviye, doluluk, günlük gider, inşaat geri sayımı), "Yapı kur" akışı (şehir seçici →
tür → maliyet/süre onayı), seviye yükseltme.

### 3.4 Rota kurucu

`RouteTaskPicker`'a depo görevleri eklenir. Depolu şehirde durak seçildiğinde:
"Depoya boşalt" / "Depodan yükle (lot seç)" / "Buraya ait her şeyi teslim et".
Lot seçici, şehir ekranındaki lot listesinin aynısıdır (tek bileşen, iki yerde).
`loopReturnKm` uyarısı da bu fazda eklenir (`ROTA_SISTEMI_PLAN.md` §2).

### 3.5 İşler → **Operasyon** sekmesi

Bugün: `İşler → Aktif|Pazar → Spot|Kontrat|İhale` (sözleşme 3 seviye derinde).
Yeni: **tek seviye, üç mod** — `Operasyon → Aktif · Sözleşmeler · Pazar`.

- **Aktif** — yoldaki her şey: spot işler, rota koşuları, sözleşme partileri tek akışta.
- **Sözleşmeler** — imzalı portföy. Her satırda arketip rozeti, kaynak → hedef(ler),
  dönem hacmi, sonraki parti geri sayımı, kalan süre (veya "Süresiz"), **kapsam rozeti**.
  Detayda GDD'nin "kabul öncesi değerlendirme" listesi: beklenen yük profili, gereken
  araç eşdeğeri, tahmini marj, ilk parti zamanı.
- **Pazar** — imzalanacak teklifler, şubeli şehirlere göre gruplanmış. Şube yoksa
  bölüm boş değil: *"Bu şehirde şube yok — sözleşme alamazsın"* + maliyet + kısayol.
  `Tender` (ihale) segmenti kaldırılır; kapsamda değil, boş sekme kafa karıştırıyor.

Aynı sözleşme teklifleri şehir ekranındaki şube kartında da görünür (tek bileşen,
iki giriş noktası) — spot işte kurulan "haritadan yönet" mantığının aynısı.

---

## 4. Uygulama fazları

Her faz kendi içinde derlenir, testleri geçer ve tek başına oynanabilir.

### Faz 0 — Veri modeli ve kayıt (kod, UI yok)
`Facility`, `Shipment`/`CargoLocation`, sözleşme alanları, `RouteTask` genişlemesi,
kayıt sürümü 8. `routeShipments` → `shipments` göçü.
**Doğrulama:** mevcut test paketi (`SimulationEngineTests`, `GameCatalogTests`,
`MapFoundationTests`, `OfferCalibrationTests`, `CityInsightTests`, `GameNotificationTests`)
kırmızıya düşmeden geçer; determinizm testi yeni tiplerle genişletilir.
`Identifiers.swift`'e `enum FacilityTag {}` + `typealias FacilityID = RuntimeID<FacilityTag>`.

### Faz 1 — Şube + HQ buff + sözleşme kapısı
`buildFacility`/`upgradeFacility`, inşaat süresi, günlük gider, HQ otomatik şubesi,
`hqLanePremiumPercent`, sözleşme üretiminde şube şartı, Tesisler sekmesi + şehir ekranı
"Şube kur", harita tesis şeridi.
**Doğrulama:** şubesiz şehirde sözleşme teklifi üretilmediğini, HQ şehrinde üretildiğini,
inşaat bitmeden hak doğmadığını gösteren testler.

### Faz 2 — Depo + lot envanteri + çok aşamalı rota
Depo kapasitesi, `dropToWarehouse` / `loadFromWarehouse` / `deliverAll`, lot türetmesi,
kapasite aşımı davranışı, depo UI'ı ve rota kurucu görev seçici.
**Doğrulama:** A→depo→B üç aşamalı teslimin tek seferde teslimle **aynı geliri**
ürettiği; kapasite dolu depoya bırakmanın reddedildiği; lot seçiminin son tarihe göre
sıralandığı testleri.

### Faz 3 — Sözleşme revizyonu
4 arketip, `leadTimeMinutes`, `deliveryWindowMinutes`, çok parçalı dönem hacmi,
`multiDrop` payları, evergreen + güvenli kapatma, `ContractCoverage`, tier kalibrasyonu.
**Doğrulama:** her arketip için parti üretim takvimi testi; gecikme cezasının yalnız
pencere aşımında işlediği; tier 1'de bulk teklif üretilmediği.

### Faz 4 — Görünürlük, cila, ekonomi kalibrasyonu
Harita aksiyon rozeti, şehir ekranı bekleyen yük bölümü, sözleşme detay ekranı,
`scripts/calibrate_contracts.py` ile hub-and-spoke ağının tek tek spot işlere karşı
%15–30 daha iyi net üretmesinin ölçülmesi.
**Doğrulama:** kalibrasyon çıktısı + `OfferCalibrationTests` benzeri bir eşik testi.

---

## 5. Riskler ve bilinçli ertelemeler

- **Depo kuyruk simülasyonu** (GDD'nin 7 kuyruk kümesi, cross-dock ayrımı) Faz 2'de
  kapı sayısına indirgenir. Tam model, hacim gerçekten dert olduğunda.
- **Depo uzmanlıkları** (Şehir Dağıtım Merkezi / Bölgesel Hub / Transit Terminal)
  kapsam dışı; seviye ve kapasite önce oturmalı.
- **Personel, yönetici, itibar, SLA puanı** kapsam dışı — sözleşme cezası tek yaptırım.
- **Performans:** 100+ araç × yüzlerce `Shipment` değer tipi; `shipments` üzerinde
  lineer aramalar Faz 2 sonunda profil edilir, gerekirse şehir/depo indeksi eklenir.
- **En büyük risk:** Faz 0'daki `RouteShipment` → `Shipment` göçü rota koşucusunun her
  yerine dokunur. Bu yüzden önce ve tek başına yapılır; UI değişikliği aynı faza girmez.

---

## 5.1 İlk oynanış turundan gelen düzeltmeler (2026-07-19)

Kullanıcı testi üç yapısal hatayı ortaya çıkardı. Hiçbiri "getiriyi artır" ile
çözülmedi; üçü de modeldeki eksikti.

**1. Kontrat aracı aç kalıyordu.** Kısa bir hatta günlük ritim tek yük istiyordu;
adanmış araç 20 saat boş bekliyor ama sahiplik maliyeti işlemeye devam ediyordu.
*Kök neden:* hacim ritimden bağımsız rastgele bir çarpandı.
*Düzeltme:* hacim artık ritimden türüyor —
`parcels = interval × %65 hedef doluluk × araç eşdeğeri / cycle`. Günlük kısa hat
artık günde 3 tur istiyor. Tier ceiling'i "parça sayısı" değil "araç eşdeğeri".

**2. Fiyat teklifi aracın kendi maliyetini saymıyordu.** `taskCost` yalnız yakıt
ve şoförü içeriyordu; `fixedCostPerDay` hiç hesaba girmiyordu, yani teklif gerçek
bir teklif değildi. `contractCycleCost` artık turun gün payını hedef dolulukla
brütleştirip ekliyor. Aracını daha iyi dolduran oyuncu farkı cebine koyar.

**3. Teklifler "bir görünüp bir kayboluyordu".** Teklif ömrü 1440 dk, tazeleme
aralığı 2880 dk idi — panoda tam bir günlük boşluk oluşuyordu. Ömür artık tazeleme
aralığının 3 katı, tazeleme günlük.

**4. Kontratlar oyunun ilk saniyesinde açıktı.** `contractsUnlockAfterDeliveries`
(varsayılan 2) eklendi: ilk günler spot iş, kontrat kazanılan bir şey.

**5. Süre gösterimi.** `Format.duration` 24 saati aşan her değeri gün, 14 günü
aşanı hafta olarak veriyor. "600 h" gibi okunamaz değerler bitti.

**6. Kontrat kartı metin duvarıydı.** Yeni `ContractBrief` motorda üç sayı
hesaplıyor — *kaç araç bağlar, günde ne bırakır, filonun ne kadarını kullanır*.
Kart artık: hat + ürün ikonu, tek büyük **$/gün** rakamı (zarar ediyorsa kırmızı
+ uyarı), üç ikon-çip (araç ×N · ritim · süre), İmzala. Firma adları, parça
kütlesi, hazırlık/teslim pencereleri "…" düğmesinin altında.

**7. Harita ikonu okunmuyordu.** Çıplak tint'li glif harita ölçeğinde leke gibi
görünüyordu; artık beyaz glifli dolu disk (şube = marka rengi, depo = mint),
3× çözünürlükte rasterize.

## 5.2 İkinci oynanış turundan gelen düzeltmeler (2026-07-19)

**1. Kontrat yüklemesi aracı doldurmuyordu — en büyük zarar kaynağı.**
`pickupContract` her durakta **tek** parti alıyordu; 22 tonluk tır 1 tonla yola
çıkıyor, turun tamamı ödenmiş ama boş gidiyordu. Artık dok ziyareti aracı
kapasitesine kadar dolduruyor (o sözleşmenin partileriyle, son tarihi yakın
olandan başlayarak). Bu aynı zamanda §4'ün altyapısı: **doğru araç seçmek ve
rotayı doğru kurmak artık ölçülebilir biçimde daha çok kazandırıyor.**
`RouteRun.claimedShipmentID` → `claimedShipmentIDs`.

**2. Sözleşmeye özel rota adanmış kalır.** Doldurma sözleşme kapsamlıdır: adanmış
rota başka sözleşmenin yükünü toplamaz. İki sözleşmeyi tek araca koymak isteyen
oyuncu bunu **custom rotaya iki `pickupContract` durağı** ekleyerek yapar (§5).

**3. Kontrat panosu boşalıp dolmuyordu.** İki neden vardı: (a) pano yalnız gün
tikinde dolduruluyordu, imzalayınca ara boşluk kalıyordu; (b) tüm teklifler aynı
anda üretilip aynı anda doluyordu. Artık `replenishContractOffers` olay
döngüsünün her geçişinde eksik panoyu tamamlıyor ve teklif ömürleri
tazeleme aralığının 2–6 katı arasında dağıtılıyor. **Şube/merkez olan şehirde
pano boş kalmaz — araç orada olmasa bile.**

**4. Kontrat bitince rota yaşam döngüsü.** `retireRoutes(ofEndedContract:)`:
sözleşmenin *kendi* rotası (otomatik kurulmuş, `Route.contractID` işaretli)
sözleşmeyle birlikte durdurulur ve `contractRouteClosed` bildirimi çıkar.
Oyuncunun kendi kurduğu rotaya **dokunulmaz** — ama artık ölü olan sözleşme
durakları `routeNeedsReview` uyarısıyla bildirilir, yoksa araç boş tur atmaya
devam eder ve oyuncu fark etmez.

**5. Aktif seferler ekranı.** İncecik iki satırlık liste gerçek sefer kartı oldu:
araç kodu + ikon, bacak (şehir → şehir, durak x/y), faz ilerleme çubuğu, **doluluk
yüzdesi ve kapasiteye karşı yük**, yükün hangi şehirlere gittiği (çip olarak
gruplanmış), teslimde tahsil edilecek tutar. Boş giden araç kırmızı "Running
empty" ile işaretlenir — verimsizlik artık görünür.

## 5.3 Spot ekonomisi — yapısal düzeltme (2026-07-19)

**Belirti:** oyuna başlayan oyuncuya ilk çıkan spot işler zararına görünüyordu;
bazen de aşırı kârlı işler çıkıyordu. Getiriyi artırmak çözüm değildi, çünkü
sapma iki yönlüydü.

**Kök neden:** `freightPayout` fiyatı `vehicleType.freightRatePerKm × km` ile
hesaplıyordu — **oran araç tipine bağlıydı**. Teklif, üretim anındaki referans
sınıfa göre fiyatlanıyor ama maliyeti oyuncunun *atadığı* araç ödüyordu. Oyunun
ilk turu bu uyuşmazlığın tam merkezi: oyuncunun henüz aracı yok → teklifler
"alınabilir en ucuz" sınıfa göre fiyatlanıyor → oyuncu box_truck alıyor →
tahtadaki her iş garanti zarar. Ters yönde de aynı şey aşırı kâr üretiyordu.

**Düzeltme (oran kaldırıldı, fiyat maliyetten türüyor):**

```
base   = yakıt + aşınma + şoför + aracın çalıştığı saatlerin gün payı
margin = spotMarginPercent × aciliyet × bölge fiyat düzeyi × doluluk × yerel varlık
fiyat  = base × (1 + margin)
```

`VehicleTypeDefinition.freightRatePerKm` tamamen kaldırıldı (katalogdan da).

**Neden clamp yok:** maliyet geri kazanımı hiçbir çarpanla ölçeklenmiyor —
şoför acele etmiyor diye yakıt ucuzlamaz. Piyasa koşullarının tamamı yalnız
**marjı** ölçekliyor ve hepsi pozitif çarpan olduğu için fiyat, yapısı gereği
maliyetin üstünde. Alt sınır bir kural değil, modelin sonucu:
**+%20,7 – +%75,2** (oran bandı 1,21× – 1,75×).

**Ayrıca:** `lanePremiumFactor` (HQ/şube primi) hesaplanıp **hiç
kullanılmıyordu** — bu yüzden merkez şehirden çıkan işler "bufflu" olmasına
rağmen farksızdı. Artık marja giriyor.

**Dünya canlılığı:** `ensureLocalSpotOffers` olay döngüsünün her geçişinde
çalışıyor — boşta aracı olan bir şehirde spot tahtası sıfırsa oraya iş üretiyor.
Yük teslim ettiğin şehirde tahta tanımı gereği boşalır (taşıdığın yük oydu);
araç artık bir sonraki parti tikini beklemiyor. Şehir kartında boş spot listesi
hiç gösterilmiyor.

## 6. Karar kaydı

| # | Soru | Karar (2026-07-19) |
|---|---|---|
| 1 | "Kimlik motorda, lot ekranda" rafinesi | Kabul |
| 2 | Sözleşmede varış şubesi de şart mı | Hayır — yalnız kaynak şehir |
| 3 | Tesis fiyatı sabit mi | Hayır — şehir verisinden türetilir (§1.2) |
| 4 | Faz sırası | Hepsi tek blokta |
| 5 | Sözleşme bolluğu | Şehir verisine bağlı, bol; arama zorluğu olmamalı (§1.6) |
| 6 | Sözleşme bilgi mimarisi | İşler → Operasyon: Aktif · Sözleşmeler · Pazar (§3.5) |
