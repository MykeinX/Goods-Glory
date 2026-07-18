---
tür: GDD - sistem tasarımı
durum: Temel tesis modeli kabul edilmiş; belirtilen önkoşullar açık
kapsam: Merkez, depo, terminal, kapasite, modül ve uzmanlaşma
kaynaklar:
  - docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md
  - docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - tesisler
  - depolar
---

# Tesisler

#gdd #tesisler #depolar

## Merkez ofis ve depo ayrımı

### Şirket merkezi

- yasal ve stratejik evdir;
- şirket çapı yönetim kapasitesi sağlar;
- departman ve merkez personeli barındırır;
- sınırlı kiralık hafif araç sahası sunabilir;
- yük depolamaz;
- ağır filo, cross-dock veya sürekli şehir dağıtımı işletmez.

### Operasyon deposu

- yük kabul eder, bekletir ve sevk eder;
- araç ve ekipman üssüdür;
- konsolidasyon/cross-dock yapar;
- yerel dağıtımı ve servis hatlarını besler;
- fiziksel personel ve yöneticiyi barındırır.

Depo kuruluşun zorunlu ilk adımı değildir. İlk araç, merkez ofisin sınırlı sahasından doğrudan müşteri-müşteri işi yapabilir.

## Depo kapasite bileşenleri

- depolama kapasitesi;
- giriş/çıkış işleme;
- cross-dock;
- yükleme kapıları;
- araç parkı;
- ekipman/dorse parkı;
- yerel dağıtım;
- yönetici kontrol kapasitesi.

Bu değerler ayrı darboğazlar üretir. Depo stokta boş olsa bile kapı veya personel yetersizliğinden kuyruk yaşayabilir.

## Seviye ve modüller

Her şehirde anlaşılır bir temel depo kurulur. Seviye; alanı, kapıları, parkı ve modül yuvalarını büyütür.

Genel modüller:

- forklift paketi: işlem süresini azaltır;
- depo ekibi: işleme ve düzeni geliştirir;
- yönetici ofisi: tesis yöneticisini açar;
- bakım alanı: filo bakım kabiliyeti sağlar;
- ekipman park uzantısı: dorse ve modüler ekipman kapasitesi ekler.

Modüller yalnızca soyut yüzde bonusu değil, fiziksel kabiliyet veya darboğaz çözümüdür.

## Ana uzmanlıklar

Seviye 2'de bir ana rol seçilmesi mevcut temel modeldir:

### Şehir Dağıtım Merkezi

- son kilometre ayrıştırma;
- sürekli şehir hizmet sözleşmeleri;
- yerel filo ve dağıtım dalgaları.

### Bölgesel Yük Hub'ı

- depolar arası ana hat;
- daha geniş iş havuzu;
- konsolidasyon ve gidiş-dönüş kapasitesi.

### Transit Aktarma Terminali

- cross-dock;
- çok duraklı ve geçiş yükü;
- hızlı araç/hat değişimi.

**Açık konu:** Olgun deponun ikinci bir yan uzmanlık kazanıp kazanamayacağı ve bunun koşulları kesinleşmemiştir. Mevcut GDD bunu açılmış özellik gibi kabul etmez.

## Yük kuyrukları

Tesis en az şu kümeleri izler:

- boşaltma bekleyen gelen yük;
- cross-dock;
- depolanan;
- sonraki servis hattını bekleyen;
- kalkış kapasitesi ayrılmış;
- yerel dağıtıma hazır;
- geciken veya uyumsuz yük.

Oyuncuya her palet gösterilmez; miktar, bekleme, risk ve sıradaki çıkış görünür.

## Tesis kurma ve coğrafi erişim

Tesis maliyeti şehir arazi/işletme profilinden etkilenir. Uygun bağlantısı olmayan şehirde liman, hava veya demiryolu işlemi açılamaz.

Uzak şehirde yeni şube veya depo kurmak için o şehirde şirket aracı bulunması gerekmez. Kuruluş; nakit, kurulum süresi, yerel izinler ve stratejik erişim koşullarıyla sınırlandırılır. Bu karar, boş araç gönderimini zorunlu bir tıklama engeline dönüştürmeden genişlemenin maliyet ve zaman riskini korur.

## Kullanım ve verimlilik

- `%0–40`: düşük kullanım, sabit maliyet baskısı;
- `%40–65`: kullanılmayan yatırım;
- `%65–85`: sağlıklı ilk hedef;
- `%85–100`: yüksek getiri, düşük tampon;
- `%100+`: aşırı yük ve gecikme riski.

Bu bantlar ilk denge referansıdır. Yönetici kötü konumlandırılmış veya hacimsiz tesisi sihirli biçimde kârlı yapmaz.

## Terminaller ve bağlantılar

Depo; bağlantı anlaşması veya modülle demiryolu yük terminali, liman ya da hava kargo terminaline besleme düğümü olabilir. Şehirde bağlantının varlığı önkoşuldur; kalite ve kapasite ilgili tesis/slot üzerinde modellenir.

## İlgili belgeler

- [[04 - Doğrudan ve Aktarmalı Taşıma]]
- [[03 - Kapasite ve Hibrit Simülasyon]]
- [[03 - Araçlar ve Ekipman]]
- [[05 - Multimodal Taşımacılık]]
- [[07 - Çalışanlar, Yöneticiler ve Otomasyon]]
