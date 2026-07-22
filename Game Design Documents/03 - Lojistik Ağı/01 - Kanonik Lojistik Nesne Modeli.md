---
tür: GDD - kanonik sistem modeli
durum: Kabul edilmiş omurga
kapsam: Lojistik ağındaki ticari ve fiziksel nesnelerin sorumlulukları
kaynaklar:
  - docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - "`AKIS_VE_HAT_REVIZYONU_PLAN.md` (2026-07-20 akış revizyonu)"
son_güncelleme: 2026-07-20
etiketler:
  - gdd
  - lojistik-ağı
  - kanonik-model
---

# Kanonik Lojistik Nesne Modeli

#gdd #lojistik-ağı #kanonik-model

## Tasarım kararı

Oyunun lojistik omurgası aşağıdaki zincirdir:

> **Yük Akışı → (Sözleşme) → Yük Partisi → Taşıma Aşaması → Servis Hattı**

Talebin kaynağı dünyadır: şehirlerdeki firmalar arasında **kalıcı yük akışları** vardır ve partileri bu akışlar üretir. Sözleşme talep yaratmaz; var olan bir akışın payını taahhüt eden ticari katmandır ve bu yüzden parantezlidir — akış sözleşmesiz de yaşar ve spot ücretle servis edilebilir.

Bu zincir ticari taahhüt ile fiziksel icrayı ayırır. **Sözleşme hiçbir araca doğrudan bağlanmaz.** Araçlar, akışların ürettiği yük partilerinin belirli taşıma aşamalarını servis hatları üzerindeki fiziksel görevlerle yürütür.

Bu ayrım [[02 - Rota ve Operasyon Planlama]], [[03 - Kapasite ve Hibrit Simülasyon]] ve [[02 - Taşıma Hatları ve Konsolidasyon]] için değişmez temeldir.

## Nesneler ve sorumlulukları

### 0. Yük akışı

İki firma arasındaki kalıcı ticari ilişkidir; dünyanın süresiz talep kaynağıdır. Şunları tanımlar:

- kaynak firma ve tesisi (yükün alındığı adres);
- hedef firma ve tesisi (yükün teslim edildiği adres);
- ürün kategorisi;
- taban debi (kütle/gün) ve haftalık dalgalanma;
- sezon, olay ve kriz çarpanlarına açık geçici değişimler.

Akışlar şehir pazar verisinden (`city_markets.json`) deterministik türetilir ve şehrin gerçek ekonomik kimliğini yansıtır (otomotiv şehri sürekli otomotiv parçası üretir). Akış süresiz yaşar; kimse taşımazsa dokta en fazla sabır penceresi kadar üretim birikir. Taşan üretim ayrıca sayılmaz veya raporlanmaz. Servis edilen akış partileri, sözleşme yoksa maliyet-türevli **spot ücretle** ödenir; şehirdeki rekabet bu ücretin marjını tek noktadan kırpar.

### 1. Sözleşme

Bir yük akışının (veya bir kaynağın birden çok akışının) belirli payını süre, hizmet seviyesi ve fiyatla taahhüt eden, müşteriye verilen uçtan uca hizmet sözüdür. Talep üretmez; akışa bağlanır. Şunları tanımlar:

- yükün alınacağı üretici, tesis, şehir veya bölge;
- nihai müşteri, şehir ya da dağıtım bölgesi;
- yük türü, toplam/dönemsel hacim ve üretim sıklığı;
- teslimat penceresi ve hizmet seviyesi;
- gereken güvenlik, soğuk zincir, ağır yük veya konteyner yetenekleri;
- gelir, fiyatlama yöntemi, itibar etkisi ve varsa ceza çerçevesi;
- sözleşme türü: spot, devam eden hat, sabit süreli fırsat veya hizmet paketi.

Sözleşme, müşterinin sonucunu tarif eder; hangi aracın hangi yoldan gideceğini tarif etmez. Süre, yenileme, erken fesih ve ceza ayrıntıları henüz bütün sözleşme türleri için kesinleşmemiştir. Bu alanlar veri modelinde desteklenir ancak tek bir evrensel kural olarak sunulmaz.

### 2. Yük partisi

Bir akışın belirli bir zamanda ürettiği fiziksel yük miktarıdır. En az şu durumu taşır:

- kaynak akış kimliği ve varsa bağlı sözleşme kimliği;
- müşteri firması, alış tesisi ve teslim tesisi (farklı firmaların aynı türdeki yükleri kimlik olarak karışmaz);
- miktar ve kapasite birimi;
- mevcut düğüm veya hareket hâli;
- son teslim zamanı ve bekleme süresi;
- yük yetenekleri ve elleçleme kısıtları;
- tamamlanan, aktif ve sıradaki aşama;
- bölünebilirlik ve başka partilerle konsolide edilebilirlik;
- gecikme, hasar veya sıcaklık riski.

Bir akışın 80 birimlik partisi, 20 birim kapasiteli dört seferle; iki aracın paralel görevleriyle; ya da farklı kalkışlara bölünerek taşınabilir. Aynı servis hattı, uyumluluk ve kapasite elverdiğinde birden fazla akışın ve sözleşmenin partilerini birlikte taşıyabilir.

### 3. Taşıma aşaması

Yük partisinin kapıdan kapıya zincirindeki tek operasyon adımıdır. Örnekler:

- üreticiden toplama;
- depoya besleme;
- depolar arası kara ana hattı;
- cross-dock;
- terminal elleçlemesi;
- demiryolu, deniz veya hava ana hattı;
- varış deposundan son kilometre dağıtımı.

Her aşama başlangıç/hedef düğümü, taşıma türü, gereken hizmet, zaman penceresi, kapasite, elleçleme süresi ve risk profilini taşır. Aşama bir servis hattıyla karşılanır; gerektiğinde dış taşıyıcı veya spot kapasite de bir servis sağlayıcı olarak kullanılabilir.

### 4. Servis hattı

Şirketin iki düğüm arasında sunduğu düzenli operasyon kapasitesidir; müşteri işi değildir. Şunları tanımlar:

- başlangıç ve hedef düğüm;
- taşıma türü;
- kalkış takvimi veya frekansı;
- dönemlik ve seferlik kapasite;
- kabul edilen yük etiketleri;
- atanmış araç, araç havuzu veya dış kapasite;
- yükleme, hareket ve boşaltma davranışı;
- maliyet, güvenilirlik ve rezerv kapasite politikası.

Bir servis hattı hiçbir sözleşmeye özel olmak zorunda değildir. Uygun yük partileri öncelik, son teslim zamanı, müşteri hizmet seviyesi ve konsolidasyon politikasına göre kalkışlara yerleşir.

### 5. Fiziksel görev

Bir araç veya taşıyıcı kapasitesi tarafından gerçekten yürütülen icra kaydıdır:

- hangi servis kalkışına ait olduğu;
- kullanılan araç ve ekipman;
- taşınan yük partisi payları;
- yükleme, yol, bekleme ve boşaltma fazları;
- gerçek başlangıç ve bitiş konumu;
- seed'li süre sonuçları;
- kilometre, maliyet, kondisyon ve olay sonuçları.

Araç sözleşmeyi değil, bu görevi yürütür. Bir görev birden çok sözleşmeden yük taşıyabilir; bir sözleşmenin tek partisi de birden çok göreve bölünebilir.

## Düğümler ve fiziksel görünürlük

Düğüm; müşteri tesisi, şirket deposu, cross-dock, liman, demiryolu terminali, hava kargo terminali veya dağıtım bölgesi olabilir. Yük partileri her zaman bir düğümde, bir kuyrukta ya da fiziksel görev üzerindedir. Kaybolan, anında ışınlanan veya yalnızca finansal sayaçta yaşayan yük bulunmaz.

Oyuncu:

- yükün nerede olduğunu;
- hangi aracı veya kalkışı beklediğini;
- ne kadarının yolda, depoda veya teslim edildiğini;
- darboğazın araç, kapı, depolama, ekipman ya da bağlantı kaynaklı olduğunu

görebilmelidir. Büyük ölçekte arayüz partileri gruplayabilir; bu, simülasyonun fiziksel akışı terk ettiği anlamına gelmez.

## Kimlik ve durum ilkeleri

- Statik katalog kimlikleri İngilizce ve kararlı tutulur.
- Canlı nesneler benzersiz kimlik, oluşturulma zamanı ve kaynak ilişkisi taşır.
- Kapasite miktarları yük türünün birimiyle birlikte saklanır; çıplak sayı kullanılmaz.
- Yük bölme/birleştirme işlemleri kaynak izini korur.
- Gerçekleşmiş görev sonuçları yeniden RNG üretmez; kayda yazılır.
- Finansal kayıtlar ilgili sözleşme, parti, aşama, hat ve görev kimliklerine izlenebilir olmalıdır.
- Silinen rota veya kapanan hat, tamamlanmış geçmiş kayıtlarını koparmamalıdır.

## Değişmez doğrulamalar

1. Her yük partisi tam olarak bir yük akışından doğar; en fazla bir sözleşmeye bağlı olabilir.
2. Her aktif parti miktarı; düğümde bekleyen, görevde taşınan ve teslim edilmiş miktarlara izlenebilir.
3. Bir fiziksel görevdeki toplam uyumlu yük, kullanılabilir kapasiteyi aşamaz.
4. Her aşamanın bitiş düğümü, sonraki aşamanın başlangıç düğümüdür.
5. Araç göreve başladığı fiziksel konumdan hareket eder ve görev sonunda gerçek varışta kalır.
6. Araç-ekipman-yük uyumluluğu görev başlamadan doğrulanır.
7. Sözleşme başarısı, yalnızca aracın varmasına değil ilgili yük partisinin uçtan uca tamamlanmasına göre belirlenir.

## Ölçekleme ilkesi

Erken oyunda tekil araç, parti ve görev görünürdür. Şirket büyüdükçe oyuncu kapasite havuzu, servis hattı ve politika yönetir. Motor güvenli biçimde toplulaştırma yapabilir; ancak aynı başlangıç durumu ve kararlar için kapasite, zaman, maliyet, risk ve teslimat sonuçları ayrıntılı simülasyonla eşdeğer kalmalıdır. Ayrıntılar [[03 - Kapasite ve Hibrit Simülasyon]] içinde tanımlanır.

## Açık konular

Bu model aşağıdaki konuları karara bağlamaz:

- olgun bir deponun ikinci uzmanlık kazanma koşulları;
- ağır araç için depo dışı ticari saha çözümü;
- sözleşme süreleri, yenileme ve fesih ayrıntılarının bütün arketiplerdeki kesin değerleri.

Bu başlıklar uygulanana veya kullanıcı testinde doğrulanana kadar “açık konu” olarak korunmalıdır.

## İlgili belgeler

- [[02 - Rota ve Operasyon Planlama]]
- [[03 - Kapasite ve Hibrit Simülasyon]]
- [[04 - Doğrudan ve Aktarmalı Taşıma]]
- [[01 - İşler, Müşteriler ve Sözleşmeler]]
- [[04 - Tesisler]]
- [[05 - Multimodal Taşımacılık]]
