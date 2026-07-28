# PerformancePars

PerformancePars; Pardus 25 ve Debian tabanlı Linux sistemlerde işlemci, bellek,
disk, ağ, GPU, sıcaklık, batarya, işlemler ve depolama sağlığı gibi değerleri
tek arayüzde izleyen masaüstü uygulamasıdır.

## Özellikler

- CPU kullanımı, sıcaklığı ve canlı performans grafikleri
- Intel, AMD ve NVIDIA GPU kullanımı, frekansı ve canlı performans grafikleri
- Bellek kullanımı ve Canlı Grafikleri
- Ağ indirme/yükleme ve disk okuma/yazma hızı takibi
- Batarya Kullanımı ve Batarya Sağlığı Takibi
- İşlem yöneticisi (Pc'deki görevleri durdurup yönetebileceğiniz)
- Gelişmiş sıcaklık sensörleri menüsü ve sistem bakımı öneren boşta sıcaklık ölçümü
- Depolama için ayrı SMART sağlık ve sıcaklık bilgileri
- Sistem bilgilerini detaylı yazan sistem bilgileri bölümü


## Son kullanıcı kurulumu

> **Önemli:** Yeşil **Code** düğmesindeki “Download ZIP” seçeneğini
> kullanmayın. Bu dosya uygulamanın kaynak kodudur ve doğrudan kurulmaz.

1. Deponun sağ tarafındaki
   [Releases](https://github.com/techasl7585/performancepars/releases/latest)
   bölümünü açın.
2. En son sürümün **Assets** bölümündeki
   `performancepars_<sürüm>_amd64.deb` dosyasını indirin.
3. İndirilen `.deb` dosyasına çift tıklayın ve Pardus Paket Kurucu ile yükleyin.

Kurucu, PerformancePars'ın ihtiyaç duyduğu standart sistem araçlarını ve
kütüphaneleri otomatik olarak yükler. Son kullanıcının Flutter SDK kurması
gerekmez.

Terminalden kurulum tercih edilirse:

```bash
cd ~/İndirilenler
sudo apt install ./performancepars_1.0.1_amd64.deb
```

Kurulum tamamlandığında PerformancePars uygulama menüsünde görünür.
Dosya adındaki `amd64`, 64 bit Intel ve AMD işlemcili bilgisayarları kapsar.

## GPU bölümünün çalışması için - Uygulamazsanız GPU Kısmı Çalışmaz Pasif Gözükür

GPU kartının “Pasif” görünmesi hata anlamına
gelmez. Önce Sürücülerin Kurulmasu Gerekmektedir. Aşağıdaki doğrulamalar GPU türüne göre yapılmalıdır.

### Intel GPU

Paket, Intel ölçümü için gereken `intel-gpu-tools` aracını ve dosya yetkisini
kurar. Intel GPU “Pasif” kalırsa performans sayaçlarına erişimi etkinleştirin:

```bash
echo 'kernel.perf_event_paranoid=0' | \
  sudo tee /etc/sysctl.d/60-performancepars.conf
sudo sysctl --system
sudo setcap cap_perfmon=ep /usr/bin/intel_gpu_top
```

Ardından PerformancePars'ı kapatıp yeniden açın. Erişimi terminalde sınamak
için:

```bash
timeout 3 intel_gpu_top -J -s 1000
```

JSON biçiminde ölçüm geliyorsa Intel GPU takibi hazırdır.

### NVIDIA GPU

NVIDIA kullanım, bellek, sıcaklık, frekans ve güç değerleri `nvidia-smi`
üzerinden okunur. Bunun için bilgisayara ve çalışan çekirdeğe uygun NVIDIA
sürücüsü kurulmuş olmalıdır. Donanıma ve çekirdeğe özel olduğu, DKMS derlemesi
ve yeniden başlatma gerektirdiği için NVIDIA sürücüsü uygulamanın `.deb`
paketine zorla eklenmez.

Pardus 25 üzerinde önce güncel çekirdek ile başlıklarını kurun:

```bash
sudo apt update
sudo apt install linux-image-amd64 linux-headers-amd64
sudo reboot
```

Sistem yeniden açıldıktan sonra:

```bash
sudo apt install nvidia-driver nvidia-smi
sudo reboot
```

Kurulumu doğrulayın:

```bash
nvidia-smi
lsmod | grep -E 'nvidia|nouveau|i915'
```

`nvidia-smi` ekran kartı bilgilerini gösteriyorsa PerformancePars NVIDIA
ölçümlerini okuyabilir. Hibrit sistemde Intel GPU masaüstünü çalıştırırken
NVIDIA GPU boşta `0%`, düşük güç durumunda veya “Pasif” görünebilir; bu normaldir.
`nvidia-smi: komut bulunamadı` mesajı ise NVIDIA sürücüsü ve ölçüm aracının henüz
kurulmadığını gösterir.

### AMD GPU

AMD GPU takibi Linux çekirdeğindeki `amdgpu` sürücüsünün sunduğu verilerle
çalışır. Çoğu Pardus sisteminde ayrıca üretici aracı kurulması gerekmez.
Sürücüyü doğrulamak için:

```bash
lspci -nnk | grep -A3 -E 'VGA|3D|Display'
lsmod | grep amdgpu
```

Çıktıda `Kernel driver in use: amdgpu` görünmelidir. Çok eski veya ölçüm
sayacını dışarı sunmayan AMD donanımlarında bazı alanlar kullanılamayabilir.

### Genel GPU tanılama

```bash
lspci -nnk | grep -A3 -E 'VGA|3D|Display'
```

Bu komut algılanan ekran kartlarını ve kullanılan çekirdek sürücülerini
gösterir. Sürücü kurulduktan veya çekirdek değiştirildikten sonra bilgisayarı
yeniden başlatmak gerekir.

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
