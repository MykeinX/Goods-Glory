---
tür: Teknik GDD
durum: Kabul adayı
kapsam: İçerik, denge, yerelleştirme ve veri doğrulama sözleşmesi
kaynaklar:
  - Ana Tasarım Özeti
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - web/data/config/README.md
son_güncelleme: 2026-07-18
etiketler: [gdd, veri-odaklı, içerik, codable]
---

# Veri Odaklı İçerik

## Temel kural

> İçerik, denge değerleri ve oyuncuya gösterilen metinler veride; algoritmalar, doğrulama ve sistem değişmezleri kodda bulunur.

Amaç her sabiti dış dosyaya taşımak değil; tasarımcıların değiştirdiği tanımları merkezi ve sürümlenebilir tutarken oyun davranışını açık, test edilebilir kodla korumaktır.

## Veride bulunanlar

- şehirler, ülkeler, bölgeler ve bağlantılar,
- yük/ürün ve talep profilleri,
- araç, ekipman ve yetenek tanımları,
- tesis seviyeleri, modülleri ve uzmanlıkları,
- spot iş, sözleşme, ihale ve olay şablonları,
- taşıma hizmeti ve hat politika profilleri,
- ücretler, maliyetler, açılma koşulları ve denge katsayıları,
- marka seçenekleri, görsel varlık kimlikleri ve tasarım tokenları,
- yerelleştirme anahtarları ve oyuncuya gösterilen metinler.

## Kodda bulunanlar

- durum geçişleri ve komut uygulama sırası,
- fiziksel kapasite, rota, uygunluk ve settlement algoritmaları,
- deterministik rastgelelik ve seed türetme,
- şema/çapraz referans doğrulama,
- atomiklik, sahiplik ve konum değişmezleri,
- hata sınıfları ve migration davranışı,
- güvenlik ve performans sınırları.

## Taşınabilir veri sözleşmesi

Tanımlar JSON uyumlu, platformdan bağımsız değerler kullanır. Runtime sınıfları, fonksiyonlar, `Date`, platform nesneleri ve davranış veriye yazılmaz.

Kurallar:

- Kimlikler kararlı, benzersiz ve tercihen İngilizce `lowercase_snake_case` biçimindedir.
- Zaman kanonik tamsayı oyun dakikasıdır.
- Kütle `massKg`, hacim `volumeM3` olarak saklanır; belirsiz “yük birimi” kullanılmaz.
- Enum değerleri açık string sözleşmeleridir.
- İlişkiler kimlikle kurulur ve katalog yüklenirken doğrulanır.
- Oyuncuya gösterilen ad, açıklama ve format metni yerelleştirme anahtarı kullanır.
- Runtime durum statik kataloglara geri yazılmaz.

## Ürün ve şehir pazarı sözleşmesi

`products.json`, her ürünü kararlı ve benzersiz İngilizce
`lowercase_snake_case` `ProductID` ile bir kez tanımlar. Ürün adı, görseli,
fiziksel özellikleri ve fiyatlama tabanı bu kanonik ürün tanımında bulunur.
`ProductID`, tek bir perakende SKU değil simülasyon çözünürlüğünde ticareti
yapılan yük kategorisidir. `cotton` ve `consumer_electronics` gibi farklı
ürün aileleri aynı sözleşmeyi kullanabilir; ancak tek bir yoğunluk, fiyatlama ve
sevkiyat aralığı kategori için anlamlı değilse daha somut ürünlere bölünür.

`city_markets.json` ayrı bir şehir pazarı profilidir. Her arz ve talep kaydı
yalnızca `ProductID` ile `UInt16 weight` taşır; ürün tanımını veya gösterim
metnini kopyalamaz. Bir şehrin arz listesi ve talep listesi ayrı ayrı en çok 20
ürün içerir. Ürün referansları ve yinelenen kayıtlar katalog yüklenirken
doğrulanır.

Bu ağırlıklar statik ekonomik eğilimdir. Olay, mevsim, şirket etkisi ve anlık
arz/talep değişimleri runtime durumunda hesaplanır; `products.json` veya
`city_markets.json` içine geri yazılmaz.

Mevcut boş şehir pazar profilleri yalnız şema yer tutucusudur. Pazar ağırlıkları
gerçek içerikle doldurulana kadar spot iş üretimi bu listeleri kullanmaz; boş
veriden ekonomik davranış türetilmez.

## Swift karşılığı

Bundle içindeki sürümlü tanımlar `Codable` struct’lara yüklenir ve salt okunur `GameCatalog` içinde doğrulanır. Ham DTO ile doğrulanmış domain tanımı gerekirse ayrılır. Hatalı veya eksik referans üretim sürümünde sessizce yoksayılmaz; build doğrulaması ve kontrollü açılış hatasıyla görünür kılınır. Katalog, şehirleri, ürünleri ve şehir pazarı profillerini kimlikle indeksleyerek runtime sistemlerine O(1) erişim sağlar.

Veri şemaları SwiftData/SQLite kayıt şemasından ayrıdır. Katalog içeriği ürün sürümüyle, oyuncu kampanyası save şemasıyla sürümlenir.

## Doğrulama hattı

1. Sözdizimi ve şema doğrulaması.
2. Benzersiz kimlik ve zorunlu alan kontrolü.
3. Çapraz referans ve enum kontrolü.
4. Birim, aralık ve fiziksel kapasite sınırları.
5. Açılma koşullarında çevrim ve erişilemez içerik kontrolü.
6. Denge smoke testleri ve kanonik simülasyon senaryoları.
7. Yerelleştirme anahtarı ve görsel varlık kapsama kontrolü.

İçerik değişikliği beklenen simülasyon fixture’larını etkiliyorsa bu fark bilinçli olarak gözden geçirilir.

## Sürümleme ve uyumluluk

- Silinen kimlikler mevcut save’leri bozabileceği için yeniden kullanılmaz.
- Yeniden adlandırma açık alias/migration tablosuyla yapılır.
- Save, oluşturulduğu katalog ve şema sürümünü taşır.
- Denge güncellemesinin devam eden sözleşme ve üretilmiş yükleri nasıl etkileyeceği sürüm politikasında açıkça belirtilir.
- Sunucudan canlı içerik indirme ilk sürüm gereksinimi değildir; bundle içeriği güvenilir temel kaynaktır.

## Browser prototipi — mevcut gerçekler

Mevcut browser prototipi `web/data/config/` altında JSON tanımları ve TypeScript çapraz referans doğrulaması kullanır. Ürün, araç, ekipman, tesis, sözleşme ve ticari kural katalogları native tasarım için iyi bir başlangıç sözleşmesidir; katalog adlarının ve alanlarının tamamı ürün kararı değildir.

Browser’daki yaklaşık 140 şehir veri seti taşınabilir bir dünya kataloğu ve test alanıdır. İlk sürümde sunulacak şehir sayısını belirlemez.

## İlişkili notlar

- [[07 - Teknik Tasarım/01 - iOS Mimarisi]]
- [[07 - Teknik Tasarım/02 - Simülasyon Çekirdeği ve Determinizm]]
- [[07 - Teknik Tasarım/04 - Kayıt, iCloud ve Yaşam Döngüsü]]
- [[08 - Sürüm Kapsamı/01 - İlk Sürüm Kapsamı]]

#gdd #veri-odaklı #içerik #codable
