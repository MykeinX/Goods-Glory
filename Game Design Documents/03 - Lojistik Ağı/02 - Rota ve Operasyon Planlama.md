---
tür: GDD - sistem tasarımı
durum: Kanonik ilkeler ve test edilecek denge
kapsam: Serbest rota, döngü, çok araç ve operasyon planlama
kaynaklar:
  - "[[01 - Kanonik Lojistik Nesne Modeli]]"
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - lojistik-ağı
  - rota-planlama
---

# Rota ve Operasyon Planlama

#gdd #lojistik-ağı #rota-planlama

## Amaç

Rota planlama, hazır görev zinciri seçmek değil; ayrı ticari taahhütleri kârlı ve güvenilir bir fiziksel operasyona dönüştürmektir. Oyuncu başlangıçta araçları doğrudan yönetir, büyüdükçe servis hattı, kapasite havuzu ve politika kurar.

## Serbest rota ilkesi

Oyuncu, erişilebilir düğümleri ve uyumlu taşıma aşamalarını özgürce birleştirebilir:

- tek yön;
- gidiş-dönüş;
- üç veya daha fazla düğümlü ring;
- açık uçlu çok duraklı rota;
- depoya bırakıp başka araçla devam eden zincir;
- boş veya ücretli geri yükle konumlandırma.

Rota, sözleşme kimliklerinin sırası değildir. Her bacak bir başlangıç/hedef düğümü ve servis ihtiyacını temsil eder; bir bacakta birden fazla sözleşmenin uyumlu yük partileri taşınabilir.

## Planlama akışı

### Erken oyun: araç odaklı

1. Boş araç veya ekipman kombinasyonu seçilir.
2. Aracın gerçek konumu gösterilir.
3. O konumdan başlayan ya da izin verilen boş konumlandırmayla erişilebilen işler süzülür.
4. İlk bacak seçilir.
5. Önceki bacağın varışından başlayan uyumlu sonraki bacaklar eklenir.
6. Zaman, kapasite, maliyet ve dönüş sonucu doğrulanır.
7. Plan görev olarak başlatılır.

Uygun araç olmadığı bilgisi planın sonunda sürpriz olarak verilmez. Uyumsuz yük, ekipman, mesafe veya tesis ihtiyacı seçim sırasında açıklanır.

### Orta ve geç oyun: hat odaklı

1. Başlangıç ve hedef düğüm seçilir.
2. Taşıma türü ve hizmet profili belirlenir.
3. Kalkış frekansı veya dönemlik kapasite hedefi girilir.
4. Araç havuzu, dış taşıyıcı veya karma kapasite atanır.
5. Uyumlu yük partilerinin yerleştirme politikası belirlenir.
6. Yedek kapasite, gecikme tamponu ve boş bacak politikası seçilir.

Oyuncu isterse hattın içindeki tekil görevleri ve araçları inceleyebilir; normal işletim için her kalkışı tek tek onaylaması gerekmez.

## Döngü ve ring rotalar

Ring rota, sistemin hazır verdiği kusursuz bir ödül değildir. Oyuncu ayrı pazar yönlerini birleştirir:

1. A → B: perakende yükü
2. B → C: makine parçası
3. C → A: paketlenmiş sanayi ürünü

Planlayıcı şunları gösterir:

- toplam kilometre ve yükle gidilen kilometre;
- boş kilometre oranı;
- her bacağın tahmini doluluğu;
- günlük/haftalık gelir ve değişken maliyet;
- ayrılan sabit gider payı;
- beklenen faaliyet marjı;
- yük, araç ve ekipman uyumluluğu;
- kalkış ve teslim penceresi çakışmaları;
- tampon süre;
- aracın veya havuzun tur sonunda hangi düğümde kalacağı.

Ring rota daha verimli olabilir, fakat daha fazla bağlantı ve olay riski taşır. Bir bacağın gecikmesi sonraki bacakları zincirleme etkileyebilir.

## Çok araçlı operasyon

Bir rota veya servis hattı tek araca mahkûm değildir. Çok araç şu biçimlerde kullanılabilir:

- aynı hatta ardışık kalkışlar;
- yüksek hacmi paralel görevlerle bölme;
- farklı kapasiteli araçlarla pik ve taban talebi karşılama;
- bir ana araç havuzu ve yedek araç;
- toplama vanları + ana hat kamyonu + dağıtım vanları.

Planlayıcı müşteri taahhüdünü “kaç araç gerekir” diye sabitlemez; dönemlik hacim ve sıklıktan tahmini araç eşdeğerini çıkarır. Dedicated fleet arketipi açıkça istemedikçe belirli araç adedi sözleşme koşulu değildir.

## Depoda bırak ve al

Bir araç yükü depoya bıraktığında:

1. Parti gelen yük kuyruğuna alınır.
2. Boşaltma kapısı ve ekip süresi tüketilir.
3. Yük cross-dock, depolama veya sonraki hat kuyruğuna yönlenir.
4. Aynı ya da başka araç, uygun kalkışta yükün tamamını veya bir bölümünü alır.
5. Kaynak sözleşme ve parti izi korunur.

Araç, yükü bıraktıktan sonra aynı partinin son teslimine bağlı kalmaz. Başka göreve geçebilir veya bulunduğu şehirde boşta bekleyebilir. Yük ise yeni araca “atanmış sözleşme” olmaz; yeni fiziksel görevin manifestosuna girer.

## Dönüş yükü ve boş hareket

Boş dönüş lojistik ekonomisinin gerçek bir sonucudur ve tamamen silinmez:

- **Planlı dolu dönüş:** Ayrı sözleşme veya partilerle sağlanır.
- **Broker dönüş yükü:** Normal pazarda uyumlu iş yoksa düşük marjlı, ücretli gerçek yük sunabilir.
- **Boş konumlandırma:** Oyuncu stratejik gerekçeyle maliyeti kabul eder.
- **Ara düğüme ilerleme:** Ana pazara doğrudan yük yoksa erişilebilir bir düğüme ücretli veya boş hareket yapılabilir.

Broker yükü garantili kâr değildir; değişken maliyeti makul güvenlikle karşılayan bir kilitlenme önleyicisidir. Pazar dengesizliğini ve doğru ring kurmanın değerini ortadan kaldırmamalıdır.

## Araç görev sonunda nerede kalır?

Araç, son fiziksel görevin teslim şehrinde veya düğümünde kalır. Otomatik olarak merkeze, ana depoya ya da rotanın ilk şehrine ışınlanmaz.

- Tek yönlü görevde varışta boş kalır.
- Kapalı ringde başlangıç düğümüne döner.
- Açık rota son düğümde biter.
- Devam eden rota kapatılırsa seçilen güvenli kapatma politikasına göre mevcut çevrimi tamamlar; başlangıca dönüş yalnızca plan bunu içeriyorsa gerçekleşir.
- Depoda bırak/al operasyonunda yük ve araç konumları birbirinden bağımsız güncellenir.

Bu kural filo konumu, geri yük, çoklu depo ve ekipman lojistiğini gerçek stratejik kararlara dönüştürür.

## Uygunluk ve fizibilite

Başlatmadan önce:

- düğüm bağlantısı;
- araç ve ekipmanın fiziksel konumu;
- yük yetenekleri;
- kapasite;
- menzil ve operasyon programı;
- tesis/terminal erişimi;
- yükleme ve depolama kapasitesi;
- görev takvimi ve sürüş/işlem süresi;
- nakit rezervi ve beklenen marj

doğrulanır. Oyuncu gizli formül nedeniyle değil, görünen riski kabul ettiği için zarar etmelidir.

## Arayüz çıktıları

Plan özeti tek ekranda şu soruları yanıtlar:

- Ne taşınıyor ve hangi sözleşmelerden geliyor?
- Hangi aşamayı hangi hat ve araçlar karşılıyor?
- Nerede boş kilometre var?
- Araçlar tur sonunda nerede kalacak?
- Hangi depo veya kapı darboğaz?
- Beklenen sonuç aralığı ve en büyük risk nedir?

Haritada fiziksel akış görünür kalır; uzak ölçekte araçlar ve partiler akış göstergeleriyle toplulaştırılabilir.

## İlgili belgeler

- [[01 - Kanonik Lojistik Nesne Modeli]]
- [[03 - Kapasite ve Hibrit Simülasyon]]
- [[04 - Doğrudan ve Aktarmalı Taşıma]]
- [[02 - Taşıma Hatları ve Konsolidasyon]]
- [[03 - Araçlar ve Ekipman]]
