---
tür: GDD - sistem tasarımı
durum: Kanonik yön; prototip sonrası kademeli uygulama
kapsam: Kara, demiryolu, deniz ve hava taşıma zincirleri
kaynaklar:
  - docs/09_ARZ_TALEP_SOZLESME_VE_YONETIM_OMURGASI.md
  - docs/10_DEPO_MERKEZLI_COK_ASAMALI_YUK_AGI.md
  - "[[01 - Kanonik Lojistik Nesne Modeli]]"
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - multimodal
  - taşımacılık
---

# Multimodal Taşımacılık

#gdd #multimodal #taşımacılık

## Tasarım ilkesi

Kara, demiryolu, deniz ve hava aynı sistemin farklı renkli araçları değildir. Hepsi aynı kanonik yük zincirini kullanır; kapasite, esneklik, takvim, maliyet, terminal bağımlılığı ve risk davranışları farklıdır.

## Modların stratejik rolleri

- **Kara:** esnek, kapıdan kapıya, orta kapasite; trafik ve sürücü/bakım bağımlılığı.
- **Demiryolu:** yüksek hacim ve verim; sabit terminal, koridor ve takvim.
- **Deniz:** çok yüksek kapasite ve düşük birim maliyet; uzun süre, liman ve sefer bağımlılığı.
- **Hava:** yüksek hız; düşük hacim, yüksek maliyet ve sıkı terminal/güvenlik gereksinimi.

## Uçtan uca zincir

Örnek kıtalar arası hizmet:

1. Üreticiden kara aracıyla toplama.
2. Bölgesel depoda konsolidasyon.
3. Limana kara veya demiryolu besleme.
4. Terminal elleçlemesi.
5. Deniz ana hattı.
6. Varış terminalinde aktarma.
7. İç bölgeye demiryolu veya kara.
8. Son şehir deposunda ayrıştırma.
9. Yerel araçlarla nihai teslim.

Müşteri tek uçtan uca sözleşme görür. Her adım ayrı taşıma aşamasıdır ve bir servis hattı/dış taşıyıcı kapasitesiyle karşılanır.

## Erişim ve sahiplik basamakları

Yeni mod açıldığında dev araç satın almak zorunlu değildir:

1. spot dış kapasite;
2. dönemlik slot veya kapasite anlaşması;
3. uzun dönem kiralama/tahsis;
4. ileri aşamada doğrudan sahiplik veya iştirak.

Bu ilerleme, sermaye eşiğini oynanabilir tutar ve oyuncuya önce ağ kararını öğretir.

## Düğüm önkoşulları

- Demiryolu aşaması iki uçta yük terminali veya bağlantılı intermodal tesis ister.
- Deniz aşaması uygun ticari limanlar veya besleme zinciri ister.
- Hava aşaması kargo terminali ve handling/güvenlik erişimi ister.
- Kara aşaması yol bağlantısı ve operasyon kabiliyeti ister.

Şehir bağlantısı ikilidir: vardır veya yoktur. Kapasite ve kalite bağlantı anlaşması, terminal ve slotta modellenir.

## Konteynerleşme

Standart konteyner aynı yük birimini:

- konteyner dorsesi;
- tren;
- gemi

arasında yükü açmadan aktarabilir. Karşılığında ekipman, terminal, slot ve yetki gerekir. Konteyner hız ve hasar avantajı sunar; her yük için otomatik en iyi çözüm değildir.

## Takvim ve bağlantı riski

Multimodal zincirde her aşama:

- kalkış penceresi;
- transit süresi;
- elleçleme;
- bağlantı tamponu;
- kapasite rezervasyonu;
- güvenilirlik ve olay riski

taşır. Bir tren/gemi/uçak kaçırılırsa sonraki slot beklenir; bekleme maliyeti ve SLA etkisi oluşur. Oyuncu ucuz-kırılgan ve pahalı-tamponlu plan arasında karar verir.

## Kapasite ve dış taşıyıcı

Dış kapasite fiziksel olmayan bir “tamamla” düğmesi değildir. Sağlayıcı:

- mod ve koridor;
- slot takvimi;
- ayrılmış kapasite;
- fiyat;
- güvenilirlik;
- iptal/olay davranışı

taşır. Yük partisi sağlayıcının fiziksel kalkışına yerleştirilir.

## Uygulama sırası

1. kara içi depo bırak/al;
2. düzenli depolar arası kara hattı;
3. ilk demiryolu veya deniz geçidi;
4. dış taşıyıcı spot kapasitesi;
5. dönemlik slot;
6. bağlantı kaçırma ve yeniden planlama;
7. kıtalar arası zincir;
8. ileri sahiplik.

Hava, demiryolu ve deniz doğrusal teknoloji sırası olmak zorunda değildir; şehir ve müşteri portföyü seçimi yönlendirir.

## İlgili belgeler

- [[04 - Doğrudan ve Aktarmalı Taşıma]]
- [[04 - Tesisler]]
- [[03 - Kapasite ve Hibrit Simülasyon]]
- [[06 - Ekonomi ve Finans]]
- [[09 - Dünya Olayları ve Risk]]
