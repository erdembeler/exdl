# HariciKur 🚀

macOS için harici diske uygulama yükleme, otomatik DMG algılama ve akıllı kısayol yöneticisi.

Mac'lerde dahili SSD depolaması pahalı olduğu için büyük uygulamaları harici bir SSD/HDD'ye kurmak isteyebilirsiniz. İnternetten indirilen `.dmg` dosyaları varsayılan olarak `/Applications` klasörüne kopyalanır ve dahili diskte yer kaplar. **HariciKur**, bu süreci otomatikleştirerek uygulamaları doğrudan harici diskinize kurmanızı ve dahili diskinizde sadece Spotlight, Launchpad ve Dock ile %100 uyumlu hafif (~500 KB) **Akıllı Kısayol Paketleri (Smart App Stubs)** bırakmanızı sağlar.

---

## ✨ Özellikler

- 💿 **DMG Açıldığı Anda Yakalama:** Bir `.dmg` disk imajına çift tıkladığınız anda devreye girer. Dahili SSD'ye hiç yazmadan doğrudan harici diske kurabilir.
- 📂 **/Applications İzleme (FSEvents):** Klasik sürükle-bırak veya arşivden çıkarma ile `/Applications` klasörüne gelen yeni uygulamaları algılar ve harici diske taşımayı teklif eder.
- 🎯 **Akıllı Kısayol Paketi (Smart App Stub):** Klasik sembolik linkleri (`ln -s`) atlayan macOS Tahoe / Sequoia Uygulamalar çekmecesi (`Apps.app`), Launchpad ve Spotlight ile tam uyumludur. Harici disk takılı olmadığında dostça bir sistem uyarısı gösterir.
- 🔄 **Otomatik Güncelleme (Auto-Update) Koruması:** Uygulamalar kendilerini güncellerken kısayolu silip gerçek dosya yazarsa, HariciKur bunu fark edip güncel sürümü otomatik olarak harici diske senkronize eder.
- 🖱️ **Apple DMG Tarzı Sürükle-Bırak Sahnesi:** Kurulum penceresinde uygulamayı farenizle tutup doğrudan hedef diske sürükleyebileceğiniz etkileşimli Apple tarzı arayüz (Demo Modu desteğiyle).
- 📊 **Depolama Yöneticisi:** Dahili `/Applications` içindeki tüm uygulamalarınızı tek ekranda listeleyip tek tıkla **"Hariciye Taşı"** veya **"Dahiliye Al"** yapma imkânı.
- ⚡ **Sistem Ayarları Entegrasyonu:** Menü çubuğu (Menu Bar) simgesi, macOS Girişinde Otomatik Başlatma (`SMAppService`) ve minimum boyut filtresi.

---

## 🛠️ Kurulum ve Derleme

### Hazır Dağıtım DMG'si
Proje kök dizinindeki `dist/HariciKur-1.0.0.dmg` dosyasını açıp `HariciKur` ikonunu `Applications` klasörüne sürüklemeniz yeterlidir.

### Kaynaktan Derleme
```bash
git clone https://github.com/kullanici/HariciKur.git
cd HariciKur

# Uygulama paketini derlemek için:
./build_app.sh

# Dağıtım DMG ve ZIP paketlerini oluşturmak için:
./package_release.sh
```

---

## 🏗️ Mimari ve Teknolojiler

- **Dil & Arayüz:** Swift 6.0, SwiftUI, AppKit
- **Disk İmajı Denetimi:** `hdiutil` plist ayrıştırma
- **Dosya İzleme:** CoreServices `FSEventStream` & `NSWorkspace.didMountNotification`
- **İzinler:** App Sandbox gerektirmeyen ad-hoc kod imzalama, LaunchServices `lsregister` ve `mdimport`
- **Başlangıç Servisi:** macOS `ServiceManagement.SMAppService`
