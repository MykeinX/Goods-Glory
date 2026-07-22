---
tür: GDD
durum: kabul-edildi
kapsam: Kuruluş ve ilk oyun deneyimi
kaynaklar:
  - "`Taslak_fikir.md`"
  - "`docs/02_OYUN_TASARIMI.md`"
  - "`docs/04_KARARLAR_VE_ACIK_SORULAR.md`"
  - "Kullanıcının 2026-07-17 tarihli Ana Tasarım Özeti"
  - "`AKIS_VE_HAT_REVIZYONU_PLAN.md` (2026-07-20 akış revizyonu)"
son_güncelleme: 2026-07-20
etiketler:
  - gdd
  - gdd/çekirdek-oynanış
  - gdd/başlangıç
  - gdd/onboarding
---

# Başlangıç Deneyimi

#gdd #gdd/çekirdek-oynanış #gdd/onboarding

## Amaç

Başlangıç deneyimi oyuncuya üç şeyi hızla öğretir:

1. Bu şirket bana ait.
2. Araçlar fiziksel konum ve kapasite taşıyan varlıklardır.
3. Kâr, işi kabul etmekten değil doğru operasyonu kurmaktan doğar.

İlk saatin hedef duygusu "iş kabul ettim" değil, **"ilk yük döngümü kurdum"**dur.

## Kuruluş Akışı

### 1. Şirket Kimliği

Oyuncu haritaya geçmeden önce:

- şirket adını,
- amblemini,
- ana kurumsal rengini

belirler. Kimlik ilk araçta, merkez tabelasında, filo kodunda ve arayüz vurgularında görünür.

### 2. Başlangıç Şehri

Oyuncu sunulan başlangıç şehirlerinden birini seçer. Seçim; yerel talep, bağlantılar, maliyet ve büyüme fırsatları açısından anlaşılır farklar taşımalıdır.

### 3. Şirket Merkezi

Oyuncu küçük şirket merkezini kurar. Başlangıç yapısı depo değildir.

Merkez:

- yönetim ofisini,
- operasyon planlamayı,
- sınırlı araç parkını,
- temel çalışan ve sürücü organizasyonunu,
- ilk finans ve kredi erişimini

temsil eder.

Depolama, cross-dock veya ağır ekipman ihtiyacı oluştuğunda ayrı tesis yatırımı yapılır.

### 4. İlk Kapasite

Oyuncu sınırlı nakit ve krediyle ilk hafif/standart ticari aracını edinir. Araç; kapasite, konum, durum ve işletme maliyetiyle gerçek bir şirket varlığıdır.

**Öneri:** Başlangıç varlıklarının kesin sayısı, araç sınıfı ve kredi limiti denge testiyle belirlenmelidir.

### 5. İlk Akış ve Sevk

Harita açıldığında başlangıç şehrinden çıkan az sayıda (2–3) kalıcı yük akışı görünür: hangi firma, hangi şehre, hangi üründen günde kaç ton. Tek iş teklifi ekranı yoktur; talep haritada durur ve beklemektedir.

Oyuncu:

- bir akışa dokunur; debi, adresler, spot ücret ve tahmini maliyeti görür,
- aracını akışa gönderir (bekleyen partiyi alır),
- haritada fazları takip eder.

### 6. İlk Sonuç ve Döngü

Teslimat tamamlandığında araç hedef şehirde kalır. Varış şehrindeki geri yönlü akış öne çıkarılır: oyuncu dönüş yükü alma, başka şehre yönelme, boş dönme veya bekleme kararını verir. Konumlandırma ve boş kilometre böylece erken öğretilir.

2–3 manuel seferden sonra oyun ilk hattı önerir: "Bu iki şehir arasında hat kur." Araç hatta bağlanır, döngü otomatikleşir ve ekranda ilk kez doluluk yüzdesi ile boş kilometre görünür. Bundan sonrası kurulan sistemi büyütmek ve optimize etmektir: ikinci akışı kapsama almak, ikinci araç, ilk sözleşme teklifi, ilk depo modülü.

## Kademeli Sistem Açılımı

Başlangıçta yalnızca mevcut kararı destekleyen ekran ve eylemler açılır.

Önerilen öğretim sırası:

1. Kimlik ve şehir
2. Merkez ve ilk araç
3. Akış okuma ve ilk sevk
4. Araç konumu ve dönüş yükü
5. İlk hat: döngü, doluluk ve boş km
6. Finans özeti ve bakım
7. İkinci araç veya ikinci akış
8. İlk sözleşme (akış payı taahhüdü)
9. Tesis modülleri (depo, ofis) ve delegasyon

Oyuncuya kilitli sistemlerin varlığı gösterilebilir; ancak gereksiz ayrıntıyla başlangıç ekranı doldurulmaz.

## Öğretim İlkeleri

- Metin açıklamasından önce bağlamlı eylem kullanılır.
- Zorunlu el tutma minimumda tutulur.
- Yanlış ama toparlanabilir kararlar öğrenmenin parçasıdır.
- İlk finans sonucu kalem kalem açıklanır.
- Her yeni sistem önce tek bir gerçek problem çözer.
- Otomasyon, oyuncu manuel davranışı anladıktan sonra açılır.

## İlk Oturum Başarı Ölçütleri

**Test hipotezleri:**

- İlk 2 dakikada şirket kimliği ve başlangıç şehri seçilebilir.
- İlk 60–90 saniye içinde ilk anlamlı iş veya kapasite kararı verilebilir.
- İlk 10 dakika içinde bir teslimat sonucu ve dönüş kararı görülebilir.
- İlk 20–30 dakika içinde düzenli büyümeye dair bir sonraki hedef anlaşılır.

Bu süreler kabul edilmiş denge değerleri değil, kullanıcı testi hedefleridir.

## Başlangıçta Gösterilmeyecek Karmaşıklık

- Tam çok modlu ağ planlama
- Büyük ihale portföyü
- Küresel regülasyon
- Ayrıntılı departman politikaları
- Çok tesisli konsolidasyon
- Satın alma ve halka arz

Bu sistemler [[05 - İlerleme ve İçerik/01 - Şirket Büyüme Aşamaları|Şirket Büyüme Aşamaları]] boyunca gerçek ihtiyaçla açılır.

## İlgili Notlar

- [[01 - Ana Oynanış Döngüsü]]
- [[03 - Zaman ve Çevrimdışı İlerleme]]
- [[01 - Ürün Vizyonu/04 - Oyuncu Fantezisi ve Marka|Oyuncu Fantezisi ve Marka]]
- [[05 - İlerleme ve İçerik/02 - Dünya, Şehirler ve Açılımlar|Dünya, Şehirler ve Açılımlar]]
