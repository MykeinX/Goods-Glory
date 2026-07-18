---
tür: GDD - sistem tasarımı
durum: Temel model kabul edilmiş; ağır ticari saha açık konu
kapsam: Araç şasileri, ekipman, fiziksel görev ve filo yaşam döngüsü
kaynaklar:
  - docs/06_DATA_DRIVEN_MODELLER_VE_ZAMAN.md
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - "[[01 - Kanonik Lojistik Nesne Modeli]]"
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - araçlar
  - ekipman
---

# Araçlar ve Ekipman

#gdd #araçlar #ekipman

## Sistem ilkesi

Araçlar sözleşme sahibi değildir. Araç; uygun ekipmanla bir servis hattının fiziksel görevini yürütür, yük partilerini taşır ve görev sonunda gerçek konumunda kalır.

## Araç ve ekipman ayrımı

### Şasi/platform

Araç modeli:

- sınıf ve kullanım rolü;
- uyumlu gövde/dorse;
- menzil ve önerilen operasyon profili;
- hız ve nominal tüketim;
- kondisyon, yıpranma ve bakım aralığı;
- sabit ve değişken maliyet;
- üs/park gereksinimi

taşır.

### Entegre gövde

Van paneli veya sabit kasa gibi aracın kalıcı parçasıdır. Normal operasyonda ayrı envanter olmaz.

### Dönüşüm/kurulum

Frigorifik dönüşüm veya ağır üstyapı gibi yarı kalıcı bileşendir. Uyumlu tesiste süre ve maliyetle takılır/sökülür.

### Ayrılabilir ekipman

Kuru yük, frigorifik, tanker ve konteyner dorsesi ayrı şirket varlığıdır. Konum, kondisyon, bağlı araç ve park edildiği tesis izlenir.

## Kapasite ve yetenek

Gerçek kapasite takılı ekipmandan ve şasi sınırlarından türetilir. Oyuncuya kısa yetenek etiketleri gösterilir:

- Genel;
- Soğutuculu;
- Ağır;
- Tanker;
- Konteyner;
- Güvenli.

Bir görevin uygunluğu:

1. aracın boş ve doğru konumda olmasını;
2. şasi-ekipman uyumunu;
3. yük kapasitesini;
4. gereken yetenekleri;
5. rota/menzil sınıfını;
6. kondisyon ve bakım durumunu;
7. şirket yetki ve kabiliyetlerini;
8. gerekli tesis veya terminal erişimini

denetler.

## Fiziksel konum

Araç `homeBase` ile gerçek `location` bilgisini ayrı taşır. Ana üs muhasebe ve yönetim ilişkisidir; konum operasyon gerçeğidir.

- Tek yön teslimat sonrası varış şehrinde kalır.
- Depoya yük bırakınca serbest kalabilir.
- Başka şehirdeki dorseyi anında bağlayamaz.
- Hat havuzuna atansa bile kalkış düğümüne fiziksel olarak ulaşmalıdır.
- Boş konumlandırma maliyet ve zaman tüketir.

## Ekipman envanteri

Her varlık:

- model kimliği;
- mevcut şehir ve tesis;
- kullanım/park durumu;
- bağlı araç;
- kondisyon;
- kurulum veya değiştirme süresi;
- gereken tesis özelliği ve lisans

taşır. Dorse ve modüler ekipman yük depolama kapasitesini değil ekipman park kapasitesini kullanır.

## Kondisyon ve bakım

Yıpranma tek küresel oran değildir. Araç modeli:

- 1.000 km başına temel kayıp;
- şehir içi, bölgesel ve uzun yol çarpanları;
- yük/ağırlık etkisi;
- bakım aralığı

ile hesaplanır. Birkaç günlük normal kullanım dramatik kondisyon kaybı üretmemelidir. Bakımsızlık maliyet, güvenilirlik ve arıza riskini artırır; oyuncuyu parça mikro yönetimine zorlamak şart değildir.

## Filo ölçeği

- **Kurucu:** adlandırılmış araç, manuel görev.
- **Yerel:** rota şablonu ve küçük havuz.
- **Bölgesel:** servis hattı kapasitesi, yönetici kontrolü ve yedek oranı.
- **Kurumsal:** yenileme, bakım, tahsis ve dış kaynak politikaları.

Araç kimliği, geçmişi ve fiziksel konumu ölçek büyüse de korunur; yalnızca zorunlu tıklama azalır.

## Satın alma ve üs gereksinimi

Standart hafif ve kendinden gövdeli araçlar merkez ofisin sınırlı kiralık sahasından çalışabilir. Depo; özel ekipman, dorse, bakım, düzenli aktarma, otomasyon ve büyük filo için anlamlı fiziksel altyapıdır.

**Açık konu:** Ağır araçların depo olmadan kiralık ticari saha üzerinden işletilmesinin kapsamı, maliyeti ve sınırları kesinleşmemiştir. Bu seçenek karar verilmiş özellik gibi sunulmamalıdır.

## Arayüz

Her araç için:

- filo kodu, ad ve model;
- ekipman;
- kapasite ve yetenek;
- gerçek konum;
- görev/hat ve taşıdığı yük özeti;
- hedef ve ETA aralığı;
- kondisyon ve bakım;
- ana üs

okunabilir olmalıdır. Haritada kalıcı etiket yalnızca kısa filo kodu ve gerektiğinde durum sayacı taşır; ayrıntı seçim panelinde açılır.

## İlgili belgeler

- [[02 - Rota ve Operasyon Planlama]]
- [[02 - Taşıma Hatları ve Konsolidasyon]]
- [[04 - Tesisler]]
- [[06 - Ekonomi ve Finans]]
