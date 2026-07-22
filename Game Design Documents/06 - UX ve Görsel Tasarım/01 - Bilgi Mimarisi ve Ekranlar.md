---
tür: GDD
durum: Öneri
kapsam: Kalıcı ürün tasarımı ve iPhone portrait bilgi mimarisi
kaynaklar:
  - Ana Tasarım Özeti
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/05_GORSEL_YON_VE_HARITA.md
  - web/README.md
  - "`AKIS_VE_HAT_REVIZYONU_PLAN.md` (2026-07-20 akış revizyonu)"
son_güncelleme: 2026-07-20
etiketler: [gdd, ux, bilgi-mimarisi, ios]
---

# Bilgi Mimarisi ve Ekranlar

## Amaç

Oyuncunun birkaç dakika içinde şirketin durumunu okuyup anlamlı bir karar verebildiği, büyüyen operasyonu bilgi kalabalığına dönüştürmeyen bir iPhone portrait arayüzü kurmak. Arayüz, “araç sürücüsü” değil “şirket CEO’su” rolünü destekler.

## Harita-öncelikli okunabilirlik (tasarım sütunu)

Oyuncu ağının durumunu **sekme sekme gezmeden haritadan okur**; sekmeler detay ve toplu yönetim içindir. Her UI kararının ilk sorusu: "Bu bilgiyi görmek için kaç dokunuş gerekiyor?"

- Dokunmadan görünür: akış çizgileri (kalınlık ≈ debi; servissiz soluk, taşınan marka renginde), hat üzerindeki araçlar ve doluluk, şehirde dikkat gerektiren durum (tek aksiyon rozeti), tesis mini şeridi.
- Tek dokunuşla görünür: akış detayı (debi, firma, spot ücret, "hat kur"), şehir detayı (akışlar, bekleyen yük, tesis), hat panosu (doluluk, boş km, $/gün, darboğaz kaynağı).
- Sistem kurma eylemleri (hat kur, kapsama ekle) haritadan başlatılabilir; sekmeye gitmek zorunlu değildir.

## Kalıcı ürün kararı

Native uygulama SwiftUI ile geliştirilir. Ana navigasyon `TabView`, ekran içi akışlar `NavigationStack`, bağlamsal ayrıntılar sheet ve inspector benzeri yüzeylerle kurulur. Harita ayrı bir ürün alanı olsa da şirket durumu, sözleşme ve finans ekranlarıyla aynı seçimi ve zamanı paylaşır.

Önerilen ana alanlar:

1. **Harita:** Ağ, akışlar, tesisler, hareket, darboğaz ve seçili analiz katmanı — ana yüzey.
2. **Operasyon:** Hatlar, akışlar, sözleşmeler; yük partileri, aktarmalar, kapasite ve otomasyon kuralları.
3. **Varlıklar:** Filo, ekipman, tesisler ve modülleri.
4. **Şirket:** Finans, itibar, çalışanlar, politikalar ve Logbook.

Alan adları kullanıcı testleriyle doğrulanır. İlk sürümde bir alanın kapsamı küçükse ayrı sekme yerine ilgili üst alan içinde kalır.

## Ekran hiyerarşisi

Her ana ekran üç seviyede bilgi verir:

- **Özet:** Şimdi dikkat gerektiren durum, temel KPI ve birincil eylem.
- **Liste/harita:** Karşılaştırma, filtreleme ve seçim.
- **Ayrıntı:** Neden-sonuç, maliyet kırılımı, bağlı nesneler ve karar seçenekleri.

Her KPI “neden değişti?” açıklamasına bağlanır. Kritik durumdan ilgili şehir, hat, sözleşme, yük veya tesise tek adımda gidilebilir.

## Ana görev akışları

### Şirket kuruluşu

Şirket adı, logo ve kurumsal renk → başlangıç şehri karşılaştırması → genel merkez kurulumu → başlangıç varlıkları → ilk uyumlu iş. Depo kuruluşun zorunlu adımı değildir.

### Akış servisi ve hat kurma

Haritada akışı gör → debi, adresler, spot ücret ve maliyeti karşılaştır → aracı gönder veya "hat kur" de → alış/teslim durakları otomatik gelir, güzergâhtaki uyumlu dönüş akışları önerilir → sonucu harita ve hat panosundan izle. Kurulum akış-önceliklidir: önce yük, sonra rota; durak eklemek istisnadır (depo aktarması, çok duraklı dağıtım).

### Düzenli sözleşme

Servis ettiğin akıştan gelen teklifi incele → hizmet sözü ver → hat ve kapasite ayır → performansı (kapsam, doluluk) izle → yenile, yeniden fiyatla veya güvenli kapat.

### Ağ yönetimi

Darboğazı seç → neden zincirini gör → kapasite, sıklık, rota, tesis veya politika değiştir → beklenen etkiyi önizle → zaman ilerledikçe sonucu doğrula.

## Mobil sunum kuralları

- Bir ekranda tek baskın görev ve tek belirgin birincil eylem bulunur.
- Harita üstünde kalıcı kart yığını oluşturulmaz; ayrıntı alttan açılan bağlamsal sheet’e taşınır.
- Geniş tablolar yerine filtrelenebilir listeler, karşılaştırma kartları ve katmanlı ayrıntı kullanılır.
- Kritik kararlar onay öncesi ekonomik ve operasyonel etkilerini gösterir.
- Seçim, filtre ve harita konumu ekranlar arasında mümkün olduğunca korunur.
- Simülasyon zamanı ve duraklatma durumu ana operasyon yüzeylerinde erişilebilir kalır.

## Browser prototipi — mevcut uygulama, ürün kararı değil

Mevcut browser prototipinde Business, Network, Fleet, Map, Finance ve Logbook alanları ile geliştirici Test Tools görünümü vardır. Daha eski plan belgesindeki Harita, Üs, Filo, İşler ve Finans omurgası bir doğrulama önerisidir. Bu adlar ve sol panel düzeni native uygulamaya aynen taşınmaz; yalnızca görev akışları, veri sözleşmeleri ve kullanıcı testi bulguları girdi kabul edilir.

Browser prototipindeki kuruluş, garanti uyumlu ilk fırsat, servis planı, koridor, fiziksel yük ve kayıt akışları UX hipotezlerini sınar. Üretim kapsamı ancak [[08 - Sürüm Kapsamı/02 - Prototip Hipotezleri|Prototip Hipotezleri]] sonuçlarıyla netleşir.

## Kabul ölçütleri

- Yeni oyuncu iki dakika içinde şirketin amacını kendi cümlesiyle açıklar.
- İlk anlamlı karar 90 saniyeden önce verilebilir.
- Oyuncu başarısız bir sonucun neden zincirini yardım almadan bulabilir.
- Bir şehir, sözleşme veya hattın bağlı yük ve kapasitesine en fazla üç gezinme adımında ulaşılır.
- Portrait küçük iPhone ekranında yatay kaydırma temel görevler için zorunlu değildir.

## İlişkili notlar

- [[06 - UX ve Görsel Tasarım/02 - Dünya Haritası ve Görsel Dil]]
- [[06 - UX ve Görsel Tasarım/03 - Erişilebilirlik ve Mobil Kullanım]]
- [[07 - Teknik Tasarım/01 - iOS Mimarisi]]
- [[08 - Sürüm Kapsamı/01 - İlk Sürüm Kapsamı]]

#gdd #ux #bilgi-mimarisi #ios
