---
tür: GDD - simülasyon tasarımı
durum: Kabul edilmiş ölçek ilkesi; denge değerleri test edilecek
kapsam: Fiziksel akış, kapasite, toplulaştırma ve sonuç eşdeğerliği
kaynaklar:
  - "[[01 - Kanonik Lojistik Nesne Modeli]]"
  - docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - simülasyon
  - kapasite
---

# Kapasite ve Hibrit Simülasyon

#gdd #simülasyon #kapasite

## Kesinleşmiş ölçek kararı

Oyuncuya fiziksel yük akışı görünür. Şirket büyüdüğünde motor performans ve okunabilirlik için güvenli toplulaştırma yapabilir; fakat toplulaştırılmış simülasyon, ayrıntılı simülasyonun ekonomik ve operasyonel sonuçlarıyla eşdeğer olmalıdır.

Toplulaştırma:

- yükü ışınlamaz;
- araç kapasitesini yaratmaz;
- zaman penceresini atlamaz;
- riski, kuyruğu veya maliyeti silmez;
- sözleşmeyi doğrudan araca bağlamaz.

## Kapasite katmanları

### Araç ve ekipman kapasitesi

Gerçek taşıma kapasitesi şasi, bağlı gövde/dorse, kondisyon ve yük uyumluluğundan oluşur. Hacim yanında ağırlık, palet, konteyner slotu veya özel yük etiketi gibi kapasite birimleri kullanılabilir. En kısıtlayıcı geçerli sınır görevin kapasitesidir.

### Servis hattı kapasitesi

Bir hattın dönemlik kapasitesi:

- kalkış sayısı;
- kalkış başına kullanılabilir kapasite;
- araç bulunabilirliği;
- yükleme/boşaltma yuvası;
- takvim ve seyahat süresi;
- ayrılmış yedek pay

ile sınırlanır. Teorik araç toplamı, fiziksel olarak yapılamayan kalkışları meşrulaştırmaz.

### Tesis kapasitesi

Tek depo sayısı yerine ayrı kaynaklar izlenir:

- depolama;
- günlük giriş/çıkış işleme;
- cross-dock;
- araç parkı;
- ekipman parkı;
- kapı ve yükleme slotu;
- yerel dağıtım;
- yönetici kontrol kapasitesi.

Depo boş göründüğü hâlde kapılar doluysa kuyruk oluşabilir. Bu ayrım [[04 - Tesisler]] içindeki modül ve personel yatırımlarını anlamlı kılar.

### Sözleşme kapasite taahhüdü

Müşteri araç sayısı değil, hacim, sıklık, teslim süresi ve hizmet seviyesi ister. Sistem bunlardan araç eşdeğeri, depo işleme yükü ve yedek kapasite ihtiyacı tahmin eder.

## Yük yerleştirme

Uygun bir kalkışa yük partileri şu sıraya göre yerleştirilebilir:

1. zorunlu hizmet ve yük uyumluluğu;
2. son teslim ve bağlantı kaçırma riski;
3. müşteri/sözleşme önceliği;
4. konsolidasyon ve doluluk hedefi;
5. oyuncunun rezerv kapasite politikası.

Bir parti bölünebiliyorsa kalan miktar sonraki kalkışı bekler. Bölünemeyen yük, tamamı sığmadıkça yüklenmez. Birleştirme ve bölme işlemleri kaynak izini korur.

## Rezerv ve aşırı satış

Başlangıç denge referansı:

- yaklaşık `%75` düzenli sözleşme kapasitesi;
- `%15` spot ve yeni fırsat payı;
- `%10` olay/gecikme tamponu.

Bu oranlar kanonik sabit değil, veriyle ayarlanacak ilk test hedefidir. Oyuncu daha yüksek doluluk seçebilir; karşılığında gecikme ve dış kaynak maliyeti riski büyür. Yüzde 100 üzeri taahhüt gizlenmez; kabul öncesi hangi gün veya kalkışta açık oluşacağı gösterilir.

## Hibrit ayrıntı düzeyleri

### Ayrıntılı mod

Şu durumlarda tekil parti ve fiziksel görev simüle edilir:

- seçili veya ekranda yakın izlenen operasyon;
- kurucu aşamasındaki küçük filo;
- kritik gecikme, olay veya darboğaz;
- özel/benzersiz yük;
- bağlantı kaçırma riski;
- doğrulama ve test senaryosu.

### Toplulaştırılmış mod

Olgun ve kararlı operasyonlarda aynı:

- servis hattı;
- yük sınıfı ve uyumluluk;
- zaman kovası;
- kaynak/hedef;
- hizmet önceliği;
- risk durumu

paylaşan partiler grup hâlinde işlenebilir. Araç havuzları da takvim ve kapasite eşdeğerleriyle çözülebilir. Oyuncu seçtiğinde grup, açıklanabilir alt bileşenlerine açılır.

### Görsel temsil

Simülasyon ayrıntısı ile çizilen sprite sayısı aynı değildir. Yakın ölçekte gerçek araçlar ve görevler; uzak ölçekte hat kalınlığı, akış darbesi, hareket sıklığı ve düğüm sayaçları kullanılır. Ancak görsel özet her zaman canlı simülasyon durumundan türetilir.

## Sonuç eşdeğerliği sözleşmesi

Aynı başlangıç durumu, seed, oyuncu kararları ve zaman aralığında ayrıntılı ve toplulaştırılmış çalışma:

- aynı toplam yükü taşır;
- aynı fiziksel düğümlerde başlangıç ve bitiş yapar;
- kapasiteyi aynı şekilde tüketir;
- aynı teslimat sınıfına ve makul zaman toleransına ulaşır;
- aynı gelir ve maliyet bileşenlerini üretir;
- aynı olay/risk maruziyetini uygular;
- aynı araç kilometresi ve kondisyon kaybı toplamına ulaşır;
- aynı backlog ve tesis kuyruğunu bırakır.

Parasal yuvarlama ve zaman kovası nedeniyle izin verilen toleranslar veriyle tanımlanır ve otomatik test edilir. Toplulaştırılmış mod daha iyi sonuç üretmek için kullanılamaz.

## Zaman ve deterministiklik

Operasyon yükleme, yol, bekleme ve boşaltma fazlarında ilerler. Süreler nominal hesap ile seed'li üçgensel sapmadan oluşur. Gerçekleşen değer görev başlatıldığında bir kez üretilir ve kayda yazılır.

- Aynı kampanya ve aynı komut sırası aynı sonucu üretir.
- Kaydet/yükle RNG'yi yeniden çalıştırmaz.
- Toplulaştırma sınırı değişse bile olay çekimleri ve finansal sonuçlar kararlı kimliklerden türetilir.
- Oyuncuya gizli kesin dakika yerine tahmin aralığı gösterilir.

## Ölçek geçişleri

- **Kurucu:** tekil araç ve görev; manuel karar.
- **Yerel operatör:** küçük rota ve araç havuzu.
- **Bölgesel şirket:** servis hatları, depo kuyrukları ve dönemlik kapasite.
- **Ulusal/küresel ağ:** bölgesel havuzlar, multimodal slotlar ve politika tabanlı tahsis.

Geçiş oyuncunun erişimini azaltmaz. Oyuncu herhangi bir toplu sonucu sözleşme → parti → aşama → hat → görev zincirinde inceleyebilmelidir.

## Test senaryoları

1. 100 birim hat kapasitesine 80 normal + 30 ekspres yük: aşırı satış ve öncelik sonucu iki modda eşleşir.
2. Depo kapıları dolu, depolama boş: iki mod da giriş kuyruğu üretir.
3. Üç araçlı hat ve bir arıza: aynı teslimat açığı, dış kaynak ihtiyacı ve maliyet oluşur.
4. Bölünmüş 80 birim parti, 20 birim araç kapasitesi: toplam dört araç-sefer eşdeğeri gerekir.
5. Aktarma bağlantısı kaçar: sonraki slot, bekleme maliyeti ve SLA sonucu eşleşir.
6. Araç varış şehrinde kalır; toplulaştırma eve dönüş üretmez.

## İlgili belgeler

- [[01 - Kanonik Lojistik Nesne Modeli]]
- [[02 - Rota ve Operasyon Planlama]]
- [[02 - Taşıma Hatları ve Konsolidasyon]]
- [[04 - Tesisler]]
- [[06 - Ekonomi ve Finans]]
