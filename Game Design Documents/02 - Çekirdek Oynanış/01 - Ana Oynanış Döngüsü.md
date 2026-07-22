---
tür: GDD
durum: kabul-edildi
kapsam: Çekirdek oynanış
kaynaklar:
  - "`Taslak_fikir.md`"
  - "`docs/01_URUN_VIZYONU.md`"
  - "`docs/02_OYUN_TASARIMI.md`"
  - "Kullanıcının 2026-07-17 tarihli Ana Tasarım Özeti"
  - "`AKIS_VE_HAT_REVIZYONU_PLAN.md` (2026-07-20 akış revizyonu)"
son_güncelleme: 2026-07-20
etiketler:
  - gdd
  - gdd/çekirdek-oynanış
  - gdd/oynanış-döngüsü
---

# Ana Oynanış Döngüsü

#gdd #gdd/çekirdek-oynanış #gdd/oynanış-döngüsü

## Döngünün Özeti

1. **Akışları oku:** Haritadaki kalıcı yük akışlarını, mevcut taahhütleri, araç konumlarını, kapasiteyi, riski ve nakdi incele.
2. **Fırsatı değerlendir:** Hangi akışı servis edeceğini, hangi taahhüdü (sözleşme, ihale, özel operasyon) alacağını getiri ve stratejik değere göre karşılaştır.
3. **Hizmet sözü ver:** Bir akışın payını hacim, süre, güvenilirlik ve fiyatla taahhüt et — veya taahhütsüz spot ücretle servis et.
4. **Operasyon zincirini kur:** Doğrudan ya da aktarmalı hat; araç, tesis ve dış kapasite planla. Hat, kapsadığı akışların partilerini kendisi çeker.
5. **Kapasiteyi tahsis et:** Sözleşmeli yük, spot yük, yedek pay ve bakım ihtiyacı arasında kaynak ayır.
6. **Zamanı çalıştır:** Sevkiyatlar sürekli simülasyon içinde yüklenir, taşınır, aktarılır ve teslim edilir.
7. **Sapmaları yönet:** Gecikme, arıza, talep değişimi, kriz ve fırsatlara müdahale et.
8. **Sonucu analiz et:** Gelir, gider, doluluk, boş kilometre, teslimat kalitesi ve itibar değişiminin nedenlerini gör.
9. **Yatırım ve politika kararı al:** Filo, tesis, teknoloji, yönetici, yeni pazar veya otomasyon seç.
10. **Daha büyük ölçekte tekrarla:** Operasyon olgunlaştıkça tekil işten hat ve portföy yönetimine geç.

## Ana Karar Nesneleri

### Başlangıçta

- Servis edilecek yük akışı seçimi
- Tekil araç ve ekipman
- Araç konumu
- Doğrudan hat (gidiş-dönüş döngüsü)
- Dönüş yükü veya boş hareket

### Büyüme Sonrasında

- Düzenli müşteri sözleşmesi
- Taşıma hattı ve kalkış sıklığı
- Kapasite havuzu
- Konsolidasyon ve aktarma kuralı
- Bölgesel politika ve yönetici yetkisi
- Çok modlu uçtan uca hizmet zinciri

Bu geçiş [[01 - Ürün Vizyonu/02 - Tasarım Sütunları|Tasarım Sütunları]] içindeki “tıklama değil karar ölçeği büyür” ilkesinin mekanik karşılığıdır.

## İş ve Sözleşme Akışı

### Yük Akışı (spot servis)

Talebin kaynağı, firmalar arasındaki kalıcı yük akışlarıdır; ayrı bir "spot iş" nesnesi yoktur. Taahhütsüz servis edilen akış partileri spot ücretle ödenir. Tek partiyi manuel taşımak başlangıç eğitimini, acil nakdi, yeni pazar testini ve boş aracın ücretli konumlandırılmasını destekler; olgun oyunda hatlar bu partileri kendisi çeker.

### Düzenli Sözleşme

Bir akışın payını belirli dönem boyunca hacim ve hizmet seviyesiyle taahhüt eder. Partiler akıştan otomatik oluşur; oyuncu her partiyi tekrar kabul etmez. Ana görev yeterli ve dayanıklı ağı sürdürmektir. Sözleşme bitince akış tabana döner; hat boşa düşmez.

### Büyük İhale

Fiyat, kapasite, itibar, kapsama ve hizmet kalitesinin rakiplerle karşılaştırıldığı stratejik taahhüttür.

### Özel Operasyon

Seyrek, geçici ve sıra dışı kapasite veya planlama isteyen olay tabanlı içeriktir.

## Fiziksel Operasyon İlkeleri

- Araç teslimat yaptığı yerde kalır; otomatik olarak merkeze ışınlanmaz.
- Boş hareket zaman, personel, enerji/yakıt ve bakım maliyeti üretir.
- Oyuncu basit, döngüsel veya çok aşamalı rota kurabilir.
- Bir operasyona birden fazla araç veya kapasite havuzu ayrılabilir.
- Farklı müşterilerin uyumlu yükleri aynı hatta konsolide edilebilir.
- Yük; doğrudan taşınabilir veya tesisler üzerinden araç ve taşıma modu değiştirebilir.

## Oyuncunun Okuduğu Sonuçlar

Her döngü sonunda en az şu göstergeler açıklanabilir olmalıdır:

- net operasyon kârı,
- doluluk ve kullanılmayan kapasite,
- dolu/boş kilometre dengesi,
- zamanında teslimat,
- gecikme ve hasar nedenleri,
- sözleşme hizmet seviyesi,
- müşteri memnuniyeti ve itibar,
- nakit ve borç baskısı.

## Karar Kalitesi Kriteri

İyi bir karar:

- en az iki makul seçenek sunar,
- kısa ve uzun vadeli sonuçları dengeler,
- oyuncuya yeterli ön bilgi verir,
- sonucu açıklanabilir kılar,
- şirket stratejisine göre farklı cevaplara izin verir.

## İlgili Notlar

- [[02 - Başlangıç Deneyimi]]
- [[03 - Zaman ve Çevrimdışı İlerleme]]
- [[04 - Başarı, Kriz ve Başarısızlık]]
- [[05 - İlerleme ve İçerik/03 - Yük Türleri ve Özel Operasyonlar|Yük Türleri ve Özel Operasyonlar]]
