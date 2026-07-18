---
tür: GDD - sistem tasarımı
durum: Yönetim ayrımı kabul edilmiş; ayrıntılı roller kademeli
kapsam: Merkez ve tesis çalışanları, delegasyon ve politika otomasyonu
kaynaklar:
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - docs/02_OYUN_TASARIMI.md
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - çalışanlar
  - otomasyon
---

# Çalışanlar, Yöneticiler ve Otomasyon

#gdd #çalışanlar #otomasyon

## Tasarım ilkesi

Şirket büyüdükçe oyuncunun işi daha fazla tıklamak değil, daha büyük kararlar vermektir. Çalışanlar yalnızca yüzde bonusu sağlamaz; yeni bir karar seviyesi, kapasite veya delegasyon biçimi açar.

## Organizasyon ayrımı

### Merkez ofis

Şirket çapındaki roller:

- **Operasyon Koordinatörü:** aktif plan kapasitesi ve ilk delegasyon;
- **Ticari Yönetici:** teklif filtreleme, yenileme ve pazar tahmini;
- **Finans Yöneticisi:** nakit ve yatırım tahminleri;
- **Uyum Yöneticisi:** özel yük ve faaliyet kabiliyetleri;
- **Bölge Yöneticisi:** birden fazla tesis ve hat için politika yönetimi.

### Tesis

Fiziksel operasyon rolleri:

- depo yöneticisi;
- dispatcher/vardiya sorumlusu;
- depo ekibi;
- forklift operatörü;
- bakım sorumlusu;
- özel yük uzmanı.

Depo yöneticisi şirketin tamamını değil kendi tesisinin araç, ekipman, kuyruk, yerel sözleşme ve hatlarını yönetir.

## Yönetim aşamaları

### Kurucu Operasyonu

- az sayıda araca manuel görev;
- tekil rota ve ekipman kararı;
- dakika/gün ölçeğinde takip.

### Bölgesel Operatör

- rota şablonları ve servis hatları;
- araç havuzları;
- tesis yöneticileri;
- günlük/haftalık istisna yönetimi.

### Lojistik Şirketi

- bölgesel kapasite ve portföy politikaları;
- otomatik tahsis ve yenileme sınırları;
- haftalık/aylık yatırım, risk ve performans kararı.

Oyuncu her aşamada ayrıntıya inebilir; ancak rutin icra için zorlanmaz.

## Otomasyon davranışı

Bir yönetici, oyuncunun tanımladığı sınırlar içinde:

- uygun aracı ve ekipmanı seçer;
- yük partilerini kalkışlara yerleştirir;
- minimum rezerv kapasitesini korur;
- bakım eşiğine göre araç değiştirir;
- düşük etkili gecikmeleri yeniden planlar;
- belirlenen marjın altındaki işi reddeder;
- eşik dışı kararı oyuncuya yükseltir.

Otomasyon:

- araç veya kapasite yaratmaz;
- fiziksel konumu yok saymaz;
- lisans/tesis koşulunu atlamaz;
- kötü hattı bedelsiz kârlı yapmaz;
- gerçekleşmiş sonucu gizlemez.

## Kontrol kapasitesi

Merkez ve yöneticiler sınırlı:

- aktif sözleşme;
- servis hattı;
- araç/kapasite havuzu;
- tesis

kontrol kapasitesi taşır. Sınırın aşılması daha fazla manuel yük veya koordinasyon riski doğurur. Bu sistem oyuncuyu çalışan almaya zorlayan yapay sayaç değil, büyümenin organizasyon ihtiyacıdır.

## Politikalar ve istisnalar

Örnek politika alanları:

- minimum beklenen marj;
- hedef doluluk;
- kriz rezervi;
- ekspres yük önceliği;
- izin verilen dış kaynak maliyeti;
- bakım eşiği;
- gecikmede otomatik yeniden yönlendirme;
- sözleşme yenileme sınırı.

Küçük sapmalar Logbook'a yazılır. Büyük sözleşme, kritik nakit, yeni bölge veya büyük kriz otomatik duraklatma üretebilir.

## Çalışan gelişimi

Deneyim, eğitim ve uzmanlık:

- daha tutarlı operasyon;
- daha doğru tahmin;
- daha yüksek kontrol kapasitesi;
- belirli yük/tesis kabiliyeti

sağlayabilir. Ayrıntılı vardiya ve bireysel sürücü mikro yönetimi ilk kapsam değildir.

## Arayüz

Oyuncu her delegasyon için:

- sorumlu kişi;
- yönettiği kapsam;
- kullanılan politika;
- kapasite sınırı;
- son istisnalar;
- kararın açıklaması

bilgilerini görür. “AI halletti” ifadesi yeterli değildir.

## İlgili belgeler

- [[02 - Taşıma Hatları ve Konsolidasyon]]
- [[04 - Tesisler]]
- [[06 - Ekonomi ve Finans]]
- [[10 - Şirket Politikaları ve İtibar]]
