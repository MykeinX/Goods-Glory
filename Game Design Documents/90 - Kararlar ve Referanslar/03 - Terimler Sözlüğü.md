---
tür: terimler-sözlüğü
durum: aktif
kapsam: GDD boyunca kullanılan kanonik ürün ve lojistik terimleri
kaynaklar:
  - Kullanıcının ana tasarım özeti
  - Taslak_fikir.md
  - docs/*.md
son_güncelleme: 2026-07-17
etiketler: [gdd, gdd/sozluk]
---

# Terimler Sözlüğü

| Terim | Kanonik anlam |
|---|---|
| Sözleşme | Şirketin müşteriye başlangıçtan nihai teslime kadar verdiği ticari hizmet sözü. Bir araca bağlı değildir. |
| Yük partisi | Bir sözleşmenin belirli zamanda ürettiği, miktarı, konumu, son tarihi ve uyumluluk gereksinimleri izlenen fiziksel yük kümesi. |
| Taşıma aşaması | Bir yük partisinin uçtan uca zincirdeki toplama, ana taşıma, aktarma, depolama veya son kilometre adımı. |
| Servis hattı | Şirketin iki düğüm arasında belirli sıklık ve kapasiteyle işlettiği düzenli taşıma hizmeti. Müşteri işi değildir. |
| Taşıma zinciri | Bir sözleşmenin hizmet sözünü karşılayan sıralı taşıma aşamaları bütünü. |
| Spot iş | Düzenli kapasite taahhüdü gerektirmeyen, kısa süre açık tekil taşıma fırsatı. |
| Hat sözleşmesi | İki nokta arasında dönemsel hacim, sıklık ve hizmet seviyesi isteyen anlaşma. |
| Hizmet sözleşmesi | Şehir dağıtımı veya çok aşamalı ağ gibi tesis, personel ve ayrılmış kapasite isteyen hizmet paketi. |
| SLA | Teslim süresi, zamanında teslimat oranı, hasar toleransı ve devamlılık gibi ölçülebilir hizmet seviyesi taahhütleri. |
| Kapasite havuzu | Tekil araç ataması yerine bir servis hattı veya sözleşmeye ayrılan eşdeğer taşıma kapasitesi. |
| Rezerve kapasite | Talep artışı, gecikme ve krizler için satılmadan tutulan kapasite payı. |
| Backlog | Henüz bir sonraki uygun taşıma aşamasına alınamamış bekleyen yük miktarı. |
| Konsolidasyon | Aynı yöne ve uyumluluğa sahip farklı yük partilerinin ortak kapasitede birleştirilmesi. |
| Cross-dock | Yükün uzun süre depolanmadan gelen araçtan sonraki taşıma aracına aktarılması. |
| Düğüm | Depo, terminal, liman, hava kargo tesisi veya müşteri tesisi gibi yükün bulunduğu ya da aktarıldığı yer. |
| Depo | Araç/equipment üssü, yük kabulü, depolama, konsolidasyon, aktarma ve yerel dağıtım rollerinin bir alt kümesini sunan fiziksel şirket tesisi. |
| Şirket merkezi (HQ) | Yönetim kapasitesi, departmanlar ve şirket çapındaki kararları taşıyan; fiziksel depo operasyonundan ayrı idari varlık. |
| Ticari saha | Depo kurmadan araç veya ekipman parkı gibi sınırlı fiziksel operasyon kapasitesi sağlayabilecek kiralık alan; ayrıntıları açık karardır. |
| Uzmanlık | Bir deponun şehir dağıtımı, bölgesel hub veya transit aktarma gibi ana operasyon rolü. |
| Ekipman | Araca takılabilen gövde, dönüşüm veya ayrılabilir dorse gibi yük yeteneği sağlayan varlık. |
| Faaliyet yetkisi | Şirketin belirli coğrafyada veya ticari rolde çalışmasına izin veren şirket seviyesi koşul. |
| Yük sertifikası | Soğuk zincir, ağır, tehlikeli veya güvenli yük gibi özel yükleri taşıma yeterliliği. |
| Operasyon kabiliyeti | Uzun yol, vardiya, gümrük veya intermodal işin güvenilir yürütülmesini temsil eden şirket programı. |
| Toplulaştırma | Çok sayıdaki gerçek varlık ve hareketi, sonuçları koruyarak kapasite, akış veya kümeler hâlinde simüle ve sunma yöntemi. |
| Fiziksel görünürlük | Araç, yük, konum, tesis ve operasyon akışının oyuncu tarafından izlenebilir olması. |
| Hibrit simülasyon | Erken ölçekte tekil fiziksel nesneleri, büyük ölçekte güvenli toplulaştırmayı kullanan kanonik yaklaşım. |
| Semantik yakınlaştırma | Yakınlaştırma düzeyine göre yalnızca boyutu değil gösterilen bilgi türünü de değiştirme. |
| Determinizm | Aynı başlangıç durumu, komutlar ve seed ile aynı simülasyon sonucunu üretme özelliği. |
| Seed | Rastlantısal görünen fakat tekrar üretilebilir sonuçların başlangıç değeri. |
| Logbook | Oyuncu eylemleri, simülasyon sonuçları ve geliştirici müdahaleleri için yapılandırılmış olay günlüğü. |
| Yönetim aşaması | Founder Operations, Regional Operator ve Logistics Enterprise gibi oyuncunun karar ölçeğini belirleyen ilerleme katmanı. |
| CEO ölçeği | Oyuncunun tekil operasyon tekrarından kapasite, politika, portföy ve ağ kararlarına yükselmesi ilkesi. |

## Dil kullanımı

- Türkçe metinde **sözleşme** tercih edilir; kaynak alıntısında geçen “kontrat” aynı kavramı ifade eder.
- Teknik veri kimlikleri İngilizce ve kararlı; oyuncuya gösterilen metinler yerelleştirilebilir olmalıdır.
- “Rota”, aracın izlediği planı; “servis hattı”, şirketin sunduğu düzenli kapasiteyi ifade eder.
- “Depo” ile “şirket merkezi” birbirinin yerine kullanılmaz.

#gdd #gdd/sozluk
