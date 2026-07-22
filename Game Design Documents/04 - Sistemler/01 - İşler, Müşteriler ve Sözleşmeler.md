---
tür: GDD - sistem tasarımı
durum: Kanonik nesne ilişkisi; ticari ayrıntılar test edilecek
kapsam: Pazar, müşteriler, işler ve sözleşme yaşam döngüsü
kaynaklar:
  - "[[01 - Kanonik Lojistik Nesne Modeli]]"
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md
  - "`AKIS_VE_HAT_REVIZYONU_PLAN.md` (2026-07-20 akış revizyonu)"
son_güncelleme: 2026-07-20
etiketler:
  - gdd
  - sözleşmeler
  - müşteriler
---

# İşler, Müşteriler ve Sözleşmeler

#gdd #sözleşmeler #müşteriler

## Sistem rolü

Pazar, oyuncuya süresi dolan bir ödül listesi sunmaz. Dünyadaki firmalar arasında kalıcı yük akışları vardır; oyuncunun işi bu akışları keşfetmek, servis etmek ve taahhüde dönüştürmektir.

Kanonik ilişki:

> Müşteri ihtiyacı → Yük akışı → (Sözleşme) → Yük partileri → Taşıma aşamaları → Servis hatları → Fiziksel görevler

Sözleşme doğrudan araca atanmaz. Araçlar [[01 - Kanonik Lojistik Nesne Modeli|kanonik modelde]] tanımlanan fiziksel görevleri yürütür.

## Pazar katmanları

### Yük akışları ve spot ücret

Ayrı bir "spot iş" nesnesi yoktur; spot, bir akışın taahhütsüz servis edilme halidir:

- akışlar süresizdir; alış tesisinde zamanla parti biriktirir;
- her parti kimliklidir: müşteri firması, alış tesisi, teslim tesisi, son tarih;
- kontratsız taşınan parti, maliyet-türevli **spot ücretle** ödenir; şehirdeki rekabet marjı tek formül noktasından kırpar;
- servis edilmeyen akışın dok birikimi sabır penceresi üretimiyle sınırlanır; taşan üretim ayrıca sayılmaz veya raporlanmaz;
- tek parti manuel de taşınabilir (öğretim ve boş aracı ücretli konumlandırma); olgun oyunda hatlar uyumlu partileri kendisi çeker.

### Hat sözleşmeleri

- var olan bir akışın payını dönemlik hacim ve sıklıkla taahhüt eder;
- dönem hacmi taahhüt edilen paydan türer — müşteri, dünyanın üretmediği yükü isteyemez;
- devam eden ya da sabit süreli olabilir;
- taahhütlü partiler spot ücrete prim, öncelik ve gecikme cezası taşır;
- sona erdiğinde akış tabana döner — talep yok olmaz, yalnız taahhüt biter;
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

Şehirler ürün grubu bazında arz, talep, taban hacim, büyüme ve oynaklık taşır. Akışlar bu veriden deterministik türetilir ve şehrin gerçek ekonomik kimliğini yansıtmalıdır ("otomotiv şehri sürekli otomotiv parçası üretir, metropol tüketir"). Bir akış ancak:

- kaynakta yeterli arz;
- hedefte talep;
- uygun bağlantı;
- yükün gerektirdiği operasyon koşulları

varsa türetilir.

Pazar her dakika rastgele değişmez. Taban akışlar kalıcıdır; haftalık taban döngüsü ile mevsim, kriz ve müşteri olayları debiyi görünür ve okunabilir biçimde değiştirir. Aynı dünya seed'i aynı akış setini üretir.

Sözleşme teklifi ilişkiden doğar: bir firmanın akışını yeterince servis eden oyuncuya o firma taahhüt önerir; şehirdeki ofis modülü eş zamanlı teklif yuvasını artırır. Şirket ölçeği (tier) bir akışın ne kadarının taahhüt edilebileceğini belirler.

Taahhüt payı fiziksel bir sınırdır: bir akışın toplam payı %100'ü aşamaz ve imzalanan pay artık dokta spot yük olarak birikmez — o tonaj sözleşme partisi olarak postalanır. Aynı yük iki kez satılamaz.

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

1. Servis edilen akış ve ilişki, sözleşme teklifi üretir.
2. Oyuncu fizibiliteyi inceler ve kabul eder/reddeder.
3. Kabul edilen sözleşme, akışın taahhütlü payını takvime bağlar; partiler akıştan üretilmeye devam eder.
4. Partiler operasyon ağına yerleştirilir.
5. Teslimatlar SLA ve müşteri güvenini günceller.
6. Dönem raporu finans, kapasite ve sorun nedenlerini açıklar.
7. Süreli sözleşme sona erer veya yenileme aşamasına gelir; devam eden sözleşme güvenli kapatma talebiyle sonlandırılabilir.

Kapatma, yoldaki yükü yok etmez. Kabul edilmiş partiler teslim edilir, devredilir veya sözleşme koşullarına göre çözümlenir. Sözleşmenin bitmesi akışı ve hattı öldürmez: taban akış kalır, hat spot ücretle dolmaya devam eder; düşen doluluk oyuncunun okuyacağı sinyaldir.

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
