# Goods & Glory — Kod Mimarisi

Bu belge kod tabanının katman sözleşmesini tanımlar. Tasarım kararlarının kaynağı
`Game Design Documents/` kasasıdır; çelişkide GDD önceliklidir.

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
  Gerçek zamanı oyun dakikasına çevirir (1 sn = 5 dk × hız), komutları doğrulatıp
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
- Harita verisi çevrimdışı ve sürümlü paketlenir. İlk ABD dilimi ülke namespace'li
  ve coğrafi kapsama göre dengelenmiş 22 şehir, stratejik Interstate koridorları
  ve bunların gerçek kavşaklarından
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
(harita / filo / işler / tesisler / şirket sekmeleri). Spot işler: seed'li
üretim, boş sürüş (deadhead) → yükleme → yol → boşaltma fazları, teslimatta
atomik settlement, araç varış şehrinde kalır. Teklif üretimi origin şehrinin
`supply` ağırlıklarından ürün seçer; varış, aynı ürünü talep eden şehirlerin
`demand` × mesafe ağırlığıyla seçilir (kısa rota tercih edilir; market eşleşmesi
yoksa mesafe ağırlıklı fallback). Araç yokken HQ'daki en ucuz alınabilir araca;
sonrasında boş araçların bulunduğu şehirlere göre iş üretir. Yük seçilen
referans aracın kütle ve hacmine sığar. Ödeme yalnız dolu gidişin araç+şoför
maliyetine minimum/yüzdesel kâr ekler; deadhead ve dönüş oyuncunun
konumlandırma riskidir. Açık sözleşmeler periyodik olarak aynı lane üzerinde
spot benzeri sevkiyat teklifi üretir. İlk harita dilimi 22 ABD metro merkezi ve
ana Interstate ağını kapsar; kara/eyalet sınırları ile yollar çevrimdışı
üretilmiş gerçek koordinat geometrileridir.

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

`Goods&GloryTests/`: bundled katalog doğrulaması, deterministik rota,
motor kuralları (settlement, kapasite/nakit reddi, teklif ömrü) ve
determinizm sözleşmesi (parçalı vs tek seferlik zaman ilerletme → bayt
düzeyinde aynı durum). Yeni sistem eklerken önce değişmezleri test edin.
