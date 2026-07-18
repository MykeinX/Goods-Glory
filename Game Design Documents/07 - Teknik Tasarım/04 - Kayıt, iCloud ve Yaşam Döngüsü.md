---
tür: Teknik GDD
durum: Hedef ve açık kararlar
kapsam: Yerel kayıt, CloudKit hedefi, çatışma ve uygulama yaşam döngüsü
kaynaklar:
  - Ana Tasarım Özeti
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - docs/08_TEST_ARACLARI_VE_LOGBOOK.md
  - web/README.md
son_güncelleme: 2026-07-17
etiketler: [gdd, kayıt, icloud, cloudkit, yaşam-döngüsü]
---

# Kayıt, iCloud ve Yaşam Döngüsü

## Ürün hedefi

İlk iOS sürümü güvenilir yerel kayıt sunmalı; CloudKit üzerinden iCloud senkronizasyonu ürün hedefidir. Cloud senkronizasyonu, yerel kaydın yerine geçmez ve ağ yokken oyunu kullanılamaz hâle getirmez.

Yerel teknoloji SwiftData veya SQLite değerlendirmesi sonucunda seçilir. Seçimden bağımsız olarak uygulama bir `SaveRepository` sözleşmesi kullanır.

## Kayıt modeli

Bir kampanya kaydı en az şunları taşır:

- save ve katalog şema sürümü,
- kampanya ve profil kimliği,
- revizyon ve son başarılı kayıt zamanı,
- simülasyon seed’i ve oyun zamanı,
- şirket, ekonomi, sözleşme, ağ, tesis, filo, yük ve rezervasyon durumu,
- üretilmiş rastgele sonuçlar ve sıra sayaçları,
- sınırlı Logbook/denetim izi,
- otomasyon politikaları ve bekleyen kritik kararlar.

Statik kataloglar save içine kopyalanmaz; save kararlı içerik kimliklerine referans verir.

## Yerel güvenilirlik

- Yazma atomiktir: yarım kayıt geçerli kaydın üzerine geçmez.
- Uygulama açılışında şema ve çapraz referans doğrulanır.
- En az bir önceki sağlıklı snapshot veya kurtarma noktası korunur.
- Autosave önemli domain işlemlerinden sonra ve ölçülü zaman aralıklarında tetiklenir.
- Manuel “şimdi kaydet” geri bildirimi sunulabilir; kayıt güvenliği yalnız buna bağlı değildir.
- Migration tek yönlü, sürümlü ve fixture’larla test edilir.

## CloudKit senkronizasyon hedefi

CloudKit entegrasyonu aşağıdaki ilkeleri karşılamalıdır:

- Oyuncunun iCloud hesabı yoksa yerel oyun devam eder.
- Senkronizasyon durumu, son başarı ve hata anlaşılır biçimde görünür.
- Kampanya revizyonu ve cihaz kimliği sessiz üzerine yazmayı önler.
- Çatışma çözümü domain bütünlüğünü korur; alan alan rastgele birleştirme yapılmaz.
- Aynı kampanyanın iki cihazda eşzamanlı ilerlemesi algılandığında güvenli varsayılan, iki tam snapshot arasında bilinçli seçim veya doğrulanmış birleştirme stratejisidir.
- Silme ve yeni oyun başlatma işlemleri iki aşamalı onay ve tombstone/sürüm politikası kullanır.

CloudKit record tasarımı, SwiftData’nın olası otomatik senkron davranışı ve özel CloudKit repository yaklaşımı prototipte karşılaştırılır. Hedef bellidir; uygulama yöntemi henüz ürün kararı değildir.

## Uygulama yaşam döngüsü

### Arka plana geçiş

Yeni simülasyon komutu kabulü durdurulur, devam eden atomik adım tamamlanır, snapshot alınır ve yeterli süre yoksa güvenli son kayıt korunur. SpriteKit render’ı durabilir; simülasyon durumu kaybolmaz.

### Ön plana dönüş

Yerel kayıt ve olası cloud revizyonu kontrol edilir. Çevrimdışı ilerleme etkinse yalnız tanımlı üst sınıra kadar deterministik yakalama yapılır. Sonuçlar uygulanmadan önce kritik karar ve güvenlik sınırları değerlendirilir.

### Sonlandırma ve çökme

Uygulama sonlandırma callback’ine güvenilmez. Kayıt stratejisi periyodik ve işlem sonrası snapshot’larla veri kaybı penceresini sınırlar. Bir sonraki açılışta yarım yazma ve uyumsuz revizyon tespit edilir.

## Çevrimdışı ilerleme

Ana tasarım hedefi sınırlı çevrimdışı ilerlemedir:

- başlatılmış operasyonlar tamamlanabilir,
- otomatik hatlar tanımlı süre boyunca çalışabilir,
- normal gelir ve giderler hesaplanır,
- büyük stratejik kararlar bekler,
- oyuncu yokken kontrolsüz iflas veya geri döndürülemez kriz uygulanmaz,
- dönüşte “Sen yokken” özeti gösterilir.

Süre sınırı, kriz davranışı ve hangi otomasyonların çalışacağı denge testine tabi açık ürün kararlarıdır. Cihaz saatinin geri/ileri alınması sonuç üretmemeli; güvenilir zaman farkı ve kayıtlı referanslar kullanılmalıdır.

## Gizlilik ve veri kapsamı

Save yalnız oyun için gereken verileri içerir. Geliştirici Test Tools durumu üretim kaydından ayrılır. Telemetri, hesap veya çapraz platform aktarımı ayrıca onaylanmadıkça CloudKit hedefinin parçası sayılmaz.

## Browser prototipi — mevcut uygulama, ürün kararı değil

Browser prototipi yerel D1 autosave, revizyon kontrolü, export/import ve schema-8 doğrulaması kullanmıştır. Bu davranışlar kayıt güvenliği için kanıt ve test senaryosu sağlar; iOS depolama teknolojisini veya CloudKit şemasını belirlemez.

Browser’daki iki saniyelik autosave aralığı, host paylaşımı ve önceki kampanyaları migrate etmeme kararı prototipe özgü teknik gerçeklerdir.

## İlişkili notlar

- [[07 - Teknik Tasarım/01 - iOS Mimarisi]]
- [[07 - Teknik Tasarım/02 - Simülasyon Çekirdeği ve Determinizm]]
- [[07 - Teknik Tasarım/03 - Veri Odaklı İçerik]]
- [[08 - Sürüm Kapsamı/01 - İlk Sürüm Kapsamı]]

#gdd #kayıt #icloud #cloudkit #yaşam-döngüsü
