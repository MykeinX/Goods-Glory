---
tür: GDD
durum: Ürün gereksinimi
kapsam: iPhone portrait erişilebilirlik ve dokunmatik kullanım
kaynaklar:
  - Ana Tasarım Özeti
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/05_GORSEL_YON_VE_HARITA.md
son_güncelleme: 2026-07-17
etiketler: [gdd, erişilebilirlik, mobil, ios]
---

# Erişilebilirlik ve Mobil Kullanım

## Hedef

Oyunun temel kararları küçük iPhone ekranında, portrait yönde ve farklı görsel/motor gereksinimleri olan oyuncular için anlaşılır olmalıdır. Erişilebilirlik sonradan eklenen bir görünüm modu değil; bilgi mimarisi, içerik ve görsel dilin kabul ölçütüdür.

## Temel gereksinimler

### Dynamic Type

- SwiftUI metin stilleri ve ölçeklenebilir ölçüler kullanılır.
- Kritik bilgi sabit yükseklikte kesilmez; kart ve satırlar gerektiğinde büyür.
- Çok büyük erişilebilirlik boyutlarında yatay yerleşim dikey yerleşime dönüşür.
- Grafik ve harita üstü kısa etiketlerin eşdeğer bilgisi erişilebilir liste veya ayrıntı görünümünde bulunur.

### VoiceOver

- Her etkileşimli öğenin kısa ad, değer, durum ve uygun eylem açıklaması vardır.
- Harita; şehir, hat, tesis, araç ve uyarıları anlamlı gruplar ve sıralı bir erişilebilir listeyle sunar.
- Dekoratif sprite ve animasyonlar erişilebilirlik ağacından çıkarılır.
- KPI değişimleri yalnız sayı olarak değil yön ve neden özetiyle okunur.
- Zaman kontrolü mevcut hız ve duraklatma durumunu açıkça bildirir.

### Kontrast ve renk dışı kodlama

- Metin, ikon ve etkileşim durumları hedeflenen Apple erişilebilirlik kontrast ölçütleriyle doğrulanır.
- Başarı, dikkat, kritik, seçim, taşıma modu ve hat durumu yalnız renkle anlatılmaz.
- İkon, şekil, çizgi deseni, kalınlık, kısa etiket ve gerektiğinde ses/haptik birlikte kullanılır.
- Oyuncu şirket rengi semantik uyarı renklerinin yerini alamaz.

### Reduce Motion

- Sistem `Reduce Motion` tercihi izlenir.
- Sürekli rota akışı, parallax, nabız ve geçiş hareketleri azaltılır veya statik durum göstergesine dönüşür.
- Animasyon kapatıldığında bilgi kaybolmaz ve simülasyon sonucu değişmez.
- Kamera otomatik hareketleri kısa tutulur; kullanıcı odağı beklenmedik biçimde taşınmaz.

### Dokunma hedefleri

- Birincil etkileşim hedefleri en az 44×44 point etkin alana sahiptir.
- Harita işaretlerinin görünmeyen seçim alanı görselinden daha geniş olabilir.
- Yakın düğümlerde yanlış seçimi azaltmak için kümelendirme, seçim menüsü veya semantik yakınlaştırma kullanılır.
- Temel eylemler doğal başparmak alanında; yıkıcı eylemler ayrı ve onaylıdır.

## Mobil etkileşim ilkeleri

- Portrait uygulama yönü kalıcı hedeftir; temel görevler landscape gerektirmez.
- Pinch, pan veya uzun basma hiçbir kritik görevin tek yolu değildir; düğme/liste alternatifi bulunur.
- Sheet’ler içerik büyüdüğünde kaydırılabilir ve kapatma hareketine erişilebilir alternatif sunar.
- Duraklatılmış oyun, arka plana geçiş ve geri dönüş durumları açık görünür.
- Kısa oturum sonunda oyuncu güvenli biçimde ayrılabilir; kaydın durumu belirsiz bırakılmaz.
- Haptik ve ses destekleyicidir, zorunlu değildir.

## İçerik ve bilişsel yük

- Aynı anda tek baskın uyarı ve tek birincil eylem gösterilir.
- Teknik lojistik terimleri kısa açıklama ve tutarlı sözlükle desteklenir.
- Süre, para, kütle ve hacim birimleri yerelleştirme kurallarına göre biçimlenir.
- Hata mesajı yalnız sorunu değil, nedeni ve düzeltme yolunu belirtir.
- Bildirimler önem düzeyine göre ayrılır; küçük olaylar Logbook’a gider, kritik kararlar kontrollü biçimde zamanı durdurabilir.

## Doğrulama matrisi

Her ana akış şu koşullarda test edilir:

- küçük desteklenen iPhone ekranı,
- en büyük erişilebilirlik yazı boyutları,
- VoiceOver açık,
- Reduce Motion açık,
- artırılmış kontrast ve koyu/açık görünüm senaryoları,
- renk algısı farklılıklarını taklit eden kontroller,
- yalnız tek elle ve sınırlı hassasiyetle kullanım.

Başarı ölçütü, yalnız ekranın “çalışması” değil; kuruluş, ilk iş, sözleşme inceleme, darboğaz bulma ve kayıt geri dönüş görevlerinin tamamlanabilmesidir.

## Browser prototipi — sınır

Browser prototipindeki mobil genişlik testleri dokunma hedefi, bilgi yoğunluğu ve renk dışı kodlama için erken kanıt sağlar. Browser’ın mevcut koyu teması ve masaüstü/sol navigasyon davranışı iOS erişilebilirlik uyumu anlamına gelmez. Native sürüm, gerçek cihazda SwiftUI ve SpriteKit erişilebilirlik API’leriyle ayrıca doğrulanır.

## İlişkili notlar

- [[06 - UX ve Görsel Tasarım/01 - Bilgi Mimarisi ve Ekranlar]]
- [[06 - UX ve Görsel Tasarım/02 - Dünya Haritası ve Görsel Dil]]
- [[07 - Teknik Tasarım/01 - iOS Mimarisi]]
- [[07 - Teknik Tasarım/04 - Kayıt, iCloud ve Yaşam Döngüsü]]

#gdd #erişilebilirlik #mobil #ios
