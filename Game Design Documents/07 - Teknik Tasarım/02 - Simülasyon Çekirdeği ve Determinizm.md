---
tür: Teknik GDD
durum: Öneri ve doğrulama gereksinimi
kapsam: Saf Swift simülasyon, hibrit çözünürlük ve deterministik sonuçlar
kaynaklar:
  - Ana Tasarım Özeti
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - web/README.md
son_güncelleme: 2026-07-17
etiketler: [gdd, simülasyon, determinizm, performans]
---

# Simülasyon Çekirdeği ve Determinizm

## Amaç

Yüzlerce varlık ve uzun kampanyalar büyürken sonuçların açıklanabilir, tekrar üretilebilir ve cihaz performansından bağımsız kalmasını sağlamak. Çekirdek saf Swift’tir; SwiftUI, SpriteKit, kayıt teknolojisi ve gerçek zamanlayıcı olmadan çalışabilir.

## Zaman ve komut modeli

Simülasyon yalnız iki girdiyle ilerler:

- doğrulanmış oyuncu/sistem komutları,
- açık miktarda oyun zamanı.

Duvar saati doğrudan oyun kuralı değildir. Duraklatma ve hız seçenekleri uygulama katmanının simülasyona kaç oyun dakikası uyguladığını değiştirir; aynı toplam oyun zamanı ve komut sırası aynı sonucu vermelidir.

Aktif görevler yükleme, taşıma, aktarma, bekleme ve boşaltma gibi açık fazlar taşır. Gelir, maliyet, rezervasyon ve kapasite değişimleri tanımlı işlem sınırlarında uygulanır.

## Determinizm sözleşmesi

Aynı:

- içerik sürümü,
- başlangıç snapshot’ı,
- kampanya seed’i,
- sıralı komut listesi,
- ilerletilen oyun süresi

aynı sonuç snapshot’ını ve aynı önemli domain olaylarını üretir.

Rastgelelik yalnız seed’li servis üzerinden kullanılır. Seed türetimi kararlı kimlikler ve sıra numaralarıyla tanımlanır. Üretilmiş gerçek süre veya talep yeniden yüklemede tekrar çekilmez; save içine yazılır. Koleksiyon sırası, kayan nokta yuvarlaması ve platforma bağlı hash davranışı açıkça kontrol edilir.

## Hibrit simülasyon

Detay çözünürlüğü şirket ölçeğine göre değişebilir:

- Oyuncunun incelediği aktif operasyonlar olay/faz düzeyinde ilerler.
- Uzak, otomatik veya çok büyük operasyon kümeleri toplu/analitik adımlarla hesaplanabilir.
- Sprite ve animasyon sayısı fiziksel varlık sayısının birebir karşılığı değildir.

Bu optimizasyonun değişmez kuralı **deterministik sonuç eşdeğerliğidir**:

> Aynı durum ve komutlar, detaylı ve toplu çözüm yollarında tanımlı gözlem noktalarında aynı ekonomik ve operasyonel sonucu üretmelidir.

Eşdeğerlik; nakit, yük miktarı, araç/tesis konumu, kapasite rezervasyonu, teslim durumu, SLA, ceza, kondisyon ve Logbook olaylarını kapsar. Tam eşitlik mümkün olmayan istatistiksel alt sistemler ancak açık tolerans, aynı seed ve ürün kararıyla kabul edilir; sessiz sapma kabul edilmez.

Çözünürlük değiştirmek oyuncuya avantaj sağlamaz, olay sırasını bozmaz ve kayıt yükleyerek farklı sonuç aramaya izin vermez.

## Değişmezler

- Fiziksel yük yoktan oluşmaz veya kaybolmaz.
- Kütle ve hacim kapasitesi ayrı ayrı aşılmaz.
- Aynı varlık aynı anda iki konumda bulunmaz.
- Rezervasyon, kabul ve settlement işlemleri atomiktir.
- Araç teslimat sonrası gerçek varış konumunda kalır.
- Uygun olmayan ekipman/yük/tesis eşleşmesi komut aşamasında reddedilir.
- Para ve ölçü birimleri tek kanonik biçimde tutulur; sunum dönüşümleri UI’da yapılır.

## Performans bütçesi ilkeleri

Kesin sayısal bütçeler desteklenen cihaz matrisi ve gerçek içerikle ölçülerek sabitlenir. Şimdiden bağlayıcı ilkeler:

- Simülasyon maliyeti render kare hızından bağımsızdır.
- Ana thread uzun simülasyon partileriyle bloklanmaz.
- Normal hızda adım süresi cihaz bütçesinin yalnız küçük bir bölümünü kullanır.
- 8×, zaman atlama ve çevrimdışı yakalama için işlem sayısı geçen her dakikayla doğrusal büyümek zorunda değildir.
- Bellek; geçmişin tamamını canlı nesne olarak tutmak yerine snapshot ve sınırlı denetim iziyle yönetilir.
- Büyük dünya, kötü cihaz performansı nedeniyle farklı ekonomik sonuç üretmez.

Ölçülecek senaryolar: erken oyun, önerilen ilk sürüm üst sınırı, yoğun otomatik ağ, yedi günlük zaman atlama, kayıt yükleme ve arka plandan dönüş. Her optimizasyon önce profiler kanıtıyla yapılır.

## Doğrulama

- Tek adım ve komut birim testleri.
- Uzun süreli invariant/property testleri.
- Ayrıntılı ve toplu çözücü karşılaştırma testleri.
- Aynı fixture için browser ve Swift beklenen sonuç testleri.
- Save/load öncesi ve sonrası sonuç eşitliği.
- Farklı cihaz ve thread zamanlamalarında aynı sonuç hash’i.

## Browser prototipi — mevcut kanıt

Browser motorunda seed’li talep, iş teklifleri, faz süreleri, koridorlar, rezervasyonlar ve settlement testleri vardır. FNV-1a/üçgensel örnekleme gibi mevcut ayrıntılar uyumluluk için değerli bir referanstır; nihai Swift RNG uygulaması ancak çapraz platform fixture’ları ve uzun dönem kalite testiyle kabul edilir.

Browser’ın mevcut 1 saniye = 5 oyun dakikası ve 1×/3×/8× hızları prototip ayarıdır; ürün hızları denge ve oturum testine tabidir.

## İlişkili notlar

- [[07 - Teknik Tasarım/01 - iOS Mimarisi]]
- [[07 - Teknik Tasarım/03 - Veri Odaklı İçerik]]
- [[07 - Teknik Tasarım/04 - Kayıt, iCloud ve Yaşam Döngüsü]]
- [[08 - Sürüm Kapsamı/02 - Prototip Hipotezleri]]

#gdd #simülasyon #determinizm #performans
