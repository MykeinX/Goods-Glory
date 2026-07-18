---
tür: GDD
durum: kabul-edildi
kapsam: Hedef oyuncu, pazar ve platform
kaynaklar:
  - "`Taslak_fikir.md`"
  - "`docs/01_URUN_VIZYONU.md`"
  - "`docs/04_KARARLAR_VE_ACIK_SORULAR.md`"
  - "Kullanıcının 2026-07-17 tarihli Ana Tasarım Özeti"
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - gdd/ürün-vizyonu
  - gdd/hedef-oyuncu
  - gdd/ios
---

# Hedef Oyuncu ve Platform

#gdd #gdd/ürün-vizyonu #gdd/ios

## Pazar

Ürün yerel bir oyun değil, global pazara çıkacak uluslararası bir lojistik yönetim oyunudur. İçerik, para birimleri, coğrafya, dil yapısı ve kültürel sunum tek bir ülkeye bağımlı tasarlanmamalıdır.

- Ana ürün dili: İngilizce
- Desteklenen ikinci dil: Türkçe
- Yerelleştirme: Metin genişlemesi, sayı/tarih biçimleri ve ölçü birimleri veri ve arayüz tasarımında baştan hesaba katılır.

## Birincil Oyuncu Profili

Birincil oyuncu:

- yönetim, tycoon ve strateji oyunlarını sever,
- sistem kurmaktan ve optimize etmekten hoşlanır,
- sayıların neden değiştiğini anlamak ister,
- uzun vadeli sahiplik ve ilerleme arar,
- refleks veya araç kontrolü yerine karar vermeyi tercih eder,
- ciddi fakat okunabilir bir mobil simülasyon bekler,
- kısa oturumlarla ilerleyebilmek, gerektiğinde ayrıntılı planlama yapmak ister.

“Yetişkin oyuncu” bir ton ve karmaşıklık yönüdür; zorunlu içerik yaş sınırlaması değildir. Nihai mağaza yaş derecesi içerik tamamlandıktan sonra belirlenir.

## Oyuncu İhtiyaçları

### Kısa vadede

- Şirketin mevcut durumunu hızla anlamak
- Öncelikli sorunu veya fırsatı görmek
- Kararın tahmini maliyetini ve riskini değerlendirmek
- Sonucun nedenini öğrenmek

### Uzun vadede

- Kendi şirket stratejisini geliştirmek
- Yerel ağın küresel ölçekte büyüdüğünü görmek
- Yeni taşıma türleri ve iş modellerinde ustalaşmak
- Markasını, itibarını ve operasyon kültürünü şekillendirmek

## Platform Kararı

Nihai ürünün öncelikli platformu iPhone’dur.

- Native Swift
- SwiftUI tabanlı uygulama arayüzü
- SpriteKit tabanlı dünya haritası ve hareketli temsil
- Portrait yönelim; landscape ana kullanım biçimi değildir
- Dokunmatik kullanıma uygun hedefler ve tek elle okunabilir temel akış
- Düşük donanım yükü, hızlı açılış ve kararlı yaşam döngüsü

Browser prototipi tasarım doğrulama aracıdır; nihai ürün platformu değildir.

## Portrait Tasarım Sonuçları

- Harita tüm bilgileri aynı anda göstermez; kalıcı ağ ile seçilebilir analiz katmanları ayrılır.
- Kritik KPI ve eylemler ekranın üst hiyerarşisinde kalır.
- Ayrıntılar kart, sheet ve bağlamsal panellerde açılır.
- Yatay geniş tabloya bağımlı sistemlerden kaçınılır.
- Harita üzerindeki araçlar operasyonu temsil eder; ayrıntı dokunmayla açılır.

## Öğrenme ve Ustalık Hedefi

“Birkaç dakikada öğren, yüzlerce saatte ustalaş” ürün yönüdür; doğrulanmış süre garantisi değildir.

**Test hipotezleri:**

- Oyuncu ilk 2 dakika içinde şirketin amacını açıklayabilir.
- İlk 60–90 saniyede anlamlı bir iş veya kapasite kararı verebilir.
- İlk 10 dakikada en az bir kararının sonucunu görebilir.
- İlk 20–30 dakikada farklı bir strateji denemek ister.

## Premium Kalite İlkesi

Premium his; yüksek grafik yükünden değil aşağıdaki özelliklerden doğar:

- temiz bilgi hiyerarşisi,
- hızlı ve tutarlı etkileşim,
- okunabilir tipografi,
- şeffaf ekonomi,
- ölçülü animasyon,
- oyuncunun zamanına saygı,
- pay-to-win baskısının olmaması.

Gelir modeli prototip sonrası karardır. Tasarım, agresif bekleme süreleri veya zorunlu reklamlarla çekirdek deneyimi bozmaz.

## İlgili Notlar

- [[01 - Oyun Özeti]]
- [[02 - Tasarım Sütunları]]
- [[04 - Oyuncu Fantezisi ve Marka]]
- [[02 - Çekirdek Oynanış/02 - Başlangıç Deneyimi|Başlangıç Deneyimi]]
