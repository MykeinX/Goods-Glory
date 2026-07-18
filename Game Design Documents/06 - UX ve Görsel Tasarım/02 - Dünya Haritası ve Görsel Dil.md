---
tür: GDD
durum: kabul-edildi
kapsam: Kalıcı dünya haritası, görsel hiyerarşi ve SpriteKit sunumu
kaynaklar:
  - Ana Tasarım Özeti
  - docs/05_GORSEL_YON_VE_HARITA.md
  - web/README.md
son_güncelleme: 2026-07-18
etiketler: [gdd, harita, görsel-tasarım, spritekit]
---

# Dünya Haritası ve Görsel Dil

## Görsel hedef

Olgun ama soğuk olmayan; kurumsal ama bürokratik olmayan; yaşayan ama kalabalık olmayan bir lojistik dünyası. Harita önce bilgi verir, ardından atmosfer ve sahiplik hissi üretir.

Görsel formül:

> Sade 2D stratejik coğrafya + hafif izometrik lojistik varlıkları + yönetim oyununa özgü okunur bilgi hiyerarşisi.

Referanslar yön tarifidir; renk, ikon, bina, hareket ve ses kimliği özgün olmalıdır.

## Kalıcı teknik yön

Harita native iOS uygulamasında SpriteKit sahnesi olarak sunulur ve SwiftUI içindeki bir `SKView` ile bağlanır. SpriteKit yalnızca haritanın çizimi, kamerası, seçimi ve görsel hareketinden sorumludur; yönetim ekranları SwiftUI olarak kalır. Oyun zamanı, rota sonuçları, araçların kanonik konumu ve ekonomi kararları render katmanından bağımsız saf Swift simülasyon çekirdeğinde üretilir.

Haritanın koordinat sistemi düz ve veri tabanlıdır. İzometrik görünüm yalnızca varlıkların çizim dilidir; coğrafi veya simülasyon koordinatlarını değiştirmez.

Harita MapKit veya başka bir navigasyon altlığı kullanmaz. Gerçek şehir konumlarını, bölgesel ilişkileri ve ana koridorları tanınabilir ölçüde koruyan; buna karşılık renk, biçim, ayrıntı ve etkileşim dili özgün olan stilize 2D oyun coğrafyasıdır.

## Kanonik yol ağı ve veri kapsamı

Şehir geçitleri, kavşaklar ve yol geometrileri kararlı kimlikli tek bir kanonik graf oluşturur. Rota bulma, araçların yol üzerindeki konumu ve SpriteKit çizimi aynı düğüm/kavşak/yol geometrisini kullanır; yalnızca görsel kestirme için şehirler arasında ayrı bir çizgi üretilmez.

Mevcut native veri seti 8 şehirlik ilk doğrulama dilimidir. Hedef kapsam 150–200 şehir ve binlerce yoldur; bu büyüme için coğrafya ve graf verisi çevrimdışı üretilir, sürümlenir ve uygulamaya paketlenir. Veri kaynağı ve lisans kökeni her sürümde izlenebilir tutulur; uygulama çalışırken canlı harita servisine bağımlı olmaz.

## Katman hiyerarşisi

1. **Coğrafi zemin:** Kara, su, ana kıyılar ve düşük kontrastlı bölgesel karakter.
2. **Şirket ağı:** Açık ve planlanan hatlar, yön, kullanım ve seçim.
3. **Dünya nesneleri:** Şehir, genel merkez, şube, depo, aktarma merkezi ve terminal.
4. **Operasyon:** Temsilî araçlar, yük akışı ve sefer durumu.
5. **Durum:** Bilgi, dikkat ve kritik uyarılar.
6. **Analiz:** Pazar, talep, finans ve risk gibi isteğe bağlı katmanlar.

Bir anda yalnızca bir analiz katmanı baskın olur. Katman değişimi kamera konumunu ve seçimi kaybetmez.

## Semantik yakınlaştırma

- **Stratejik ölçek:** Şehir kümeleri, ana koridorlar, bölgesel performans ve yalnızca kritik sorunlar.
- **Operasyon ölçeği:** Şehirler, hatlar, kapasite, temsili araçlar, sözleşme ve olay işaretleri.
- **Tesis ölçeği:** Seçili tesisin silueti, bağlı hatları, kapasite bileşimi ve darboğazı.

Yakınlaştırma yalnızca nesneleri büyütmez; bilgi türünü değiştirir. Uzak ölçekte tekil filo yerine akış gösterilir. Bu hem CEO ölçeğini hem performans bütçesini korur.

## Şehir, tesis ve araç dili

- Şehirler küçük boyutta ayırt edilebilir ortak açılı siluetler kullanır.
- Tesis türü yalnız renkle değil siluet ve ikonla anlaşılır.
- Seçim alanı görünen varlıktan daha geniştir.
- Araçlar gerçek markaları kopyalamaz; rol, ekipman ve şirket rengini okunur biçimde taşır.
- Erken oyunda az sayıdaki gerçek araç gösterilebilir; büyüyen filoda çizilen sprite sayısı operasyon yoğunluğunu temsil eder.
- Rota, yük, ETA, kondisyon ve sözleşme ayrıntıları yalnız seçim sonrası bağlamsal panelde görünür.

## Renk, tipografi ve hareket

Zemin taş, lacivert, petrol, sis mavisi ve sıcak gri gibi düşük doygunluklu tonlara dayanır. Oyuncu markası kontrollü bir vurgu rengidir. Başarı, dikkat ve kritik renkleri yalnız semantik görevleri için kullanılır.

Renk hiçbir durumu tek başına anlatmaz; şekil, ikon, çizgi deseni, kalınlık ve metinle desteklenir. Sayılar kısa ve karşılaştırılabilir biçimlenir.

Hareket durum anlatır:

- araç veya akış hareketi operasyonu,
- kısa duraksama darboğazı,
- ölçülü nabız bekleyen kararı,
- rota çizimi ağ genişlemesini,
- tesis gelişimi şirket büyümesini

ifade eder. Aynı anda birden fazla güçlü animasyon dikkat için yarışmaz.

## Performans ilkeleri

- Sprite sayısı gerçek araç veya yük adedine doğrudan bağlanmaz.
- Kamera dışında kalan ve semantik ölçekte görünmeyen öğeler çizilmez.
- Statik coğrafya ve yol geometrisi birleştirilmiş/döşenmiş katmanlarla; hareketli
  varlıklar havuzlanmış sprite'larla çizilir. Geometri, rota ve ikon önbellekleri
  ölçümle doğrulanarak kullanılır.
- Görsel güncelleme hızı simülasyon adımından ayrıdır; render kare kaybı oyun sonucunu değiştirmez.
- Hedef, desteklenen en düşük cihazda etkileşim sırasında akıcı kamera ve dokunma tepkisidir; kesin kare/süre bütçeleri prototip ölçümlerinden sonra cihaz matrisiyle sabitlenir.

## Browser prototipi — mevcut durum

Browser prototipi düşük kontrastlı SVG harita, veriyle tanımlı koridorlar ve yaklaşık 140 ana ticaret şehri içerir. Bu sayı, prototipin dünya veri seti ve ağ doğrulama alanıdır; ilk iOS sürümünün içerik hedefi değildir.

Koyu tema, SVG işaretler, üç sakin bölge katmanı ve mevcut koridor geometrileri uygulanmış teknik gerçeklerdir. Nihai sanat, tema seçimi veya dünya kapsamı hakkında bağlayıcı ürün kararı sayılmazlar. Taşınacak değer; okunabilirlik bulguları, koordinatlar, kararlı kimlikler ve görsel durum sözleşmeleridir.

## İlişkili notlar

- [[06 - UX ve Görsel Tasarım/01 - Bilgi Mimarisi ve Ekranlar]]
- [[06 - UX ve Görsel Tasarım/03 - Erişilebilirlik ve Mobil Kullanım]]
- [[07 - Teknik Tasarım/01 - iOS Mimarisi]]
- [[08 - Sürüm Kapsamı/01 - İlk Sürüm Kapsamı]]

#gdd #harita #görsel-tasarım #spritekit
