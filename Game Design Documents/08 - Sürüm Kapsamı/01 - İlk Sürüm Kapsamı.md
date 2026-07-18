---
tür: Kapsam GDD
durum: Önerilen kapsam ve denge doğrulamasına tabi
kapsam: İlk ticari iOS sürümü
kaynaklar:
  - Ana Tasarım Özeti
  - docs/03_BROWSER_PROTOTIP_PLANI.md
  - docs/05_GORSEL_YON_VE_HARITA.md
  - web/README.md
son_güncelleme: 2026-07-17
etiketler: [gdd, sürüm-kapsamı, ios, v1]
---

# İlk Sürüm Kapsamı

## Kapsam ilkesi

İlk ticari sürüm, küçük bir şirketten çok bölgeli lojistik operatörüne uzanan anlamlı bir ilerleme sunmalıdır. Sayısal büyüklük, çekirdek döngünün anlaşılabilirliğini ve cihaz bütçesini aşamaz.

## Dünya hedefi

Ana tasarım özetindeki hedef:

- **yaklaşık 50–60 şehir,**
- **yaklaşık 10–15 ülke,**
- **yaklaşık 3–4 kıta**

olarak korunur; bu değerler **önerilen kapsam/denge doğrulamasına tabi**dır. Şehirlerin sayısından çok ekonomik rol, bağlantı çeşitliliği, başlangıç bölgesi dengesi ve taşıma modlarına anlamlı geçiş üretmesi önemlidir.

Browser prototipindeki yaklaşık 140 şehir bu hedefe dahil değildir. O veri seti prototip haritası ve bağlantı doğrulama alanıdır; V1 içerik taahhüdü değildir.

## Oyuncuya sunulan temel deneyim

- iPhone portrait native uygulama.
- Şirket adı, logo ve kurumsal renk ile kuruluş.
- Başlangıç şehri ve genel merkez seçimi.
- Az sayıda kara aracıyla doğrudan spot taşıma.
- Araçların teslimat şehrinde kalması, boş kilometre ve dönüş yükü.
- Düzenli müşteri sözleşmeleri ve hizmet sözü.
- Çift yönlü taşıma hatları, kapasite rezervasyonu ve konsolidasyon.
- Doğrudan ve aktarmalı taşıma planları.
- Şube, araç sahası, aktarma merkezi ve temel depo/dağıtım gelişimi.
- Kütle ve hacim temelli fiziksel yük/araç uygunluğu.
- Açıklanabilir finans, itibar, gecikme ve Logbook.
- Büyüdükçe tekil atamadan hat, politika ve yönetici tabanlı otomasyona geçiş.

## Taşıma modları

Ana tasarım özeti kara, demir, deniz ve hava taşımacılığını ilk sürüm önerisine dahil eder. Bu hedef şu teslim kapısına tabidir:

- Her mod yalnız farklı renk/araç değil, farklı maliyet-hız-kapasite-esneklik kararı üretmelidir.
- Kara çekirdeği eğlenceli ve dengeli olmadan diğer modlar üretim kapsamına alınmaz.
- Oyuncu önce dış hizmet ve kapasite satın alır; özel terminal yatırımı yüksek hacim/geç oyun içeriğidir.
- Her modun doğrudan ve intermodal zincirde anlaşılır bir rolü olmalıdır.

Kalite veya takvim riski oluşursa mod sayısı azaltılır; yüzeysel dört mod için çekirdek okunabilirlik feda edilmez.

## İçerik hedefleri

- Sınırlı fakat rolleri belirgin araç sınıfları ve değiştirilebilir ekipmanlar.
- Standart, soğuk zincir, değerli/güvenli, ağır ve seçili özel yükler.
- Spot işler, düzenli sözleşmeler; sınırlı ihale ve özel proje örnekleri.
- Haber verilen ve stratejiyi sınayan dünya olayları.
- Temel kredi, sabit/değişken gider, ceza ve kârlılık kırılımı.
- Algoritmik rakip baskısı veya düşük maliyetli NPC şirket görünürlüğü.
- İngilizce ana dil ve Türkçe tam destek hedefi; kesin dil listesi üretim planında doğrulanır.

## Teknik teslimatlar

- SwiftUI arayüz ve SpriteKit harita.
- UI’dan bağımsız saf Swift deterministik simülasyon.
- Veri odaklı kataloglar ve build-time doğrulama.
- SwiftData veya SQLite ile güvenilir yerel kayıt.
- CloudKit/iCloud senkronizasyon hedefi.
- Dynamic Type, VoiceOver, kontrast, Reduce Motion, 44×44 point dokunma hedefleri ve renk dışı kodlama.
- Desteklenen cihazlarda ölçülmüş simülasyon ve harita performans bütçesi.

## Kabul kapıları

- İlk karar 90 saniye içinde verilebilir.
- Oyuncu kâr/güvenilirlik/büyüme gerilimini anlayabilir.
- 20–30 dakikada farklı strateji deneme isteği oluşur.
- Hat ve sözleşme büyümesi tıklama sayısını doğrusal artırmaz.
- Hibrit simülasyon detaylı sonuçlarla deterministik eşdeğerlik testlerini geçer.
- Kayıt, migration ve iki cihaz çatışma senaryoları veri kaybetmez.
- En küçük hedef iPhone’da ana akışlar erişilebilir ve akıcıdır.

## İlişkili notlar

- [[08 - Sürüm Kapsamı/02 - Prototip Hipotezleri]]
- [[08 - Sürüm Kapsamı/03 - Sonraki Sürümler ve Kapsam Dışı]]
- [[07 - Teknik Tasarım/04 - Kayıt, iCloud ve Yaşam Döngüsü]]
- [[06 - UX ve Görsel Tasarım/03 - Erişilebilirlik ve Mobil Kullanım]]

#gdd #sürüm-kapsamı #ios #v1
