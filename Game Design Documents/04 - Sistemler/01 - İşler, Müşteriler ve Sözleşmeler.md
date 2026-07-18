---
tür: GDD - sistem tasarımı
durum: Kanonik nesne ilişkisi; ticari ayrıntılar test edilecek
kapsam: Pazar, müşteriler, işler ve sözleşme yaşam döngüsü
kaynaklar:
  - "[[01 - Kanonik Lojistik Nesne Modeli]]"
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - sözleşmeler
  - müşteriler
---

# İşler, Müşteriler ve Sözleşmeler

#gdd #sözleşmeler #müşteriler

## Sistem rolü

Pazar, oyuncuya yalnızca ödül listesi sunmaz. Müşteri ihtiyacını, şirketin verdiği hizmet sözünü ve bu sözden doğan fiziksel yük akışını üretir.

Kanonik ilişki:

> Müşteri ihtiyacı → Sözleşme → Yük partileri → Taşıma aşamaları → Servis hatları → Fiziksel görevler

Sözleşme doğrudan araca atanmaz. Araçlar [[01 - Kanonik Lojistik Nesne Modeli|kanonik modelde]] tanımlanan fiziksel görevleri yürütür.

## Pazar katmanları

### Spot işler

- kısa süre açık kalır;
- kuruluş öğretimi ve acil nakit sağlar;
- tek seferlik gerçek yük üretir;
- boş aracı ücretli biçimde yeniden konumlandırabilir;
- düzenli kapasite sözü istemez.

Şirket büyüdükçe ana strateji olmaktan çıkar, ancak tamamen kaybolmaz.

### Hat sözleşmeleri

- iki veya daha fazla ticari nokta arasında dönemlik hacim ve sıklık ister;
- devam eden ya da sabit süreli olabilir;
- yük partilerini düzenli takvimde üretir;
- oyuncunun servis hattı ve kapasite planlamasını yönlendirir.

### Hizmet sözleşmeleri

- şehir dağıtımı, müşteri ağı veya uçtan uca çok aşamalı hizmet sunar;
- tesis, personel, ekipman ve ayrılmış kapasite isteyebilir;
- oyuncuyu tekil sevkiyattan portföy yönetimine taşır.

## Müşteriler

Müşteri profili şu tercihleri taşıyabilir:

- fiyat hassasiyeti;
- hız ve zamanında teslimat beklentisi;
- hasar/güvenlik toleransı;
- hacim kararlılığı ve oynaklığı;
- sürdürülebilirlik veya özel yük beklentisi;
- ilişki güveni;
- pazarlık ve yenileme eğilimi.

İlk sürümde bütün müşterileri ayrıntılı kişilik simülasyonuna dönüştürmek gerekmez. Bu nitelikler farklı sözleşme kararları üretmeye yettiği ölçüde kullanılmalıdır.

## Arz-talep üretimi

Şehirler ürün grubu bazında arz, talep, taban hacim, büyüme ve oynaklık taşır. Bir teklif ancak:

- kaynakta yeterli arz;
- hedefte talep;
- uygun bağlantı;
- yükün gerektirdiği operasyon koşulları

varsa üretilir.

Pazar her dakika rastgele değişmez. Haftalık taban döngüsü; mevsim, kriz ve müşteri olaylarıyla görünür biçimde değişir. Aynı dünya seed'i ve dönem aynı teklif setini üretmeye elverişli olmalıdır.

## Sözleşme alanları

- müşteri ve sözleşme arketipi;
- kaynak ve nihai hedef;
- yük türü ve hizmet gereksinimleri;
- yük partisi üretim takvimi;
- dönemlik hacim ve kalkış beklentisi;
- teslimat penceresi ve tolerans;
- fiyat, endeksleme veya ödeme yöntemi;
- gereken lisans, tesis ve kabiliyetler;
- itibar/güven etkisi;
- süre, yenileme, başarısızlık ve fesih alanları.

Son gruptaki ayrıntılar veri modelinde bulunur; **kesin süre, ceza ve fesih kuralları henüz kanonik değildir.** Devam eden anlaşma, sabit süreli fırsat ve hizmet sözleşmesi kendi arketipine göre test edilmelidir.

## Kabul öncesi değerlendirme

Oyuncuya:

- beklenen yük profili;
- gerekli hat ve araç eşdeğeri;
- tesis ve ekipman açığı;
- tahmini gelir, maliyet ve faaliyet marjı;
- kapasite kullanımı ve yedek pay;
- gecikme/olay riski;
- başka sözleşmelerle çatışma;
- ilk yük partisinin üretileceği zaman

gösterilir. Gerçekçilik bahanesiyle kritik maliyet veya risk saklanmaz.

## Yaşam döngüsü

1. Pazar ihtiyacı teklif üretir.
2. Oyuncu fizibiliteyi inceler ve kabul eder/reddeder.
3. Kabul edilen sözleşme takvime göre yük partileri üretir.
4. Partiler operasyon ağına yerleştirilir.
5. Teslimatlar SLA ve müşteri güvenini günceller.
6. Dönem raporu finans, kapasite ve sorun nedenlerini açıklar.
7. Süreli sözleşme sona erer veya yenileme aşamasına gelir; devam eden sözleşme güvenli kapatma talebiyle sonlandırılabilir.

Kapatma, yoldaki yükü yok etmez. Kabul edilmiş partiler teslim edilir, devredilir veya sözleşme koşullarına göre çözümlenir.

## Büyük sözleşmeler

Müşteri normalde “10 kamyon sahibi ol” demez; günlük/haftalık hacim, sıklık, teslim süresi ve güvenilirlik ister. Sistem tahmini araç eşdeğerini hesaplar. Oyuncu:

- farklı boy araçları;
- araç havuzunu;
- dış kaynak kapasitesini;
- multimodal ana hattı

birleştirebilir. Yalnızca dedicated fleet sözleşmesi açıkça ayrılmış araç isteyebilir.

## Müşteri güveni ve itibar

Tekil teslimat:

- sözleşme müşteri güvenini;
- benzer müşteri segmenti algısını;
- şirketin genel itibarını

farklı ağırlıklarla etkileyebilir. İlk prototip tek itibar değeri kullanabilir; segment ayrımı kesinleşmiş zorunluluk değildir. Etkinin nedeni oyuncuya gösterilir.

## İlgili belgeler

- [[02 - Taşıma Hatları ve Konsolidasyon]]
- [[06 - Ekonomi ve Finans]]
- [[09 - Dünya Olayları ve Risk]]
- [[10 - Şirket Politikaları ve İtibar]]
