---
tür: GDD
durum: kabul-edildi
kapsam: Simülasyon zamanı ve çevrimdışı ilerleme
kaynaklar:
  - "`docs/02_OYUN_TASARIMI.md`"
  - "`docs/04_KARARLAR_VE_ACIK_SORULAR.md`"
  - "Kullanıcının 2026-07-17 tarihli Ana Tasarım Özeti"
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - gdd/çekirdek-oynanış
  - gdd/zaman
  - gdd/çevrimdışı
---

# Zaman ve Çevrimdışı İlerleme

#gdd #gdd/çekirdek-oynanış #gdd/çevrimdışı

## Zaman Modeli

Oyun tur bazlı değildir. Simülasyon zamanı sürekli akar; oyuncu zamanı durdurabilir ve hızlandırabilir.

Kabul edilmiş davranış:

- Duraklatma bulunur.
- Normal ve hızlandırılmış zaman seçenekleri bulunur.
- Teslimatlar yükleme, yol, aktarma ve boşaltma fazlarında ilerler.
- Gelir ve operasyon sonuçları ilgili olay tamamlandığında işlenir.
- Dönemsel sabit giderler kendi kapanış zamanlarında hesaplanır.
- Büyük kararlar zamanı otomatik durdurabilir.
- Küçük olaylar bildirim ve şirket günlüğüne düşer.

## Hız Değerleri

Ürün temposu: **0× / 1× / 3× / 6×**, taban dönüşüm **1 gerçek saniye = 10 oyun dakikası** (1×). Üst kademeler tam çarpan: 3× = 30 dk/sn, 6× = 60 dk/sn (1 oyun saati / sn). Harita araç hareketi aynı tick penceresine bağlanır; ayrı bir harita hızı yoktur.

Eski browser prototipi 1 sn = 5 dk ve 8× kullanıyordu; ana tasarım özetindeki 5× ifadesi de kilitlenmemişti. Bu değerler oturum okunabilirliği ve harita sıçrama boyutu için seçilmiştir; gerekirse denge parametresi olarak yeniden ayarlanır.

## Otomatik Duraklatma

Otomatik duraklatma yalnızca oyuncudan anlamlı ve zaman hassasiyetli karar isteyen olaylarda kullanılır:

- kritik nakit seviyesi,
- büyük ihale veya süreli teklif,
- yeni bölge/taşıma modu açılımı,
- ana kapasitenin dolması,
- büyük kriz,
- önemli finans veya yeniden yapılandırma teklifi.

Sık ve düşük etkili olaylar oyunu kesmez. Oyuncu otomatik duraklatma kategorilerini yönetebilmelidir.

## Çevrimdışı İlerleme

Çevrimdışı ilerleme kabul edilmiş ürün yönüdür. Oyun kapalıyken şirket sınırlı ve güvenli biçimde çalışmaya devam eder.

### Devam Edenler

- Başlatılmış sevkiyatlar tamamlanabilir.
- Önceden kurulmuş otomatik hatlar çalışabilir.
- Normal gelir ve giderler hesaplanır.
- Planlı bakım ve kapasite sonuçları ilerleyebilir.
- Mevcut sözleşmeler, tanımlı otomasyon kuralları içinde hizmet üretir.

### Duraklayan veya Güvenli Hâle Gelenler

- Oyuncu adına yeni büyük stratejik karar alınmaz.
- Yeni ihale veya uzun vadeli taahhüt otomatik kabul edilmez.
- Şirket oyuncu yokken otomatik olarak nihai iflasa sürüklenmez.
- Büyük krizler kalıcı ve geri döndürülemez zarar vermeden karar bekler.
- Yetkisi tanımlanmamış yönetici eylemleri uygulanmaz.

### Süre Sınırı

Çevrimdışı simülasyon belirli bir süreyle sınırlandırılır.

**Denge parametresi:** Sürenin kesin değeri kabul edilmiş değildir. Ekonomi, geri dönüş sıklığı, adalet ve pil/hesaplama maliyeti test edilerek belirlenir. Süre sınırı monetizasyon baskısı olarak kullanılmaz.

## “Sen Yokken” Raporu

Oyuncu geri döndüğünde tek ve açıklanabilir bir özet görür:

- geçen gerçek ve oyun süresi,
- tamamlanan ve geciken teslimatlar,
- gelir ve gider dökümü,
- sözleşme hizmet seviyesi değişimleri,
- bakım bekleyen araçlar,
- kapasite darboğazları,
- süresi devam eden fırsatlar,
- karar bekleyen krizler.

Rapor, sonuçların nedenini ve öncelikli önerilen eylemleri gösterir; oyuncuyu çok sayıda ayrı bildirimle karşılamaz.

## Adalet Kuralları

- Çevrimdışı sonuçlar çevrimiçi simülasyonla aynı ekonomik kuralları kullanır.
- Oyuncunun görmediği yeni riskler geri döndürülemez ceza üretmez.
- Otomasyonun yaptığı işlem, hangi politika veya yönetici yetkisiyle yapıldığını açıklar.
- Saat değiştirme ve tekrar hesaplama istismarlarına karşı kayıtlı simülasyon zamanı kullanılır.
- Çevrimdışı kazanç, aktif karar vermeyi anlamsızlaştıracak kadar avantajlı değildir.

## İlgili Notlar

- [[01 - Ana Oynanış Döngüsü]]
- [[04 - Başarı, Kriz ve Başarısızlık]]
- [[01 - Ürün Vizyonu/03 - Hedef Oyuncu ve Platform|Hedef Oyuncu ve Platform]]
- [[05 - İlerleme ve İçerik/01 - Şirket Büyüme Aşamaları|Şirket Büyüme Aşamaları]]
