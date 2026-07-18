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

Browser prototipinde 0×/1×/3×/8× ve başlangıçta 1 gerçek saniye = 5 oyun dakikası uygulanmıştır. Ana tasarım özetindeki 1×/3×/5× ifadesiyle farklılık vardır.

**Denge parametresi:** Kesin zaman oranı ve hız kademeleri ürün kararı olarak kilitlenmemiştir. Kullanıcı testi; okunabilirlik, bekleme süresi, pil yükü ve çevrimdışı dengeye göre nihai değerleri belirler.

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
