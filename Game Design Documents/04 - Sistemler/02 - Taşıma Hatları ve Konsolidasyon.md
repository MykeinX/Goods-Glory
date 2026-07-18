---
tür: GDD - sistem tasarımı
durum: Kabul edilmiş ağ ilkesi
kapsam: Servis hatları, kalkışlar, konsolidasyon ve kapasite havuzları
kaynaklar:
  - "[[01 - Kanonik Lojistik Nesne Modeli]]"
  - "[[02 - Rota ve Operasyon Planlama]]"
  - docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - servis-hatları
  - konsolidasyon
---

# Taşıma Hatları ve Konsolidasyon

#gdd #servis-hatları #konsolidasyon

## Temel tanım

Servis hattı bir müşteri sözleşmesi değil, şirketin iki düğüm arasında işlettiği düzenli taşıma hizmetidir. Aynı hat, uygun olduğu sürece birden fazla müşterinin yük partisini taşır.

Örnek:

> Riverton Deposu → Pinecrest Deposu, günde iki kalkış, genel ve güvenli kuru yük, 40 birim/kalkış.

## Hat bileşenleri

- başlangıç ve hedef düğüm;
- taşıma türü;
- kalkış takvimi veya hedef frekans;
- seferlik/dönemlik kapasite;
- kabul edilen yük ve ekipman etiketleri;
- araç ya da kapasite havuzu;
- yükleme ve boşaltma tesisleri;
- öncelik, doluluk ve bekletme politikası;
- yedek kapasite;
- maliyet, güvenilirlik ve olay hassasiyeti;
- açık, askıda, kapanıyor veya kapalı durum.

Hat açılması yük yaratmaz. Hacim, kabul edilen sözleşmelerin partilerinden ve spot pazardan gelir.

## Konsolidasyon

Aynı yöne giden yükler şu koşullarda bir kalkışta birleştirilebilir:

- yük ve ekipman uyumlu;
- kaynak ve hedef aşamaları aynı;
- teslim pencereleri birlikte çalışabilir;
- güvenlik/ayrıştırma kuralları ihlal edilmez;
- toplam miktar kapasiteyi aşmaz.

Konsolidasyon doluluğu ve marjı yükseltir; yükü bekletme, bağlantı kaçırma ve depoda kuyruk riskini de artırabilir.

## Kalkış yerleştirme politikaları

- **Son teslim öncelikli:** En yakın deadline önce.
- **Hizmet sınıfı öncelikli:** Ekspres ve kritik yük önce.
- **Doluluk hedefli:** Güvenli pencere içinde daha dolu kalkış beklenir.
- **Müşteri öncelikli:** Stratejik müşteriye ayrılmış pay korunur.
- **Dengeli:** Deadline, önem ve doluluk ortak puanlanır.

Politikalar görünür sonuç üretir; gizli yüzde bonusu değildir.

## Çok araç ve kapasite havuzu

Bir hatta:

- tek araç;
- farklı kapasitelerde birden çok araç;
- belirli araçlardan oluşan havuz;
- şirket filosu + dış kaynak;
- multimodal slot

atanabilir. Motor kalkışları fiziksel uygunluğa göre araçlara dönüştürür. Araç başka şehirdeyse hatta anında katılamaz; konumlandırma görevi gerekir.

Yedek araç günlük gelir üretmeden maliyet yaratabilir, fakat arıza ve pik talepte hizmet seviyesini korur. Bu, kârlılık-güvenilirlik geriliminin açık karşılığıdır.

## Hat döngüsü ve kapanış

Tek yönlü hat aracı hedefte bırakır. Çift yönlü hizmet iki ayrı yön kapasitesi olarak izlenir. Ring hizmet birden çok bacaklı plan olabilir; her bacağın yük ve zaman dengesi ayrıdır.

Hat kapatma:

1. yeni yük rezervasyonunu durdurur;
2. yüklenmiş görevleri tamamlar;
3. bekleyen partiler için yeniden yönlendirme uyarısı üretir;
4. araçları son görevlerinin bittiği düğümde boş bırakır.

“Başlangıca dön” ayrıca planlanmış bir bacak değilse otomatik uygulanmaz.

## Performans göstergeleri

- toplam ve kullanılabilir kapasite;
- doluluk;
- yükle/boş kilometre;
- zamanında kalkış ve teslim;
- depoda ortalama bekleme;
- kaçırılan veya ertelenen yük;
- birim başına maliyet;
- katkı marjı;
- yedek kapasite;
- olay sonrası toparlanma süresi.

Her göstergenin değişim nedeni hat, tesis, sözleşme ve görev kayıtlarına bağlanır.

## Darboğazlar

Bir hattın nominal araç kapasitesi yeterli olsa bile:

- yükleme kapısı;
- ekipman/dorse;
- sürücü veya operasyon programı;
- depo işleme;
- hedefte boşaltma;
- sonraki bağlantı;
- araç kondisyonu

gerçek kapasiteyi düşürebilir. Arayüz en düşük etkili kapasiteyi ve kaynağını gösterir.

## Otomasyon

Kurucu aşamasında oyuncu kalkışları doğrudan başlatabilir. Bölgesel aşamada yönetici:

- uygun aracı seçer;
- partileri politikaya göre yerleştirir;
- rezerv sınırını korur;
- küçük gecikmeleri çözer;
- eşik dışı riski oyuncuya yükseltir.

Otomasyon yeni kapasite yaratmaz ve kötü fiyatlanmış hattı sihirli biçimde kârlı yapmaz.

## İlgili belgeler

- [[03 - Kapasite ve Hibrit Simülasyon]]
- [[04 - Doğrudan ve Aktarmalı Taşıma]]
- [[03 - Araçlar ve Ekipman]]
- [[04 - Tesisler]]
- [[07 - Çalışanlar, Yöneticiler ve Otomasyon]]
