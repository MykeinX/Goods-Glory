---
tür: GDD
durum: kabul-edildi
kapsam: Yük içeriği, ihaleler ve özel operasyonlar
kaynaklar:
  - "`Taslak_fikir.md`"
  - "`docs/02_OYUN_TASARIMI.md`"
  - "`docs/04_KARARLAR_VE_ACIK_SORULAR.md`"
  - "Kullanıcının 2026-07-17 tarihli Ana Tasarım Özeti"
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - gdd/ilerleme
  - gdd/yükler
  - gdd/özel-operasyonlar
---

# Yük Türleri ve Özel Operasyonlar

#gdd #gdd/ilerleme #gdd/yükler

## Tasarım Amacı

Yük türleri yalnızca farklı isim ve fiyat değildir. Her tür; araç, ekipman, tesis, rota, süre, güvenlik veya risk açısından yeni ve anlaşılır karar üretir.

Bir yük özelliği yeni karar üretmiyorsa bağımsız sistem yerine mevcut sınıf içinde veri varyasyonu olarak kalır.

## Temel Yük Aileleri

### Standart Yük

- Standart kara aracı, tren, gemi ve depo ile uyumludur.
- Başlangıç ekonomisinin ve konsolidasyonun temelidir.
- Doluluk, süre ve dönüş yükü kararlarını öğretir.

### Bozulabilir Ürün

- Soğutmalı ekipman ve sıcaklık kontrollü tesis ister.
- Bekleme ve aktarma toleransı düşüktür.
- Daha hızlı planlama ile daha yüksek maliyet arasında gerilim kurar.

### İlaç ve Medikal

- Kesintisiz takip, sıcaklık kontrolü, güvenlik ve yüksek hizmet seviyesi ister.
- İtibar getirisi yüksektir; başarısızlık etkisi ağırdır.
- Uygun lisans, personel ve tesis kabiliyeti gerektirir.

### Değerli Elektronik

- Güvenlikli araç/tesis, sigorta ve düşük aktarma sayısını teşvik eder.
- Hız, güvenlik ve taşıma maliyeti dengesi üretir.

### Ağır ve Büyük Yük

- Özel araç, ekipman, güzergâh ve terminal kabiliyeti ister.
- Kapasite ve izin planlamasıyla seyrek fakat değerli operasyon oluşturur.

### Tehlikeli Madde

- Şirket seviyesinde anlamlı lisanslar,
- uygun araç ve tesis,
- kısıtlı güzergâh,
- yüksek güvenlik ve uyum standardı

gerektirir. Sürücü başına belge mikro yönetimi yapılmaz.

## Ekipman ve Tesis İlişkisi

Yük uygunluğu yalnızca araç sınıfına bağlanmaz:

- Entegre gövdeler aracın kalıcı parçası olabilir.
- Dorseler ayrı şirket varlığı olarak tesiste tutulabilir.
- Soğutma veya özel kurulumlar zaman ve tesis gerektirebilir.
- Depo, aktarma merkezi ve terminal eklentileri belirli hizmetleri açar.

Depo başlangıç zorunluluğu değildir; stoklama, fulfillment, paketleme, iade, soğuk zincir ve şehir dağıtımı gibi yeni iş modellerini açan stratejik yatırımdır.

## İş İçeriği Kategorileri

### Spot İşler

Tek seferlik taşımalardır. Başlangıç öğretimi, dönüş yükü, fazla kapasite ve yeni pazar testi için kullanılır.

### Düzenli Sözleşmeler

Belirli süre, hacim, sıklık, fiyat ve hizmet seviyesi taşır. Ana gelir ve ağ planlama sistemi budur.

### Büyük İhaleler

Fiyat, kapasite, güvenilirlik, itibar, coğrafi kapsama ve uygun kabiliyet üzerinden rekabet edilir.

Örnekler:

- teknoloji şirketinin bölgesel dağıtımı,
- fabrika parça lojistiği,
- küresel perakende ağı,
- kamu veya yardım kurumu operasyonu.

### Özel Projeler

Seyrek gelir, geçici kapasite baskısı ve özgün planlama ister.

Örnekler:

- fabrika taşınması,
- yeni ürün lansmanı,
- sezonluk tarım dağıtımı,
- acil tıbbi yardım,
- büyük fuar veya spor organizasyonu.

## Özel Operasyon Tasarım Şablonu

Her özel operasyon:

1. Açık bir müşteri ve dünya bağlamı sunar.
2. Hazırlık süresi veya ön sinyal verir.
3. Hacim, süre, yük özelliği ve hizmet hedefini açıklar.
4. Doğrudan, aktarmalı, dış kaynaklı veya çok modlu seçeneklere izin verir.
5. Normal ağı geçici olarak zorlar; tek doğru çözüm dayatmaz.
6. Finans, itibar ve stratejik erişim sonuçlarını açıklar.

## Açılma Yapısı

Yeni yük aileleri aşağıdaki birleşimle açılır:

- yeterli şirket aşaması,
- uygun lisans/uyum,
- araç veya dış kapasite erişimi,
- gerekli tesis kabiliyeti,
- eğitilmiş personel/yönetici,
- yeterli müşteri itibarı.

Kesin sayılar ve eşikler denge parametresidir.

## Risk ve Ödül

Yüksek özel gereksinim:

- daha yüksek gelir,
- daha değerli müşteri,
- uzmanlık itibarı

sağlayabilir; karşılığında sabit yatırım, düşük esneklik ve ağır başarısızlık etkisi doğurur. En pahalı ekipmanı almak otomatik başarı sağlamaz.

## İlgili Notlar

- [[01 - Şirket Büyüme Aşamaları]]
- [[02 - Dünya, Şehirler ve Açılımlar]]
- [[02 - Çekirdek Oynanış/01 - Ana Oynanış Döngüsü|Ana Oynanış Döngüsü]]
- [[02 - Çekirdek Oynanış/04 - Başarı, Kriz ve Başarısızlık|Başarı, Kriz ve Başarısızlık]]
