# PerformancePars

PerformancePars; Pardus 25 ve Debian tabanlı Linux sistemlerde işlemci, bellek,
disk, ağ, GPU, sıcaklık, batarya, işlemler ve depolama sağlığı gibi işlevleri tek arayüzde
izleyen masaüstü uygulamasıdır.

## Özellikler

- CPU Sıcaklık ve Kullanım Takibi ve Grafikleri
- GPU Sıcaklık Frekans Takibi ve Grafikleri
- Ağ indirme/yükleme ve fiziksel disk okuma/yazma grafikleri
- İşlem yöneticisi
- Gelişmiş sıcaklık ve fan sensörleri
- SSD ve HDD için ayrı SMART sağlık ve sıcaklık bilgileri
- Kullanıcı tarafından başlatılan, 128 MB geçici dosyalı disk hız testi
- Pardus uygulama menüsü ve masaüstü entegrasyonu

## Son kullanıcı kurulumu

GitHub Releases bölümünden `performancepars_1.0.0_amd64.deb` dosyasını indirin
ve dosyaya çift tıklayarak Pardus Paket Kurucu ile yükleyin. Kurucu,
PerformancePars'ın ihtiyaç duyduğu sistem araçlarını otomatik olarak yükler.
Flutter SDK kurulması gerekmez.

Terminalden kurulum tercih edilirse:

```bash
sudo apt install ./performancepars_1.0.0_amd64.deb
```

Kurulumdan sonra PerformancePars uygulama menüsünde görünür.

> NVIDIA kullanım, bellek ve güç değerleri için bilgisayara uygun NVIDIA
> sürücüsünün işletim sistemi tarafından kurulmuş olması gerekir. Donanıma ve
> çekirdeğe özel olduğu için NVIDIA sürücüsü uygulama paketine zorla eklenmez.
> Intel ve AMD'nin çekirdek sürücüleri çoğu Pardus kurulumunda hazır gelir.

## Geliştirici kurulumu

Flutter Linux masaüstü ortamını hazırladıktan sonra:

```bash
flutter pub get
flutter run -d linux
```

Kod denetimi ve sürüm derlemesi:

```bash
dart format --output=none --set-exit-if-changed lib/main.dart
flutter analyze
flutter build linux --release
```

## `.deb` paketi üretme

```bash
chmod +x scripts/build-deb.sh
./scripts/build-deb.sh
```

Paket ve SHA-256 dosyası `dist/` klasörüne yazılır. `v1.0.0` gibi bir Git etiketi
gönderildiğinde GitHub Actions aynı paketi üretip Releases bölümüne ekler.

## Güvenlik

SMART verisi salt okunur bir sistem yardımcısıyla alınır. Yardımcı yalnızca
gerçek blok aygıtlarını kabul eder ve SMART üzerinde değişiklik yapan komutlara
izin vermez. Disk hız testi kullanıcının önbellek dizininde geçici dosya
oluşturur ve test sonunda dosyayı siler.
