---
tür: Teknik GDD
durum: Öneri
kapsam: Native iOS uygulama mimarisi
kaynaklar:
  - Ana Tasarım Özeti
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - web/README.md
son_güncelleme: 2026-07-17
etiketler: [gdd, teknik, ios, swiftui, spritekit]
---

# iOS Mimarisi

## Mimari hedef

Native iPhone uygulaması; SwiftUI arayüzü, SpriteKit dünya haritası ve UI’dan bağımsız saf Swift simülasyon çekirdeği olarak ayrılır. Framework seçimi domain sınırlarını belirlemez. MVVM, SwiftUI sunumunu düzenlemek için kullanılabilir; simülasyon motorunun tamamı ViewModel’lere yerleştirilmez.

## Önerilen katmanlar

### Domain / Simulation

- Saf Swift veri türleri, kurallar ve durum geçişleri.
- SwiftUI, SpriteKit, SwiftData, CloudKit ve duvar saatine bağımlı değildir.
- Aynı başlangıç durumu, komut dizisi ve seed ile aynı sonucu üretir.
- Değer tipleri ve açık bağımlılıklar tercih edilir.

### Application

- Oyuncu komutlarını doğrular ve simülasyona uygular.
- Oturum, zaman kontrolü, kayıt anı, senaryo ve uygulama yaşam döngüsünü koordine eder.
- Domain olaylarını sunum için okunabilir sonuçlara dönüştürür.

### Data / Persistence

- Bundle içeriğini yükler ve doğrular.
- Save snapshot, Logbook ve kullanıcı tercihlerini saklar.
- Yerel kayıt ile CloudKit senkronizasyonu arasındaki sınırı yönetir.
- Domain modellerine framework nesneleri sızdırmaz.

### Presentation

- SwiftUI ekranları, erişilebilirlik, navigasyon ve kullanıcı niyeti.
- ViewModel/observable durumlar yalnız ekranın ihtiyacı kadar veri yayımlar.
- Harita sunumu SpriteKit sahnesine dönüştürülmüş salt okunur render snapshot’ları kullanır.

## Ana bileşenler

- `GameCatalog`: Doğrulanmış, salt okunur içerik tanımları.
- `SimulationEngine`: Komut ve zaman adımı uygulayan saf çekirdek.
- `GameSession`: Aktif kampanya, hız, duraklatma ve uygulama koordinasyonu.
- `SaveRepository`: Atomik snapshot okuma/yazma sözleşmesi.
- `SyncCoordinator`: CloudKit kayıtları ve çatışma politikasını koordine eden sınır.
- `MapSceneAdapter`: Domain snapshot’ını SpriteKit düğümlerine dönüştürür.
- `LogbookStore`: Açıklanabilir sonuçları ve denetim izini sunar.

Bu adlar öneridir; sorumluluk sınırları adlardan daha önemlidir.

## Durum akışı

1. SwiftUI kullanıcı niyetini bir uygulama komutuna dönüştürür.
2. Application katmanı komutu doğrular.
3. Saf çekirdek yeni durum ve domain olayları üretir.
4. Kayıt katmanı uygun noktada atomik snapshot alır.
5. SwiftUI ve SpriteKit aynı sürümlenmiş durumdan sunum modeli üretir.

UI doğrudan nakit, araç konumu veya sözleşme performansı değiştiremez. SpriteKit temasları yalnız seçim veya komut niyeti üretir.

## Eşzamanlılık

Aktif kampanya durumu tek bir sahip tarafından seri biçimde değiştirilir; Swift concurrency ile bir `actor` veya eşdeğer tek-yazarlı yürütme modeli değerlendirilir. Ağ, CloudKit ve dosya işlemleri çekirdeği bloklamaz. `Sendable` sınırları ve iptal davranışı test edilir.

Simülasyon deterministik kalması gereken hesaplarda görev yarışına, cihaz saatine veya tamamlanma sırasına dayanmaz.

## SwiftData veya SQLite değerlendirmesi

Kalıcı teknoloji prototip ölçümü sonrası seçilir:

- **SwiftData:** Apple ekosistemiyle hızlı modelleme, sorgu ve SwiftUI entegrasyonu sağlar; migration, benzersiz kimlik, toplu yazma ve CloudKit davranışı gerçek veri hacmiyle doğrulanmalıdır.
- **SQLite:** Şema, transaction, migration, performans ve denetim izi üzerinde daha açık kontrol sağlar; repository ve eşleme kodu maliyeti yüksektir.

Seçim ölçütleri: snapshot boyutu, Logbook hacmi, migration güvenliği, atomik yazma, sorgu ihtiyacı, test edilebilirlik ve CloudKit çatışma stratejisi. Domain katmanı seçilen teknolojiye bağımlı olmaz.

## Test stratejisi

- Domain kuralları ve değişmezler için birim testleri.
- Sabit seed ve komut dizileri için golden sonuç testleri.
- Browser ve Swift motoru arasında veri/formül uyumluluk fixture’ları.
- Kayıt migration, bozuk veri ve atomik yazma testleri.
- SwiftUI ana akış ve erişilebilirlik testleri.
- SpriteKit harita seçimi ve performans ölçümleri.

## Browser prototipi — taşınacak ve taşınmayacaklar

TypeScript/React kaynak kodunun Swift’e doğrudan çevrilmesi hedef değildir. Taşınacak varlıklar; kararlı kimlikler, JSON şemaları, formüller, doğrulama kuralları, seed sözleşmesi, test senaryoları ve beklenen sonuçlardır.

Browser’daki D1 kayıt, schema-8 save, React görünüm yapısı ve mevcut modül adları uygulanmış prototip gerçekleridir; native mimari kararı değildir.

## İlişkili notlar

- [[07 - Teknik Tasarım/02 - Simülasyon Çekirdeği ve Determinizm]]
- [[07 - Teknik Tasarım/03 - Veri Odaklı İçerik]]
- [[07 - Teknik Tasarım/04 - Kayıt, iCloud ve Yaşam Döngüsü]]
- [[06 - UX ve Görsel Tasarım/02 - Dünya Haritası ve Görsel Dil]]

#gdd #teknik #ios #swiftui #spritekit
