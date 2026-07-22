# Yeni Çekirdek Tasarım Karar Planı

Son güncelleme: 2026-07-22  
Durum: **Aktif karar taslağı — uygulama yetkisi değildir**

Bu belge, yeni şehir ekonomisi ve taşıma hizmeti modelini netleştirmek için
tek aktif çalışma planıdır. Buradaki **kesin** maddeler sonraki tartışmalarda
yeniden açılmadıkça sabit kabul edilir. **Açık** maddeler kararlaştırılmadan
GDD veya uygulama yeni modele geçirilmez.

Mevcut GDD, eski planlar ve mevcut kod bu yeniden tasarım için kanonik kaynak
değildir. Nihai karar turundan sonra eski model çalışma ağacından temizlenecek,
kanonik belgeler yeni modele göre yeniden yazılacak ve ancak ardından kod
uygulamasına geçilecektir.

## 1. Hedef

Oyuncu tek tek iş veya kontrat kabul eden bir sevk görevlisi değil; yaşayan
şehir pazarlarını okuyup fiziksel, kârlı ve ölçeklenebilir taşıma ağı kuran bir
lojistik şirketi yöneticisi olmalıdır.

Yeni çekirdek zincir için mevcut aday:

> Şehir ekonomisi → net pazar fırsatı → oyuncu rotası/hizmeti → ayrılan pazar
> hacmi → fiziksel yük → taşıma ve teslimat

## 2. Tasarım değişmezleri — kesin

- Tekil iş kabulü çekirdek oynanış değildir.
- Kontrat sistemi bütünüyle kaldırılacaktır.
- Kontrat kodu, UI'ı, testleri, lokalizasyonu ve belgeleri korunmayacaktır.
- Kontrat gerekçesi veya eski ayrıntıları çalışma ağacındaki karar geçmişinde
  tutulmayacaktır; yalnız Git geçmişinde bulunabilir.
- Şehir işleri, kontrat pazarı, kontrat partileri ve `Send truck` işlemi
  kaldırılacaktır.
- Oyuncu ürün alıp satmaz; yalnız lojistik hizmeti sunar.
- Firmalar ilk modelde bulunmaz; şehir pazarı toplulaştırılmıştır.
- Dünya haritası görünür kalır, yalnız ABD oynanabilir olur.
- Aktif şehir seti kıta ABD'sinde yaklaşık 20–25 metropolitan lojistik pazardır.
- Şehirler harita okunabilirliği için homojen dağılır; çok yakın adaylardan
  daha tanınan/büyük olan tercih edilir.
- Şehir seçim önceliği: coğrafi dağılım ve tanınırlık, ardından gerçek lojistik
  değer.
- Seçilen bütün ABD şehirleri görünür ve erişilebilir olur; yapay bölge kilidi
  bulunmaz.
- Eski kayıtlar desteklenmez; yeni kampanya gerekir.
- Dünya veya şehir genelindeki servis edilmeyen hacim sonsuza kadar birikmez.
- Tek tek fabrika simüle edilmez.
- Üretim zincirleri toplulaştırılmış şehir ekonomisi düzeyindedir.
- İlk modelde üretim zinciri derinliği en fazla iki aşamadır.
- Dönemsel arz-talep modeli kullanılır; her şehir-ürün için sürekli fiziksel stok
  simülasyonu yapılmaz.
- Olağan pazar hareketleri küçük, kademeli ve açıklanabilir olur; büyük sıçrama
  dünya olayına veya açık bir nedene dayanır.
- Oyuncunun hizmeti şehir ekonomisindeki darboğazları azaltabilir ve kullanılmayan
  üretim kapasitesini açabilir; oyuncu tek başına bütün şehri yaşatmaz.
- Rotalar fiziksel araç hareketini korur.
- Oyuncu tek yön, gidiş-dönüş veya çok şehirli rota/döngü kurabilir.
- Rota oyuncu tarafından düzenlenebilir ve yönetilebilir.
- Hizmetler ürün adına değil fiziksel yük/ekipman uyumluluğuna göre çalışabilir.
- Pazar payı yeni hizmette hemen tam dolmaz; ilk yük hızlı gelir, pay güvenilir
  hizmetle kademeli büyür.
- Başlangıçta navlun piyasa tarafından oluşur; oyuncu fiyat politikası daha
  sonraki şirket ölçeğinde değerlendirilebilir.

## 3. Dünya ve şehir modeli — kesin yön

### 3.1 Oynanabilir kapsam

- Dünya coğrafyası haritada görünür.
- Yalnız kıta ABD'sindeki seçilmiş şehirler aktif oyun düğümüdür.
- ABD dışı şehir, pazar, firma ve yol ağı verileri kaldırılır.
- Gelecekte yeni ülkeler aynı veri sözleşmesiyle kontrollü biçimde eklenir.

### 3.2 Şehir kavramı

Bir şehir, belediye sınırı değil **metropolitan lojistik pazar** temsilidir.
Tek bir şehir düğümü şunları toplulaştırabilir:

- metro nüfusu ve tüketim tabanı;
- üretim ve işleme endüstrileri;
- yerel lojistik maliyeti;
- kara, demir yolu, hava ve liman erişimi;
- çevresindeki üretim ve dağıtım alanı.

### 3.3 Statik şehir kimliği

Şehir kataloğunda veya ilişkili profilinde değişmeyen/çok yavaş değişen temel
veriler tutulur:

- koordinat ve metro nüfusu;
- maliyet ve trafik tabanı;
- taşıma modu erişimleri;
- ana ve ikincil endüstriler;
- endüstri üretim kapasitesi tabanı;
- tüketim profili;
- lojistik merkez niteliği;
- gerektiğinde kontrollü uzun vadeli büyüme eğilimi.

Veriler gerçek ekonomik kimliği temel alır, oyun için normalize edilir. Şehir
kimliğini rastgele gürültü belirlemez.

### 3.4 Oyuncuya gösterilen pazar

Motor brüt üretim ve kullanımı hesaplayabilir; ana UI net sonucu gösterir:

- ihraç edilebilir ürün fazlası;
- karşılanmamış ithalat/girdi ihtiyacı;
- oyuncuya açık hacim;
- değişimin ana nedeni.

Şehirde motor 10–14 anlamlı talep kaydı tutabilir; ana ekranda en yüksek 5–6
tanesi gösterilir. İhracat tarafında az sayıda belirgin ekonomik kimlik korunur.

## 4. Ürün ve üretim modeli — kesin yön

### 4.1 Ürün ile taşıma koşulu ayrılır

`refrigerated_goods` gibi taşıma gereksinimini ürün sanan türler kaldırılır.

Ürün ailesi örnekleri:

- tarım ürünü;
- işlenmiş gıda;
- içecek;
- tüketim malı;
- elektronik;
- otomotiv parçası;
- makine;
- inşaat malzemesi;
- kimyasal;
- ilaç;
- tekstil/mobilya (kesin liste açık).

Taşıma gereksinimi örnekleri:

- standart;
- soğutmalı;
- tehlikeli;
- yüksek güvenlik;
- ağır/hacimli;
- hassas;
- zaman kritik.

### 4.2 Fiziksel ürün tanımı

Her ürün, simülasyonda gerçekten kullanılacak doğru fiziksel alanlara sahip
olmalıdır. Aday alanlar:

- kg başına hacim veya yoğunluk;
- bölünebilirlik ve parti büyüklüğü;
- uyumlu araç/ekipman etiketleri;
- sıcaklık, tehlike, güvenlik ve hasar koşulları;
- elleçleme süresi veya zorluğu;
- bozulabilirlik/zaman hassasiyeti;
- ekonomik değer sınıfı.

Ekonomik değer oyuncuya alış-satış fiyatı olarak gösterilmez; kaynak rekabeti,
sigorta, hasar, güvenlik ve hizmet için ödenebilir azami bedel gibi motor
hesaplarında kullanılabilir.

### 4.3 İki aşamalı üretim zinciri

Şehir endüstrileri toplulaştırılmış girdileri tüketip çıktı üretir. Örnek:

> tarımsal girdi + ambalaj → işlenmiş gıda

Girdi yeterliliği, kapasite kullanımını ve dışarı açılan çıktı hacmini etkiler.
Oyuncunun hizmeti eksik girdiyi tamamlayarak ek çıktı fırsatı oluşturabilir.
Diğer taşıyıcılar taban ekonominin büyük bölümünü taşır; oyuncu hizmeti
durduğunda şehir ekonomisi bütünüyle çökmez.

## 5. Dönemsel pazar motoru — aday model

Bu bölümün ayrıntıları açık olmakla birlikte kabul edilen yönü somutlaştırır.

Her ekonomi döneminde motor:

1. Şehrin temel tüketimini hesaplar.
2. Endüstri girdilerinin karşılanma oranını hesaplar.
3. Endüstri kapasite kullanımını belirler.
4. Üretim çıktılarını hesaplar.
5. Yerel kullanımı çıktıdan düşer.
6. Net ihracat fazlası ve net ithalat ihtiyacı üretir.
7. Uygun kaynakları maliyet, süre, güvenilirlik ve kapasiteye göre sıralar.
8. Oyuncunun çalışan hizmetlerine kazanabilecekleri pazar payını ayırır.
9. Yalnız ayrılan hacmi fiziksel yük üretimine açar.

Bu hesap her simülasyon tick'inde yapılmak zorunda değildir. Günlük veya
haftalık pazar anlık görüntüsü üretip fiziksel rota motoruna sabit oranlar
sağlayabilir. Kesin dönem ve performans bütçesi açık karardır.

## 6. Rota ve hizmet modeli — kesin yön ve açık ayrımlar

Oyuncu rota kurar, taşınacak yük kapsamını belirler, fiziksel araç veya kapasite
atar ve rotayı sonradan düzenler. Rota:

- tek yönlü;
- gidiş-dönüş;
- çok duraklı;
- kapalı döngü

olabilir.

Tek tek pazar yükünü kabul etmek geri gelmez. “Taşınacak yükü seçmek” ifadesinin
kesin granülaritesi K-01'de kararlaştırılacaktır.

## 7. Açık karar kaydı

Her karar sonuçlandığında seçenekler kaldırılıp sonuç ilgili kesin bölüme
işlenecektir.

### K-01 — Oyuncu rotada taşınacak yükü hangi düzeyde seçer?

- A: Her ürün/pazar akışını oyuncu izin listesine tek tek ekler.
- B: Oyuncu yalnız ekipman sınıfını seçer; motor bütün uyumlu yükleri otomatik
  konsolide eder.
- C: Varsayılan otomatik konsolidasyon; oyuncu ürün/pazarları önceliklendirebilir
  veya hariç tutabilir.

İlk değerlendirme: C, oyuncu iradesini korurken parti kabulü mikro yönetimine
dönmeyi önler.

### K-02 — Tek yönlü rota fiziksel olarak nasıl süreklilik sağlar?

- Mevcut motor her rotayı sonsuz döngü olarak çalıştırır; son duraktan sonra
  araç fiziksel olarak ilk durağa gider.
- Açık rota bir kez çalışıp araç hedefte durabilir.
- Açık rota düzenli hizmettir; hedefte kalan araç başka rotalarla dengelenir.
- Ticari hizmet yalnız A→B yükü kabul ederken fiziksel rota B→A dönüş bacağını
  yine sürer; dönüş boş veya izin verilen fırsat yükleriyle dolu olabilir.
- Sistem görünmeyen otomatik boş dönüş yapamaz; bütün dönüş hareketleri fiziksel
  ve maliyetli olmalıdır.

Tek yönlü rota ile sürekli hizmet kavramı birbirinden ayrılmalıdır.

### K-03 — Araç atama mı, kapasite havuzu mu?

- Erken ve geç oyunda belirli araçlar tek tek atanır.
- Oyuncu yalnız ton/gün kapasitesi ayırır, motor araç seçer.
- Erken oyunda araç, büyümede kapasite havuzu kullanılır.

Araçların fiziksel konumu her seçenekte korunacaktır.

### K-04 — Rota sıklığı nasıl belirlenir?

- Araç hazır oldukça sürekli döner.
- Oyuncu kalkış sıklığı/tarife belirler.
- Kara taşımacılığında sürekli döngü, tarifeli modlarda sıklık kullanılır.
- Şirket büyüdükçe manuel araç döngüsü kapasite/sıklık kararına dönüşür.

### K-05 — Araç ne zaman kalkar?

- Hemen kalkış;
- asgari doluluk;
- azami bekleme;
- son teslim süresini koruyan dengeli otomatik politika;
- rota bazında oyuncu politikası.

### K-06 — Çok duraklı rotada pazar kapsamı

Dallas → Kansas City → Chicago rotası, duraklar arasındaki bütün uyumlu
pazarları otomatik kapsar mı; yoksa oyuncu hangi yön/yük çiftlerinin kabul
edileceğini ayrıca mı seçer?

### K-07 — Araç kapasitesi yükler arasında nasıl paylaştırılır?

Aday öncelikler:

- son teslim baskısı;
- yük başına katkı marjı;
- oyuncunun ürün/pazar önceliği;
- rota doluluğu;
- stratejik pazar payı.

### K-08 — Aktarma ve hub kontrolü

- Her yük zincirini oyuncu çizer.
- Motor mevcut ağdaki en uygun yolu tamamen otomatik bulur.
- Oyuncu hub, izin ve politika seçer; motor yükün ayrıntılı yolunu bulur.

### K-09 — Rota kurma giriş noktası

- şehir çifti;
- ihracat fırsatı → talep pazarı;
- boş araç;
- mevcut ağdaki kapasite/darboğaz önerisi.

### K-10 — Rota önizlemesi

Kesin gösterge seti açık. Adaylar:

- yön bazında pazar hacmi;
- gidiş/dönüş doluluğu;
- gereken araç veya kapasite;
- günlük navlun;
- günlük maliyet;
- net katkı;
- tam pazar payına erişme süresi;
- özel ekipman ve risk açığı.

### K-11 — Rota sonrası yönetim kararları

Kapasite, araç türü, ekipman, durak, hub, kalkış/doluluk politikası, dış
kapasite, geçici durdurma ve kapatma seçeneklerinin kesin kapsamı açık.

### K-12 — Açıklanabilir sonuç standardı

Her kayıp veya fırsatın tek ana nedeni ve uygulanabilir müdahalesi gösterilmeli
mi; hangi göstergelerin nedensel kaydı tutulacağı kararlaştırılmalı.

### K-13 — Ürün ailesi listesi ve üretim tarifleri

- İlk ürün sayısı;
- hangi ürünlerin ham, ara veya nihai olduğu;
- iki aşamalı tarifler;
- taşıma gereksinimleri;
- fiziksel veri kaynakları ve doğrulama yöntemi.

### K-14 — Uluslararası ticaretin ABD pazarına etkisi

ABD dışı şehirler oynanamazken ithalat/ihracat:

- yalnız şehirlerin temel net pazar değerlerine gömülebilir;
- liman/hava düğümünde arka plan hacmi üretebilir;
- oyuncuya yalnız ABD içindeki devam bacağını taşıma fırsatı verebilir;
- hiçbir oyuncu fırsatı üretmeden sadece kaynak rekabetini etkileyebilir.

Soyut yabancı şehir veya sahte kontrat oluşturulmayacaktır.

### K-15 — Kaynak rekabeti ve toplam teslim maliyeti

Bir hedef pazara birden fazla kaynak uygunsa payın üretim maliyeti, navlun,
süre, güvenilirlik ve kapasite arasında nasıl bölüneceği açık.

### K-16 — Ürün ekonomik değerinin kesin rolü

Ürün değeri motor içinde:

- azami ekonomik taşıma mesafesi;
- hız/güvenlik için ödeme isteği;
- hasar ve sigorta;
- kaynak seçimi

için kullanılabilir. Oyuncu ürün ticareti yapmayacaktır.

### K-17 — Navlun oluşumu ve sonraki fiyat politikası

İlk aşama pazar navlununun maliyet, mesafe, mod, yük özelliği, arz-talep baskısı
ve rekabetten nasıl türetileceği; fiyat politikasının hangi büyüme aşamasında
açılacağı kararlaştırılmalı.

### K-18 — Pazar payı kazanma/kaybetme

- İlk yükün ne kadar hızlı geldiği;
- tam hacme kaç dönemde ulaşıldığı;
- güvenilirlik ve fiyat etkisi;
- hizmet kesilince kayıp hızı;
- yeni kapasitenin dolma süresi.

### K-19 — Diğer taşıyıcıların soyutlama düzeyi

Diğer taşıyıcılar yalnız pazar payı/rekabet katsayısı mı olacak, yoksa ileride
isimli ve görünür rakip şirketler mi bulunacak?

### K-20 — Ekonomi hesap dönemi ve performans bütçesi

- Günlük veya haftalık pazar çözümü;
- yalnız değişen şehirleri yeniden hesaplama;
- deterministik sonuç;
- rota sayısı ve şehir sayısına göre hedef işlem süresi;
- fiziksel yüklerin toplulaştırma eşiği.

### K-21 — Şehir setinin kesin seçimi

20–25 şehir; homojen dağılım, tanınırlık, metro büyüklüğü ve lojistik değer
ölçütleriyle karşılaştırılacaktır. Çok yakın şehirlerden biri seçilecektir.

### K-22 — Şehir verisi kaynak ve normalizasyon standardı

- Metro nüfus tanımı;
- endüstri kimliği kaynakları;
- liman/demir/hava erişimi;
- maliyet ve trafik;
- oyun kapasitesine normalizasyon;
- kaynak tarihi ve yeniden üretilebilir veri işlemi.

### K-23 — Başlangıç şehri seçimi

- bütün şehirler seçilebilir mi;
- zorluk etiketi ve nedeni;
- dengesiz şehirlerde başlangıç desteği;
- sabit eğitim kampanyası gerekip gerekmediği.

### K-24 — Başlangıç filosu

Bir, iki veya daha fazla araç; başlangıçta araç seçimi; ilk kapasite kararının
ne zaman doğacağı açık.

### K-25 — İlk fırsat sunumu

Tek zorunlu eğitim rotası, üç karşılaştırmalı fırsat veya tamamen serbest pazar
okuması seçenekleri tartışılacaktır.

### K-26 — İlk oturum başarı ölçütleri

Aday testler:

- ilk rota kurulumu için süre;
- oyuncunun kâr/zarar nedenini açıklayabilmesi;
- tekil yük kabulü yapmadan ağ kurabilmesi;
- ikinci rotada anlamlı stratejik farklılık;
- uzak ulusal hedefin erken görünürlüğü.

### K-27 — Uzun mesafe ve gelecek modlara hazır mimari

ABD ilk sürümünde yalnız kara taşımacılığı bulunsa bile rota/pazar modeli
gelecekte demir, deniz, hava, terminal slotu ve kıtalararası aktarmayı temel
modeli yıkmadan desteklemelidir.

### K-28 — Rota başarısızlığı, bakım ve kesinti davranışı

Arıza, kapasite açığı, trafik ve hizmet kesintisinin pazar payı, fiziksel yük ve
rota güvenilirliğine etkisi daha sonraki karar turunda ele alınacaktır.

### K-29 — İlerleme ve otomasyon

Oyuncunun karar ölçeğinin araçtan rota, kapasite havuzu, hub ve bölgesel
politikaya hangi eşiklerle geçeceği kararlaştırılacaktır.

## 8. Karar ve uygulama sırası

1. Açık rota/hizmet kararları (K-01–K-12).
2. Ürün, pazar ve ekonomi formülleri (K-13–K-20).
3. ABD şehir seti ve kaynak standardı (K-21–K-22).
4. Başlangıç deneyimi ve başarı testleri (K-23–K-26).
5. Ölçek, risk ve otomasyon (K-27–K-29).
6. Nihai çelişki denetimi.
7. Eski plan, GDD ve kod referanslarının kapsamlı envanteri.
8. Eski modelin çalışma ağacından temizlenmesi ve kanonik GDD'nin yazılması.
9. Uygulama planının dosya/faz/test düzeyinde hazırlanması.
10. Kullanıcı onayından sonra kod uygulaması.
