---
tür: GDD
durum: kabul-edildi
kapsam: Dünya yapısı, şehirler ve coğrafi açılımlar
kaynaklar:
  - "`Taslak_fikir.md`"
  - "`docs/01_URUN_VIZYONU.md`"
  - "`docs/02_OYUN_TASARIMI.md`"
  - "`docs/04_KARARLAR_VE_ACIK_SORULAR.md`"
  - "Kullanıcının 2026-07-17 tarihli Ana Tasarım Özeti"
son_güncelleme: 2026-07-18
etiketler:
  - gdd
  - gdd/ilerleme
  - gdd/dünya
  - gdd/şehirler
---

# Dünya, Şehirler ve Açılımlar

#gdd #gdd/ilerleme #gdd/dünya

## Dünya Vizyonu

Nihai ürün global pazara yönelik, gerçek dünya coğrafyasından ve ana ulaşım koridorlarından yararlanan stilize bir lojistik dünyasıdır.

- Şehirler veriden ortaya çıkan ekonomik karakterleri ve bağlantılarıyla ayrışır.
- Ana kara, demir, deniz ve hava koridorları tanınabilir ilişkilere dayanır.
- Görsel ve operasyonel doğruluk, iPhone portrait okunabilirliği için kontrollü biçimde sadeleştirilir.
- Gerçekçilik oynanabilirliğin ve şeffaf kararların önüne geçmez.

## Şehirlerin Oyun İşlevi

Her şehir yalnızca harita düğümü değildir; ancak statik şehir tanımı küçük ve nesneldir. Kimlik, coğrafya ve yol grafı bağlantısının yanında şu başlangıç verilerini taşır:

- nüfus,
- demir yolu yük erişimi ve hava kargo erişimi için boolean bayraklar,
- 1000 tabanlı maliyet endeksi,
- 1000 tabanlı trafik gecikme endeksi.

Talep hesabındaki nüfus, belediye sınırı yerine şehrin adreslenebilir
pazar/servis alanını temsil eder. Bütün şehirler aynı coğrafi kapsam kuralıyla
üretilir; city-proper ve metro değerleri aynı katalogda karıştırılmaz.

Şehir tanımı rol veya tag saklamaz. “Üretim merkezi”, “tüketim pazarı” veya “dağıtım merkezi” gibi ekonomik karakter; ürün arz/talep ağırlıkları, nüfus, erişim bayrakları, maliyet ve bağlantıların birleşiminden ortaya çıkar.

Demir yolu ve hava erişim bayrakları yalnızca statik başlangıç kabiliyeti metadatasıdır; terminal kapasitesi veya servis kalitesi simülasyonu değildir. Olaylar, mevsimsellik, talep şokları, rekabet ve geçici trafik etkileri runtime durumunda dinamik değiştirici olarak tutulur ve statik şehir kataloğuna geri yazılmaz.

Maliyet endeksi doğrudan inşaat maliyeti verisi değil, yapı ve yerel operasyon
formüllerinde kullanılacak normalize edilmiş oyun vekilidir. Trafik endeksi de
statik başlangıç vekilidir; günün saati ve olaylar bu değeri runtime'da
değiştirir.

## Başlangıç Bölgesi

Oyuncu farklı stratejik özelliklere sahip birkaç başlangıç şehrinden birini seçer. Seçim:

- ilk müşteri türlerini,
- yakın şehirleri,
- maliyetleri,
- büyüme yollarını

etkiler; tek doğru başlangıç yaratmaz.

Browser prototipindeki kurgusal ve sınırlı bölge, doğrulama kapsamıdır; nihai dünya vizyonunun yerine geçmez.

## Coğrafi Açılım

Yeni şehir veya ülkeye açılmak yalnızca para ödenen kilit değildir. Uygun koşulların birleşimini ister:

- itibar ve hizmet geçmişi,
- bağlantı veya taşıyıcı erişimi,
- yeterli nakit/finansman,
- ilgili lisans ve uyum kabiliyeti,
- yerel şube, ortak veya tesis kararı,
- operasyonu destekleyecek yönetim kapasitesi.

Kesin eşikler denge parametresidir.

## Yeni Pazara Giriş Yöntemleri

Oyuncu ölçeğe göre:

- dış taşıyıcıyla hizmet satın alabilir,
- yerel ortak kullanabilir,
- kapasite anlaşması yapabilir,
- şube veya tesis kiralayabilir,
- kendi operasyonunu kurabilir,
- geç oyunda ortaklık veya satın alma yapabilir.

Bu kademeli model, yeni taşıma türlerinde de geçerlidir: önce hizmet erişimi, sonra kapasite sözleşmesi, kiralama ve yalnızca yeterli hacimde doğrudan sahiplik.

## Taşıma Modlarının Açılması

### Kara

Başlangıç modu; esnek, doğrudan ve orta ölçekli operasyon sağlar.

### Demir Yolu

Yüksek hacim ve düşük birim maliyet; terminal, tarifeye uyum ve ilk/son kilometre bağlantısı ister.

### Deniz

Çok yüksek hacim ve uzun süre; liman, konteyner, aktarma ve gecikme riskiyle çalışır.

### Hava

Yüksek hız ve maliyet; düşük hacim, güvenlik ve terminal erişimi gerektirir.

### Şehir İçi Son Kilometre

Dağıtım merkezi, küçük araçlar, teslimat yoğunluğu ve zaman pencereleri üzerinden ayrı karar alanı üretir.

## İlk Sürüm Kapsamı

Ana tasarım özeti ilk sürüm için yaklaşık 50–60 şehir, 10–15 ülke ve 3–4 kıta yönü verir.

**Öneri / kapsam hipotezi:** Bu sayılar içerik üretimi, cihaz performansı ve çekirdek sistemlerin olgunluğuna göre doğrulanmalıdır; kabul edilmiş kesin içerik taahhüdü değildir. Önce her şehrin anlamlı ekonomik karakter ve rota kararı üretmesi sağlanmalıdır.

## Dünya Açılımlarının Okunabilirliği

Oyuncu yeni pazar öncesinde şunları görür:

- potansiyel talep ve müşteri türleri,
- bağlantı ve süre,
- tahmini sabit yatırım,
- lisans/uyum ihtiyacı,
- rekabet ve risk,
- önerilen giriş yöntemleri.

## İlgili Notlar

- [[01 - Şirket Büyüme Aşamaları]]
- [[03 - Yük Türleri ve Özel Operasyonlar]]
- [[01 - Ürün Vizyonu/03 - Hedef Oyuncu ve Platform|Hedef Oyuncu ve Platform]]
- [[02 - Çekirdek Oynanış/01 - Ana Oynanış Döngüsü|Ana Oynanış Döngüsü]]
