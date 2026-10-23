<div align="center">

<p align="center">
  <a href="README.md">English</a> ·
  <strong>Türkçe</strong> ·
  <a href="README_JA.md">日本語</a> ·
  <a href="README_ZH.md">简体中文</a> ·
  <a href="README_ES.md">Español</a>
</p>

<img src="assets/icon.png" width="128" height="128" alt="EXdl simgesi">

# EXdl
### macOS Harici Disk İndirme ve Uygulama Yöneticisi

**Mac uygulamalarını doğrudan harici diskinize kurun, Launchpad ve Spotlight uyumluluğunu kaybetmeyin.**

<br>

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white)](#gereksinimler)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-0A84FF?style=flat-square)](#gereksinimler)
[![Sürüm](https://img.shields.io/badge/S%C3%BCr%C3%BCm-v1.1.1-blue?style=flat-square)](https://github.com/erdembeler/exdl/releases/latest)
[![Notarized](https://img.shields.io/badge/Apple-notarized-34C759?style=flat-square)](#kurulum)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white)](Package.swift)
[![MIT Lisansı](https://img.shields.io/badge/Lisans-MIT-yellow?style=flat-square)](LICENSE)

[**Son Sürümü İndir**](https://github.com/erdembeler/exdl/releases/latest) &nbsp;·&nbsp; [Nasıl Çalışır?](#nasıl-çalışır) &nbsp;·&nbsp; [İzinler](#izinler-ve-nedenleri) &nbsp;·&nbsp; [Kaynak Koddan Derleme](#kaynak-koddan-derleme)

</div>

<br>

EXdl, harici SSD sürücünüzü macOS ekosisteminin doğal bir parçası haline getiren hafif ve yerel bir menü çubuğu uygulamasıdır.

---

## Yaşanan Problem

Mac bilgisayarlarda dahili SSD depolaması sonradan yükseltilemez. Geliştirici araçları, 3B modelleme yazılımları, oyun motorları ve oyunlar gibi yüksek boyutlu uygulamalar dahili depolamayı hızla doldurur.

macOS üzerinde bir `.dmg` dosyası açıldığında sunulan sürükle-bırak penceresi yalnızca dahili diskteki `/Applications` klasörünü hedefler. Uygulamayı elle harici diske taşıyıp dahili diske kısayol veya sembolik bağ (symlink) oluşturulduğunda ise şu sorunlar ortaya çıkar:
- macOS Launchpad, Spotlight ve macOS Sequoia Uygulamalar listesi sembolik bağları düzgün indeksleyemez; uygulama görünmez veya aramalarda çıkmaz.
- Harici disk takılı değilken kısayola tıklandığında uygulama sessizce açılmaz veya anlamsız sistem hataları verir.
- Uygulama arka planda kendini güncellediğinde, güncelleme aracı harici diskteki bağlantıyı ezip dahili SSD'ye tam bir kopya yazar; dahili disk alanı fark edilmeden tekrar dolar.

---

## Nasıl Çalışır?

<p align="center">
  <img src="assets/how-it-works.svg" width="720" alt="EXdl kurulum ve akıllı başlatıcı işleyişi">
</p>

EXdl kırılgan sembolik bağlar kullanmaz. Bunun yerine **Akıllı Başlatıcı (Smart App Stub)** mimarisini kullanır:
1. Bir `.dmg` disk imajı açıldığında EXdl bunu otomatik algılar ve doğrudan harici SSD'nizi hedefleyen yerel bir kurulum penceresi sunar.
2. Uygulama paketinin tamamı harici diskinize kopyalanır.
3. `/Applications` klasörüne orijinal uygulamanın ikonunu, meta verilerini ve kimliğini taşıyan yaklaşık 500 KB boyutunda yerel bir başlatıcı yerleştirilir.
4. Launchpad, Spotlight ve Dock bu başlatıcıyı gerçek bir uygulama olarak tanır.
5. Harici disk takılı değilken uygulamayı açmak istediğinizde sistem kilitlenmez; EXdl diski bağlamanızı belirten anlaşılır bir uyarı penceresi açar.

---

## Öne Çıkan Özellikler

- **Otomatik Disk İmajı Algılama** — Açılan `.dmg` dosyalarını yakalar, harici diske tek tıkla kurulum sunar ve işlem bittiğinde disk imajını masaüstünden otomatik çıkarır.
- **Otomatik Güncelleme Koruması** — Bir uygulama güncellenirken başlatıcıyı silip dahili diske kurulursa, EXdl bunu tespit eder ve güncellenen sürümü tekrar harici diske taşır.
- **Depolama Yöneticisi ve Taşıma Paneli** — Dahili ve harici disklerinizdeki uygulamaları listeleyin. Dahili diskteki mevcut uygulamaları tek tıkla hariciye taşıyın veya dilediğinizde dahiliye geri alın.
- **Uyumsuz Uygulama Koruması** — Harici diske taşındığında sistemle entegrasyonu bozulacak uygulamalar (Xcode, Apple sistem araçları, macOS Sistem Uzantısı veya oturum açılışı arka plan servisi barındıran araçlar) otomatik tespit edilir ve taşınması engellenir.
- **10 Menü Çubuğu İkon Tasarımı** — Ayarlar altından 10 farklı Retina vektör ikondan dilediğinizi seçin (varsayılan: EX Monogram). İzleme etkinken ikonların içi dolu, duraklatıldığında çizgisel/içi boş olarak net bir biçimde görünür.
- **Dahili OTA Yazılım Güncelleme** — GitHub Releases üzerinden yeni sürümleri denetler, kod imzasını doğrular ve uygulamayı tek tıkla yerinde günceller.
- **Hafif ve Gizlilik Odaklı** — Menü çubuğundan sessizce çalışır, sistem kaynaklarını tüketmez, güncelleme denetimi dışında hiçbir ağ trafiği oluşturmaz.

---

## Karşılaştırma Tablosu

| Özellik | Standart macOS | Elle Sembolik Bağ | EXdl ile |
| :-- | :-- | :-- | :-- |
| **DMG Kurulum Hedefi** | Yalnızca dahili disk | Elle taşıma gerektirir | Doğrudan harici diske tek tıkla kurulum |
| **Launchpad ve Spotlight** | Desteklenir | Çoğunlukla indekslenmez | Eksiksiz ve yerel destek |
| **Disk Takılı Değilken** | Uygulanamaz | Hata vermeden kapanır | Açıklayıcı disk bağlantı uyarısı |
| **Uygulama Güncellemeleri** | Dahili diske yazar | Bağlantıyı bozar | Otomatik olarak hariciye taşınır |
| **Dahili SSD Kazancı** | 0 GB | Yüksek ancak kararsız | Tam tasarruf, kararlı ve yerel |

---

## İzinler ve Nedenleri

EXdl'in görevini eksiksiz yerine getirebilmesi için macOS tarafından sağlanan iki izne ihtiyaç vardır:

1. **Uygulama Yönetimi (`App Management`) — Zorunlu**
   - **Neden gerekli:** EXdl'in `/Applications` dizini altında hafif başlatıcı paketleri oluşturabilmesi ve uygulamaları harici diske taşıyabilmesi için bu izin şarttır.
   - **Nasıl verilir:** *Sistem Ayarları → Gizlilik ve Güvenlik → Uygulama Yönetimi* bölümünden EXdl anahtarını açın. Listede görünmüyorsa sol alttaki `+` butonuna tıklayıp Applications klasöründen EXdl'i ekleyin.
2. **Tam Disk Erişimi (`Full Disk Access`) — Önerilen**
   - **Neden gerekli:** İndirilenler klasöründeki disk imajlarını okurken ve harici diske yazarken macOS'in her klasör için tekrar tekrar izin sormasını önler.
   - **Nasıl verilir:** *Sistem Ayarları → Gizlilik ve Güvenlik → Tam Disk Erişimi* bölümünden EXdl anahtarını açın.

---

## Kurulum

1. [GitHub Releases](https://github.com/erdembeler/exdl/releases/latest) sayfasından en son sürümü indirin (`EXdl-1.1.1.dmg` veya `EXdl-1.1.1.zip`).
2. İndirilen DMG dosyasını açın ve **EXdl** uygulamasını **Applications** klasörüne sürükleyin.
3. EXdl'i başlatın. İlk çalıştırma yardımcısı dil seçimi, hedef harici disk ve izin adımlarında size rehberlik edecektir.
4. Kurulum tamamlandıktan sonra EXdl ekranınızın sağ üst menü çubuğunda çalışmaya başlayacaktır.

Tüm dağıtım paketleri resmi Apple Developer ID sertifikası ile imzalanmış ve Apple tarafından noter onayından (notarization) geçirilmiştir.

---

## Gereksinimler

- macOS 14 Sonoma veya üzeri
- Apple Silicon işlemcili Mac (M1 / M2 / M3 / M4)
- **APFS** (önerilen) veya **Mac OS Genişletilmiş (Günlüklü)** biçiminde harici disk

---

## Kaynak Koddan Derleme

```bash
git clone https://github.com/erdembeler/exdl.git
cd exdl

# Uygulama paketini derle
./build_app.sh

# Dağıtım paketlerini (DMG ve ZIP) oluştur
./package_release.sh
```

---

## Lisans

Bu proje [MIT Lisansı](LICENSE) kapsamında sunulmaktadır.
