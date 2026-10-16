# EXdl (External Download & Install Manager)

macOS işletim sisteminde uygulamaları doğrudan harici disklere kurmayı sağlayan, otomatik DMG tespiti, yerel sürükle-bırak sahnesi ve Spotlight ile tam uyumlu Akıllı Vekil Paket (Smart App Stub) mimarisine sahip açık kaynaklı bir yardımcı araçtır.

---

## Yaşanan Problem ve Geliştirilme Nedeni

Mac bilgisayarlarda dahili SSD depolaması fabrika çıkışında sınırlıdır ve sonradan fiziksel olarak yükseltilemez. Xcode, Android Studio, Docker, Unreal Engine, Blender veya büyük oyunlar gibi onlarca gigabaytlık araçlar kurulduğunda dahili disk hızla tükenir.

Bu noktada harici hızlı bir SSD/NVMe sürücü kullanmak en yaygın çözümdür; ancak macOS kullanıcı deneyimi harici diske uygulama yüklerken ciddi engeller çıkarır:

1. **DMG Kalıplarındaki Sürükle-Bırak Sınırlaması:**
   İnternetten indirilen bir `.dmg` dosyası açıldığında geleneksel Apple kurulum penceresi gösterilir. Bu penceredeki kısayol sadece dahili diskteki `/Applications` klasörüne işaret eder. Uygulamayı harici bir diske kurmak isteyen bir kullanıcı bu pencereden yararlanamaz.

2. **Manuel Kopyalama ve Kısayol Karmaşası:**
   Uygulamayı harici diske elle sürüklemek, ardından Finder veya Terminal üzerinden `/Applications` içine geleneksel bir kısayol (veya `ln -s` sembolik linki) oluşturmak gerekir.

3. **macOS Launchpad ve Apps.app Görünmeme Sorunu:**
   macOS Sequoia ve sonraki sürümlerde (özellikle yeni nesil `Apps.app` ve Launchpad dizinleme sisteminde), `/Applications` klasörüne yerleştirilen üst düzey POSIX sembolik linkleri ve klasik kısayollar sistem tarafından taranmaz (`Skipping symlink folder` mekanizması). Bunun sonucunda harici diske taşınan ve kısayolu oluşturulan uygulamalar:
   - Spotlight aramalarında çıkmaz,
   - Launchpad veya Uygulamalar çekmecesinde görünmez,
   - Dock üzerinde soru işaretine dönüşebilir veya başlatılamaz.

4. **Kopuk Kısayollar ve Sistem Donmaları:**
   Harici disk bağlı olmadığında bu kısayollara tıklandığında sistem açıklayıcı bir uyarı vermez; uygulama sessizce açılmaz ya da hata verir.

5. **Otomatik Güncelleme Kayıpları:**
   Birçok uygulama (Sparkle vb. çerçeveler kullananlar) arka planda otomatik güncellendiğinde `/Applications` altındaki kısayol dosyasını siler ve yerine güncel sürümü dahili diske yazar. Bu da kullanıcının haberi olmadan dahili disk alanının yeniden dolmasına yol açar.

EXdl, tüm bu süreci tek bir yerel deneyime dönüştürerek harici disk kullanımını dahili disk kadar pürüzsüz hale getirmek amacıyla geliştirilmiştir.

---

## Temel Özellikler

- **Otomatik DMG Yakalama:**
  İndirdiğiniz bir `.dmg` dosyasına çift tıkladığınız anda EXdl arka planda disk kalıbını analiz eder. Dahili diske hiçbir veri yazmadan doğrudan kurulum penceresini açar.

- **Yerel Görsel Sürükle-Bırak Deneyimi:**
  Apple'ın standart DMG kurulum arayüzüne sadık kalınarak tasarlanan pencerede; uygulama ikonu, takılı harici diskleriniz ve dahili `/Applications` dizini yan yana listelenir. Tek yapmanız gereken uygulama ikonunu hedef harici diskin simgesine sürükleyip bırakmaktır.

- **Akıllı Vekil Paketler (Smart App Stubs):**
  EXdl, klasik sembolik linkler (`ln -s`) kullanmaz. Bunun yerine `/Applications` dizini içerisine yaklaşık 500 KB boyutunda, orijinal uygulamanın simgelerini ve kimliğini (`Info.plist`) taşıyan hafif bir yerel macOS paketi (`.app`) yerleştirir.
  - Uygulama; Spotlight, Launchpad, Dock ve macOS `Apps.app` çekmecesinde yerel bir uygulama gibi taranır ve görünür.
  - Harici disk bağlı değilken uygulama çalıştırılırsa sistem donması yerine "Lütfen harici diskinizi bağlayın" uyarısı görüntülenir.

- **Otomatik Güncelleme Koruması:**
  Uygulama kendini güncelleyip `/Applications` içine yeni sürüm yazmaya çalışırsa EXdl (CoreServices FSEvents motoru) değişikliği fark eder, yeni sürümü harici diske taşır ve vekil paketi korur.

- **Depolama Yöneticisi (Dashboard):**
  Dahili diskinizde daha önceden yer kaplayan büyük uygulamaları tek bir ekranda listeleyebilir; tek tıkla harici diske aktarabilir veya dilediğiniz zaman dahili diske geri alabilirsiniz.

- **Menü Çubuğu Entegrasyonu:**
  Menü çubuğundaki durum simgesi üzerinden anlık durumu izleyebilir, disk kullanım istatistiklerini kontrol edebilir ve tercihleriniz doğrultusunda arka plan izlemesini yönetebilirsiniz.

---

## Güvenlik ve İzin İhtiyaçları

EXdl, sistem çekirdeğine herhangi bir kext veya sistem uzantısı yüklemez; macOS'in resmi kamu API'leri (`AppKit`, `CoreServices`, `ServiceManagement`) ile çalışır.

Uygulamanın düzgün çalışabilmesi için aşağıdaki izinler gereklidir:

1. **Tam Disk Erişimi (Full Disk Access):**
   - **Neden Gereklidir:** macOS TCC (Transparency, Consent, and Control) güvenlik mimarisi nedeniyle `/Applications` klasörüne dosya yazmak, DMG içeriklerini harici bağlı disklere (`/Volumes/...`) taşımak ve vekil paket oluşturmak için bu izin zorunludur.
   - **Gizlilik:** EXdl tamamen açık kaynaklıdır. Kişisel belgelere, fotoğraflara veya kullanıcı verilerine kesinlikle erişmez. Herhangi bir sunucuya veri göndermez; telemetri, analitik veya izleme kodu barındırmaz.

2. **Bildirim İzni:**
   - Bir disk kalıbı algılandığında veya arka planda bir taşıma işlemi tamamlandığında sizi bilgilendirmek için kullanılır.

---

## Kurulum

### GitHub Releases Üzerinden İndirme

1. Bu deponun [Releases](../../releases) sayfasını ziyaret edin.
2. En güncel sürümün altında bulunan `EXdl-1.0.0.dmg` dosyasını bilgisayarınıza indirin.
3. İndirilen DMG dosyasını açın ve `EXdl` uygulamasını `Applications` klasörüne sürükleyin.
4. Uygulamayı ilk kez başlattığınızda karşınıza çıkacak adımları takip ederek:
   - **Sistem Ayarları > Gizlilik ve Güvenlik > Tam Disk Erişimi** bölümünden `EXdl` için izin anahtarını aktif hale getirin.

> **Güvenlik Notu:** EXdl, Apple Geliştirici Sertifikası (`Developer ID Application: Erdem Beler`) ile imzalanmış ve doğrudan Apple Noter Servisi (Apple Notarization) tarafından resmi olarak taranıp onaylanmıştır. Gatekeeper engeliyle karşılaşmadan güvenle çalışır.

---

## Kaynaktan Derleme

Geliştiriciler projeyi doğrudan kaynak kodundan derleyebilir:

```bash
git clone https://github.com/erdembeler/exdl.git
cd exdl

# Swift Package Manager ile derleme ve uygulama paketini hazırlama:
./build_app.sh

# Dağıtım DMG paketini oluşturma:
./package_release.sh
```

---

## Sistem Gereksinimleri

- **İşletim Sistemi:** macOS 14.0 (Sonoma) veya daha yeni bir macOS sürümü (macOS 15 Sequoia ve macOS 26 Tahoe ile tam uyumludur)
- **Mimari:** Apple Silicon (M1/M2/M3/M4) ve Intel x86_64
- **Depolama:** APFS veya Mac OS Genişletilmiş (Günlüklü) formatında biçimlendirilmiş harici depolama aygıtları

---

## Lisans

Bu proje [MIT Lisansı](LICENSE) kapsamında sunulmaktadır.
