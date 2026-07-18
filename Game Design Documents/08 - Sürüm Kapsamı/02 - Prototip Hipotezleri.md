---
tür: Doğrulama GDD
durum: Test edilecek
kapsam: Browser ve native teknik prototip karar kapıları
kaynaklar:
  - Ana Tasarım Özeti
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/05_GORSEL_YON_VE_HARITA.md
  - docs/08_TEST_ARACLARI_VE_LOGBOOK.md
  - web/README.md
son_güncelleme: 2026-07-17
etiketler: [gdd, prototip, hipotez, doğrulama]
---

# Prototip Hipotezleri

## Amaç

Prototip, nihai oyunun eksik görselli kopyası değil; riskli ürün ve teknik varsayımları düşük maliyetle yanlışlayacak bir laboratuvardır. Bir özellik prototipte uygulanmış olsa bile test sonucu ve açık karar olmadan kalıcı ürün gereksinimi sayılmaz.

## Ürün hipotezleri

### H1 — Hizmet sözü stratejik karar üretir

Oyuncu sözleşmeyi yalnız en yüksek ödül olduğu için değil; kapasite, süre, risk ve gelecekteki ağ planıyla birlikte değerlendirir.

**Kanıt:** Test oturumunda oyuncu en az iki ödünleşmeyi kendi cümlesiyle açıklar; sözleşme seçimleri tek bir baskın seçeneğe yığılmaz.

### H2 — Kârlılık, güvenilirlik ve büyüme okunabilir

Oyuncu başarısız sonucun hat kapasitesi, gecikme, maliyet ve ceza zincirini yardım almadan bulabilir.

**Kanıt:** İlk başarısız olay sonrası neden üç dakika içinde doğru teşhis edilir.

### H3 — Fiziksel yük ağı derinlik üretir

Kütle/hacim, konum, rezervasyon, aktarma ve depolama kararları strateji üretir; yalnız işlem yükü oluşturmaz.

**Kanıt:** Oyuncu doğrudan ve aktarmalı plan arasında gerekçeli seçim yapar; yük kaybı/çifte rezervasyon invariant testleri sıfır hata verir.

### H4 — Büyüme mikro yönetimi azaltır

Hat, politika ve yöneticiler oyuncuyu her araç için sürekli iş bulmaktan kurtarır.

**Kanıt:** Orta oyun senaryosunda filo iki katına çıktığında zorunlu etkileşim sayısı iki katına çıkmaz.

### H5 — Mobil harita hızlı okunur

Portrait iPhone genişliğinde oyuncu şehir, hat, sorun ve seçimi ayırt eder.

**Kanıt:** Kritik hat üç saniye içinde bulunur; renk kapatıldığında durum yine anlaşılır; yanlış dokunma oranı kabul eşiğinin altındadır.

### H6 — Kısa oturum anlamlıdır

Oyuncu birkaç dakika içinde durumu okuyup karar verir ve güvenli biçimde ayrılır.

**Kanıt:** İlk karar 90 saniyeden önce, ilk neden-sonuç gözlemi ilk 10 dakika içinde gerçekleşir.

## Teknik hipotezler

### T1 — Çekirdek platformdan bağımsız tanımlanabilir

JSON sözleşmeleri, formüller ve fixture’lar browser ile saf Swift motorunda aynı kanonik sonuçları üretir.

### T2 — Hibrit simülasyon eşdeğerdir

Detaylı ve toplu hesap yolları tanımlı gözlem noktalarında aynı ekonomik ve operasyonel sonuçları verir.

### T3 — Dünya cihaz bütçesine sığar

Önerilen 50–60 şehirlik ilk sürüm ve üst sınır yoğun operasyon senaryosu, en düşük hedef cihazda etkileşim ve simülasyon bütçesini karşılar.

### T4 — Kayıt güvenlidir

Arka plana geçiş, zorla kapatma, migration, bozuk snapshot ve iki cihaz revizyon çatışması veri kaybı oluşturmadan yönetilir.

### T5 — Erişilebilir ana akışlar tamamlanabilir

Kuruluş, ilk iş, sözleşme inceleme ve darboğaz bulma; Dynamic Type, VoiceOver ve Reduce Motion açıkken tamamlanır.

## Browser prototipinin mevcut kapsamı

Mevcut prototip kara odaklıdır; kuruluş, ilk uyumlu fırsat, düzenli müşteri sözleşmesi, servis planı, çift yönlü koridor, fiziksel yük, tesis, finans ve Logbook akışlarını içerir. Deniz, demir ve hava tanımları pasiftir. Yaklaşık 140 şehirli harita bir veri/ağ test alanıdır.

Bu uygulamalar “hipotez test edilebilir” anlamına gelir; “hipotez doğrulandı” anlamına gelmez. D1 kayıt, koyu tema, sol navigasyon, schema-8 ve mevcut modül adları prototip gerçekleridir.

## Karar kapısı

Native üretim kapsamı büyütülmeden önce:

- çekirdek döngünün eğlenceli olduğu,
- sözleşme ve hat UX’inin anlaşılır olduğu,
- kapasite/tesis derinliğinin işlem yüküne dönüşmediği,
- mobil bilgi yoğunluğunun yönetilebildiği,
- veri şemaları ve kanonik testlerin yeterince kararlı olduğu

kanıtlanmalıdır.

## İlişkili notlar

- [[08 - Sürüm Kapsamı/01 - İlk Sürüm Kapsamı]]
- [[08 - Sürüm Kapsamı/04 - Browser Prototipi Uygulama Notları]]
- [[07 - Teknik Tasarım/02 - Simülasyon Çekirdeği ve Determinizm]]
- [[06 - UX ve Görsel Tasarım/03 - Erişilebilirlik ve Mobil Kullanım]]

#gdd #prototip #hipotez #doğrulama
