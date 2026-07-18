---
tür: Uygulama notu
durum: Mevcut prototipin anlık görüntüsü
kapsam: Browser prototipi gerçekleri, taşınabilir çıktılar ve sınırlar
kaynaklar:
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/05_GORSEL_YON_VE_HARITA.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - docs/08_TEST_ARACLARI_VE_LOGBOOK.md
  - web/README.md
  - web/data/config/README.md
son_güncelleme: 2026-07-17
etiketler: [gdd, browser-prototipi, uygulama-notu, teknik]
---

# Browser Prototipi Uygulama Notları

## Belgenin statüsü

Bu not çalışan browser prototipinin 2026-07-17 tarihli teknik ve içerik durumunu kaydeder. Buradaki uygulanmış davranışlar otomatik olarak kalıcı ürün kararı değildir. Çelişkide kabul edilmiş GDD kararı ve doğrulanmış ürün hedefi önceliklidir.

## Prototipin görevi

Browser sürümü iOS oyununun web portu değildir. Şunları sınayan bir tasarım laboratuvarıdır:

- sözleşme ve hizmet sözü kararları,
- kapasite, kârlılık ve güvenilirlik ilişkisi,
- fiziksel yük ve tesis ağı,
- açıklanabilir sonuçlar,
- şirket büyümesi ve otomasyon,
- mobil bilgi yoğunluğu,
- taşınabilir veri ve deterministik test sözleşmeleri.

## Çalışan kapsam

Mevcut `web/` uygulamasında:

- şirket kuruluşu, merkez şehri ve başlangıç rolü,
- garanti uyumlu ilk spot fırsat,
- düzenli müşteri sözleşmesi ve servis planı,
- çift yönlü koridorlar, doluluk/bekleme/öncelik politikaları,
- fiziksel kütle ve hacim kullanan yükler,
- doğrudan taşıma, aktarma, rezervasyon ve depolama,
- filo, ekipman ve modüler tesisler,
- Finance ve yapılandırılmış Logbook,
- yerel autosave, revizyon koruması ve export/import

bulunur.

Road ilk oynanabilir moddur. Demir, deniz ve hava servis tanımları geleceğe dönük pasif veridir; oynanabilir ürün özelliği değildir.

## Mevcut ürün alanları

Browser navigasyonu Business, Network, Fleet, Map, Finance ve Logbook alanlarını kullanır. Test Tools geliştirici alanıdır ve üretim navigasyonuna taşınmaz.

Bu bilgi mimarisi doğrulanacak bir uygulamadır. Native iOS’ta `TabView`, `NavigationStack`, sheet ve harita bağlamı yeniden tasarlanır; web sol paneli birebir kopyalanmaz.

## Dünya ve görsel durum

- Düşük kontrastlı düz SVG dünya haritası.
- Yaklaşık 140 ana ticaret şehri.
- Veriyle tanımlı kara/deniz/demir bağlantı omurgası ve eğriler.
- Koyu tema, kontrollü şirket rengi ve kompakt vektör işaretler.
- Seçim sonrası açılan yük, rota, ETA, ekipman ve kondisyon ayrıntıları.

Yaklaşık 140 şehir, prototip veri ve harita doğrulama kapsamıdır. İlk iOS sürümü için önerilen 50–60 şehir, 10–15 ülke ve 3–4 kıta hedefiyle karıştırılmaz. Koyu tema ve SVG sanat nihai ürün kararı değildir.

## Veri ve domain uygulaması

`web/data/config/` JSON katalogları kararlı kimlikler, tamsayı oyun dakikası, `massKg` ve `volumeM3` kullanır. Runtime davranışı tanım dosyalarına yazılmaz. Import sırasında çapraz referanslar doğrulanır.

Önemli domain modülleri; yük/talep, görev, ağ/koridor, tesis, zaman, save ve JSON uyumlu tip sözleşmelerini ayırır. Eski job, delivery, lane-contract ve route-plan modülleri güncel runtime’ın parçası değildir.

Browser uygulamasındaki kurallar:

- üretilen her yük geçerli `productId` taşır,
- yük ve araçlar kütle/hacim ile değerlendirilir,
- kampanya seed’i ve üretilmiş faz süreleri kaydedilir,
- render sırasında rastgelelik kullanılmaz,
- kabul, rezervasyon ve settlement akışları test edilir.

Bu yapının amacı TypeScript’i Swift’e çevirmek değil; şemaları, kimlikleri, formülleri ve beklenen sonuçları taşımaktır.

## Kayıt ve geliştirici araçları

Logbook yapılandırılmış kategori, ton, oyun zamanı ve olay ayrıntısı tutar. Test Tools; canlı durum, statik kataloglar, kilit istisnaları, hazır senaryolar ve kontrollü zaman atlama sağlar.

Mevcut kayıt uygulaması dokümanlarda yerel D1 autosave/revizyon koruması ve `web/README.md` içinde schema-8 portable export/import olarak tarif edilir. Bunlar prototipin gelişim sürecindeki uygulanmış gerçeklerdir; SwiftData, SQLite veya CloudKit kararı değildir. Native test fixture’larına dönüştürülmeden önce çalışan kodla belge uyumu ayrıca doğrulanmalıdır.

## iOS’a taşınacak çıktılar

- Kararlı içerik ve varlık kimlikleri.
- JSON şemaları ve birim sözleşmeleri.
- Formüller, seed türetme tanımı ve kanonik fixture’lar.
- Veri doğrulama ve invariant testleri.
- Kayıt/migration/çatışma senaryoları.
- Harita okunabilirliği ve mobil kullanıcı testi bulguları.
- Kabul edilen tasarım kararları ve reddedilen denemelerin gerekçeleri.

Taşınmayacak varsayımlar: React bileşen yapısı, D1 seçimi, SVG render tekniği, web sol navigasyonu, mevcut klasör adları ve yaklaşık 140 şehirlik sunum kapsamı.

## Doğrulama komutları

Prototip kendi README’sine göre build, lint, TypeScript kontrolü ve Node testleriyle doğrulanır. Bu komutların başarılı olması oynanış hipotezlerinin doğrulandığı anlamına gelmez; teknik regresyon kontrolüdür.

## İlişkili notlar

- [[08 - Sürüm Kapsamı/02 - Prototip Hipotezleri]]
- [[08 - Sürüm Kapsamı/01 - İlk Sürüm Kapsamı]]
- [[07 - Teknik Tasarım/01 - iOS Mimarisi]]
- [[07 - Teknik Tasarım/03 - Veri Odaklı İçerik]]

#gdd #browser-prototipi #uygulama-notu #teknik
