---
tür: GDD - sistem tasarımı
durum: Tek tesis + modül modeli kabul edildi (2026-07-20 akış revizyonu)
kapsam: Tesis, modüller, eklentiler, kapasite ve uzmanlaşma
kaynaklar:
  - docs/07_MERKEZ_DEPO_IS_TURLERI_VE_SOZLESMELER.md
  - docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - "`AKIS_VE_HAT_REVIZYONU_PLAN.md` (2026-07-20 akış revizyonu)"
son_güncelleme: 2026-07-20
etiketler:
  - gdd
  - tesisler
  - depolar
---

# Tesisler

#gdd #tesisler #depolar

## Tek tesis modeli

Bir şehirde şirketin **tek tesisi** olur; yetenekleri modüller belirler. "Şube" ve "depo" ayrı yapı türleri değildir — aynı tesisin farklı modülleridir.

Temel modüller:

- **Ofis:** yerel ticari temsil, sözleşme teklif yuvaları, hat primi. Yük depolamaz.
- **Depo:** yük kabul eder, bekletir, sevk eder; konsolidasyon/cross-dock alanıdır.
- **Dok:** eşzamanlı yükleme/boşaltma ve araç çevirme hızı.
- **Otopark:** araç, dorse ve modüler ekipman barındırma. *(Henüz uygulanmadı: filo park sınırı gibi bunu kullanacak bir kısıt tanımlanmadan modül eklenmez.)*

Elleçleme süresi depo ve dok çarpanlarının çarpımıdır: aynı bütçe derin bir depoya da hızlı bir cross-dock'a da dönüşebilir; ikisi birden isteniyorsa iki modül birden kurulur. Tesis stratejisi bu seçimden doğar.

Şirket merkezi (HQ), kuruluşta küçük ofis + otopark modülleriyle gelen ilk tesistir; satılamaz. Depo modülü kuruluşun zorunlu ilk adımı değildir: ilk araç, merkezin sınırlı sahasından doğrudan müşteri-müşteri taşıması yapabilir.

### Modül, eklenti ve seviye — uzmanlaşma buradan doğar

İki gelişim ekseni vardır:

- **Modül seviyesi** kapasiteyi büyütür (depo sv2 = daha çok ton/m³, ofis sv2 = daha çok teklif yuvası).
- **Eklenti** (modüle takılır, kendi seviyesi olabilir) niteliği değiştirir: forklift paketi → elleçleme hızı; ek dok → eşzamanlı servis; soğuk oda → ürün yeteneği; depo ekibi → işleme düzeni; bakım alanı → filo bakımı; park uzantısı → ekipman kapasitesi.

Her modül ve eklentinin etkisi **tek ve fiziksel** bir değere bağlanır (süre, kapasite, yetenek bayrağı); soyut bileşik yüzde bonusu kullanılmaz. Aynı seviyedeki iki depo, farklı eklenti dizilişiyle farklı karakter kazanır (hız deposu vs hacim deposu) — uzmanlaşma ayrı bir "rol seçme" mekaniği değil, oyuncunun yatırım dizilişinin doğal sonucudur. Şehir Dağıtım Merkezi / Bölgesel Hub / Transit Terminal profilleri hedeflenebilir sonuç örnekleridir, seçilen sınıflar değildir.

## Tesis kapasite bileşenleri

- depolama kapasitesi;
- giriş/çıkış işleme;
- cross-dock;
- yükleme kapıları;
- araç parkı;
- ekipman/dorse parkı;
- yerel dağıtım;
- yönetici kontrol kapasitesi.

Bu değerler ayrı darboğazlar üretir. Depo stokta boş olsa bile kapı veya personel yetersizliğinden kuyruk yaşayabilir. Modüller yalnızca soyut yüzde bonusu değil, fiziksel kabiliyet veya darboğaz çözümüdür.

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

Tesis ve modül maliyeti şehir arazi/işletme profilinden (maliyet endeksi, nüfus, erişim bayrakları) türetilir; sabit fiyat yoktur. Uygun bağlantısı olmayan şehirde liman, hava veya demiryolu işlemi açılamaz.

Uzak şehirde tesis kurmak için o şehirde şirket aracı bulunması gerekmez. Kuruluş; nakit, kurulum süresi, yerel izinler ve stratejik erişim koşullarıyla sınırlandırılır. Bu karar, boş araç gönderimini zorunlu bir tıklama engeline dönüştürmeden genişlemenin maliyet ve zaman riskini korur.

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
