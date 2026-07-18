---
tür: GDD - ekonomi tasarımı
durum: Tasarım ilkeleri kabul edilmiş; sayısal denge test edilecek
kapsam: Gelir, maliyet, nakit, yatırım ve finansal okunabilirlik
kaynaklar:
  - docs/02_OYUN_TASARIMI.md
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - ekonomi
  - finans
---

# Ekonomi ve Finans

#gdd #ekonomi #finans

## Ana ilke

Ekonomi gerçekçi ilişkiler kurar; muhasebe simülasyonu olmaya çalışmaz. Bir maliyet oyuncuya yeni karar üretmiyorsa ayrı mikro sistem olmak yerine açıklanabilir bir kalemde toplulaştırılır. Gerçekçilik oynanabilirliğin, okunabilirliğin ve adil kararın önüne geçmez.

## Ortak operasyon formülü

`faaliyet sonucu = gelir - değişken taşıma - elleçleme - bekleme/dış kaynak - sabit gider payı - beklenen ceza`

### Gelir

- teslim edilen yük veya tamamlanan dönem;
- hizmet sınıfı;
- sözleşme fiyatı;
- kalite/başarı koşulları

üzerinden oluşur. Gelir, sözleşme kabul anında değil tanımlı teslimat veya dönem kapanışında tahakkuk eder.

### Değişken maliyet

Oyuncuya tek okunabilir taşıma maliyeti altında yakıt/enerji, sürücü zamanı ve bakım-lastik rezervi toplanabilir. Ayrı kalem ancak karar üretirse açılır.

### Sabit gider

- araç finansmanı ve sigorta;
- merkez;
- tesis;
- personel;
- kapasite/slot anlaşmaları

günlük veya dönemlik tahakkuk eder.

## Fiziksel akışla bağ

Her finans kaydı sözleşme, yük partisi, taşıma aşaması, servis hattı ve fiziksel göreve izlenebilir olmalıdır. Toplulaştırılmış simülasyon finansal sonucu değiştiremez.

Araç varış şehrinde kaldığı için boş dönüş, konumlandırma ve dönüş yükü gerçek maliyet sonuçları üretir. Depoda bırak/al; elleçleme ve tesis maliyeti yaratırken ana hat doluluğunu yükseltebilir.

## Denge hedefleri

İlk test koridorları:

- kötü eşleşmiş tek yön: `%0–6`;
- normal tek yön: `%5–12`;
- iki yönü dolu hat: `%12–20`;
- iyi ring: `%16–25`;
- yüksek riskli özel/ekspres: `%10–24`.

Bu değerler kesin karar değil, başlangıç hipotezidir. Ring daha yüksek potansiyele sahipken takvim ve aksama riski taşır. Araç ve depo birkaç teslimatta kendini amorti etmemelidir.

## Yatırım ve sermaye

Ortak karşılaştırma için bir sermaye birimi, standart başlangıç aracının edinim maliyetine bağlanabilir. Amaç fiyatları gerçek para taklidiyle değil, büyüme ritmiyle tutarlı kılmaktır:

- küçük kara kabiliyeti: haftalar/aylar;
- tesis ve intermodal erişim: aylar;
- büyük taşıt/iştirak: uzun vadeli kurumsal karar.

Oyuncu büyürken güvenli nakit rezervi tutmalı; tek kötü olay yüzünden açıklamasız şekilde kampanyasını kaybetmemelidir.

## Finansman araçları

Kredi, leasing, dış yatırım ve kapasite kiralama ileride:

- başlangıç maliyetini;
- dönemlik nakit baskısını;
- esneklik ve sahiplik riskini

değiştirebilir. Bunlar bedava büyüme değil, farklı nakit akışı profilleridir. Ayrıntılı ürün seti kanonik değildir.

## Ana KPI'lar

- nakit ve kullanılabilir rezerv;
- günlük/haftalık faaliyet sonucu;
- servis hattı katkı marjı;
- kapasite kullanımı;
- boş kilometre;
- zamanında teslimat;
- sözleşmeye bağlı gelecek gelir ve maliyet;
- tesis/filo geri ödeme tahmini.

Her KPI için “neden değişti?” açıklaması bulunur. Tahminler aralık ve varsayımlarla gösterilir.

## Zamanlama

- teslimat geliri ilgili teslim koşulunda;
- günlük sabit giderler gün kapanışında;
- hizmet sözleşmesi sonuçları sözleşme döneminde;
- bakım ve yatırım harcamaları işlem anında;
- büyük stratejik ödeme/teklifler gerektiğinde otomatik duraklatma

üretir.

## Başarısızlık ve toparlanma

Temel yaklaşım toparlanabilir krizdir:

- düşük marjlı sözleşmeyi güvenli kapatma;
- varlık satışı veya leasing;
- yeniden yapılandırma;
- dış kaynakla geçici hizmet koruma;
- küçülme.

Ani ve anlaşılmaz “game over” yerine sebep-sonuç görünürlüğü korunur.

## İlgili belgeler

- [[01 - İşler, Müşteriler ve Sözleşmeler]]
- [[02 - Taşıma Hatları ve Konsolidasyon]]
- [[03 - Araçlar ve Ekipman]]
- [[04 - Tesisler]]
- [[09 - Dünya Olayları ve Risk]]
