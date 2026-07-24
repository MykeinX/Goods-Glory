# Goods & Glory — Kod Mimarisi

Kod tabanının teknik sözleşmesi. Ürün vizyonu: kök `VISION.md`. Açık yönler: kök `OPEN.md`. Mikro tasarım kararı belgelenmez; kod ve bu dosya yeterlidir.

## Okuma kuralı (ajanlar)

1. `VISION.md` — ne için yapıyoruz
2. Bu dosya — ne nerede, nasıl bölünür
3. İlgili Swift / JSON — uygulama gerçeği
4. `OPEN.md` — yalnız yön belirsizse

Eski GDD, plan taslakları ve karar günlükleri yoktur; aranmaz.

## Katmanlar

```
Presentation (SwiftUI + SpriteKit harita)
    ↓ komut                     ↑ salt okunur durum
Application (GameSession)
    ↓                           ↑
Domain (Catalog, State, Engine)  ← framework bilmez; deterministik
    ↑
Persistence (SaveRepository)     Resources/Catalog (JSON)
```

| Katman | Klasör | Sorumluluk |
|---|---|---|
| Domain | `Domain/Core` | Typed ID, birimler, seed RNG |
| Domain | `Domain/Catalog` | JSON içerik, doğrulama, yol grafı, türetim |
| Domain | `Domain/State` | `GameState` ve serileştirilebilir durum |
| Domain | `Domain/Engine` | `GameCommand`, `SimulationEngine` |
| Application | `Application/` | Gerçek zaman → oyun dakikası, oturum, kayıt anı |
| Persistence | `Persistence/` | Sürümlü JSON snapshot |
| Presentation | `Presentation/` | Ekranlar; harita SpriteKit + adapter |
| İçerik | `Resources/Catalog/` | Şehir, ürün, pazar, yol, araç, ekonomi JSON |

UI `GameState`’i doğrudan değiştirmez; komut gönderir. Domain SwiftUI/SpriteKit/duvar saati bilmez.

## Kod düzeni

Hedef: bakımı kolay, modüler, tekrarlamayan, data-driven kod. MVVM (SwiftUI view + `GameSession` / domain) ve sorumluluklara göre dosya bölmesi sürer; her şeyi tek dosyaya yığmak yasaktır.

Bu proje şişme ve tekrarı pahalıya ödedi; kurallar zorunludur.

1. **Dosya boyutu** — ~400 satırda bölünür, 700 üst sınır. Klasör açmak bölmek değildir.
2. **Ne zaman yeni dosya** — yeni tip (tek ekranın iç detayı değilse) kendi dosyasına; yeniden kullanılan satır/kart/sheet ikinci kullanımda kendi dosyasına.
3. **Tekrar yasağı** — aynı hesap/bileşen ikinci kez yazılmaz.
   - Kurallar: `Domain`
   - Biçim: `Format`
   - Katalog/oturum okuma: `SessionDisplay`
   - Görsel bileşen: `DesignSystem`
   - Domain tipinin sunumu: `*Display` (ör. `RouteTaskDisplay`)
4. **Hesap Domain’de** — bir sayı birden çok ekranda görünüyorsa motor hesaplar; view okur.
5. **Bölme** — sorumluluk ekseninde. `private` dosya kapsamlıdır; paylaşılan üyeler `internal` olur. Stored property ana tipte kalır; extension’a yalnız fonksiyon / computed property gider. Serbest `extension View` blokları bölünürken taşınır.

### Motor dosya haritası

`SimulationEngine` tek tiptir ama tek dosya değildir: sorumluluklara göre extension dosyalarına ayrılır. Yeni motor mantığı doğru `+…` dosyasına gider; mevcut parçalar tek gövdeye geri birleştirilmez.

| Dosya | Ne aranır |
|---|---|
| `SimulationEngine` | Komut dağıtımı |
| `+Pricing` | Zaman, süre, maliyet, fiyat |
| `+Standing` | Duran maliyetler |
| `+Flows` | Hat birikimi, parti üretimi, sevkiyat |
| `+Facilities` | Tesis / modül |
| `+Routes` | Rota düzenleme komutları |
| `+RouteRunner` | Rota yürütme |
| `+Cargo` | Durak yük işlemleri |
| `+Analysis` | Salt okunur UI hesapları |

Benzer bölme: `GameCatalog` (`+Loading`, `+Validation`, `+Routing`, `+Derivation`), `GameMapScene` (`+Camera`, `+Terrain`, `+Snapshot`).

## Veri odaklı içerik

- **İçerik JSON’da, kurallar kodda.** Yeni şehir/ürün/yol mümkünse veri kaydıdır; motor sözleşmesi değişmez.
- Kimlikler kararlı `lowercase_snake_case`; yeniden kullanılmaz.
- Birimler: oyun dakikası (Int), `massKg`, `volumeM3`, para tam dolar.
- Çapraz referanslar yüklemede doğrulanır; bozuk katalog sessizce yutulmaz.
- `GameCatalog` kimlik indekslerini yüklemede kurar; runtime erişim O(1).
- Yol grafı (`road_nodes.json` / `roads.json`) mesafe ve rota hesabının tek kaynağıdır. Harita sunumu aynı graftan türetilir; simülasyon ekran koordinatı kullanmaz.
- Oyuncu metinleri `Localizable.xcstrings` üzerinden gider.

Ana katalog dosyaları: `cities.json`, `city_markets.json`, `products.json`, `roads.json`, `road_nodes.json`, `vehicle_types.json`, `economy.json`, `map_board_silhouette.json`.

## Harita teknik sözleşmesi

- SpriteKit yalnız `MapRenderSnapshot` çizer; simülasyon ve rota kuralı Domain'de kalır.
- `map_board_silhouette.json` yazarlı Mini Metro tahta sanatıdır (`import_board_art.py`): yüksek detaylı kontur + oktilinear (yatay/dikey/45°) kenar snap. Renderer düz kenarları koruyup yalnız köşeleri küçük sabit radius ile yumuşatır. Ülke sınırı çizilmez; yakınlaştırma yeni coğrafi detay üretmez.
- `MapProjection` şehirleri, yolları ve silüeti aynı yazarlı tahta koordinatına taşır. `cities.json` lat/lon’u ham WGS84 değil; silüetle aynı board uzayıdır (pin’ler tahta sanatına oturur).
- Domain yol grafı kanoniktir ve yazarlıdır: `generate_trade_network.py` şehirleri gerçek koridorlardan esinlenen az sayıda yönlendirme kavşağı ve döngülü bölgesel omurgayla bağlar. Yeni şehir en yakın omurga kenarını bölerek veya bir-iki hub'a bağlanarak eklenir; tam bağlı şehir grafı kurulmaz. `MapCorridorCache` katalog başına bir kez şematik ve yumuşak `RoadID` geometrisi kurar; çizgi ile araç aynı koridoru kullanır, kesişen rotalar ortak segmenti paylaşır. Ağ kullanıcıya gösterilmez; yalnız aktif rotaların kullandığı parçalar çizilir.
- Kara/deniz geçilebilirliği sunum poligonundan çıkarılmaz. Bugünkü `roads.json` kara ağıdır; deniz taşımacılığı geldiğinde kendi modlu ağına sahip olur.
- Aktif rotalar araç başına çizilmez. Kullanılan `RoadID` birleşimi tek halo + tek yol path'i olarak batch edilir.
- Hareketli araçlar havuzlanan kapsül `MapVehicleNode`'larıdır; şehirdeki boşta araçlar ayrı sprite yerine şehir sayacında özetlenir.

## Bugünkü oyun iskeleti

Ana menü → şirket kuruluşu → sekmeler: harita, filo, işler/operasyon, tesisler, şirket.

- **Talep:** katalogdan türetilen kalıcı hatlar (`FreightLane`); dokta biriken yük; rota ile taşıma.
- **Rotalar:** durak + görev; atanmış araçlar `RouteRun` ile tur atar.
- **Tesisler:** şehirde tek site; yetenekler modüllerle (`office`, `warehouse`, `dock`).
- **Harita:** SwiftUI içinde SpriteKit; sahne salt okunur snapshot ile çizilir, simülasyon kuralı taşımaz.
- **Kayıt:** atomik JSON snapshot; CloudKit yok.

Davranış ayrıntısı için ilgili `Domain/Engine` veya `Domain/State` dosyasına bakılır; buraya kopyalanmaz.

## Test

`Goods&GloryTests/`: katalog doğrulama, yol grafı, rota koşucusu, determinizm (`advance` parçalı vs tek sefer → aynı durum). Etkilenen API ile testler güncellenir; istenmedikçe yeni test dosyası üretilmez.
