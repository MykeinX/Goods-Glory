---
tür: GDD - operasyon tasarımı
durum: Kanonik akış; ayrıntılı denge test edilecek
kapsam: Doğrudan teslimat, depo aktarması ve uçtan uca hizmet
kaynaklar:
  - "[[01 - Kanonik Lojistik Nesne Modeli]]"
  - docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - doğrudan-taşıma
  - aktarma
---

# Doğrudan ve Aktarmalı Taşıma

#gdd #doğrudan-taşıma #aktarma

## Tasarım amacı

Oyuncu aynı müşteri sözünü farklı fiziksel ağlarla yerine getirebilir. Doğrudan taşıma basit ve hızlıdır; aktarmalı taşıma konsolidasyon, uzman araç kullanımı ve ölçek avantajı sağlar. Hiçbiri her koşulda üstün değildir.

## Doğrudan taşıma

Tek fiziksel görev veya kesintisiz araç zinciri yükü kaynak tesisten nihai hedefe götürür.

Uygun kullanım:

- erken oyun ve düşük hacim;
- iki nokta arasında yeterli araç kapasitesi;
- aktarmanın ek süre ve işlem maliyetinin gereksiz olduğu kısa/orta mesafe;
- hassas veya bölünemeyen yük;
- şirket deposu olmayan kaynak ya da hedef şehir.

Kaynak şehirde depo zorunlu değildir. Araç üreticiden doğrudan yük alabilir. Nihai müşteri tesisine teslim yapabiliyorsa hedef şehirde de depo gerekmeyebilir.

Avantajlar:

- az elleçleme;
- kısa ve okunabilir operasyon;
- düşük bağlantı kaçırma riski;
- küçük filo için kolay planlama.

Dezavantajlar:

- aracın tüm rotayı ve şehir içi işi üstlenmesi;
- düşük hacimde boş kapasite;
- dönüş yükü bulunamazsa boş kilometre;
- farklı teslim bölgelerinde ana hat aracının verimsiz kullanımı.

Görev tamamlandığında araç teslim şehrinde kalır. Otomatik eve dönüş yoktur.

## Varış deposuna bırak ve dağıt

Uçtan uca hizmetin ilk aktarmalı biçimidir:

1. Uzun yol aracı kaynak tesisten yükü alır.
2. Varış şehrindeki şirket deposuna getirir.
3. Parti depoda boşaltılır.
4. Yük dağıtım bölgelerine ayrılır.
5. Yerel araçlar teslimat dalgalarıyla nihai müşterilere götürür.

Bu modelde kaynak şehirde depo olmayabilir; varış deposu tam hizmetin fiziksel düğümüdür. Ana hat aracı depoda yükü bıraktıktan sonra başka yük alabilir. Son kilometre araçları kendi görevlerini yürütür.

## İki depolu ağ

Kaynak ve hedefte depo olduğunda:

- küçük araçlar birden fazla üreticiden toplar;
- yükler kaynak depoda konsolide edilir;
- ana hat aracı daha yüksek dolulukla kalkar;
- hedef depoda ayrıştırma yapılır;
- yerel araçlar son teslimatı tamamlar;
- dönüş yönündeki yükler aynı ağda birleştirilebilir.

Ek tesis ve personel sabit maliyet yaratır. Yeterli hacim yoksa doğrudan taşımadan daha kötü sonuç vermelidir.

## Cross-dock ve depolama

### Cross-dock

Yük depolama stokuna girmeden gelen araçtan giden araca aktarılır. Kısa bekleme ve düşük depolama kullanımı sağlar; kapı, personel ve takvim uyumu ister.

### Kontrollü bekletme

Yük bir sonraki servis kalkışını beklemek üzere depolanır. Konsolidasyonu artırır ancak:

- teslim süresini;
- alan kullanımını;
- soğuk zincir ve güvenlik riskini;
- işlem maliyetini

yükseltebilir.

Oyuncu “hemen gönder” ile “doluluk için beklet” arasında politika seçebilir. Son teslim riski görünür olmalıdır.

## Aktarma işleminin durum akışı

1. `inbound`: yük depoya yaklaşıyor.
2. `awaiting-unload`: kapı veya ekip bekliyor.
3. `cross-dock` ya da `stored`: fiziksel işleme kararı verildi.
4. `awaiting-service`: uygun hat/kalkış bekleniyor.
5. `reserved`: sonraki kalkışta kapasite ayrıldı.
6. `loading`: giden araca yükleniyor.
7. `in-transit`: sonraki aşama başladı.

Her geçiş zaman, kapasite ve maliyet tüketir. Arayüz toplam miktarı özetleyebilir; fakat yükün hangi durumda olduğu kaybolmaz.

## Aktarma fizibilitesi

Bir aktarma için:

- iki aşamanın ortak düğümde birleşmesi;
- tesisin yük türünü işleyebilmesi;
- yeterli kapı, cross-dock veya depolama kapasitesi;
- ekipman ve personel;
- giden hattın uygun takvim ve boş kapasitesi;
- kabul edilebilir bağlantı tamponu

gerekir.

Bağlantı kaçırılırsa yük bir sonraki kalkışı bekler. Sistem anlık teleport veya cezasız takvim düzeltmesi yapmaz.

## Rota biçimleriyle ilişki

- **Tek yön:** Doğrudan veya aktarmalı olabilir; araç son düğümde kalır.
- **Gidiş-dönüş:** Dönüş bacağı ayrı yüklerden oluşabilir.
- **Ring:** Her şehirde bırak/al yapılabilir; araç manifestosu bacaklar arasında değişir.
- **Çok araç:** Aynı parti bölünebilir veya farklı aşamalar farklı araç sınıflarıyla yürütülür.
- **Dönüş yükü:** Depoda bekleyen uyumlu partiler, dönüş kapasitesine yerleştirilebilir.

Bu davranışların planlama kuralları [[02 - Rota ve Operasyon Planlama]] içinde tanımlanır.

## Ekonomik tercih

Doğrudan ve aktarmalı seçenekler ortak formülle karşılaştırılır:

`gelir - km maliyeti - elleçleme - bekleme - sabit gider payı - beklenen risk`

Aktarma yalnızca “ileri seviye olduğu için” daha kârlı değildir. Hacim, yön dengesi, araç uzmanlaşması ve tesis kullanımı avantaj sağlıyorsa kazanır. Gerçekçi maliyetler karar üretmeli; gereksiz ayrıntı oynanabilirliğin önüne geçmemelidir.

## Arayüz

Sözleşme ağ görünümü:

- uçtan uca aşamaları;
- doğrudan/aktarmalı seçenekleri;
- her aşamayı karşılayan servis hattını;
- depoda bekleyen miktarı;
- tahmini teslim aralığını;
- aktarma ve kapasite riskini;
- toplam maliyet ile hizmet seviyesi farkını

gösterir.

## İlgili belgeler

- [[01 - Kanonik Lojistik Nesne Modeli]]
- [[02 - Rota ve Operasyon Planlama]]
- [[03 - Kapasite ve Hibrit Simülasyon]]
- [[04 - Tesisler]]
- [[05 - Multimodal Taşımacılık]]
