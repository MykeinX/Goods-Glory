# Akış ve Hat Revizyonu — Çekirdek Oynanış Planı

Son güncelleme: 2026-07-20. Statü: **onaylandı** (geri bildirimler §0.2'ye işlendi).

Bu belge revizyonun **gerekçesi ve faz kaydıdır**. Sistemin güncel tanımı GDD
(`Game Design Documents/`), kodun güncel tanımı `Goods&Glory/ARCHITECTURE.md`
içindedir; çelişkide onlar geçerlidir.

---

## 0. Teşhis — neden bu revizyon

**GDD'nin vizyonu doğruydu; kod ters kuruldu.** Kanonik model belgesi
"Sözleşme hiçbir araca doğrudan bağlanmaz" der ve servis hattını sözleşmeden
bağımsız, birden çok müşterinin yükünü taşıyan kalıcı bir operasyon olarak
tanımlar. Kodda ise `Route.contractID` var: rota sözleşmenin hizmetkârı,
kontrat bitince rota boşa dönüyor. Bu bir bug değil, ters modelin sonucu.

**Kök sorun:** Oyunda talep *kalıcı bir akış* değil, *süresi dolan işlemler*
(spot teklif + süreli kontrat). Mini Motorways'te evler sürekli üretir,
Satisfactory'de maden bitmez — oyuncu kalıcı akışın üzerine sistem kurar ve
onu optimize eder. Bizde optimizasyon hedefi (rota), sürekli buharlaşan talep
üzerine oturduğu için "sistem kurdum" hissi hiç oluşmuyor; ilk saat de
tıkla-kabul-et döngüsüne düşüyor.

## 0.1 Onaylanan yön kararları (2026-07-20)

| # | Konu | Karar |
|---|---|---|
| 1 | Talep modeli | Kalıcı firma→firma yük akışları temel; süreli fırsat olayları sonraki fazda üstüne |
| 2 | Spot iş | Ayrı bir "spot iş" nesnesi kalmaz; spot = akışın servis edilmemiş partileri. Manuel tek sefer göndermek mümkün kalır ama tekliflerle değil akışlarla |
| 3 | Kontrat | Talep yaratmaz; mevcut akışın üzerine taahhüt katmanıdır (daha iyi fiyat + SLA + ceza). Bitince akış tabana döner, hat boşa düşmez |
| 4 | Tesis | Şube/depo ayrımı kalkar: şehirde **tek tesis + modüller** (ofis, depo, dok, otopark…) |
| 5 | Kapsam | Önce bu plan; onaydan sonra GDD güncellenir, sonra uygulama fazları |

## 0.2 Onay turu geri bildirimleri (2026-07-20) — bağlayıcı ilkeler

1. **Şehir üretim/tüketim kimliği gerçekçi olmalı.** Akışlar şehrin gerçek
   ekonomik kimliğinden türemeli ("Bursa sürekli otomotiv parçası üretir,
   İstanbul tüketir" netliğinde). `city_markets.json` üretimi Faz 0'da bu gözle
   denetlenir; gerekirse ürün/ağırlık tanımları geliştirilir.
2. **Sabit ama canlı:** taban akışlar kalıcıdır; haftalık dalgalanma + ileride
   olaylar canlılık verir. Rastgele kaos yok, okunabilir değişim var.
3. **Harita-öncelikli okunabilirlik (tasarım sütunu).** Oyuncu sistemi sekme
   sekme gezmeden haritadan anlayıp takip edebilmeli. Sekmeler derinlik içindir,
   ana yüzey haritadır (§3 buna göre revize edildi).
4. **Parametre diyeti.** Yeni denge parametresi eklemek istisnadır, kural değil.
   Eldeki veriler (nüfus, costIndex, rekabet, erişim bayrakları) yeniden
   kullanılır; her yeni parametre "dengelemesi mümkün mü?" sorusunu geçmek
   zorundadır. Rekabet, fiyat marjına **tek noktadan** etki eder (§1.2).
5. **Hat kurucu UX yeniden tasarlanır.** Mevcut durak-durak kurulum, sistemi
   bilen kullanıcıyı bile zorluyor. Yeni kurulum akış-önceliklidir (§3.1).
6. **Tesis uzmanlaşması strateji alanıdır.** Modül + eklenti + seviye ile her
   tesis farklı yönde (hız vs depolama vs kapasite) özelleştirilebilir (§1.5).
7. **Şirket kapasitesi göstergesi onaylı** (zorunlu mekanik değil, ölçüm aracı).
8. **Doküman hijyeni:** revizyon tamamlanınca eski plan/karar dokümanları
   temizlenir; hiçbir oturumda eski talimat yürürlükte kalmaz (Faz 6).

---

## 1. Yeni çekirdek model

Yeni omurga (GDD kanonik zincirinin önüne bir halka eklenir):

> **Yük Akışı → (Kontrat) → Yük Partisi → Hat → Fiziksel Görev**

### 1.1 Yük Akışı (FreightFlow) — dünyanın kalıcı talebi

```swift
struct FreightFlow: Codable, Identifiable, Sendable {
    let id: FlowID                    // deterministik: origin firma + hedef firma + ürün
    let originFirmID: FirmID          // yük buradan alınır (tesis adresi)
    let destinationFirmID: FirmID     // buraya teslim edilir
    let productID: ProductID
    var ratePerDayKg: Int             // taban debi; yavaş dalgalanır (haftalık)
}
```

- **Türetme:** Firmalar gibi `city_markets.json` arz/talep ağırlıklarından
  deterministik türetilir (yeni kayıt verisi yok, seed + katalog yeter).
  Bir şehir çifti + ürün eşleşmesi = bir hat (lane); hat üzerinde 1–3 akış.
- **Süresizdir.** Debi haftalık taban döngüsüyle dalgalanır; sezon/kriz/olay
  çarpanları sonraki fazda aynı noktaya eklenir (GDD "Arz-talep üretimi"
  bölümüyle uyumlu).
- **Kimlik korunur (kullanıcı maddeleri 6–7):** Akıştan doğan her parti
  `Shipment` kimliğiyle yaşar: `flowID`, müşteri firması, alış tesisi, teslim
  tesisi, son tarih. Farklı firmaların aynı üründeki yükleri karışmaz; kapasite
  uyumluysa birlikte taşınır (bugünkü `Shipment`/`CargoLocation` aynen kalır).

### 1.2 Akıştan partiye: sınırlı birikim

- Akış, alış tesisinde zamanla yük biriktirir; birikim araç-partisi boyuna
  ulaştıkça **bekleyen parti** üretir (son tarihi ürün servis sınıfından).
- **Birikim sonsuz değildir.** Dokta en fazla sabır penceresi kadar üretim
  tutulur; bunun üzerindeki üretim ayrıca sayılmaz veya raporlanmaz. Oyuncunun
  fırsatı, akışın güncel debisi ve dokta bekleyen yük üzerinden okunur.
- Fiyat: 5.3'te kurulan maliyet-türevli model aynen kalır
  (`base × (1 + margin)`); bu, akışın **spot ücreti**dir. Kontratsız taşınan
  her parti bu ücretle ödenir. Şehir rekabeti (`CityInsight.competitionPercent`)
  marjı bu tek formül noktasında kırpar — kontrat marjında zaten böyle,
  spot ücrete de aynı çarpan girer. Yeni rekabet parametresi eklenmez.

### 1.3 Hat — ana oyuncu nesnesi

Bugünkü `Route` modeli korunur ve **sözleşmeden bağımsızlaşır**:

- `Route.contractID` **kaldırılır**; `assignVehicleToContract` ve otomatik
  kontrat rotası kurulumu kalkar. Kontrata hizmet etmek = hattın kapsamına o
  akışı almak.
- **Kapsam (coverage) tersine döner:** Hat, hangi akışları/kontratları
  taşıdığını bilir (`servedFlowIDs` / politika); duraklarında biriken uyumlu
  partileri **kendisi çeker**. Öncelik: SLA'lı kontrat partisi → son tarihi
  yakın → getirisi yüksek. (GDD "kalkış yerleştirme politikaları"nın ilk
  somut hali; tek varsayılan politikayla başlanır, seçenekler sonra.)
- Depo görevleri (`dropToWarehouse`, `loadFromWarehouse`, `deliverAll`) aynen
  kalır — toplama/dağıtım ve hub-and-spoke bunlarla kurulmaya devam eder.
- Kontrat bitince hat **boşa düşmez**: aynı duraklardaki taban akıştan spot
  ücretle dolmaya devam eder. Doluluk düşer; sinyali oyuncu okur ve hattı
  düzenler ya da kapatır. `routeNeedsReview` "ölü durak" uyarısı yerine
  "doluluk düştü" bilgisine dönüşür.

### 1.4 Kontrat — akış üzerine taahhüt

- Kontrat teklifi bir **akıştan** doğar: "Bu akışın debisinin %X'ini şu SLA
  ile taahhüt et" → spot ücrete prim + öncelik + gecikme cezası.
- Teklif kaynağı ilişkidir: bir firmanın akışını yeterince servis eden oyuncuya
  o firma kontrat önerir; ofis modülü (eski şube) şehirdeki teklif yuvası
  sayısını artırır. `companyTier` hacim tavanı aynen kalır.
- Mevcut 4 arketip korunur ama anlamı değişir: hepsi akış payı taahhüdünün
  varyantlarıdır (dönemsel hat = tek akış; multiDrop = bir kaynağın birden çok
  akışı; bulk = dönemsel debi sıçraması; evergreen = süresiz pay).
- Bitiş/fesih: taahhüt biter, **akış kalır**. `ContractCoverage` ölçümü hat
  doluluk metriğine katılır.

### 1.5 Tesis — tek yapı + modüller

```swift
struct Facility {
    let id: FacilityID
    let cityID: CityID
    let isHeadquarters: Bool
    var modules: [FacilityModule]     // her modül: tür + seviye + inşaat durumu
}

enum FacilityModuleKind: String, Codable {
    case office      // eski şube: kontrat yuvaları, yerel temsil
    case warehouse   // depolama kapasitesi, lot/konsolidasyon
    case dock        // eşzamanlı yükleme/boşaltma servisi (+forklift seviyeleri hızlandırır)
    case parking     // araç park + dorse/ekipman barındırma
}
```

- Şehirde tek tesis; HQ kuruluşta `office 1 + parking 1` ile gelir.
- `siteFactor` maliyet modeli (costIndex × nüfus × erişim) modül bazına taşınır.
- **Uzmanlaşma = modül + eklenti + seviye.** İki eksen vardır:
  - *Modül seviyesi* kapasiteyi büyütür (depo sv2 = daha çok ton/m³).
  - *Eklenti* (modüle takılır, kendi seviyesi olabilir) niteliği değiştirir:
    forklift → elleçleme hızı, ek dok → eşzamanlı servis, soğuk oda → ürün
    yeteneği, dorse parkı → ekipman barındırma.
  - Böylece iki depo aynı seviyede farklı karaktere sahip olabilir (hız deposu
    vs hacim deposu) — strateji zenginliği buradan gelir. GDD Tesisler
    belgesindeki modül listesi ve "modüller fiziksel kabiliyettir, soyut yüzde
    değildir" ilkesi temel alınır; uzmanlık ayrı bir "rol seçimi" mekaniği
    olarak değil, eklenti dizilişinin doğal sonucu olarak ortaya çıkar.
  - Parametre diyeti burada da geçerli: her eklentinin etkisi tek ve fiziksel
    bir değere bağlanır (süre, kapasite, yetenek bayrağı) — bileşik yüzde
    bonusları yok.
- Mevcut `branch`/`warehouse` kayıtları modüllü tek tesise göç eder
  (prototip: kayıt sürümü artar, eski kayıt yeni kampanya).

### 1.6 Şirket kapasitesi (kullanıcı maddesi 10)

Filonun toplam debi kapasitesi (kg/gün eşdeğeri) birinci sınıf gösterge olur:
şirket panosunda "taahhüt edilen akış / filo kapasitesi" oranı, kontrat kabul
ekranında "bu taahhüt filonun %X'ini bağlar" uyarısı. `companyTier` türetmesi
zaten bu yönde; sadece görünür hale gelir.

---

## 2. İlk saat — yeniden tasarım

Hedef duygu: "iş kabul ettim" değil, **"ilk yük döngümü kurdum"**.

1. **Kuruluş aynı** (kimlik, şehir, ilk araç).
2. Harita açılır; başlangıç şehrinden çıkan **2–3 akış** görünür
   ("TexMill Dallas → Chicago, tekstil, ~12 t/gün").
3. **İlk sevk (≤2 dk):** akışa dokun → aracı ata → araç bekleyen partiyi alır,
   yola çıkar. Tek teklif ekranı yok; akış zaten orada.
4. **Dönüş dersi:** varış şehrinde geri yönlü akış öne çıkarılır — "boş dönme".
   2–3 manuel sefer boş km kavramını öğretir.
5. **Hat açılışı (~10 dk):** "Bu iki şehir arasında hat kur" → araç hatta
   bağlanır, döngü otomatikleşir; ekranda ilk kez **doluluk % ve boş km**
   görünür. Bundan sonrası optimizasyon: ikinci akışı kapsama al, ikinci araç,
   ilk kontrat teklifi, depo modülü…
6. Kademeli açılım GDD "Başlangıç Deneyimi" sırasını korur; yalnız 3–4. adımlar
   (spot iş → dönüş yükü) akış diliyle yeniden yazılır.

---

## 3. UI — harita ana yüzeydir

**İlke (§0.2/3):** Oyuncu ağının durumunu haritadan okur; sekmeler detay ve
toplu yönetim içindir. "Bu bilgiyi görmek için kaç dokunuş gerekiyor?" her UI
kararının ilk sorusudur. Mevcut sekme/harita düzeni korunur ama ağırlık merkezi
haritaya kayar.

**Haritada okunanlar (dokunmadan):**
- Akışlar: şehirler arası çizgi kalınlığı ≈ debi; servissiz akış soluk,
  oyuncunun taşıdığı marka renginde. Zoom-out'ta yalnız büyük akışlar.
- Hatlar: hat çizgisi + üzerinde hareket eden araçlar; doluluk çizgi
  saydamlığıyla, sorun (düşük doluluk, biriken yük, geciken parti) şehir
  üstünde tek aksiyon rozetiyle görünür.
- Tesis: şehir işaretinde mini modül şeridi (mevcut tasarım korunur).

**Tek dokunuş detayı:** akışa dokun → debi, firma, kim taşıyor, spot ücret,
"hattıma ekle / hat kur". Şehre dokun → şehrin akışları, bekleyen yük, tesis.
Hat çizgisine dokun → hat panosu (doluluk, boş km, $/gün, darboğaz ipucu).

**Sekmeler:** Operasyon → **`Hatlar · Akışlar · Kontratlar`** (liste/karşılaştırma
görünümleri, toplu yönetim). Tesisler sekmesi tek tesis + modül modeline uyar.

### 3.1 Hat kurucu — akış-öncelikli kurulum

Mevcut sorun: durak-durak kurulum; hangi adreste ne alınacağı görünmüyor,
sistemi bilen kullanıcı bile zorlanıyor. Ters çevrilir — **önce yük, sonra rota**:

1. Giriş noktası akıştır: haritada/listede akış seç → "Hat kur". Alış ve teslim
   durakları **otomatik** gelir (akış adresleri zaten belli).
2. Kurucu, hattın güzergâhındaki **uyumlu diğer akışları kendisi önerir**:
   "dönüşte Chicago→Dallas 8 t/gün tekstil var — kapsama ekle?" Boş dönüş
   uyarısı (loopReturnKm) burada sinyal olur.
3. Durak eklemek istisnadır (depo aktarması, çok duraklı dağıtım); eklenen her
   durakta o şehirde ne alınıp bırakılacağı görev satırıyla açık gösterilir.
4. Önizleme her değişiklikte günceller: tur süresi, doluluk tahmini, $/gün.
5. Araç atama kapasite uyumunu gösterir ("bu debi için ~2 tır gerekir").

Depo görevleri (`dropToWarehouse` / `loadFromWarehouse` / `deliverAll`) aynen
kalır; lot seçici tek bileşen olarak şehir ekranıyla paylaşılır.

---

## 4. Kaldırılanlar / korunanlar

**Kaldırılır:** `JobOffer` spot panosu ve üretim döngüleri
(`ensureLocalSpotOffers`, tazeleme), `acceptJob`, `Route.contractID`,
`assignVehicleToContract`, kontrat-otomatik-rota, `contractsUnlockAfterDeliveries`,
`branch`/`warehouse` ayrı yapı türleri.

**Korunur:** `Shipment`/`CargoLocation` (çekirdek), `RouteTask` + depo
görevleri, rota koşucusu ve determinizm sözleşmesi, maliyet-türevli fiyatlama
(5.3), `siteFactor`, firma türetme, `companyTier`, harita/katalog altyapısı,
kayıt zarfı.

---

## 5. Uygulama fazları

Her faz derlenir, test geçer, tek başına oynanabilir; kayıt sürümü fazla artar.

**Faz 0 — Veri denetimi + akış türetme (kod, UI yok).** Önce
`city_markets.json` gerçekçilik denetimi: her şehrin üretim/tüketim profili
ekonomik kimliğiyle uyumlu mu ("Detroit otomotiv üretir" netliğinde); gerekirse
`products.json` / üretim scripti geliştirilir. Sonra `FlowID`, `FreightFlow`,
katalogdan deterministik türetme, haftalık dalgalanma.
*Doğrulama:* aynı seed → aynı akış seti; şehir toplam debisi nüfusla orantılı;
kalibrasyon scripti (`scripts/`) hat başına debi bandını ve şehir başına akış
listesini insan-okur raporlar (göz denetimi için).
**Durum: TAMAMLANDI (2026-07-20).** `CITY_INDUSTRIES` kimlik tablosu (71 şehir)
+ yeniden üretilen `city_markets.json`; `FreightFlow`/`FlowConfig`/`FlowID`;
`GameCatalog.deriveFlows` + doğrulama + sorgular; `economy.json > flows`;
`FreightFlowTests`; raporlar `scripts/city_market_audit.txt` ve
`scripts/freight_flow_report.txt` (814 akış; şehir başına 3–16; tek akış
0.9–100 t/gün). GameState değişmedi → kayıt sürümü aynı kaldı.

**Faz 1 — Akış partileri + manuel sevk.** Birikim → bekleyen parti → sabır
penceresiyle sınırlı birikim; `claimFlowShipments(vehicleID, flowID)` komutu;
spot pano ve `acceptJob` söküm; Akışlar UI + harita akış görselleştirme.
*Doğrulama:* servis edilmeyen akışın kaçırılan yükü ölçülür; parti kimliği
(firma/tesis) uçtan uca korunur; determinizm testleri.
**Durum: TAMAMLANDI (2026-07-20)** — tasarım netleşmeleriyle:
partiler pano teklifi olarak yayınlanmaz; `flowAccrualKg` birikimi dokta
bekleyen yükün kendisidir ve `pickupFlow` görevi partileri **yükleyen aracın
sınıfına göre fiyatlayarak** anlık basar (referans-sınıf uyumsuzluğu kökten
kalktı, teklif seli yok). Sevk komutu `dispatchVehicleToFlow` iki duraklı
mekik rota kurar (`pickupFlow`→`deliverAll`) — Faz 2 hattının embriyosu.
`acceptJob` kontrat partileri için kaldı (Faz 2/3'te gözden geçirilecek).
Sökülenler: spot üretim döngüleri, `UrgencyTier` + 6 spot ekonomi alanı,
`OfferCalibrationTests` (Faz 5'te `calibrate_flows` gelecek). UI: Operasyon →
Flows listesi + FlowRow/sevk, şehir ekranı akışları + kaçırılan yük, harita
popup'ı bekleyen partilere döndü. **Haritada akış katmanı:** koridor başına
tek çizgi (iki yön toplanır), kalınlık ekrandaki en yoğuna göre üç banda
normalize (mutlak tonaj sabiti yok — parametre diyeti), yalnız ayak izine
değen koridorlar çizilir; servis edilen hat zaten rota katmanıyla marka
renginde göründüğü için ayrı "servisli" rengi eklenmedi. Testler: akış
sınırlı birikim, sevk+mekik, parti fiyatlaması, harita kapsaması ve
akış yollu determinizm testleri eklendi; eski spot testleri akış diline
uyarlandı. Kayıt sürümü 10.

**Faz 2 — Hat devralması.** `Route.contractID` söküm, kapsanan akışlar +
otomatik çekme politikası, kontrat bitiminde tabana dönüş, hat panosu
(doluluk, boş km, $/gün, darboğaz), akış-öncelikli hat kurucu (§3.1).
*Doğrulama:* kontratı biten hat spot akışla dolmaya devam eder (test);
hat metrikleri koşucu kayıtlarından hesaplanır; chunked determinizm;
"akıştan hat kur" ≤3 dokunuşta çalışan hat üretir.
**Durum: ÇEKİRDEK TAMAMLANDI (2026-07-20).** `Route.contractID` ve
`contractRouteClosed` kaldırıldı; rota kapsamı artık durak görevlerinden
türeyen `coveredContractIDs`/`coveredFlowIDs`. Tek-hedefli kontrata araç
atamak `[pickupContract + aynı-hat pickupFlow'ları + deliverAll]` kurar:
SLA yükü önce, kalan kapasite akıştan (spot top-off) — kontrat bitince
`routeNeedsReview` bilgisi düşer ama hat akışla çalışmaya **devam eder**
(tabana dönüş). `unassignVehicleFromContract` silindi (rota üzerinden).
`RouteStats` (dolu/boş km, gelir/gider, `firstStartedAt`) koşucuda birikir;
Fleet rota kartı doluluk %, boş km ve $/gün gösterir. Kayıt sürümü 11.
**Faz 2 cilası da tamamlandı (2026-07-20):** Hat kurucunun şehir görev
seçicisi artık o şehirden çıkan **akışları** da listeliyor ve sıralamayı
"lapa uyan önce" yapıyor: hedefi zaten rotada olan akış en üstte, *"Fills the
leg to X you already drive"* etiketiyle — boş dönüşün çözümü aranmıyor,
oyuncuya veriliyor. Diğer akışlar bekleyen yükle birlikte "adds a stop"
uyarısıyla gösteriliyor. **Darboğaz ipucu** (`SimulationEngine.bottleneck`)
tek cevap veriyor, pano değil: araç yok → yük kapasiteyi aşıyor → lapın
%X'i boş → araçlar %X dolu çıkıyor → sağlıklı. Fleet rota kartında tek satır.
Bir motor hatası da bu turda düzeldi: **dolu araç artık dokta beklemiyor**
(yükün müşterisi ve son tarihi var); yalnız boş araç bekler.

**Faz 3 — Kontrat revizyonu.** Akış payı taahhüdü, ilişki tabanlı teklif
üretimi, arketiplerin akış diline çevrimi, SLA/ceza, tier bağları.
*Doğrulama:* teklif yalnız servis edilmiş/ofisli akışlardan; taahhüt payı
debiyi aşamaz; ceza yalnız pencere aşımında.
**Durum: TAMAMLANDI (2026-07-20).** Kontrat artık talep üretmiyor:
`ContractDestination` bir `flowID` + `committedShareBps` taşıyor, teklif
şehrin **mevcut akışlarından** doğuyor (debiye göre ağırlıklı seçim), dönem
hacmi `akış debisi × pay × dönem` olarak türüyor — dünyanın üretmediği yükü
isteyen kontrat artık kurulamıyor. **Çift sayım engellendi:** imzalı payın
tonajı dok birikimine girmiyor (`accrueFlows` serbest payı uyguluyor), o
tonaj kontrat partisi olarak postalanıyor. Fiyat artık maliyetten değil
**akışın spot ücretinden** türüyor: `spot × (1 + contractPremiumPercent)` —
imzalamak ödüllendiriliyor, SLA ve ceza riskinin karşılığı bu. Pay tavanı
tier'a bağlı (%30 → %100), tek akış birden çok kontrata bölünebilir ama
toplam %100'ü aşamaz (açık teklifler de sayılır). MultiDrop = aynı şehrin
farklı akışları. Sökülenler: `pickSuppliedProduct`, `pickDemandingDestination`,
`populationPull`, `productFits`, `parcelsPerCycle`, `vehicleEquivalents`,
`contractCycleCost`, `contractMarginPercent` (→ `contractPremiumPercent`).
Kontrat teklif kartı artık "şu akışın %X'ini kilitler" diyor. Kayıt sürümü 11.
*Kalan:* ilişki tabanlı teklif önceliği (servis ettiğin akıştan daha çok
teklif) Faz 5 kalibrasyonuna bırakıldı — şu an akış debisi ağırlığı yeterli.

**Faz 3 düzeltmesi (test koşusundan):** İlk uygulamada parti boyutu hâlâ
referans aracın kapasitesinden geliyordu; küçük akışın küçük payı bir tır
partisini dolduramayınca teklif üretilemiyor ve **kontrat tahtası tamamen
boşalıyordu**. Doğru yön ters: parti boyutu yükten türer, araç sınıfı yalnız
**tavandır**. Ayrıca dönem, en az bir gönderilebilir parti biriktirecek kadar
uzun olmak zorunda — günde 300 kg taşıyan hat günlük tır sözü veremez, daha
küçük yükü daha seyrek söz verir (`parcelSize`, `minimumDaysPerParcel`).
Bu, `makeLoad`'ı da öksüz bıraktı (silindi).

**Faz 3 düzeltmesi 2 (2026-07-21, oyun testinden): kontrat *değerlendirmesi*
yeni modele geçmemişti.** Teklif üretimi Faz 3'te akış payına geçmişti ama
`brief(for:)` hâlâ eski soruyu soruyordu: "bu hat kendine bir kamyon
kazandırır mı?" Gidiş-dönüşün tamamını ve bir aracın **tüm dönem boyunca
günlük sabit giderini** tek partiye yazıyordu. Kontrat tanımı gereği akışın
%15–30'unu taahhüt ettiğine göre parti referans aracı hiçbir zaman
doldurmuyor — sonuç: pano yapısal olarak eksiye kilitli ("çoğu kontrat zarar
gösteriyor"). 400 km'de box truck %30 dolulukla −$112/gün, semi −$218/gün.
Düzeltmeler:

1. `ContractBrief` marjinal oldu: `committedKgPerDay` (kilitlenen tonaj),
   `spotRevenuePerDay` / `contractRevenuePerDay` ve türevi `premiumPerDay`,
   `fleetLoad` (bir aracın gününün yüzde kaçı). Kâr/zarar satırı yok — kontrat
   yük yaratmıyor, mevcut hattın üzerine biniyor; marjinal maliyeti ~sıfır,
   getirisi prim, riski SLA cezası. Kart iki sayıyla açılıyor: kilitlenen
   ton/gün ve spot'a göre +$/gün (`ContractHeadline`, pazar ve şehir ekranı
   ortak).
2. **Fiyat garaja bağlıydı.** Parti, sahip olunan araçlardan *rastgele* seçilen
   referans sınıfla fiyatlanıyordu; `fillFloor` yüzünden 1.8 t'lik bir taahhüt
   semi ile "yarım tır" parası ediyordu ve aynı yük semi'si olan şirkete daha
   değerliydi. Artık referans sınıf yalnız parti boyutu **tavanı** (en büyük
   sahip olunan sınıf, rastgele değil); fiyat partinin **sığdığı en küçük
   sınıfla** yapılıyor. 800 kg −$368, 4 t +$115 → fiyat yüke göre.

**Hat verimi ölçümü (2026-07-21).** Hat kartı ömür boyu `loadedShare`
gösteriyordu — "bacak bir şey taşıdı mı" sorusu, ki %10 dolu giden tır da
%100 alıyordu. `RouteStats` artık kapasite-km ve yük-km biriktiriyor ve son
3 *aktif* günün ortalamasını veriyor (`recentLoadFactor`); boş günler pencereye
girmiyor, park etmiş hat "verimsiz" görünmesin diye. $/gün zaten aynı 3 günlük
pencerede. Kayıt sürümü 13.

**Terim değişikliği (2026-07-21): "flow" → "lane".** "Flow" bir modelleme
kelimesiydi, oyunun kelimesi değil. Nakliyede *lane* zaten tam olarak bu şeydir:
iki nokta arasında düzenli tekrar eden yük hacmi ("Dallas–Chicago lane", "lane
rate"). Oyuncunun kurduğu şey ise *route*'tur — sektör ayrımının aynısı.
`FreightFlow`→`FreightLane`, `FlowID`→`LaneID`, `pickupFlow`→`pickupLane`,
`flowAccrualKg`→`laneAccrualKg`, `economy.json > flows`→`lanes` ve tüm türevleri
yeniden adlandırıldı; kod ve oyun aynı kelimeyi kullanıyor. Route için prose
içinde kullanılan "lane" temizlendi (artık "route"). Dokunulmayanlar: RNG
tohumu `"flow_week"` (yalnız RNG besler, değiştirmek dünyanın haftalık
dalgalanmasını sebepsiz kaydırırdı), `FlowWrappingHStack`/`FlowPerkChips`
(SwiftUI akış yerleşimi, konuyla ilgisiz) ve `scripts/` altındaki rapor
dosyaları. Kayıt sürümü 14 (`JobSource.lane` ham değeri ve state anahtarları
değişti).

*Açık soru:* Türkçe yerelleştirmede "hat" hâlihazırda Route için kullanılıyor
(GDD "Taşıma Hatları"). Lane = "hat" yapılırsa Route'a başka bir karşılık
gerekir; karar verilmedi.

**Şehir içi besleme + iç transfer fiyatı (2026-07-21).** Aynı şehirden alıp
aynı şehrin deposuna bırakan rota üç ayrı nedenle kırıktı: (a) lane alımı
eklenince motor varış şehrine zorla `deliverLane` enjekte ediyordu, (b) rota
istatistikleri yalnız `legDistanceKm > 0` iken yazılıyordu — 0 km süren rota
ölçülemiyordu ama dok ücreti ona yazılıyordu, (c) `dropToWarehouse` bilerek
sıfır gelir kaydediyordu, dolayısıyla depoyu besleyen her rota yapısal olarak
zarardı. Oysa bu gerçek bir strateji: dok birikimini depoya çekip tek büyük
sefer için biriktirir.

Çözüm: **iç transfer fiyatı.** `Shipment` artık `carriedCost` (mevcut taşıyıcının
o parsele harcadığı) ve `settledPayout` (önceki bacaklara ödenmiş kısım)
taşıyor. Her bacak ve her dok ücreti, o an araçtaki parsellere kütleye göre
dağıtılıyor; yük depoya devredilirken taşıyan rota **masrafı + piyasa marjı**
kadar iç gelir yazıyor, teslimatı bitiren rota `payout − settledPayout` alıyor.
Nakit yalnız nihai teslimatta ve tam olarak bir kez hareket ediyor. Mesafeye
göre bölmek yerine maliyet-artı seçildi: şehir içi besleyici 0 km sürüyor ama
iş yapıyor.

Verim ölçüsü de kilometreden **dakikaya** taşındı (`noteWork`): sürmek de dokta
durmak da aracın günü. Böylece 0 km rotada da doluluk raporlanıyor. Ek olarak
`emptyReturn` ipucu artık tek şehirlik rotalarda hiç çıkmıyor ve "kusur" değil
"masada kalan para" diliyle yazıyor — dönüş yükü bir strateji, zorunluluk değil.
Kayıt sürümü 15.

**İlişki tabanlı teklif (2026-07-21) — Faz 3'ün ertelenen yarısı tamamlandı.**
Teklifler şehrin *tüm* lane'lerinden debiye göre doğuyordu, dolayısıyla oyuncunun
hiç sürmediği hatlarda kontrat çıkıyor ve imzalamak kör bir bahis oluyordu.
Artık `stats.deliveredKgByLane` her teslimatta o lane'e yazılıyor;
`servedShareBps` "bu hattın üretiminin yüzde kaçını fiilen taşıdın" sorusunu
cevaplıyor ve teklif hem **yalnız hizmet edilen lane'lerden** doğuyor hem de
tavanı `min(tier, taşıdığın pay × 1.25)`. Yani iyi taşıdıkça firma daha büyük
pay ayırıyor. Ağırlıklandırma da ilişkiyi hesaba katıyor: en çok hizmet edilen
firma önce teklif ediyor. Boş kontrat panosu artık nedenini yazıyor.
Kayıt sürümü 16.

**Test turu düzeltmeleri (2026-07-21, üçüncü koşu).** İlişki sistemi doğrulandı
(tüm teklifler %70'i taşınan tek lane'den geldi), ama üç yeni sorun çıktı:
(a) aynı lane'e dört ayrı kontrat imzalanabildi ve toplamda hattın **%91'i**
kilitlendi — her teklif tek başına ilişki tavanının altındaydı; artık
`openShareBps` **toplam** taahhüdü ilişki tavanıyla sınırlıyor, güven bir
bütçedir. (b) Parsel boyutu referans aracın kapasitesine eşit olabiliyordu
(5.0 t kamyona 5.0 t parsel); tek bir 150 kg'lık spot alımı onu turlarca kilitli
bıraktı — tavan kapasitenin %90'ı oldu. (c) `HOLD` satırı lane durağı başına
yazılıyordu, altı lane'li bir dokta aynı dakikaya altı özdeş satır; artık şehir
ziyareti başına bir kez. Kayıt sürümü 18.

*Kalan (sırayla):* akış birikimini ayak iziyle sınırlama (servis edilmeyen dok
zaten analitik olarak tavanda oturur, simüle edilecek şey yok); ardından
`JobOffer` panosu + `acceptJob` sökümü — kontrat payı da spot gibi **alınırken
basılsın**, "bekleyen parsel" kavramı yerine taahhüt kartı gelsin.

**Faz 4 — Tek tesis + modüller.** `FacilityModule` + eklenti/seviye modeli,
şube/depo göçü, modül maliyet/süre (`siteFactor`), dok servis sınırı, UI.
*Doğrulama:* eski davranış eşdeğerliği (ofis=şube hakları, depo=depolama);
dok sınırı bekletmesi deterministik; iki farklı eklenti dizilişi ölçülebilir
farklı sonuç üretir (hız vs hacim testi).
**Durum: TAMAMLANDI (2026-07-20).** `FacilityKind` (branch/warehouse) kalktı;
şehirde **tek site** var ve yetenekleri `[FacilityModule]` belirliyor:
`office` (kontrat hakkı + yuva), `warehouse` (depolama), `dock` (elleçleme
hızı). Her modül kendi inşa/yükseltme saatinde çalışır. Komutlar
`installModule` / `upgradeModule` / `removeModule`; HQ ofisi sökülemez, dolu
depo modülü sökülemez, son modül gidince site de gider. **Uzmanlaşma gerçek:**
elleçleme süresi warehouse ve dock çarpanlarının **çarpımı** — aynı paraya
"derin depo" ya da "hızlı cross-dock" kurulabilir, ikisi birden istenirse iki
modül de gerekir. `economy.json > facilities` artık `office/warehouse/dock`
merdivenlerini taşıyor. Kayıt sürümü 12.
**Faz 4 tamamlaması (2026-07-21): bağımlılık ağacı + eklentiler.** Modüller
birbirinden bağımsız üç satın alma seçeneğiydi: hiçbir şeyi olmayan şehre
yükleme rampası kurulabiliyordu. `FacilityModuleKind.requires` ile ağaç kuruldu
(`office → warehouse → dock`), kaldırma da bağımlıyı olan modülü reddediyor
(`dependentModuleExists`). Ön koşulun **başlamış** olması yeterli, bitmiş olması
değil — aynı şantiyede işler paralel yürür.

Eklentiler bunun üstüne ayrı bir tip olarak değil, **ebeveyni olan modül**
olarak eklendi: `racking` (warehouse → depolama), `forklift` (dock → elleçleme
süresi). İkinci bir kurulum/yükseltme/kaldırma yolu yok, dolayısıyla ayrışacak
kopya da yok; `isEquipment`/`depth` yalnız sunum içindir. Her eklenti **tek
fiziksel değeri** oynatıyor (parametre diyeti): depolama artık tesisteki tüm
modüllerin toplamı, elleçleme çarpanı da tüm modüllerin çarpımı — sabit
`[.warehouse, .dock]` listesi kalktı. wh1×dock1×forklift1 = 0.68; wh1+racking1 =
550 t. `coldStore`/`extraBay` **yazılmadı**: onları tüketecek bir mekanik
(ürün yeteneği, eşzamanlı servis kuyruğu) yok — `docks` alanı hâlâ hiçbir yerde
okunmuyor, yani kural yazılmadan modül eklemek ölü içerik olurdu.

*Bilinçli erteleme:* `parking` modülü (araç/dorse barındırma) yazılmadı —
onu kullanacak bir kısıt (filo park sınırı) henüz yok ve kuralsız modül ölü
içeriktir. Eklenti katmanı (forklift, soğuk oda) da modül seviyesinin içinde
kaldı; ayrı eklenti sistemi gerçek bir ihtiyaç doğduğunda gelir.

**Faz 5 — İlk saat + kalibrasyon.** §2 onboarding akışı, kademeli açılım,
`scripts/calibrate_flows.py`: iyi kurulmuş hat, manuel tek seferlerden
%15–30 daha iyi net üretmeli; ilk 10 dk hedefleri (GDD test hipotezleri).

**Kalibrasyon TAMAMLANDI (2026-07-20)** — ilk oyun testinin denge kaydı üç
ayrı hata gösterdi, üçü de düzeltildi:

1. **Yapısal: boş dönüş fiyatlanmıyordu.** `freightPayout` yalnız *dolu*
   bacağın maliyetini fiyatlıyordu; tur iki bacak. Marj %38 iken açık %100
   olduğu için **her mekik turu yapısal olarak zarardı** (log: 100% dolu tur
   −$1716). Artık fiyat tabanı `dolu bacak + %85 × boş dönüş`. %85, tamamı
   değil: dengesiz hat kurmanın küçük bir cezası kalsın diye. Dönüş yükü bulan
   oyuncu ikinci yükün tamamını kâr yazar — **860 km'de +$763 → +$3518/tur,
   4.6 kat**. "Kur ve optimize et" döngüsünün ekonomik karşılığı bu.
2. **Doluluk teşviki yoktu.** 1.1 t ve 5.0 t partiler neredeyse aynı parayı
   alıyordu ($3047 / $3335), çünkü doluluk yalnız *marjı* ölçekliyordu. Artık
   **tabanı** ölçekliyor (`fillFloor` alt sınırıyla): yarım yük ≈ yarım hat
   ücreti. Yarı dolu tur artık zarar eder — "kamyonu doldur" tavsiye olmaktan
   çıkıp aritmetik oldu.
3. **Araç maliyetleri gerçeğin 2–5 katıydı** (box truck $2.30/km ve $320/gün;
   gerçekçi ~$0.78 ve ~$82). Fiyatlar maliyetten türediği için tüm pano
   şişmişti. Gerçekçi seviyeye çekildi; `spotMarginPercent` 38 → 55, HQ ofis
   günlük gideri −%55, `foundingCostPerCostIndex` 40 → 22 ve başlangıç nakdi
   75k → 90k (kuruluş + ilk araç sonrası $800 tampon kalıyordu).

*Sonuç (`scripts/flow_calibration.txt`):* dolu tur her sınıfta pozitif, yarı
dolu tur zararda, dengeli hat 4–5 kat kârlı; ilk araç kendini van'da ~28,
box truck'ta ~43 günde çıkarıyor. Kayıt sürümü 12'de kalıyor (şema değişmedi,
yalnız denge verisi).

**Onboarding kapsam dışı bırakıldı (2026-07-20, ürün sahibi kararı).** §2'deki
ilk saat rehberliği şimdilik yapılmayacak; ekonominin doğru olması rehberlikten
önce gelir. Hat başına aynı fikir zaten çalışıyor: `bottleneck(of:state:)` Fleet
hat kartında "ne yapmalıyım"ı tek cümleyle söylüyor. Rehberlik geri gelirse
paralel bir sistem değil, onun üstüne kurulur.

**Kuruluş ekranı donması düzeltildi.** İsim alanına ilk dokunuşta 1–2 sn donma,
iOS'un klavyeyi ilk kez kurmasıydı (giriş modları, otomatik düzeltme yığını,
yerleşim). Artık ana menü boştayken önceden ısıtılıyor
(`KeyboardPrewarm`, görünmez alan, tek runloop turu) ve kuruluş ekranındaki
`scrollDismissesKeyboard` etkileşimliden anlıka çevrildi — tek alanlı bir
ekranda her kaydırma karesini klavye konumuna bağlamanın anlamı yok.

**Faz 6 — Doküman temizliği. TAMAMLANDI (2026-07-20).**
`ROTA_SISTEMI_PLAN.md` ve `TESIS_SOZLESME_PLAN.md` silindi — geçerli
içerikleri GDD ve `ARCHITECTURE.md`'ye taşınmıştı, geriye yalnız eski modele
ait talimatlar kalıyordu ve bunlar başka bir oturumda yanlış yön verirdi.
`ARCHITECTURE.md` güncel motoru anlatıyor; bu belge bundan sonra yalnız
gerekçe ve faz kaydıdır, talimat kaynağı değildir.

---

## 6. GDD güncelleme kapsamı (onaydan sonra)

| Belge | Değişiklik |
|---|---|
| 03/01 Kanonik Model | Zincirin başına Yük Akışı; "sözleşme talep yaratmaz, akışı taahhüt eder" |
| 04/01 İşler ve Sözleşmeler | "Spot işler" katmanı → "Akışlar ve spot ücret"; teklif=ilişki; yaşam döngüsü revizesi |
| 04/02 Taşıma Hatları | Büyük ölçüde aynı kalır; akış çekme politikası ve tabana dönüş eklenir |
| 04/04 Tesisler | Tek yapı + modül modeli |
| 02/01 Ana Döngü | Adım 2–3 akış diliyle; karar nesneleri güncellenir |
| 02/02 Başlangıç Deneyimi | §2'deki ilk saat; öğretim sırası revizesi |
| 05/01 Büyüme Aşamaları | Aşama 1 tanımı (spot iş → akış servis) |
| 90 Kararlar | Bu revizyonun karar kaydı |

## 7. Riskler ve açık sorular

- **Denge bilinmezleri:** akış debisi bantları, sabır penceresi, kontrat primi —
  Faz 0/5 scriptleriyle ölçülür, kod sabiti değil `economy.json` verisi olur.
- **Erken oyun nakit akışı:** spot panonun "garantili ilk iş" rolü kalkıyor;
  başlangıç şehri akışlarının ilk aracı besleyecek debide olması Faz 5
  kalibrasyon kriteridir.
- **Göç maliyeti:** Faz 2 (`Route.contractID` söküm) koşucunun her yerine
  dokunur — tek başına, UI'sız yapılır (TESIS planındaki Faz 0 dersi).
- **Açık:** hat politika seçenekleri (deadline/doluluk/müşteri öncelikli) hangi
  fazda oyuncuya açılır; çok modlu (gemi/uçak) akış konsolidasyonu bu planın
  üstüne ayrı plan ister (kullanıcı maddesi 11).
