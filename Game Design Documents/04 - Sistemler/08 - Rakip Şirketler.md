---
tür: GDD - sistem tasarımı
durum: Kademeli öneri; bağımsız tam AI ertelenmiş
kapsam: Rekabet baskısı, pazar payı ve rakip davranışı
kaynaklar:
  - docs/02_OYUN_TASARIMI.md
  - docs/04_KARARLAR_VE_ACIK_SORULAR.md
  - "[[01 - İşler, Müşteriler ve Sözleşmeler]]"
son_güncelleme: 2026-07-17
etiketler:
  - gdd
  - rakipler
  - rekabet
---

# Rakip Şirketler

#gdd #rakipler #rekabet

## Amaç

Rakipler yaşayan pazar ve stratejik baskı üretir. Oyuncunun fiziksel ağıyla aynı ayrıntıda yüzlerce rakip araç simüle etmek ilk aşamada gerekli değildir.

## Kademeli model

### 1. Pazar baskısı

İlk prototipte şehir-yük-koridor bazında görünür rekabet seviyesi:

- teklif sayısını;
- fiyat/marj aralığını;
- müşteri beklentisini;
- yenileme olasılığını

etkiler. Değişimin nedeni olay veya rakip hamlesi olarak açıklanır.

### 2. Adlandırılmış rakip profilleri

Rakipler farklı strateji taşır:

- düşük fiyat/yüksek hacim;
- yüksek güvenilirlik;
- ekspres;
- özel yük;
- geniş coğrafi kapsama;
- multimodal ölçek.

Profil, hangi pazarda baskı kuracağını ve hangi olaya nasıl tepki vereceğini belirler.

### 3. Stratejik varlıklar

İleri aşamada rakiplerin:

- güçlü olduğu bölgeler;
- ana tesis/terminal erişimleri;
- kapasite anlaşmaları;
- müşteri portföyü;
- mali sağlık durumu

izlenebilir. Her aracı fiziksel olarak simüle etmek yerine sonuç eşdeğerliğine uygun bölgesel kapasite modeli kullanılabilir.

### 4. Bağımsız rakip AI

Yalnızca oyuncu ekonomisi ve sözleşme ağı kendi başına eğlenceli olduğunda eklenir. Tam AI kesinleşmiş ilk sürüm özelliği değildir.

## Rekabet eylemleri

- belirli koridorda fiyat baskısı;
- büyük müşteriye teklif;
- terminal slotu veya kapasite anlaşması;
- kriz sırasında kapasite çekme/ekleme;
- yeni bölgeye giriş;
- şirket satın alma veya ortaklık;
- itibar kampanyası.

Eylemler görünür sinyaller ve karşı hamleler üretmelidir. Rakip, oyuncunun sözleşmesini açıklamasız şekilde çalamaz.

## Pazar payı

Pazar payı tek zafer sayacı değildir. Şehir, ürün grubu ve hizmet sınıfı bazında:

- taşınan hacim;
- aktif müşteri ilişkisi;
- güvenilirlik;
- erişilebilir kapasite

üzerinden tahmin edilir. Yüksek pay; gelir yanında fiyat savaşı, regülasyon ve kapasite baskısı doğurabilir.

## Adalet ve bilgi

Oyuncu:

- rakibin bilinen güçlü yönünü;
- pazar değişiminin kaynağını;
- tahmini kapasite/fiyat baskısını;
- karşılık seçeneklerini

görür. Rakipler oyuncudan farklı sadeleştirilmiş simülasyon kullanabilir, ancak bedava kaynak veya kural ihlali sonucu üretmemelidir.

## Karşı hamleler

- hizmet kalitesini artırma;
- farklı müşteri segmentine yönelme;
- uzun dönem kapasite güvenceye alma;
- maliyet düşüren konsolidasyon;
- stratejik ortaklık;
- fiyat savaşından çekilme;
- güvenilirlik/özel yük kimliği geliştirme.

En düşük fiyat her zaman doğru cevap değildir.

## İlgili belgeler

- [[01 - İşler, Müşteriler ve Sözleşmeler]]
- [[05 - Multimodal Taşımacılık]]
- [[06 - Ekonomi ve Finans]]
- [[09 - Dünya Olayları ve Risk]]
- [[10 - Şirket Politikaları ve İtibar]]
