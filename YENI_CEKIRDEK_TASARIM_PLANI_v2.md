# Yeni Çekirdek Tasarım Kararı — v2

Son güncelleme: 2026-07-22
Durum: **Aktif karar taslağı — uygulama yetkisi değildir**
Önceki sürüm: `YENI_CEKIRDEK_TASARIM_PLANI.md` (arşiv, kanonik değil)

Bu belge v1'in yerini alır. v1'e göre üç yapısal değişiklik içerir:

1. Açık karar sayısı 29'dan 6'ya indirildi. Kalan maddeler karar değil,
   uygulama sırasında ayarlanacak parametre olarak yeniden sınıflandırıldı.
2. v1'de hiç bulunmayan iki bölüm eklendi: **oyunun zorluk kaynağı** ve
   **oyuncunun dakikalık eylemi**. Bunlar açık karar değil, değişmezdir.
3. Kapsam, "veri kapsamı" ve "mekanik kapsamı" olarak ikiye ayrıldı.

---

## 1. Hedef

Oyuncu tek tek iş veya kontrat kabul eden bir sevk görevlisi değil; yaşayan
şehir pazarlarını okuyup fiziksel, kârlı ve ölçeklenebilir taşıma ağı kuran bir
lojistik şirketi yöneticisi olmalıdır.

Çekirdek zincir:

> Şehir ekonomisi → net pazar fırsatı → oyuncu rotası/hizmeti → ayrılan pazar
> hacmi → fiziksel yük → taşıma ve teslimat

Nihai vizyon küresel ölçekte, kıtalararası, çok modlu lojistiktir. ABD ilk
sürümü bu vizyonun küçültülmüş bir uygulaması değil, **test yatağıdır**.

---

## 2. Kapsam: veri ve mekanik ayrımı

v1'in en büyük çelişkisi, küresel vizyon ile ABD+karayolu kapsamının aynı
kararmış gibi ele alınmasıydı. İkisi ayrılır:

### 2.1 Veri kapsamı — kademeli

- **Faz 0 (test yatağı):** Kıta ABD'sinde 20–25 metropolitan lojistik pazar.
- **Faz 1 (küresel açılım):** Test ve dengeleme tamamlandıktan sonra bütün
  kıtalarda toplam ~150 şehre çıkılır.
- Gerekçe: model doğrulanmadan 150 şehrin ekonomik verisi üretilirse, çekirdek
  revizyona uğradığında bu emeğin tamamı çöpe gider. Veri üretimi en pahalı ve
  en geri dönüşsüz iştir; en sona bırakılır.
- Faz 1 aynı veri sözleşmesini kullanır. Yeni şehir eklemek kod değişikliği
  değil, veri kaydı eklemek olmalıdır. Bu, Faz 0'ın sertleşme kriteridir.

### 2.2 Mekanik kapsamı — baştan tam

Veri kademeli, mekanik değildir. Faz 0'da şu mekanikler **çalışır durumda**
bulunur:

- deniz taşımacılığı ve liman düğümü;
- konteyner/birim yük kavramı;
- hub üzerinden aktarma;
- çok modlu tek yük zinciri (deniz → liman → kara ve tersi);
- uzun transit süresi (günler/haftalar) ile kısa transitin bir arada yaşaması.

Bunu sağlamak için ABD şehir setine **2–3 denizaşırı geçit düğümü** eklenir
(aday: Rotterdam, Şanghay, Santos). Bu düğümler oynanabilir şehir değildir;
üretim zinciri, iç pazarı veya rota kurulumu içermezler. Yalnızca ihracat
fırsatı ve ithalat girdisi üreten gerçek liman uçlarıdır.

Gerekçe: kıtalararası lojistik, ABD içi kamyonculuktan farklı bir problemdir.
Çekirdek yalnızca kamyon üzerinde dengelenirse model sessizce kamyon
varsayımlarını içselleştirir (araç = tek yük birimi, transit = saatler, rota =
tek modlu kesintisiz hareket). Faz 1'de bunu sökmek temel modeli yıkar.
2–3 geçit düğümünün veri maliyeti ihmal edilebilir; sağladığı mimari kanıt
ise Faz 1'in tek güvencesidir.

**Sertleşme kriteri:** Faz 0 ancak Şanghay → Los Angeles → Chicago zinciri tek
bir yük olarak, modeli özel durumla delmeden çalıştığında Faz 1'e geçilebilir.

### 2.3 Kapsam değişmezleri

- Dünya haritası görünür kalır.
- Faz 0'da yalnız ABD şehirleri oynanabilir düğümdür.
- Geçit düğümleri oynanabilir değildir; soyut sahte şehir de değildir — gerçek
  liman, gerçek mesafe, gerçek transit süresi.
- Faz 0'da yapay bölge kilidi bulunmaz; seçilen bütün ABD şehirleri erişilebilir.
- Eski kayıtlar desteklenmez; yeni kampanya gerekir.

---

## 3. Oyunun zorluk kaynağı — değişmez

**v1'de bu bölüm yoktu ve en kritik eksikti.** Mükemmel modellenmiş bir ekonomi,
baskı kaynağı tanımlanmadığında oyun değil tablodur. Oyuncunun şikâyet ettiği
sıkıcılık, kötü kurgulanmış bir iş sisteminden değil, gerilim yokluğundan da
doğabilir. Bu nedenle zorluk kaynakları açık karar değil, tasarım değişmezidir.

### 3.1 Ana bilişsel bulmaca: dönüş bacağı dengesi

Oyunun imza mekaniği budur ve her şey buna hizmet eder.

Fiziksel araç geri dönmek zorundadır. Boş dönen bir araç, maliyetin tamamını
taşıyıp gelirin yarısını üretir. Dolayısıyla oyuncunun asıl sorusu "hangi rota
kârlı?" değil, **"hangi rota çifti dengeli?"** olur.

Bu bulmaca:

- tek bir doğru cevabı olmayan, ağ ölçeğinde düşünmeyi gerektiren bir problemdir;
- şehir ekonomileri asimetrik olduğu için doğal olarak zordur (tarım ihraç eden
  şehir elektronik ithal eder, hacimleri eşleşmez);
- ölçek büyüdükçe zorlaşmaz, **zenginleşir** — üç şehirli döngüler, hub üzerinden
  dengeleme, mod karışımı;
- kıtalararası ölçeğe doğrudan taşınır ve orada daha da keskinleşir (gerçek
  dünyada Asya→ABD konteyner dengesizliği tam olarak budur).

Motor bu bulmacayı asla oyuncu adına çözmez. Görünmeyen otomatik boş dönüş
yapılamaz; bütün dönüş hareketleri fiziksel ve maliyetlidir.

### 3.2 Ölçek merdiveni — birincil meşguliyet kaynağı

Oyuncunun ilgisini ayakta tutan şey daha fazla tıklama değil, **her ölçek
kademesinde açılan yeni bir problem sınıfıdır.** Oyuncu daha çok şey yapmaz;
daha farklı şey düşünür. Merdivenin her basamağı öncekini geçersiz kılmaz,
üstüne biner.

| Ölçek | Açılan problem sınıfı | Oyuncunun sorusu |
|---|---|---|
| 1–3 rota | Dönüş bacağı dengesi | Hangi rota *çifti* dengeli? |
| 4–10 rota | Rotalar arası besleme | Bir rotanın zayıf dönüşünü başka rotanın yüküyle doldurabilir miyim? |
| 10–25 rota | Ağ topolojisi | Doğrudan hat mı, hub üzerinden konsolidasyon mu? |
| 25+ / kıtalararası | Mod, koridor, konteyner dengesizliği | Haftalarca bağlanan sermaye ve yapısal yön dengesizliği nasıl yönetilir? |

Topoloji kademesi (10–25) gerçek lojistiğin en derin sorusudur ve tek doğru
cevabı yoktur: doğrudan hat kısa transit verir ama düşük doluluk; hub
konsolidasyon verir ama aktarma maliyeti ve gecikme yaratır. Cevap ağın şekline
bağlıdır, bu yüzden her kampanyada yeniden düşünülür.

**Tasarım kısıtı:** her kademe, oyuncunun arayüz yükünü artırmadan açılmalıdır.
Ölçek büyürken tıklama sayısı artıyorsa merdiven yanlış kurulmuştur.

### 3.3 Dünya olayları — ikincil meşguliyet kaynağı

Ölçek merdiveni oyunun omurgasıdır; dünya olayları omurganın üzerine
öngörülemezlik ve tazelik ekler. Olaylar tek başına taşıyıcı değildir —
sürekli olay üretimi gürültüye ve angaryaya dönüşür.

**Olay ilkeleri — değişmez:**

1. **Olay ceza değil, haritanın yeniden çizilmesidir.** Her olay aynı anda hem
   kaybeden hem kazanan üretir. Kapanan koridor, alternatif koridoru değerli
   yapar; talep çöken sektör, başka sektöre kapasite açar. Yalnızca zarar veren
   olay üretilmez.
2. **Önceden haber verilir.** Her olayın uyarı → gelişme → etki aşamaları vardır.
   Oyuncunun hazırlanma penceresi olur. Ani ve habersiz vuruş yapılmaz.
3. **Açıklanabilirdir.** §5.2 gereği her olay tek cümlelik nedene ve en az bir
   uygulanabilir müdahaleye sahiptir.
4. **Ölçeğe eşlenir.** Olayın *doğrudan hedefi* oyuncunun ağının kapsamıyla
   orantılıdır: yeni oyuncunun rotaları kıtalararası bir kanal kriziyle doğrudan
   kesilmez. Ancak arka plan etkisi görünür kalır — A-04 gereği yeni oyuncu da
   ithalat zincirlerinin iç bacağını taşıdığından, küresel bir olay onun
   hacmini dolaylı olarak değiştirebilir ve bu §5.2 gereği açıklanır.
   Bu, olay sistemini ölçek merdivenine bağlar: büyüyen oyuncu daha büyük
   olaylara **doğrudan** maruz kalır.
5. **Ağ çeşitliliğini ödüllendirir.** Tek koridora bağımlı ağ sarsılır;
   dağıtılmış ağ dayanır. Bu ilke olayları saf şans olmaktan çıkarıp
   **strateji testine** çevirir — en kritik ilke budur.
6. **Nadirdir ve kalıcı iz bırakır.** Sık, küçük ve unutulan olay yerine seyrek,
   hatırlanan olay.

**Olay aileleri:**

- *Altyapı:* liman tıkanması, kanal kapanması, köprü/yol kesintisi, ağır hava.
- *Ekonomik:* yakıt fiyat krizi, sektörel talep patlaması veya çöküşü,
  navlun oranı şoku.
- *Jeopolitik:* savaş, bölgesel kapanma, ambargo, gümrük rejimi değişikliği.
- *Yapısal ve olumlu:* yeni liman açılışı, fabrika yatırımı, altyapı
  iyileştirmesi, yeni ticaret koridoru. Bu aile kalıcı değişiklik üretir ve
  olay sisteminin yalnızca kriz üretmesini engeller.

Jeopolitik ve kanal ölçeğindeki olaylar Faz 1'de tam anlamını kazanır; Faz 0'da
geçit düğümleri üzerinden sınırlı biçimde test edilir.

### 3.4 Destekleyici gerilim kaynakları

**Sermaye kıtlığı.** Araç pahalıdır, sermaye sınırlıdır, her alım bir bahistir.

**Kapasite–pay geribildirim döngüsü.** Pazar payı güvenilir hizmetle kademeli
büyür, ama büyüyen payı taşımak için kapasite *gelirden önce* alınmalıdır.
Erken yatırım = atıl varlık riski; geç yatırım = payı rakibe kaptırma. Bu döngü
v1'in K-18'inden doğal olarak çıkar ve oyunun ana ritmini kurar.

**Asimetrik güvenilirlik.** Pay yavaş kazanılır, hızlı kaybedilir. Aşırı
genişleme somut biçimde cezalandırılır.

**Rakip baskısı.** Servis edilmeyen hacmi rakipler alır. Bir hattı boşaltırsan
yerin dolar; geri dönmek ilk girişten pahalıdır.

**Darboğaz fırsatı.** Bir şehrin eksik girdisini tamamlamak, o şehrin atıl
üretim kapasitesini açar ve **yeni ihracat hacmi yaratır.** Bu, oyuncunun
pazarı sadece okumakla kalmayıp büyütebildiği tek mekanizmadır ve ağ
düşünmenin ödülüdür. Üretim zincirini okuyabilen oyuncu bileşik getiri elde eder.

---

## 4. Oyuncunun dakikalık eylemi — değişmez

**v1'de bu bölüm de yoktu.** Rotalar otomatik döner, motor yükü konsolide eder,
pay kendiliğinden büyürse oyuncu beş rota kurduktan sonra ne yapar? Cevap
tasarlanmazsa oyun kendiliğinden boşalır.

### 4.1 İş listesi yerine sinyal akışı

Tek tek iş kabulü geri gelmez. Yerine **fırsat ve uyarı akışı** konur. Kritik
fark: sinyaller işlemsel değil **bilgilendiricidir**. Oyuncu sinyali "kabul
etmez"; sinyali okuyup ağında bir karar alır.

Sinyal örnekleri:

- "Chicago'da elektronik girdi darboğazı büyüyor — karşılanırsa ek çıktı açılır."
- "Dallas–Memphis rotanda dönüş doluluğu %62'den %20'ye düştü."
- "Memphis'te rakip payı artırıyor; teslim güvenilirliğin iki dönemdir düşük."
- "Los Angeles limanında konteyner birikimi var; iç bacak kapasitesi yetersiz."

Her sinyal bir **neden** ve en az bir **uygulanabilir müdahale** taşır. Neden
gösteremeyen sinyal üretilmez.

### 4.2 Anlamlı duraklama — zaman akışı

"Oyuncu izliyor" sorununun bir kısmı sıkıcılıktan değil, zaman ölçeğinden doğar.
Çözüm: oyun hızlı akar, yalnız karar gerektiğinde yavaşlar.

- Oyun varsayılan olarak hızlı ilerler; olaysız dönemler hızla geçilir.
- §4.1'deki sinyal akışında bir eşik aşıldığında oyun yavaşlar veya duraklar ve
  oyuncuyu uyarır.
- Oyuncu boş zamanı izlemez; yalnız karar anlarını yaşar.
- Duraklama eşikleri oyuncu tarafından ayarlanabilir olmalıdır — ilerleyen
  oyunda küçük sinyaller dikkat çekmeyi bırakmalıdır, aksi hâlde büyüyen ağ
  sürekli kesinti üretir.
- Manuel hız kontrolü de bulunur; otomatik duraklama onun yerine geçmez,
  üstüne eklenir.

**Tasarım kısıtı:** duraklama nedeni her zaman gösterilir. Nedensiz duraklama
üretilmez.

### 4.3 Oynanış eğrisi

**0–1 saat.** Pazarı oku, ilk rotayı kur, dönüş bacağını doldurmaya çalış.
Öğrenilen ders: tek yönlü düşünmek zarar ettirir.

**1–10 saat.** Darboğaz avı, iki yönlü hat dengeleme, ikinci ve üçüncü rotanın
birbirini beslemesi, kapasite alım zamanlaması. Oyuncu rota kurucudan **ağ
tasarımcısına** döner.

**10+ saat.** Ağ topolojisi, hub politikası, mod seçimi, kıtalararası koridor
kurulumu, bölgesel otomasyon. Oyuncu artık tek rotayla değil, ağın şekliyle
uğraşır.

### 4.4 Karar ölçeğinin yükselmesi

Oyuncunun eylemi büyüdükçe *daha fazla* olmamalı, **daha soyut** olmalıdır.
Araç → rota → hat politikası → hub → bölgesel politika. Aksi hâlde ölçek
büyüdükçe oyun mikro yönetime boğulur; bu, eski sistemin başarısızlık nedeninin
farklı bir biçimde tekrarıdır.

---

## 5. Tasarım değişmezleri

### 5.1 Çekirdek döngü

- Tekil iş kabulü çekirdek oynanış değildir ve geri gelmez.
- Kontrat pazarı, şehir işleri, kontrat partileri ve `Send truck` işlemi
  kaldırılır; kod, UI, test, lokalizasyon ve belgeleri korunmaz.
- Oyuncu ürün alıp satmaz; yalnız lojistik hizmeti sunar.
- **Not:** "tek tek iş kabulü" yasaklıdır, ancak *uzun vadeli gönderici
  anlaşması* kavramı geç oyun için saklıdır. 20 rotalık bir ağa yıllık garantili
  hacim anlaşması sunmak, başarısız olan tek-tek-iş sistemiyle aynı şey değildir.
  Faz 0'da bulunmaz, kavramsal olarak yasaklanmaz.

### 5.2 Açıklanabilirlik — yükseltilmiş değişmez

v1'de bu bir açık karardı (K-12); değişmeze yükseltilir.

Gerekçe: oyuncu alıp satmadığı için fiyat farkı gibi kendini anlatan bir sinyal
yok. "Bu rotada payın %12" cümlesinin nedeni tamamen motorun içinde. Bu, v1
modelinin en büyük anlaşılabilirlik riskidir.

- Her pazar payı, her kayıp ve her fırsat **tek cümlelik bir ana nedenle**
  gösterilir.
- Neden üretilemiyorsa gösterge de üretilmez.
- Ekonomi çözümü **deterministiktir**; aynı tohum aynı sonucu verir. Aksi hâlde
  açıklanabilirlik teknik olarak imkânsızdır.
- Olağan pazar hareketleri küçük ve kademelidir; büyük sıçrama açık bir dünya
  olayına dayanır.

### 5.3 Ekonomi

- Firmalar ilk modelde bulunmaz; şehir pazarı toplulaştırılmıştır.
- Tek tek fabrika simüle edilmez; üretim zincirleri şehir ekonomisi düzeyindedir.
- İlk modelde üretim zinciri derinliği en fazla iki aşamadır.
- Dönemsel arz-talep modeli kullanılır; sürekli fiziksel stok simülasyonu yoktur.
- Servis edilmeyen hacim sonsuza kadar birikmez.
- Oyuncu darboğazı azaltıp atıl kapasite açabilir; ama tek başına şehri
  yaşatmaz. Diğer taşıyıcılar taban ekonominin büyük bölümünü taşır.
- Navlun başlangıçta piyasa tarafından oluşur; oyuncu fiyat politikası sonraki
  şirket ölçeğinde açılır.

### 5.4 Rota ve hizmet

- Rotalar fiziksel araç hareketini korur.
- Tek yön, gidiş-dönüş, çok duraklı ve kapalı döngü rota kurulabilir.
- **"Tek yönlü rota" ticari bir tanımdır, fiziksel değil.** Hizmet yalnız A→B
  yükü kabul etse bile araç B→A bacağını fiziksel olarak sürer; bu bacak boş
  veya izin verilen fırsat yüküyle dolu olabilir. (v1 K-02 kapatıldı.)
- Rota oyuncu tarafından düzenlenebilir ve yönetilebilir.
- Hizmetler ürün adına değil fiziksel yük/ekipman uyumluluğuna göre çalışır.
- Pazar payı yeni hizmette hemen dolmaz; ilk yük hızlı gelir, pay kademeli büyür.

**Sefer modeli — iki temel tip.** Rota motoru iki sefer modelini de **birinci
sınıf tip** olarak destekler; biri diğerinin özel hâli olarak kodlanmaz.

- *Sürekli döngü modları* (kara): araç hazır oldukça döner. Esnek, tarifesiz.
- *Tarifeli modlar* (deniz, demiryolu, ileride hava): sabit sefer takvimi,
  kalkış penceresi, liman/terminal slotu. Kaçırılan sefer bir sonrakini bekler.

Bunun zorunlu sonucu: **tarifeli mod ile sürekli mod arasındaki her arayüz
tampon gerektirir.** Deniz seyrek ve büyük partiler hâlinde gelir, kara sürekli
akar; aradaki depo isteğe bağlı bir optimizasyon değil, yapısal bir
gerekliliktir (§9, madde 3).

### 5.5 Ürün

- Ürün ile taşıma koşulu ayrılır. `refrigerated_goods` gibi taşıma gereksinimini
  ürün sanan türler kaldırılır.
- **Kesin ürün listesi §8.1'dedir.** Bu bölümde ürün adı sayılmaz; tek kanonik
  liste §8'dir.
- Taşıma gereksinimleri: standart, soğutmalı, tehlikeli, yüksek güvenlik,
  ağır/hacimli, hassas, zaman kritik.
- Her ürün gerçekten kullanılan fiziksel alanlara sahiptir: yoğunluk,
  bölünebilirlik, uyumlu ekipman etiketleri, sıcaklık/tehlike/güvenlik koşulları,
  elleçleme süresi, bozulabilirlik, ekonomik değer sınıfı.
- Ekonomik değer oyuncuya alış-satış fiyatı olarak gösterilmez; toplam teslim
  maliyeti, ekonomik menzil, navlun tavanı, sigorta ve kaynak seçimi
  hesaplarında kullanılır. Ayrıntı: §7.2–§7.7.
- **Ürün maliyeti modellenmek zorundadır.** Oyuncunun ticaret yapmaması,
  motorun fiyat bilmemesi anlamına gelmez; kaynak rekabeti maliyetsiz
  hesaplanamaz.

---

## 6. Dünya ve şehir modeli

### 6.1 Şehir kavramı

Bir şehir, belediye sınırı değil **metropolitan lojistik pazar** temsilidir.
Tek düğüm şunları toplulaştırır: metro nüfusu ve tüketim tabanı, üretim ve
işleme endüstrileri, yerel lojistik maliyeti, kara/demir/hava/liman erişimi,
çevresindeki üretim ve dağıtım alanı.

### 6.2 Statik şehir kimliği

Koordinat, metro nüfusu, maliyet ve trafik tabanı, taşıma modu erişimleri, ana
ve ikincil endüstriler, endüstri kapasite tabanı, tüketim profili, lojistik
merkez niteliği, kontrollü uzun vadeli büyüme eğilimi.

Veriler gerçek ekonomik kimliği temel alır, oyun için normalize edilir. Şehir
kimliğini rastgele gürültü belirlemez.

### 6.3 Oyuncuya gösterilen pazar

Motor brüt üretim ve kullanımı hesaplar; ana UI net sonucu gösterir: ihraç
edilebilir fazla, karşılanmamış girdi ihtiyacı, oyuncuya açık hacim, değişimin
ana nedeni.

Motor şehir başına 10–14 anlamlı **ürün** talebi tutabilir; her ürün talebi
§7.4 gereği iki segmente (baz + acil) ayrıldığı için motor içindeki kayıt sayısı
bunun iki katıdır. Ana ekranda en yüksek 5–6 **ürün** gösterilir; segment
kırılımı ancak oyuncu o ürüne baktığında açılır.

Gerekçe: segmentasyon motorun çözünürlüğünü artırır, ana ekranın bilgi yükünü
artırmaz.

### 6.4 Şehir seçimi

- Faz 0: kıta ABD'sinde 20–25 şehir. Homojen dağılım ve tanınırlık önce, gerçek
  lojistik değer sonra. Çok yakın adaylardan büyük/tanınan olan seçilir.
- **Dengeleme 8–10 şehirlik bir alt kümeyle başlar.** Katalog 25 olsa da ilk
  tuning turu dar tutulur. 25 şehri iki aşamalı zincirlerle aynı anda dengelemeye
  çalışmak, sistemin bozuk mu yoksa yalnızca ayarsız mı olduğunu ayırt etmeyi
  imkânsızlaştırır.
- Faz 1: aynı veri sözleşmesiyle bütün kıtalarda ~150 şehre çıkılır.

---

## 7. Dönemsel pazar motoru

### 7.1 Dönem döngüsü

Her ekonomi döneminde motor:

1. Şehrin temel tüketimini hesaplar.
2. Endüstri girdilerinin karşılanma oranını hesaplar.
3. Endüstri kapasite kullanımını belirler.
4. Üretim çıktılarını hesaplar.
5. Yerel kullanımı çıktıdan düşer.
6. Net ihracat fazlası ve net ithalat ihtiyacı üretir; talebi segmentlere ayırır (§7.4).
7. Her talep segmenti için aday kaynakların **toplam teslim maliyetini** hesaplar (§7.2).
8. Kaynak payını yumuşak bölüşümle dağıtır (§7.5).
9. Oyuncunun çalışan hizmetlerine kazanabilecekleri pazar payını ayırır.
10. Yalnız ayrılan hacmi fiziksel yük üretimine açar.

Çözüm **günlüktür** ve deterministiktir. Yalnız değişen şehirler yeniden
hesaplanır. Fiziksel rota motoru bu günlük anlık görüntüden sabit oranlar alır.

### 7.2 Toplam teslim maliyeti — kaynak rekabetinin temeli

Oyuncu ticaret yapmaz, ama motorun kaynak seçimi yapabilmesi için ürün maliyeti
zorunludur. Bir hedef pazardaki her talep için aday kaynaklar tek bir sayıyla
yarışır:

> **Toplam teslim maliyeti = üretim maliyeti + navlun + süre maliyeti +
> risk primi + gümrük/vergi + elleçleme ve aktarma**

Bileşenler:

- **Üretim maliyeti:** kaynak şehrin o ürün için maliyet tabanı (endüstri
  kapasitesi, yerel maliyet tabanı ve girdi yeterliliğinden türer).
- **Navlun:** mesafe, mod, yük özelliği ve ekipman gereksiniminden türer (§7.6).
- **Süre maliyeti:** transit süresi × ürünün zaman hassasiyeti. Bağlanan
  sermayeyi, stok tutma maliyetini ve eskimeyi temsil eder.
- **Risk primi:** zincir uzunluğu, mod sayısı ve hizmet güvenilirliğinden türer;
  uzun ve çok aktarmalı zincirler güvenlik stoku gerektirir.
- **Gümrük/vergi:** yalnız uluslararası kaynaklarda.
- **Elleçleme ve aktarma:** her mod değişimi ve hub geçişi maliyet ekler.

**Çalışılmış örnek — Denver elektronik talebi** (normalize birim):

| Bileşen | Şanghay → Denver | Boston → Denver |
|---|---|---|
| Üretim maliyeti | 100 | 145 |
| Navlun | 12 | 6 |
| Süre maliyeti (32 gün / 3 gün) | 8 | 1 |
| Gümrük | 5 | 0 |
| Elleçleme ve aktarma | 3 | 1 |
| Risk primi | 4 | 1 |
| **Toplam teslim** | **132** | **154** |

Şanghay baz hacimde üretim maliyeti avantajıyla kazanır; Boston acil segmentte
süre maliyeti ağırlığı arttığında öne geçer (§7.4).

Oyuncunun konumu kritiktir: navlunu düşüren, transit süresini kısaltan veya
güvenilirliği artıran taşıyıcı, bir kaynağın rekabet gücünü **doğrudan**
değiştirir. Oyuncu pazarı yalnız okumaz; kaynak rekabetinin bir bileşenidir.

### 7.3 Değer yoğunluğu ve ekonomik menzil

Ürünün ekonomik değeri (§5.5) asıl işini burada yapar.

> **Değer yoğunluğu = birim ağırlık (veya hacim) başına ekonomik değer**

Yüksek değer yoğunluklu ürünlerde navlun, malın değerinin küçük bir yüzdesidir;
uzun mesafe ekonomik kalır. Düşük değer yoğunluklu ürünlerde navlun değeri
hızla aşar; kaynak zorunlu olarak yerel olur.

**Bu, oyunun en önemli türetilmiş yasasıdır: azami ekonomik taşıma mesafesi
elle yazılmaz, formülden doğar.** İnşaat malzemesinin neden bölgesel,
elektroniğin neden küresel olduğu kural olarak tanımlanmaz — toplam teslim
maliyeti hesabının doğal sonucudur. Gerçekçilik hedefi bu tek mekanizmadan
gelir ve Faz 1'de 150 şehre elle ayar gerektirmeden ölçeklenir.

Aynı alan navlun tavanını da belirler (§7.6).

### 7.4 Talep segmentasyonu

Bir şehir-ürün talebi tek kayıt değildir; iki segmente ayrılır:

- **Baz hacim:** maliyet güdümlü, süreye toleranslı. Süre maliyeti ağırlığı
  düşüktür. Uzun mesafe, deniz ve düşük maliyetli kaynaklar kazanır.
- **Acil/yenileme hacmi:** süre güdümlü, maliyete toleranslı. Süre maliyeti
  ağırlığı belirgin biçimde yüksektir. Yakın kaynaklar, kara ve hava kazanır.

İki segment aynı toplam teslim maliyeti formülünü kullanır; yalnız süre maliyeti
ağırlıkları farklıdır. Böylece ek bir sistem değil, tek formülün iki
parametrelendirmesi olur.

Sonuç: aynı şehir çiftinde bile **iki farklı hizmet stratejisi** açılır. Bu,
deniz/hava ve yavaş/hızlı mod ayrımını oyuncu için anlamlı kılan mekanizmadır ve
gerçek tedarik zincirlerinin (deniz taban hacim, hava acil ikmal) doğrudan
karşılığıdır.

### 7.5 Kaynak payı bölüşümü — yumuşak bölüşüm

Pay "kazanan hepsini alır" biçiminde dağıtılmaz. Toplam teslim maliyeti birbirine
yakın kaynaklar hacmi orantılı biçimde bölüşür; maliyet farkı büyüdükçe pay
farkı hızla açılır.

Gerekçe:

- Gerçekçidir — gerçek pazarlarda tek kaynak nadiren tüm hacmi alır.
- Dayanıklıdır — küçük bir formül veya ayar değişikliği haritanın yarısını
  öldürmez. Keskin eşikli modeller dengeleme sırasında kırılgandır.
- Oyuncuya alan açar — ikinci en iyi kaynağın hattında da iş vardır.

Kaynak üretim kapasitesi bölüşüme üst sınır koyar: bir kaynak en ucuz olsa da
kapasitesinin üzerinde hacim veremez, kalan hacim sonraki kaynaklara akar.

### 7.6 Navlun oluşumu ve tavanı

Navlun başlangıçta piyasa tarafından oluşur (§5.3). Türetildiği girdiler:

- mesafe ve mod temel maliyeti;
- yük özelliği ve ekipman gereksinimi (soğutmalı, tehlikeli, ağır/hacimli primi);
- hattaki arz-talep baskısı — servis edilmeyen hacim navlunu yükseltir;
- rekabet yoğunluğu.

**Navlun tavanı değer yoğunluğuna bağlıdır.** Bir yükün taşınması için ödenebilir
azami bedel, o yükün ekonomik değerinin bir oranını aşamaz. Değeri 1.000 olan
yüke 5.000 navlun talep edilemez.

Bu tavan oyuncuya gerçek bir stratejik ayrım verir:

- **yüksek değer / düşük hacim** hatları — birim başına yüksek navlun, küçük
  hacim, özel ekipman ve güvenlik gereksinimi;
- **düşük değer / yüksek hacim** hatları — birim başına düşük navlun, büyük
  hacim, doluluk ve ölçek ekonomisine bağımlı.

Gerçek nakliye şirketlerinin verdiği kararın aynısıdır ve iki farklı geçerli
şirket kimliği üretir.

### 7.7 Oyuncuya gösterilen

Oyuncu **ürün alış-satış fiyatını görmez** — ticaret yapmadığı için anlamsızdır.

Oyuncu şunları görür:

- **Kendi navlununu ve maliyetini tam olarak** — bu onun geliri ve gideridir,
  gizlenmesi savunulamaz.
- **Kaynak rekabetinin nedenli özetini** — kırılım değil, sonuç ve neden.
  Örnek: *"Denver elektronik, baz hacim: Şanghay %58 (üretim maliyeti),
  Boston %27 (transit süresi), Guadalajara %15 (denge)."*
- **Kendi hizmetinin bu tabloyu nasıl değiştirdiğini** — §5.2 açıklanabilirlik
  değişmezinin doğrudan uygulaması.

Rakip kaynakların toplam teslim maliyeti kırılımı gösterilmez; bilgi yükü
yaratır ve oyunu tabloya çevirir. Nedenli özet, açıklanabilirlik değişmezini
karşılamak için yeterlidir.

---

## 8. Ürün kataloğu ve üretim zincirleri — kesin

A-06 karara bağlanmıştır. Katalog serbest bir liste değildir; §7.3'ün ekonomik
menzil yasasını gözlemlenebilir kılmak ve §3.1'in dönüş bacağı bulmacasını
üretmek zorundadır.

### 8.1 Ürün listesi — 19 ürün

**Ham (5):** tarım ürünü, maden cevheri, kereste, petrokimya girdisi,
tekstil hammaddesi.

**Ara (6):** işlenmiş metal, kimyasal/plastik, inşaat malzemesi, ambalaj,
elektronik bileşen, kumaş.

**Nihai (8):** işlenmiş gıda, içecek, tüketim elektroniği, otomotiv parçası,
makine, ilaç, mobilya, giyim.

Dengeleme baştan 19 ürünün tamamıyla yapılır; ürün alt kümesi kullanılmaz.

**Not — §6.4 ile ilişkisi:** dar dengeleme turu **şehir** sayısını daraltır
(8–10 şehir), **ürün** sayısını değil. İki daraltma birlikte yapılırsa üretim
zincirleri kopar ve sistem test edilemez hâle gelir.

### 8.2 Değer yoğunluğu yelpazesi

Her ürün tam olarak bir kademede yer alır; kademe dışı ürün bulunamaz.

| Yoğunluk | Ürünler | Beklenen doğal menzil |
|---|---|---|
| 1 — çok düşük | inşaat malzemesi, maden cevheri | Bölgesel (~300–500 km) |
| 2 — düşük | kereste, ambalaj, içecek, tarım ürünü, işlenmiş metal, petrokimya girdisi | Bölgesel–ulusal |
| 3 — orta | kimyasal/plastik, işlenmiş gıda, mobilya, kumaş, tekstil hammaddesi | Ulusal |
| 4 — yüksek | otomotiv parçası, makine, giyim | Ulusal–kıtalararası |
| 5 — çok yüksek | tüketim elektroniği, elektronik bileşen, ilaç | Kıtalararası |

Bu tablo hedef değil **beklenen çıktıdır.** Menziller kural olarak yazılmaz;
§7.3 formülünden doğar. Tablo yalnız doğrulama referansıdır: uçlardaki iki ürün
(inşaat malzemesi ve tüketim elektroniği) doğrulama kapısı 11'in test
malzemesidir.

### 8.3 Öğretici uç ürünler

Her biri farklı bir mekaniği oyuncuya öğretir:

- **ilaç** — soğutmalı + yüksek güvenlik + zaman kritik → premium ekipman oyunu;
- **otomotiv parçası** — JIT/zaman kritik → acil segmentin (§7.4) vitrini;
- **içecek** — ağır sıvı, düşük değer yoğunluğu → yüksek hacimli dönüş dolgusu;
- **mobilya** — hafif ama hacimli → kapasitenin iki ekseni olduğunu öğretir (§8.5);
- **inşaat malzemesi** — uç düşük değer → ekonomik menzilin alt sınırı;
- **tüketim elektroniği** — uç yüksek değer → ekonomik menzilin üst sınırı;
- **ambalaj** — gıda, içecek ve tüketim malını besleyen çapraz girdi → bol
  miktarda kısa mesafe bölgesel hacim ve konsolidasyon fırsatı üretir.

### 8.4 Asimetri ilkesi — dönüş bacağı bulmacasının kaynağı

Dönüş bacağı bulmacası tesadüfe bırakılmaz. Katalog ve şehir profilleri şu ilkeye
göre kurulur:

> **Ağırlık akışı ile değer akışı ters yönlüdür.**

Tarım ve maden bölgeleri ağır ve ucuz ihraç eder, hafif ve değerli ithal eder;
sanayi ve tüketim bölgeleri tam tersi. Araçlar ağırlık veya hacim sınırlı olduğu
için oyuncu hattı **değerle dengeleyemez, tonajla dengelemek zorundadır.**

Bu, gerçek dünyadaki konteyner dengesizliğinin doğrudan karşılığıdır ve
kıtalararası ölçekte kendiliğinden keskinleşir.

### 8.5 Kapasitenin iki ekseni

Araç kapasitesi tek sayı değildir: **tonaj sınırı ve hacim sınırı** birlikte
bulunur. Bir yük hangi sınırı önce doldurursa aracı o kapatır.

- İşlenmiş metal, maden cevheri, inşaat malzemesi → tonajı doldurur, hacim boş kalır.
- Mobilya, ambalaj → hacmi doldurur, tonaj boş kalır.
- İdeal yük karışımı iki ekseni birlikte doldurandır.

Sonuç: doluluk artık tek bir yüzde değil, çözülecek bir eşleştirme problemidir.
Bu, dönüş bacağı bulmacasını (§3.1) belirgin biçimde zenginleştirir ve
depolamanın (§9) gerekçesini güçlendirir — iki ekseni birlikte dolduracak yükler
aynı anda hazır olmayabilir.

### 8.6 İki aşamalı üretim tarifleri

Zincir derinliği en fazla iki dönüşümdür.

| Aşama 1 (ham → ara) | Aşama 2 (ara → nihai) |
|---|---|
| maden cevheri → işlenmiş metal | işlenmiş metal + kimyasal/plastik → otomotiv parçası |
| kereste → inşaat malzemesi | işlenmiş metal → makine |
| kereste → ambalaj | elektronik bileşen + kimyasal/plastik → tüketim elektroniği |
| petrokimya girdisi → kimyasal/plastik | kumaş → giyim |
| kimyasal/plastik → ambalaj | kimyasal/plastik → ilaç |
| tekstil hammaddesi → kumaş | tarım ürünü + ambalaj → işlenmiş gıda |
| maden cevheri → elektronik bileşen | tarım ürünü + ambalaj → içecek |
| — | kereste + kumaş → mobilya |

Girdi yeterliliği kapasite kullanımını belirler. Oyuncunun hizmeti eksik girdiyi
tamamlayarak ek çıktı fırsatı açar (§3.4 darboğaz fırsatı).

**Ambalaj kasıtlı olarak çapraz girdidir:** düşük değer yoğunluklu, hacimli ve
birçok nihai ürünü besler. Bu, haritada bol miktarda kısa/orta mesafe bölgesel
hacim üretir ve dönüş bacağı dolgusu için doğal malzeme sağlar.

---

## 9. Depolama, aktarma ve hub

Eski iş tabanlı sistemde depolama işlevsizdi — bu bir uygulama eksikliği değil,
**yapısal bir imkânsızlıktı.** Her iş atomik bir noktadan-noktaya taahhüt
olduğu için yükü ortada bekletmek yalnız süre ve maliyet ekliyor, karşılığında
hiçbir şey vermiyordu. Konsolide edilecek bir şey yoktu.

Yeni modelde depolama altı ayrı nedenle işlevseldir ve bu nedenlerin hepsi
zaten alınmış kararlardan doğar:

1. **Konsolidasyon.** Birçok kaynaktan gelen küçük akışlar hub'da birleşip tam
   yük oluşturur. Gerçek lojistikte hub'ların var olma nedeni budur ve A-01'in
   otomatik konsolidasyon kararıyla (§10) doğrudan uyumludur.
2. **Segment arbitrajı.** Baz hacim süreye toleranslıdır (§7.4). Acil yük hemen
   hareket ederken baz yük depoda iyi bir dönüş fırsatı bekleyebilir. Depolamayı
   değerli kılan şey tam olarak talep segmentasyonudur.
3. **Mod tamponu.** Deniz büyük partiler hâlinde ve seyrek gelir; kara sürekli
   akar. Tarifeli mod ile sürekli mod arasında tampon **zorunludur.** §5.4'teki
   iki sefer modeli kararının doğrudan sonucudur — bu madde "faydalı" değil,
   kaçınılmazdır. Liman ve terminal düğümleri tampon kapasitesi olmadan
   çalışamaz.
4. **Dönüş bacağı dolgusu.** Depo, boş dönüş kapasitesi olan bir araç geçene
   kadar yükü tutmayı mümkün kılar. §3.1'in imza bulmacasına doğrudan hizmet
   eder. §8.5'in iki eksenli kapasitesiyle birleştiğinde daha da anlamlıdır:
   tonajı ve hacmi birlikte dolduracak yükler aynı anda hazır olmayabilir.
5. **Risk primini düşürür.** §7.2'deki risk primi güvenlik stokunu temsil eder.
   Tampon stok tutabilen bir ağ daha düşük risk primi taşır; bu, **kaynağın
   toplam teslim maliyetini doğrudan iyileştirir.** Depolama yalnız oyuncunun
   iç verimliliği değil, rekabet gücünün bileşenidir.
6. **Olay dayanıklılığı.** §3.3 olayları (liman kapanması, koridor kesintisi)
   karşısında tamponlu ağ ayakta kalır. Bu, §3.3'ün 5. ilkesini —
   "olaylar ağ çeşitliliğini ödüllendirir" — somut bir mekaniğe bağlar.

### 9.1 Maliyet tarafı — bedava kazanç değildir

Depolama gerçek bir ödünleşme olmalıdır, yoksa her zaman doğru cevaba dönüşür:

- depo kurulumu sermaye gerektirir ve kapasitesi sınırlıdır;
- tutma süresi işletme maliyeti üretir;
- bekleyen yük §7.2'deki süre maliyetini artırır, yani kaynağın rekabet gücünü
  düşürür — 2. ve 5. maddelerin tersi yönde çalışır;
- her aktarma elleçleme maliyeti ve gecikme ekler.

Doğru kurulduğunda oyuncunun sorusu "depo kurayım mı" değil, **"nerede, ne
kadar ve hangi yükler için"** olur.

### 9.2 Hub kontrol modeli

A-03 kararı gereği: oyuncu hub'ı, izinleri ve politikayı seçer; motor yükün
ayrıntılı yolunu bulur. Oyuncu tek tek yük zinciri çizmez.

---

## 10. Açık kararlar

v1'deki 29 madde ikiye ayrıldı: mimariyi belirleyen ve yanlış kararın geri
dönüşü pahalı olanlar burada kaldı. Kalan maddeler §11'e, "uygulama sırasında
ayarlanacak parametreler" başlığına taşındı — bunlar masa başında değil,
oynayarak çözülür ve çekirdeği bloke etmemelidir.

**Durum: A-01, A-02, A-03, A-04 ve A-06 kapandı. Yalnız A-05 açıktır ve
formüller kesinleşmeden sayısal hedefe bağlanamaz.**

### A-01 — Oyuncu rotada taşınacak yükü hangi düzeyde seçer? — **KAPANDI**

**Sonuç: varsayılan otomatik konsolidasyon; oyuncu ürün/pazarları
önceliklendirebilir veya hariç tutabilir.**

Gerekçe: oyuncu iradesini korurken parti kabulü mikro yönetimine dönüşü önler.
Her akışı tek tek izin listesine ekletmek, eski sistemin kılık değiştirmiş
hâlidir ve §5.1 değişmezini ihlal eder.

### A-02 — Araç atama mı, kapasite havuzu mu? — **KAPANDI**

**Sonuç: her zaman fiziksel araç. Kapasite havuzu kullanılmaz.**

Gerekçe: kapasite havuzu araçların fiziksel konumunu soyutlar ve dönüş bacağı
bulmacasını (§3.1) yok eder — yani oyunun imza mekaniğini. Ölçek sorunu havuzla
değil, iyi toplu-atama ve filo yönetimi UI'ıyla çözülür. Karar ölçeği yükselirken
(§4.4) bile araçlar fiziksel kalır; soyutlanan şey oyuncunun *arayüzü*, motorun
modeli değildir.

### A-03 — Aktarma ve hub kontrolü — **KAPANDI**

**Sonuç: oyuncu hub, izin ve politika seçer; motor yükün ayrıntılı yolunu bulur.**

Gerekçe: kıtalararası ölçekte sürdürülebilir tek seçenek budur. Her yük zincirini
oyuncuya çizdirmek 150 şehirde imkânsız; yolu tamamen motora bırakmak oyuncuyu
seyirciye çevirir.

### A-04 — Kıtalararası fırsatın Faz 0'daki biçimi — **KAPANDI**

**Sonuç: kademeli açılım, ilk saatten devam bacağı.**

- Oyuncu **ilk saatten itibaren** ithalat/ihracat zincirlerinin ABD içi devam
  bacağını taşıyabilir (LA limanı → Chicago). Böylece kıtalararası ekonominin
  içinde yaşar ve vizyonu erken görür.
- **Derin deniz bacağı ekonomik bariyerle açılır:** gemi yüksek sermaye ve liman
  varlığı gerektirir. Bu bir seviye kilidi veya yapay bölge kilidi **değildir**
  (§2.3 değişmezi korunur); doğal bir sermaye eşiğidir.
- **Gemi araç sınıfı Faz 0'da yazılır ve test edilir.** Gerekçe: gemi ekonomisi
  kamyondan kökten farklıdır (devasa kapasite, haftalarca transit, tarifeli
  sefer, çok yüksek sermaye) ve rota motorunun temel varsayımlarını zorlar.
  Faz 0'da yazılmazsa Faz 1'de rota motoru yeniden yazılmak zorunda kalır —
  §2.2'nin kaçınmak için var olduğu tuzağın ta kendisi.
- Zincir **tek yük** olarak uçtan uca izlenir; iki ayrı yük olarak modellenmez.
  Doğrulama kapısı 1'in anlamı budur.

Soyut yabancı şehir veya sahte kontrat oluşturulmayacaktır.

### A-05 — Ekonomi dönemi ve performans bütçesi

Günlük çözüm ve determinizm §5.2'de sabitlendi. Açık kalan: rota ve şehir
sayısına göre hedef işlem süresi, fiziksel yüklerin toplulaştırma eşiği,
değişmeyen şehirlerin atlanma stratejisi. 150 şehir hedefi bu bütçenin tasarım
girdisidir.

### A-06 — Ürün ailesi listesi ve üretim tarifleri — **KAPANDI**

Sonuç §8'e işlenmiştir: 18 ürün, beş kademeli değer yoğunluğu yelpazesi,
asimetri ilkesi, iki eksenli kapasite ve iki aşamalı tarifler.

Geriye kalan yalnız veri işidir, karar değildir: her ürünün fiziksel alan
değerleri (yoğunluk, parti büyüklüğü, elleçleme süresi, bozulabilirlik),
taşıma gereksinimi eşlemesi ve bunların kaynak/doğrulama yöntemi. §11'de
parametre olarak izlenir.

---

## 11. Uygulama sırasında ayarlanacak parametreler

Bunlar açık karar değildir ve çekirdeği bloke etmez. Makul bir varsayılanla
uygulanır, oynayarak ayarlanır.

- Sürekli döngü modlarında kalkış politikası (araç hazır oldukça / asgari
  doluluk / azami bekleme / rota bazında politika).
- Tarifeli modlarda sefer sıklığı, kalkış penceresi genişliği ve liman/terminal
  slot kıtlığının şiddeti.
- Gemi sermaye eşiği ve liman varlığı gereksinimi — deniz bacağının doğal
  açılma zamanlamasını bu belirler (§10, A-04).
- Araç kapasitesinin yükler arasında paylaştırılma önceliği.
- Çok duraklı rotada pazar kapsamının genişliği.
- Rota kurma giriş noktası ve rota önizleme gösterge seti.
- Rota sonrası yönetim seçeneklerinin kesin kapsamı.
- Pazar payı kazanma/kaybetme oranları ve süreleri.
- Yumuşak bölüşüm eğrisinin keskinliği (maliyet farkının paya dönüşüm hızı).
- Toplam teslim maliyeti bileşenlerinin kalibrasyonu; iki talep segmentinin
  süre maliyeti ağırlıkları ve hacim oranı.
- Navlun tavanının değer yoğunluğuna oranı ve fiyat politikasının açılma eşiği.
- Diğer taşıyıcıların soyutlama düzeyi (Faz 0'da katsayı; isimli rakip sonra).
- Şehir seti kesin listesi ve veri normalizasyon standardı.
- Başlangıç şehri, başlangıç filosu ve ilk fırsat sunumu.
- İlk oturum başarı ölçütleri.
- Rota başarısızlığı, bakım ve kesinti davranışı.
- Otomasyon eşikleri.
- Dünya olaylarının sıklığı, şiddeti, süresi ve uyarı penceresi uzunluğu.
- Anlamlı duraklama eşikleri ve sinyal önem sıralaması.
- 18 ürünün fiziksel alan değerleri ve taşıma gereksinimi eşlemesi (§8, A-06'dan
  devreden veri işi).
- Araç tipi başına tonaj/hacim sınır oranları (§8.5).
- Depo kurulum sermayesi, kapasite kademeleri, tutma maliyeti ve elleçleme
  gecikmesi (§9.1) — bu kalibrasyon depolamanın "her zaman doğru cevap"
  olmamasını sağlayan tek şeydir.

---

## 12. Doğrulama kapıları

Faz 0'ın tamamlandığını gösteren, öznel olmayan kriterler:

1. **Çok modlu kanıt.** Şanghay → Los Angeles → Chicago zinciri tek yük olarak,
   modeli özel durumla delmeden çalışır.
2. **Veri sözleşmesi kanıtı.** Yeni bir şehir eklemek yalnız veri kaydı
   gerektirir; kod değişmez.
3. **Bulmaca kanıtı.** Oyuncu dönüş bacağı dengesini düşünmeden kurduğu ağda
   ölçülebilir biçimde daha az kâr eder.
4. **Açıklanabilirlik kanıtı.** Rastgele seçilen 10 pazar payı ve 10 kayıp
   göstergesinin hepsi tek cümlelik bir nedene sahiptir.
5. **Determinizm kanıtı.** Aynı tohumla iki kampanya 100 dönem sonunda özdeştir.
6. **Angarya kanıtı.** Oyuncu tekil yük kabulü yapmadan 10+ rotalık ağ kurar ve
   ağ büyüdükçe tıklama başına karar değeri artar, azalmaz.
7. **Performans kanıtı.** Ekonomi çözümü 150 şehir ölçeğine ekstrapole
   edildiğinde bütçe içinde kalır.
8. **Ölçek merdiveni kanıtı.** Oyuncu 3, 10 ve 25 rota eşiklerinde *farklı türde*
   kararlar aldığını fark eder; aynı kararı daha çok kez almaz.
9. **Olay kanıtı.** Test edilen her olay hem kaybeden hem kazanan üretir ve
   dağıtılmış ağ kurmuş oyuncu, tek koridora bağımlı oyuncudan ölçülebilir
   biçimde daha az etkilenir.
10. **Duraklama kanıtı.** Oyuncunun oyunu izleyerek geçirdiği pasif süre,
    karar verdiği süreden kısadır.
11. **Ekonomik menzil kanıtı.** Hiçbir elle yazılmış mesafe kuralı olmadan,
    düşük değer yoğunluklu ürünler bölgesel, yüksek değer yoğunluklu ürünler
    kıtalararası kaynak dağılımı üretir. (§7.3'ün doğrulaması — bu başarısız
    olursa gerçekçilik hedefi çöker.)
12. **Segment kanıtı.** Aynı şehir çiftinde baz hacim ve acil hacim farklı
    kaynakları ve farklı modları kazandırır; iki segment aynı stratejiye
    çökmez.
13. **Dayanıklılık kanıtı.** Yumuşak bölüşüm eğrisi ±%20 değiştirildiğinde
    hiçbir şehir pazarı tamamen ölmez.
14. **İki eksen kanıtı.** Tonaj sınırlı ve hacim sınırlı yükleri birlikte
    dengeleyen oyuncu, tek eksene göre optimize eden oyuncudan ölçülebilir
    biçimde daha yüksek doluluk elde eder.
15. **Depo kanıtı.** Depolama ne her zaman doğru cevaptır ne de hiç işe yaramaz;
    en az bir açık senaryoda kârlı, en az bir açık senaryoda zararlıdır ve
    oyuncu hangisi olduğunu §5.2 açıklamasından anlayabilir.
16. **Asimetri kanıtı.** Şehir profilleri §8.4 gereği ağırlık ve değer akışını
    ters yönlü üretir; hiçbir büyük şehir çifti her iki yönde de kendiliğinden
    dengeli değildir.
17. **Sefer modeli kanıtı.** Tarifeli ve sürekli sefer modelleri rota motorunda
    ayrı temel tip olarak yaşar; tarifeli mod, sürekli modun özel hâli olarak
    kodlanmamıştır. Kaçırılan bir gemi seferi bir sonrakini bekler ve bu durum
    oyuncuya açıklanır.
18. **Kademeli açılım kanıtı.** Yeni oyuncu ilk oturumda kıtalararası bir
    zincirin ABD içi bacağını taşıyabilir; deniz bacağını yalnız sermaye eşiğini
    aştığında satın alabilir ve bu eşik hiçbir yerde yapay kilit olarak
    uygulanmamıştır.

Bu kapılar geçilmeden Faz 1 veri üretimine başlanmaz.

---

## 13. Karar ve uygulama sırası

1. ~~A-01 – A-06 kararlarının sonuçlandırılması.~~ **Tamamlandı; yalnız A-05 açık.**
2. ~~Nihai çelişki denetimi.~~ **Tamamlandı (bkz. §14).**
3. A-05'in formüller yazıldıktan sonra sayısal hedefe bağlanması.
4. §11 parametreleri için makul varsayılanların belirlenmesi.
5. Eski plan, GDD ve kod referanslarının envanteri.
6. Eski modelin çalışma ağacından temizlenmesi ve kanonik GDD'nin yazılması.
7. Uygulama planının dosya/faz/test düzeyinde hazırlanması.
8. Kullanıcı onayından sonra kod uygulaması.
9. 8–10 şehirlik dar dengeleme turu (19 ürünün tamamıyla).
10. 20–25 şehre genişletme ve §12 doğrulama kapıları.
11. Faz 1: küresel veri üretimi (~150 şehir).

---

## 14. Çelişki denetimi kaydı

2026-07-22 tarihli denetimde bulunan ve düzeltilen tutarsızlıklar:

| # | Bulgu | Düzeltme |
|---|---|---|
| 1 | §8.1 "18 ürün" diyordu ama liste 19 ürün içeriyordu; "Nihai (7)" başlığı altında 8 ürün vardı. | Sayım 19'a düzeltildi. |
| 2 | Petrokimya girdisi ürün listesinde vardı ama §8.2 değer yoğunluğu tablosunda yoktu — §7.3 yasası bu ürün için tanımsız kalıyordu. | Kademe 2'ye eklendi; "kademe dışı ürün bulunamaz" kuralı yazıldı. |
| 3 | §5.5 eski v1 ürün ailesi listesini taşıyordu ve §8.1 ile çelişiyordu (iki rakip kanonik liste). | §5.5'ten liste kaldırıldı; tek kanonik liste §8.1 oldu. |
| 4 | §8.6'da "tarım ürünü → ambalaj girdisi" tarifi mantıksızdı; ambalaj tarımdan üretilmez. | "kereste → ambalaj" ve "kimyasal/plastik → ambalaj" olarak düzeltildi. |
| 5 | §8.6'da "kereste → mobilya girdisi" satırı, Aşama 2'deki "kereste + kumaş → mobilya" ile çakışıyordu. | Kaldırıldı; yerine "maden cevheri → elektronik bileşen" eklendi (elektronik bileşenin girdisi tanımsızdı). |
| 6 | §6.3 "10–14 talep kaydı" §7.4 segmentasyonundan sonra belirsizleşti — ürün mü, segment mi? | Ürün olduğu netleştirildi; segment kırılımının ana ekranı şişirmeyeceği yazıldı. |
| 7 | §6.4 dar dengeleme (8–10 şehir) ile §8.1 tam ürün dengelemesi çelişkili okunuyordu. | §8.1'e not eklendi: daraltma **şehir** eksenindedir, ürün ekseninde değil. |
| 8 | §3.3 ilke 4 "yeni oyuncu kıtalararası krizden etkilenmez" diyordu; A-04 ise yeni oyuncuya ithalat iç bacağı verdiği için dolaylı etki kaçınılmazdı. | Doğrudan/dolaylı etki ayrımı yapıldı. |
| 9 | §10, §13 ve §9'da bölüm numarası kaymalarından doğan bayat çapraz referanslar. | Tümü güncellendi (§4.3→§4.4, §9→§11, §10→§12, §8→§10). |

**Çözülmemiş bağımlılık:** §12'deki 7. doğrulama kapısı (performans) A-05
kapanmadan ölçülemez. Bu bir çelişki değil, sıralama bağımlılığıdır.
