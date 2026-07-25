import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const PerformanceParsApp());
}

class PerformanceParsApp extends StatelessWidget {
  const PerformanceParsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF07101E);
    const surface = Color(0xFF101B2D);
    const primary = Color(0xFF6CE5C3);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PerformancePars',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: Color(0xFF66A8FF),
          surface: surface,
          error: Color(0xFFFF6B7A),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.8),
          titleLarge: TextStyle(fontWeight: FontWeight.w700),
          titleMedium: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      home: const SystemDashboard(),
    );
  }
}

class SystemDashboard extends StatefulWidget {
  const SystemDashboard({super.key});

  @override
  State<SystemDashboard> createState() => _SystemDashboardState();
}

class _SystemDashboardState extends State<SystemDashboard> {
  static const int _historyLimit = 60;

  Timer? _timer;
  CpuTicks? _previousCpu;
  NetworkCounters? _previousNetwork;
  DiskIoCounters? _previousDiskIo;
  bool _isUpdating = false;
  bool _isHistoryPaused = false;
  int _selectedPage = 0;
  int _lowCpuSeconds = 0;
  int _updateCounter = 0;
  DateTime? _lastUpdated;
  DateTime? _lastProcessRefresh;

  final List<double> _cpuHistory = [];
  final List<double> _ramHistory = [];
  final List<double> _diskHistory = [];
  final List<double> _downloadHistory = [];
  final List<double> _uploadHistory = [];
  final List<double> _diskReadHistory = [];
  final List<double> _diskWriteHistory = [];
  final List<double> _gpuHistory = [];
  final List<double> _temperatureHistory = [];

  double _cpuPercent = 0;
  double _ramPercent = 0;
  double _diskPercent = 0;
  double _temperatureValue = 0;
  double _idleTemperatureValue = 0;

  String _ramText = 'Okunuyor...';
  String _diskText = 'Okunuyor...';
  String _temperatureText = 'Okunuyor...';
  String _idleTemperatureText = 'Henüz ölçülmedi';
  String _temperatureSensor = 'Sensör aranıyor';
  String _hostName = 'Pardus bilgisayar';
  String _operatingSystem = 'Pardus GNU/Linux';
  String _uptime = '—';
  NetworkPerformance _networkPerformance = const NetworkPerformance(
    interfaceName: 'Ağ aranıyor',
    downloadBytesPerSecond: 0,
    uploadBytesPerSecond: 0,
    totalReceivedBytes: 0,
    totalSentBytes: 0,
  );
  DiskIoPerformance _diskIoPerformance = const DiskIoPerformance(
    readBytesPerSecond: 0,
    writeBytesPerSecond: 0,
    deviceCount: 0,
  );
  GpuPerformance _gpuPerformance = const GpuPerformance(
    available: false,
    name: 'GPU bilgisi hazırlanıyor',
    usagePercent: 0,
    temperature: null,
    memoryUsedBytes: null,
    memoryTotalBytes: null,
    source: '—',
  );
  List<TemperatureSensorReading> _temperatureSensors = const [];
  List<FanReading> _fanReadings = const [];
  List<SystemProcessInfo> _processes = const [];
  String _processError = '';
  BatteryInfo _batteryInfo = const BatteryInfo(
    available: false,
    percent: 0,
    status: 'Batarya aranıyor',
    healthPercent: null,
    cycleCount: null,
    remainingTime: '—',
    model: '—',
  );
  SystemHardwareInfo _hardwareInfo = const SystemHardwareInfo(
    cpuModel: 'İşlemci bilgisi okunuyor',
    gpuModel: 'Ekran kartı bilgisi okunuyor',
    kernel: '—',
    architecture: '—',
    deviceModel: '—',
    storageModel: 'Depolama modeli okunuyor',
    logicalThreads: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadStaticSystemInfo();
    _updateSystemInfo();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateSystemInfo());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStaticSystemInfo() async {
    final hostName = Platform.localHostname.trim();
    final operatingSystem = _readOperatingSystemName();
    final hardwareInfo = await _readSystemHardwareInfo();

    if (!mounted) {
      return;
    }

    setState(() {
      if (hostName.isNotEmpty) {
        _hostName = hostName;
      }
      if (operatingSystem.isNotEmpty) {
        _operatingSystem = operatingSystem;
      }
      _hardwareInfo = hardwareInfo;
    });
  }

  Future<void> _updateSystemInfo() async {
    if (_isUpdating) {
      return;
    }
    _isUpdating = true;

    try {
      _updateCounter++;
      final currentCpu = _readCpuTicks();
      final currentRam = _readRamInfo();
      final currentDisk = await _readDiskInfo();
      final currentTemperature = _readTemperatureInfo();
      final currentTemperatureSensors = _readAllTemperatureSensors();
      final currentFanReadings = _readFanReadings();
      final currentBattery = _readBatteryInfo();
      final currentUptime = _readUptime();
      final currentNetwork = _readNetworkCounters();
      final currentDiskIo = _readDiskIoCounters();
      final currentGpu = _updateCounter == 1 || _updateCounter % 3 == 0
          ? await _readGpuPerformance(_hardwareInfo.gpuModel)
          : _gpuPerformance;

      List<SystemProcessInfo>? currentProcesses;
      String? processError;
      final shouldRefreshProcesses =
          _selectedPage == 3 &&
          (_lastProcessRefresh == null ||
              DateTime.now().difference(_lastProcessRefresh!).inSeconds >= 2);
      if (shouldRefreshProcesses) {
        try {
          currentProcesses = await _readSystemProcesses();
          processError = '';
        } catch (_) {
          processError = 'İşlem listesi okunamadı';
        }
      }

      var newCpuPercent = _cpuPercent;
      if (_previousCpu != null && currentCpu != null) {
        newCpuPercent = _calculateCpuPercent(_previousCpu!, currentCpu);
      }
      _previousCpu = currentCpu;

      final newNetworkPerformance = _calculateNetworkPerformance(
        _previousNetwork,
        currentNetwork,
      );
      final newDiskIoPerformance = _calculateDiskIoPerformance(
        _previousDiskIo,
        currentDiskIo,
      );
      _previousNetwork = currentNetwork;
      _previousDiskIo = currentDiskIo;

      if (!mounted) {
        return;
      }

      setState(() {
        _cpuPercent = newCpuPercent;
        _ramPercent = currentRam.percent;
        _ramText = currentRam.text;
        _diskPercent = currentDisk.percent;
        _diskText = currentDisk.text;
        _batteryInfo = currentBattery;
        _uptime = currentUptime;
        _networkPerformance = newNetworkPerformance;
        _diskIoPerformance = newDiskIoPerformance;
        _gpuPerformance = currentGpu;
        _temperatureSensors = currentTemperatureSensors;
        _fanReadings = currentFanReadings;
        if (currentProcesses != null) {
          _processes = currentProcesses;
          _lastProcessRefresh = DateTime.now();
        }
        if (processError != null) {
          _processError = processError;
        }

        if (!_isHistoryPaused) {
          _appendHistory(_cpuHistory, newCpuPercent);
          _appendHistory(_ramHistory, currentRam.percent);
          _appendHistory(_diskHistory, currentDisk.percent);
          _appendRawHistory(
            _downloadHistory,
            newNetworkPerformance.downloadBytesPerSecond,
          );
          _appendRawHistory(_uploadHistory, newNetworkPerformance.uploadBytesPerSecond);
          _appendRawHistory(_diskReadHistory, newDiskIoPerformance.readBytesPerSecond);
          _appendRawHistory(
            _diskWriteHistory,
            newDiskIoPerformance.writeBytesPerSecond,
          );
          _appendHistory(_gpuHistory, currentGpu.usagePercent);
          if (currentTemperature.value > 0) {
            _appendRawHistory(_temperatureHistory, currentTemperature.value);
          }
        }

        if (newCpuPercent < 20) {
          _lowCpuSeconds++;
        } else {
          _lowCpuSeconds = 0;
        }

        if (currentTemperature.value > 0) {
          _temperatureValue = currentTemperature.value;
          _temperatureText = currentTemperature.text;
          _temperatureSensor = currentTemperature.sensor;

          if (_lowCpuSeconds >= 30) {
            _idleTemperatureValue = currentTemperature.value;
            _idleTemperatureText = currentTemperature.text;
          }
        } else {
          _temperatureValue = 0;
          _temperatureText = currentTemperature.text;
          _temperatureSensor = currentTemperature.sensor;
        }

        _lastUpdated = DateTime.now();
      });
    } finally {
      _isUpdating = false;
    }
  }

  void _appendHistory(List<double> history, double value) {
    history.add(value.clamp(0, 100).toDouble());
    if (history.length > _historyLimit) {
      history.removeAt(0);
    }
  }

  void _appendRawHistory(List<double> history, double value) {
    history.add(math.max(0, value).toDouble());
    if (history.length > _historyLimit) {
      history.removeAt(0);
    }
  }

  void _clearHistory() {
    setState(() {
      _cpuHistory.clear();
      _ramHistory.clear();
      _diskHistory.clear();
      _downloadHistory.clear();
      _uploadHistory.clear();
      _diskReadHistory.clear();
      _diskWriteHistory.clear();
      _gpuHistory.clear();
      _temperatureHistory.clear();
    });
  }

  Future<void> _terminateProcess(SystemProcessInfo process) async {
    if (process.processId == pid) {
      _showMessage('PerformancePars kendi işlemini sonlandıramaz.');
      return;
    }

    var success = false;
    try {
      success = Process.killPid(process.processId, ProcessSignal.sigterm);
    } catch (_) {
      success = false;
    }
    _showMessage(
      success
          ? '${process.name} işlemine kapatma sinyali gönderildi.'
          : '${process.name} sonlandırılamadı. Yetki gerekebilir.',
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _refreshProcesses();
  }

  Future<void> _refreshProcesses() async {
    try {
      final processes = await _readSystemProcesses();
      if (!mounted) {
        return;
      }
      setState(() {
        _processes = processes;
        _processError = '';
        _lastProcessRefresh = DateTime.now();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _processError = 'İşlem listesi okunamadı';
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maintenance = _thermalMaintenance;

    return Scaffold(
      body: SafeArea(
        child: SelectionArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth < 720 ? 18.0 : 30.0;

              return RefreshIndicator(
                onRefresh: _updateSystemInfo,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: const Color(0xFF142138),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        24,
                        horizontalPadding,
                        18,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _DashboardHeader(
                          hostName: _hostName,
                          operatingSystem: _operatingSystem,
                          lastUpdated: _lastUpdated,
                          onRefresh: _updateSystemInfo,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        0,
                        horizontalPadding,
                        18,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _PageSelector(
                          selectedPage: _selectedPage,
                          onChanged: (page) {
                            setState(() {
                              _selectedPage = page;
                            });
                            if (page == 3) {
                              _refreshProcesses();
                            }
                          },
                        ),
                      ),
                    ),
                    if (_selectedPage == 0)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          30,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _MainOverview(
                            cpuPercent: _cpuPercent,
                            ramPercent: _ramPercent,
                            ramText: _ramText,
                            diskPercent: _diskPercent,
                            diskText: _diskText,
                            temperatureValue: _temperatureValue,
                            temperatureText: _temperatureText,
                            idleTemperatureText: _idleTemperatureText,
                            temperatureSensor: _temperatureSensor,
                            batteryInfo: _batteryInfo,
                            maintenance: maintenance,
                            hardwareInfo: _hardwareInfo,
                            uptime: _uptime,
                            cpuHistory: List<double>.of(_cpuHistory),
                            ramHistory: List<double>.of(_ramHistory),
                            networkPerformance: _networkPerformance,
                            diskIoPerformance: _diskIoPerformance,
                            gpuPerformance: _gpuPerformance,
                          ),
                        ),
                      ),
                    if (_selectedPage == 1)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          30,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _LiveChartsPanel(
                            cpuHistory: List<double>.of(_cpuHistory),
                            ramHistory: List<double>.of(_ramHistory),
                            downloadHistory: List<double>.of(_downloadHistory),
                            uploadHistory: List<double>.of(_uploadHistory),
                            diskReadHistory: List<double>.of(_diskReadHistory),
                            diskWriteHistory: List<double>.of(_diskWriteHistory),
                            gpuHistory: List<double>.of(_gpuHistory),
                            temperatureHistory: List<double>.of(_temperatureHistory),
                            networkPerformance: _networkPerformance,
                            diskIoPerformance: _diskIoPerformance,
                            gpuPerformance: _gpuPerformance,
                            temperatureSensors: _temperatureSensors,
                            fanReadings: _fanReadings,
                            isPaused: _isHistoryPaused,
                            onTogglePause: () {
                              setState(() {
                                _isHistoryPaused = !_isHistoryPaused;
                              });
                            },
                            onClear: _clearHistory,
                          ),
                        ),
                      ),
                    if (_selectedPage == 2)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          18,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _HealthBanner(
                            maintenance: maintenance,
                            idleTemperatureText: _idleTemperatureText,
                          ),
                        ),
                      ),
                    if (_selectedPage == 2)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          30,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _SystemDetails(
                            hostName: _hostName,
                            operatingSystem: _operatingSystem,
                            uptime: _uptime,
                            cpuPercent: _cpuPercent,
                            idleTemperatureValue: _idleTemperatureValue,
                            hardwareInfo: _hardwareInfo,
                            batteryInfo: _batteryInfo,
                          ),
                        ),
                      ),
                    if (_selectedPage == 3)
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          30,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _ProcessManagerPanel(
                            processes: _processes,
                            error: _processError,
                            onRefresh: _refreshProcesses,
                            onTerminate: _terminateProcess,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  ThermalMaintenance get _thermalMaintenance {
    if (_idleTemperatureValue <= 0) {
      return const ThermalMaintenance(
        label: 'Boşta ölçüm bekleniyor',
        description:
            'Güvenilir değerlendirme için CPU kullanımının 30 saniye boyunca %20 altında kalması bekleniyor.',
        color: Color(0xFFFFC857),
        icon: Icons.hourglass_top_rounded,
      );
    }

    if (_idleTemperatureValue < 50) {
      return const ThermalMaintenance(
        label: 'Bakım gerekmiyor',
        description: 'Son boşta sıcaklığı normal aralıkta.',
        color: Color(0xFF6CE5C3),
        icon: Icons.verified_rounded,
      );
    }

    if (_idleTemperatureValue < 65) {
      return const ThermalMaintenance(
        label: 'Orta seviye',
        description: 'Hava kanallarını ve fan temizliğini uygun zamanda kontrol edin.',
        color: Color(0xFFFFC857),
        icon: Icons.info_rounded,
      );
    }

    return const ThermalMaintenance(
      label: 'Bakım önerilir',
      description:
          'Boşta sıcaklığı yüksek. Fan, hava kanalı ve termal macun kontrolü önerilir.',
      color: Color(0xFFFF6B7A),
      icon: Icons.warning_amber_rounded,
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.hostName,
    required this.operatingSystem,
    required this.lastUpdated,
    required this.onRefresh,
  });

  final String hostName;
  final String operatingSystem;
  final DateTime? lastUpdated;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final time = lastUpdated == null
        ? 'Veriler hazırlanıyor'
        : 'Son güncelleme ${_twoDigits(lastUpdated!.hour)}:'
              '${_twoDigits(lastUpdated!.minute)}:'
              '${_twoDigits(lastUpdated!.second)}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6CE5C3), Color(0xFF4B8EFF)],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(color: Color(0x336CE5C3), blurRadius: 24, offset: Offset(0, 8)),
            ],
          ),
          child: const Icon(
            Icons.monitor_heart_rounded,
            color: Color(0xFF07101E),
            size: 30,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PerformancePars',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 3),
              Text(
                'Pardus performans merkezi  •  $hostName  •  '
                '$operatingSystem  •  $time',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Şimdi yenile',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _PageSelector extends StatelessWidget {
  const _PageSelector({required this.selectedPage, required this.onChanged});

  final int selectedPage;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1728),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PageButton(
              selected: selectedPage == 0,
              icon: Icons.dashboard_rounded,
              label: 'Genel Bakış',
              onTap: () => onChanged(0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PageButton(
              selected: selectedPage == 1,
              icon: Icons.show_chart_rounded,
              label: 'Canlı Grafikler',
              onTap: () => onChanged(1),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PageButton(
              selected: selectedPage == 2,
              icon: Icons.info_outline_rounded,
              label: 'Sistem Bilgileri',
              onTap: () => onChanged(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PageButton(
              selected: selectedPage == 3,
              icon: Icons.list_alt_rounded,
              label: 'İşlemler',
              onTap: () => onChanged(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageButton extends StatelessWidget {
  const _PageButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Material(
      color: selected ? primary.withValues(alpha: 0.13) : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? primary : Colors.white.withValues(alpha: 0.48),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? primary : Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainOverview extends StatelessWidget {
  const _MainOverview({
    required this.cpuPercent,
    required this.ramPercent,
    required this.ramText,
    required this.diskPercent,
    required this.diskText,
    required this.temperatureValue,
    required this.temperatureText,
    required this.idleTemperatureText,
    required this.temperatureSensor,
    required this.batteryInfo,
    required this.maintenance,
    required this.hardwareInfo,
    required this.uptime,
    required this.cpuHistory,
    required this.ramHistory,
    required this.networkPerformance,
    required this.diskIoPerformance,
    required this.gpuPerformance,
  });

  final double cpuPercent;
  final double ramPercent;
  final String ramText;
  final double diskPercent;
  final String diskText;
  final double temperatureValue;
  final String temperatureText;
  final String idleTemperatureText;
  final String temperatureSensor;
  final BatteryInfo batteryInfo;
  final ThermalMaintenance maintenance;
  final SystemHardwareInfo hardwareInfo;
  final String uptime;
  final List<double> cpuHistory;
  final List<double> ramHistory;
  final NetworkPerformance networkPerformance;
  final DiskIoPerformance diskIoPerformance;
  final GpuPerformance gpuPerformance;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PerformanceHero(
          cpuPercent: cpuPercent,
          ramPercent: ramPercent,
          diskPercent: diskPercent,
          cpuHistory: cpuHistory,
          ramHistory: ramHistory,
        ),
        const SizedBox(height: 24),
        const _SectionTitle(
          title: 'Kaynak kullanımı',
          subtitle: 'İşlemci, bellek ve depolamanın anlık durumu',
          icon: Icons.speed_rounded,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            const gap = 14.0;
            final cardWidth = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: MetricCard(
                    title: 'İşlemci',
                    value: '${cpuPercent.toStringAsFixed(1)}%',
                    detail: hardwareInfo.cpuModel,
                    secondaryDetail: hardwareInfo.logicalThreads > 0
                        ? '${hardwareInfo.logicalThreads} thread • Canlı kullanım'
                        : 'Canlı işlemci kullanımı',
                    percent: cpuPercent,
                    color: const Color(0xFF66A8FF),
                    icon: Icons.memory_rounded,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: MetricCard(
                    title: 'Bellek',
                    value: '${ramPercent.toStringAsFixed(1)}%',
                    detail: ramText,
                    secondaryDetail: 'Sistem belleği kullanımı',
                    percent: ramPercent,
                    color: const Color(0xFFB18CFF),
                    icon: Icons.dns_rounded,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: MetricCard(
                    title: 'Depolama',
                    value: '${diskPercent.toStringAsFixed(1)}%',
                    detail: hardwareInfo.storageModel,
                    secondaryDetail: diskText,
                    percent: diskPercent,
                    color: const Color(0xFFFFB86B),
                    icon: Icons.storage_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const _SectionTitle(
          title: 'Cihaz durumu',
          subtitle: 'Isı, batarya ve donanım bilgileri',
          icon: Icons.monitor_heart_outlined,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            const gap = 14.0;
            final cardWidth = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: TemperatureCard(
                    value: temperatureValue,
                    valueText: temperatureText,
                    idleText: idleTemperatureText,
                    sensor: temperatureSensor,
                    maintenance: maintenance,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: BatteryCard(info: batteryInfo),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _QuickSystemCard(hardwareInfo: hardwareInfo, uptime: uptime),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const _SectionTitle(
          title: 'Canlı veri akışı',
          subtitle: 'Ağ, disk ve grafik birimi performansı',
          icon: Icons.data_usage_rounded,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 620
                ? 2
                : 1;
            const gap = 14.0;
            final cardWidth = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _TelemetrySummaryCard(
                    title: 'Ağ performansı',
                    icon: Icons.swap_vert_circle_outlined,
                    color: const Color(0xFF6CE5C3),
                    primaryLabel: 'İndirme',
                    primaryValue: _formatSpeed(
                      networkPerformance.downloadBytesPerSecond,
                    ),
                    secondaryLabel: 'Yükleme',
                    secondaryValue: _formatSpeed(
                      networkPerformance.uploadBytesPerSecond,
                    ),
                    detail: networkPerformance.interfaceName,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _TelemetrySummaryCard(
                    title: 'Disk performansı',
                    icon: Icons.storage_rounded,
                    color: const Color(0xFFFFB86B),
                    primaryLabel: 'Okuma',
                    primaryValue: _formatSpeed(diskIoPerformance.readBytesPerSecond),
                    secondaryLabel: 'Yazma',
                    secondaryValue: _formatSpeed(diskIoPerformance.writeBytesPerSecond),
                    detail: '${diskIoPerformance.deviceCount} fiziksel disk izleniyor',
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _TelemetrySummaryCard(
                    title: 'GPU takibi',
                    icon: Icons.developer_board_rounded,
                    color: const Color(0xFF59D4FF),
                    primaryLabel: 'Kullanım',
                    primaryValue: gpuPerformance.available
                        ? '${gpuPerformance.usagePercent.toStringAsFixed(0)}%'
                        : 'Desteklenmiyor',
                    secondaryLabel: 'Sıcaklık',
                    secondaryValue: gpuPerformance.temperature == null
                        ? '—'
                        : '${gpuPerformance.temperature!.toStringAsFixed(0)} °C',
                    detail: gpuPerformance.memoryTotalBytes == null
                        ? gpuPerformance.name
                        : '${gpuPerformance.name} • VRAM '
                              '${_formatBytes(gpuPerformance.memoryUsedBytes ?? 0)} / '
                              '${_formatBytes(gpuPerformance.memoryTotalBytes!)}',
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PerformanceHero extends StatelessWidget {
  const _PerformanceHero({
    required this.cpuPercent,
    required this.ramPercent,
    required this.diskPercent,
    required this.cpuHistory,
    required this.ramHistory,
  });

  final double cpuPercent;
  final double ramPercent;
  final double diskPercent;
  final List<double> cpuHistory;
  final List<double> ramHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14263A), Color(0xFF0D1829)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF66A8FF).withValues(alpha: 0.18)),
        boxShadow: const [
          BoxShadow(color: Color(0x26000000), blurRadius: 34, offset: Offset(0, 15)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF6CE5C3).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: const Color(0xFF6CE5C3).withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LiveDot(),
                    SizedBox(width: 7),
                    Text(
                      'CANLI İZLEME',
                      style: TextStyle(
                        color: Color(0xFF6CE5C3),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Sistem performansı',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 26),
              ),
              const SizedBox(height: 6),
              Text(
                'Kaynak kullanımı saniyede bir yenileniyor.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusPill(label: 'CPU', value: cpuPercent),
                  _StatusPill(label: 'RAM', value: ramPercent),
                  _StatusPill(label: 'Disk', value: diskPercent),
                ],
              ),
            ],
          );

          final chart = Container(
            height: 220,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF081321).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Son 60 saniye',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    _ChartLegend(label: 'CPU', color: const Color(0xFF66A8FF)),
                    const SizedBox(width: 14),
                    _ChartLegend(label: 'RAM', color: const Color(0xFFB18CFF)),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: CustomPaint(
                    painter: _OverviewChartPainter(
                      cpuValues: cpuHistory,
                      ramValues: ramHistory,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Text(
                      '60 sn önce',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.28),
                        fontSize: 9,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Şimdi',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          if (constraints.maxWidth < 820) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [summary, const SizedBox(height: 22), chart],
            );
          }

          return Row(
            children: [
              SizedBox(width: 310, child: summary),
              const SizedBox(width: 28),
              Expanded(child: chart),
            ],
          );
        },
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFF6CE5C3),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x996CE5C3), blurRadius: 7, spreadRadius: 1),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickSystemCard extends StatelessWidget {
  const _QuickSystemCard({required this.hardwareInfo, required this.uptime});

  final SystemHardwareInfo hardwareInfo;
  final String uptime;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF59D4FF);

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _CardIcon(icon: Icons.computer_rounded, color: color),
              SizedBox(width: 11),
              Text(
                'Sistem',
                style: TextStyle(color: Color(0xFFAAB5C8), fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Spacer(),
          _QuickInfoLine(
            icon: Icons.schedule_rounded,
            label: 'Çalışma süresi',
            value: uptime,
          ),
          const SizedBox(height: 10),
          _QuickInfoLine(
            icon: Icons.videogame_asset_rounded,
            label: 'Grafik birimi',
            value: hardwareInfo.gpuModel,
          ),
          const SizedBox(height: 10),
          _QuickInfoLine(
            icon: Icons.architecture_rounded,
            label: 'Mimari',
            value: hardwareInfo.architecture,
          ),
        ],
      ),
    );
  }
}

class _QuickInfoLine extends StatelessWidget {
  const _QuickInfoLine({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF59D4FF)),
        const SizedBox(width: 8),
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 10),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _TelemetrySummaryCard extends StatelessWidget {
  const _TelemetrySummaryCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.primaryLabel,
    required this.primaryValue,
    required this.secondaryLabel,
    required this.secondaryValue,
    required this.detail,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String primaryLabel;
  final String primaryValue;
  final String secondaryLabel;
  final String secondaryValue;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardIcon(icon: icon, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _TelemetryValue(
                  label: primaryLabel,
                  value: primaryValue,
                  color: color,
                ),
              ),
              Container(
                width: 1,
                height: 38,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _TelemetryValue(
                  label: secondaryLabel,
                  value: secondaryValue,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _TelemetryValue extends StatelessWidget {
  const _TelemetryValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.36),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = value >= 90
        ? const Color(0xFFFF6B7A)
        : value >= 75
        ? const Color(0xFFFFC857)
        : const Color(0xFF6CE5C3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.46)),
            ),
            TextSpan(
              text: '${value.toStringAsFixed(0)}%',
              style: TextStyle(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewChartPainter extends CustomPainter {
  const _OverviewChartPainter({required this.cpuValues, required this.ramValues});

  final List<double> cpuValues;
  final List<double> ramValues;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;

    for (var index = 0; index <= 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var index = 1; index < 6; index++) {
      final x = size.width * index / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    _drawSeries(canvas, size, cpuValues, const Color(0xFF66A8FF));
    _drawSeries(canvas, size, ramValues, const Color(0xFFB18CFF));
  }

  void _drawSeries(Canvas canvas, Size size, List<double> values, Color color) {
    if (values.isEmpty) {
      return;
    }

    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1 ? 0.0 : size.width * index / (values.length - 1);
      final normalized = values[index].clamp(0, 100).toDouble() / 100;
      points.add(Offset(x, size.height - (size.height * normalized)));
    }

    final path = _smoothPath(points);
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.005)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(points.last, 5, Paint()..color = const Color(0xFF081321));
    canvas.drawCircle(points.last, 3, Paint()..color = color);
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) {
      return path;
    }

    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final middleX = (previous.dx + current.dx) / 2;
      path.cubicTo(middleX, previous.dy, middleX, current.dy, current.dx, current.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _OverviewChartPainter oldDelegate) {
    return oldDelegate.cpuValues != cpuValues || oldDelegate.ramValues != ramValues;
  }
}

class _LiveChartsPanel extends StatelessWidget {
  const _LiveChartsPanel({
    required this.cpuHistory,
    required this.ramHistory,
    required this.downloadHistory,
    required this.uploadHistory,
    required this.diskReadHistory,
    required this.diskWriteHistory,
    required this.gpuHistory,
    required this.temperatureHistory,
    required this.networkPerformance,
    required this.diskIoPerformance,
    required this.gpuPerformance,
    required this.temperatureSensors,
    required this.fanReadings,
    required this.isPaused,
    required this.onTogglePause,
    required this.onClear,
  });

  final List<double> cpuHistory;
  final List<double> ramHistory;
  final List<double> downloadHistory;
  final List<double> uploadHistory;
  final List<double> diskReadHistory;
  final List<double> diskWriteHistory;
  final List<double> gpuHistory;
  final List<double> temperatureHistory;
  final NetworkPerformance networkPerformance;
  final DiskIoPerformance diskIoPerformance;
  final GpuPerformance gpuPerformance;
  final List<TemperatureSensorReading> temperatureSensors;
  final List<FanReading> fanReadings;
  final bool isPaused;
  final VoidCallback onTogglePause;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Canlı performans',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Son 60 saniyelik kullanım geçmişi',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.46),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onTogglePause,
              icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
              label: Text(isPaused ? 'Devam ettir' : 'Grafiği duraklat'),
            ),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Geçmişi temizle'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (isPaused)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC857).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pause_circle_outline_rounded,
                  size: 18,
                  color: Color(0xFFFFC857),
                ),
                SizedBox(width: 8),
                Text(
                  'Grafik kaydı duraklatıldı',
                  style: TextStyle(
                    color: Color(0xFFFFC857),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const _SectionTitle(
          title: 'Kaynak ve donanım grafikleri',
          subtitle: 'CPU, RAM, GPU ve sıcaklık geçmişi',
          icon: Icons.query_stats_rounded,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1360
                ? 4
                : constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 680
                ? 2
                : 1;
            const gap = 14.0;
            final cardWidth = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _LiveChartCard(
                    title: 'İşlemci kullanımı',
                    icon: Icons.memory_rounded,
                    color: const Color(0xFF66A8FF),
                    values: cpuHistory,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _LiveChartCard(
                    title: 'Bellek kullanımı',
                    icon: Icons.dns_rounded,
                    color: const Color(0xFFB18CFF),
                    values: ramHistory,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _LiveChartCard(
                    title: 'GPU kullanımı',
                    icon: Icons.developer_board_rounded,
                    color: const Color(0xFF59D4FF),
                    values: gpuPerformance.available ? gpuHistory : const [],
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _LiveChartCard(
                    title: 'İşlemci sıcaklığı',
                    icon: Icons.thermostat_rounded,
                    color: const Color(0xFFFF6B7A),
                    values: temperatureHistory,
                    valueSuffix: ' °C',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const _SectionTitle(
          title: 'Veri aktarımı',
          subtitle: 'Anlık ağ ve fiziksel disk okuma/yazma hızları',
          icon: Icons.swap_vert_rounded,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 820 ? 2 : 1;
            const gap = 14.0;
            final cardWidth = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _DualSpeedChartCard(
                    title: 'Ağ performansı',
                    detail:
                        '${networkPerformance.interfaceName} • '
                        'Toplam ↓ ${_formatBytes(networkPerformance.totalReceivedBytes)} '
                        '↑ ${_formatBytes(networkPerformance.totalSentBytes)}',
                    firstLabel: 'İndirme',
                    secondLabel: 'Yükleme',
                    firstColor: const Color(0xFF6CE5C3),
                    secondColor: const Color(0xFF59D4FF),
                    firstValues: downloadHistory,
                    secondValues: uploadHistory,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _DualSpeedChartCard(
                    title: 'Disk performansı',
                    detail:
                        '${diskIoPerformance.deviceCount} fiziksel disk • '
                        'Gerçek zamanlı I/O',
                    firstLabel: 'Okuma',
                    secondLabel: 'Yazma',
                    firstColor: const Color(0xFFFFB86B),
                    secondColor: const Color(0xFFB18CFF),
                    firstValues: diskReadHistory,
                    secondValues: diskWriteHistory,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _AdvancedTemperaturePanel(sensors: temperatureSensors, fans: fanReadings),
      ],
    );
  }
}

class _DualSpeedChartCard extends StatelessWidget {
  const _DualSpeedChartCard({
    required this.title,
    required this.detail,
    required this.firstLabel,
    required this.secondLabel,
    required this.firstColor,
    required this.secondColor,
    required this.firstValues,
    required this.secondValues,
  });

  final String title;
  final String detail;
  final String firstLabel;
  final String secondLabel;
  final Color firstColor;
  final Color secondColor;
  final List<double> firstValues;
  final List<double> secondValues;

  @override
  Widget build(BuildContext context) {
    final firstCurrent = firstValues.isEmpty ? 0.0 : firstValues.last;
    final secondCurrent = secondValues.isEmpty ? 0.0 : secondValues.last;

    return _CardShell(
      height: 330,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.36),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              _ChartLegend(label: firstLabel, color: firstColor),
              const SizedBox(width: 13),
              _ChartLegend(label: secondLabel, color: secondColor),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _TelemetryValue(
                  label: firstLabel,
                  value: _formatSpeed(firstCurrent),
                  color: firstColor,
                ),
              ),
              Expanded(
                child: _TelemetryValue(
                  label: secondLabel,
                  value: _formatSpeed(secondCurrent),
                  color: secondColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: CustomPaint(
              painter: _DualSeriesPainter(
                firstValues: firstValues,
                secondValues: secondValues,
                firstColor: firstColor,
                secondColor: secondColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '60 sn önce',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.26),
                  fontSize: 9,
                ),
              ),
              const Spacer(),
              Text(
                'Şimdi',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DualSeriesPainter extends CustomPainter {
  const _DualSeriesPainter({
    required this.firstValues,
    required this.secondValues,
    required this.firstColor,
    required this.secondColor,
  });

  final List<double> firstValues;
  final List<double> secondValues;
  final Color firstColor;
  final Color secondColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var index = 1; index < 6; index++) {
      final x = size.width * index / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final allValues = [...firstValues, ...secondValues];
    final maximum = allValues.isEmpty
        ? 1.0
        : math
              .max(1, allValues.reduce((a, b) => math.max(a, b).toDouble()) * 1.15)
              .toDouble();

    _drawLine(canvas, size, firstValues, firstColor, maximum);
    _drawLine(canvas, size, secondValues, secondColor, maximum);
  }

  void _drawLine(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color,
    double maximum,
  ) {
    if (values.isEmpty) {
      return;
    }

    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1 ? 0.0 : size.width * index / (values.length - 1);
      final normalized = (values[index] / maximum).clamp(0, 1).toDouble();
      points.add(Offset(x, size.height - (size.height * normalized)));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final middleX = (previous.dx + current.dx) / 2;
      path.cubicTo(middleX, previous.dy, middleX, current.dy, current.dx, current.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(points.last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DualSeriesPainter oldDelegate) {
    return oldDelegate.firstValues != firstValues ||
        oldDelegate.secondValues != secondValues ||
        oldDelegate.firstColor != firstColor ||
        oldDelegate.secondColor != secondColor;
  }
}

class _AdvancedTemperaturePanel extends StatelessWidget {
  const _AdvancedTemperaturePanel({required this.sensors, required this.fans});

  final List<TemperatureSensorReading> sensors;
  final List<FanReading> fans;

  @override
  Widget build(BuildContext context) {
    final visibleSensors = sensors.take(16).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1728),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CardIcon(
                icon: Icons.device_thermostat_rounded,
                color: Color(0xFFFF6B7A),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gelişmiş sıcaklık takibi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${sensors.length} sıcaklık sensörü • '
                      '${fans.length} fan sensörü',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          if (visibleSensors.isEmpty)
            const _EmptyTelemetry(
              icon: Icons.sensors_off_rounded,
              message: 'Uyumlu sıcaklık sensörü bulunamadı',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1200
                    ? 4
                    : constraints.maxWidth >= 760
                    ? 3
                    : constraints.maxWidth >= 480
                    ? 2
                    : 1;
                const gap = 10.0;
                final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final sensor in visibleSensors)
                      SizedBox(
                        width: width,
                        child: _TemperatureSensorTile(sensor: sensor),
                      ),
                  ],
                );
              },
            ),
          if (fans.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final fan in fans)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF59D4FF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '${fan.label} • ${fan.rpm} RPM',
                      style: const TextStyle(
                        color: Color(0xFF59D4FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TemperatureSensorTile extends StatelessWidget {
  const _TemperatureSensorTile({required this.sensor});

  final TemperatureSensorReading sensor;

  @override
  Widget build(BuildContext context) {
    final color = sensor.temperature >= 85
        ? const Color(0xFFFF6B7A)
        : sensor.temperature >= 70
        ? const Color(0xFFFFC857)
        : const Color(0xFF6CE5C3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.032),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.thermostat_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sensor.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${sensor.temperature.toStringAsFixed(1)} °C',
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _EmptyTelemetry extends StatelessWidget {
  const _EmptyTelemetry({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.32)),
          const SizedBox(width: 10),
          Text(
            message,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _LiveChartCard extends StatelessWidget {
  const _LiveChartCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.values,
    this.valueSuffix = '%',
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<double> values;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    final current = values.isEmpty ? 0.0 : values.last;
    final average = values.isEmpty
        ? 0.0
        : values.reduce((first, second) => first + second) / values.length;
    final peak = values.isEmpty
        ? 0.0
        : values.reduce((first, second) => math.max(first, second).toDouble());

    return _CardShell(
      height: 310,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardIcon(icon: icon, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${current.toStringAsFixed(1)}$valueSuffix',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _LiveChartPainter(values: values, color: color),
                  ),
                ),
                if (values.isEmpty)
                  Center(
                    child: Text(
                      'Veri bekleniyor...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.38),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ChartStat(
                  label: 'Ortalama',
                  value: average,
                  valueSuffix: valueSuffix,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChartStat(label: 'Tepe', value: peak, valueSuffix: valueSuffix),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChartStat(label: 'Örnek', valueText: '${values.length}/60'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartStat extends StatelessWidget {
  const _ChartStat({
    required this.label,
    this.value,
    this.valueText,
    this.valueSuffix = '%',
  });

  final String label;
  final double? value;
  final String? valueText;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.36),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            valueText ?? '${value?.toStringAsFixed(1)}$valueSuffix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _LiveChartPainter extends CustomPainter {
  const _LiveChartPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;

    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var index = 1; index < 5; index++) {
      final x = size.width * index / 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (values.isEmpty) {
      return;
    }

    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1 ? 0.0 : size.width * index / (values.length - 1);
      final normalized = values[index].clamp(0, 100).toDouble() / 100;
      final y = size.height - (size.height * normalized);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final middleX = (previous.dx + current.dx) / 2;
      path.cubicTo(middleX, previous.dy, middleX, current.dy, current.dx, current.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.26), color.withValues(alpha: 0.01)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    canvas.drawCircle(points.last, 5, Paint()..color = const Color(0xFF101B2D));
    canvas.drawCircle(points.last, 2.8, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LiveChartPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.values != values;
  }
}

enum _ProcessSort { cpu, memory, name }

class _ProcessManagerPanel extends StatefulWidget {
  const _ProcessManagerPanel({
    required this.processes,
    required this.error,
    required this.onRefresh,
    required this.onTerminate,
  });

  final List<SystemProcessInfo> processes;
  final String error;
  final Future<void> Function() onRefresh;
  final Future<void> Function(SystemProcessInfo process) onTerminate;

  @override
  State<_ProcessManagerPanel> createState() => _ProcessManagerPanelState();
}

class _ProcessManagerPanelState extends State<_ProcessManagerPanel> {
  final TextEditingController _searchController = TextEditingController();
  _ProcessSort _sort = _ProcessSort.cpu;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final processes = widget.processes
        .where(
          (process) =>
              query.isEmpty ||
              process.name.toLowerCase().contains(query) ||
              process.user.toLowerCase().contains(query) ||
              process.processId.toString().contains(query),
        )
        .toList();

    switch (_sort) {
      case _ProcessSort.cpu:
        processes.sort((a, b) => b.cpuPercent.compareTo(a.cpuPercent));
        break;
      case _ProcessSort.memory:
        processes.sort((a, b) => b.memoryBytes.compareTo(a.memoryBytes));
        break;
      case _ProcessSort.name:
        processes.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('İşlem yöneticisi', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(
                  '${widget.processes.length} işlem izleniyor',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 11,
                  ),
                ),
              ],
            );
            final controls = Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 620 ? constraints.maxWidth : 270,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'İşlem, kullanıcı veya PID ara',
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Aramayı temizle',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      filled: true,
                      fillColor: const Color(0xFF101B2D),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101B2D),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<_ProcessSort>(
                      value: _sort,
                      dropdownColor: const Color(0xFF142138),
                      borderRadius: BorderRadius.circular(13),
                      items: const [
                        DropdownMenuItem(
                          value: _ProcessSort.cpu,
                          child: Text('CPU kullanımına göre'),
                        ),
                        DropdownMenuItem(
                          value: _ProcessSort.memory,
                          child: Text('RAM kullanımına göre'),
                        ),
                        DropdownMenuItem(
                          value: _ProcessSort.name,
                          child: Text('Ada göre'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _sort = value);
                        }
                      },
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'İşlem listesini yenile',
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            );

            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 14), controls],
              );
            }
            return Row(
              children: [
                Expanded(child: title),
                controls,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C1728),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showUser = constraints.maxWidth >= 850;
              final showPid = constraints.maxWidth >= 620;

              return Column(
                children: [
                  _ProcessTableHeader(showUser: showUser, showPid: showPid),
                  if (widget.error.isNotEmpty)
                    _EmptyTelemetry(
                      icon: Icons.error_outline_rounded,
                      message: widget.error,
                    )
                  else if (processes.isEmpty)
                    const _EmptyTelemetry(
                      icon: Icons.manage_search_rounded,
                      message: 'Aramayla eşleşen işlem bulunamadı',
                    )
                  else
                    for (final process in processes.take(80))
                      _ProcessRow(
                        process: process,
                        showUser: showUser,
                        showPid: showPid,
                        onTerminate: () => _confirmTerminate(process),
                      ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmTerminate(SystemProcessInfo process) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İşlem sonlandırılsın mı?'),
        content: Text(
          '${process.name} (PID ${process.processId}) işlemine güvenli kapatma '
          'sinyali gönderilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sonlandır'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.onTerminate(process);
    }
  }
}

class _ProcessTableHeader extends StatelessWidget {
  const _ProcessTableHeader({required this.showUser, required this.showPid});

  final bool showUser;
  final bool showPid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white.withValues(alpha: 0.025),
      child: Row(
        children: [
          const Expanded(flex: 4, child: _TableLabel('İşlem')),
          if (showUser) const Expanded(flex: 2, child: _TableLabel('Kullanıcı')),
          if (showPid) const SizedBox(width: 80, child: _TableLabel('PID')),
          const SizedBox(
            width: 100,
            child: _TableLabel('CPU', textAlign: TextAlign.right),
          ),
          const SizedBox(
            width: 110,
            child: _TableLabel('Bellek', textAlign: TextAlign.right),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _TableLabel extends StatelessWidget {
  const _TableLabel(this.text, {this.textAlign = TextAlign.left});

  final String text;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.34),
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.process,
    required this.showUser,
    required this.showPid,
    required this.onTerminate,
  });

  final SystemProcessInfo process;
  final bool showUser;
  final bool showPid;
  final VoidCallback onTerminate;

  @override
  Widget build(BuildContext context) {
    final cpuColor = process.cpuPercent >= 70
        ? const Color(0xFFFF6B7A)
        : process.cpuPercent >= 35
        ? const Color(0xFFFFC857)
        : const Color(0xFF66A8FF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: cpuColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.terminal_rounded, size: 15, color: cpuColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    process.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (showUser)
            Expanded(
              flex: 2,
              child: Text(
                process.user,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.46),
                  fontSize: 10,
                ),
              ),
            ),
          if (showPid)
            SizedBox(
              width: 80,
              child: Text(
                process.processId.toString(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 10,
                ),
              ),
            ),
          SizedBox(
            width: 100,
            child: Text(
              '${process.cpuPercent.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: cpuColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              _formatBytes(process.memoryBytes),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: IconButton(
              tooltip: '${process.name} işlemini sonlandır',
              onPressed: onTerminate,
              icon: const Icon(Icons.stop_circle_outlined, size: 19),
              color: const Color(0xFFFF6B7A),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthBanner extends StatelessWidget {
  const _HealthBanner({required this.maintenance, required this.idleTemperatureText});

  final ThermalMaintenance maintenance;
  final String idleTemperatureText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: maintenance.color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: maintenance.color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: maintenance.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(maintenance.icon, color: maintenance.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  maintenance.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: maintenance.color),
                ),
                const SizedBox(height: 3),
                Text(
                  '${maintenance.description} Son boşta: $idleTemperatureText',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.cpuPercent,
    required this.ramPercent,
    required this.ramText,
    required this.diskPercent,
    required this.diskText,
    required this.temperatureValue,
    required this.temperatureText,
    required this.idleTemperatureText,
    required this.temperatureSensor,
    required this.maintenance,
    required this.batteryInfo,
    required this.hardwareInfo,
  });

  final double cpuPercent;
  final double ramPercent;
  final String ramText;
  final double diskPercent;
  final String diskText;
  final double temperatureValue;
  final String temperatureText;
  final String idleTemperatureText;
  final String temperatureSensor;
  final ThermalMaintenance maintenance;
  final BatteryInfo batteryInfo;
  final SystemHardwareInfo hardwareInfo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1320
            ? 5
            : constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const gap = 14.0;
        final cardWidth = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'İşlemci',
                value: '${cpuPercent.toStringAsFixed(1)}%',
                detail: hardwareInfo.cpuModel,
                secondaryDetail: hardwareInfo.logicalThreads > 0
                    ? '${hardwareInfo.logicalThreads} thread • Canlı kullanım'
                    : 'Canlı işlemci kullanımı',
                percent: cpuPercent,
                color: const Color(0xFF66A8FF),
                icon: Icons.memory_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Bellek',
                value: '${ramPercent.toStringAsFixed(1)}%',
                detail: ramText,
                percent: ramPercent,
                color: const Color(0xFFB18CFF),
                icon: Icons.dns_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Disk',
                value: '${diskPercent.toStringAsFixed(1)}%',
                detail: hardwareInfo.storageModel,
                secondaryDetail: diskText,
                percent: diskPercent,
                color: const Color(0xFFFFB86B),
                icon: Icons.storage_rounded,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: TemperatureCard(
                value: temperatureValue,
                valueText: temperatureText,
                idleText: idleTemperatureText,
                sensor: temperatureSensor,
                maintenance: maintenance,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: BatteryCard(info: batteryInfo),
            ),
          ],
        );
      },
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.detail,
    this.secondaryDetail,
    required this.percent,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final String detail;
  final String? secondaryDetail;
  final double percent;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardIcon(icon: icon, color: color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.48), fontSize: 12),
          ),
          if (secondaryDetail != null) ...[
            const SizedBox(height: 3),
            Text(
              secondaryDetail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.36),
                fontSize: 11,
              ),
            ),
          ],
          SizedBox(height: secondaryDetail == null ? 17 : 9),
          _PercentBar(percent: percent, color: color),
        ],
      ),
    );
  }
}

class TemperatureCard extends StatelessWidget {
  const TemperatureCard({
    super.key,
    required this.value,
    required this.valueText,
    required this.idleText,
    required this.sensor,
    required this.maintenance,
  });

  final double value;
  final String valueText;
  final String idleText;
  final String sensor;
  final ThermalMaintenance maintenance;

  @override
  Widget build(BuildContext context) {
    final progress = value <= 0 ? 0.0 : ((value - 20) / 80) * 100;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardIcon(icon: Icons.thermostat_rounded, color: maintenance.color),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Sıcaklık',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            valueText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Son boşta: $idleText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: maintenance.color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sensor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.44), fontSize: 11),
          ),
          const SizedBox(height: 12),
          _PercentBar(percent: progress, color: maintenance.color),
        ],
      ),
    );
  }
}

class BatteryCard extends StatelessWidget {
  const BatteryCard({super.key, required this.info});

  final BatteryInfo info;

  @override
  Widget build(BuildContext context) {
    final color = !info.available
        ? const Color(0xFF7C8AA5)
        : info.percent <= 20
        ? const Color(0xFFFF6B7A)
        : info.percent <= 40
        ? const Color(0xFFFFC857)
        : const Color(0xFF6CE5C3);
    final valueText = info.available
        ? '${info.percent.toStringAsFixed(0)}%'
        : 'Batarya yok';
    final detail = info.available
        ? '${info.status} • ${info.remainingTime}'
        : 'Masaüstü bilgisayar veya bataryasız cihaz';
    final health = info.healthPercent == null
        ? 'Sağlık bilgisi yok'
        : 'Batarya sağlığı: ${info.healthPercent!.toStringAsFixed(0)}%';

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardIcon(
                icon: info.available
                    ? _batteryIcon(info.percent, info.status)
                    : Icons.battery_unknown_rounded,
                color: color,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Batarya',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            valueText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            health,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.44), fontSize: 11),
          ),
          const SizedBox(height: 12),
          _PercentBar(percent: info.available ? info.percent : 0, color: color),
        ],
      ),
    );
  }
}

class _CardShell extends StatefulWidget {
  const _CardShell({required this.child, this.height = 222});

  final Widget child;
  final double height;

  @override
  State<_CardShell> createState() => _CardShellState();
}

class _CardShellState extends State<_CardShell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedSlide(
        offset: Offset(0, _isHovered ? -0.012 : 0),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: widget.height,
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            color: _isHovered ? const Color(0xFF142138) : const Color(0xFF101B2D),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _isHovered
                  ? primary.withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.065),
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? const Color(0x26000000) : const Color(0x1A000000),
                blurRadius: _isHovered ? 28 : 22,
                offset: Offset(0, _isHovered ? 13 : 10),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _CardIcon extends StatelessWidget {
  const _CardIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class _PercentBar extends StatelessWidget {
  const _PercentBar({required this.percent, required this.color});

  final double percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final safePercent = percent.clamp(0, 100).toDouble();

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(end: safePercent),
      builder: (context, animatedPercent, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: animatedPercent / 100,
            minHeight: 7,
            backgroundColor: Colors.white.withValues(alpha: 0.07),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        );
      },
    );
  }
}

class _SystemDetails extends StatelessWidget {
  const _SystemDetails({
    required this.hostName,
    required this.operatingSystem,
    required this.uptime,
    required this.cpuPercent,
    required this.idleTemperatureValue,
    required this.hardwareInfo,
    required this.batteryInfo,
  });

  final String hostName;
  final String operatingSystem;
  final String uptime;
  final double cpuPercent;
  final double idleTemperatureValue;
  final SystemHardwareInfo hardwareInfo;
  final BatteryInfo batteryInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1728),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sistem ayrıntıları', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DetailChip(
                icon: Icons.computer_rounded,
                label: 'Cihaz',
                value: hostName,
              ),
              _DetailChip(
                icon: Icons.laptop_chromebook_rounded,
                label: 'Sistem',
                value: operatingSystem,
              ),
              _DetailChip(
                icon: Icons.devices_rounded,
                label: 'Cihaz modeli',
                value: hardwareInfo.deviceModel,
              ),
              _DetailChip(
                icon: Icons.memory_rounded,
                label: 'İşlemci',
                value: hardwareInfo.cpuModel,
              ),
              _DetailChip(
                icon: Icons.account_tree_rounded,
                label: 'Mantıksal işlemci',
                value: hardwareInfo.logicalThreads > 0
                    ? '${hardwareInfo.logicalThreads} thread'
                    : 'Okunamadı',
              ),
              _DetailChip(
                icon: Icons.videogame_asset_rounded,
                label: 'Grafik birimi',
                value: hardwareInfo.gpuModel,
              ),
              _DetailChip(
                icon: Icons.storage_rounded,
                label: 'SSD / Disk modeli',
                value: hardwareInfo.storageModel,
              ),
              _DetailChip(
                icon: Icons.developer_board_rounded,
                label: 'Kernel',
                value: hardwareInfo.kernel,
              ),
              _DetailChip(
                icon: Icons.architecture_rounded,
                label: 'Mimari',
                value: hardwareInfo.architecture,
              ),
              _DetailChip(
                icon: Icons.schedule_rounded,
                label: 'Çalışma süresi',
                value: uptime,
              ),
              _DetailChip(
                icon: Icons.speed_rounded,
                label: 'Boşta ölçüm',
                value: cpuPercent < 20 ? 'Etkin' : 'CPU %20 altına düşünce güncellenir',
              ),
              _DetailChip(
                icon: Icons.device_thermostat_rounded,
                label: 'Son güvenilir sıcaklık',
                value: idleTemperatureValue > 0
                    ? '${idleTemperatureValue.toStringAsFixed(1)} °C'
                    : 'Bekleniyor',
              ),
              _DetailChip(
                icon: Icons.battery_saver_rounded,
                label: 'Batarya durumu',
                value: batteryInfo.available
                    ? '${batteryInfo.percent.toStringAsFixed(0)}% • ${batteryInfo.status}'
                    : 'Batarya bulunamadı',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CpuTicks {
  const CpuTicks({required this.idle, required this.total});

  final int idle;
  final int total;
}

class MemoryInfo {
  const MemoryInfo({required this.percent, required this.text});

  final double percent;
  final String text;
}

class DiskInfo {
  const DiskInfo({required this.percent, required this.text});

  final double percent;
  final String text;
}

class TemperatureInfo {
  const TemperatureInfo({
    required this.value,
    required this.text,
    required this.sensor,
  });

  final double value;
  final String text;
  final String sensor;
}

class BatteryInfo {
  const BatteryInfo({
    required this.available,
    required this.percent,
    required this.status,
    required this.healthPercent,
    required this.cycleCount,
    required this.remainingTime,
    required this.model,
  });

  final bool available;
  final double percent;
  final String status;
  final double? healthPercent;
  final int? cycleCount;
  final String remainingTime;
  final String model;
}

class SystemHardwareInfo {
  const SystemHardwareInfo({
    required this.cpuModel,
    required this.gpuModel,
    required this.kernel,
    required this.architecture,
    required this.deviceModel,
    required this.storageModel,
    required this.logicalThreads,
  });

  final String cpuModel;
  final String gpuModel;
  final String kernel;
  final String architecture;
  final String deviceModel;
  final String storageModel;
  final int logicalThreads;
}

class ThermalMaintenance {
  const ThermalMaintenance({
    required this.label,
    required this.description,
    required this.color,
    required this.icon,
  });

  final String label;
  final String description;
  final Color color;
  final IconData icon;
}

class NetworkCounters {
  const NetworkCounters({
    required this.interfaceName,
    required this.receivedBytes,
    required this.sentBytes,
    required this.sampledAt,
  });

  final String interfaceName;
  final int receivedBytes;
  final int sentBytes;
  final DateTime sampledAt;
}

class NetworkPerformance {
  const NetworkPerformance({
    required this.interfaceName,
    required this.downloadBytesPerSecond,
    required this.uploadBytesPerSecond,
    required this.totalReceivedBytes,
    required this.totalSentBytes,
  });

  final String interfaceName;
  final double downloadBytesPerSecond;
  final double uploadBytesPerSecond;
  final int totalReceivedBytes;
  final int totalSentBytes;
}

class DiskIoCounters {
  const DiskIoCounters({
    required this.readBytes,
    required this.writeBytes,
    required this.deviceCount,
    required this.sampledAt,
  });

  final int readBytes;
  final int writeBytes;
  final int deviceCount;
  final DateTime sampledAt;
}

class DiskIoPerformance {
  const DiskIoPerformance({
    required this.readBytesPerSecond,
    required this.writeBytesPerSecond,
    required this.deviceCount,
  });

  final double readBytesPerSecond;
  final double writeBytesPerSecond;
  final int deviceCount;
}

class GpuPerformance {
  const GpuPerformance({
    required this.available,
    required this.name,
    required this.usagePercent,
    required this.temperature,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    required this.source,
  });

  final bool available;
  final String name;
  final double usagePercent;
  final double? temperature;
  final double? memoryUsedBytes;
  final double? memoryTotalBytes;
  final String source;
}

class TemperatureSensorReading {
  const TemperatureSensorReading({required this.label, required this.temperature});

  final String label;
  final double temperature;
}

class FanReading {
  const FanReading({required this.label, required this.rpm});

  final String label;
  final int rpm;
}

class SystemProcessInfo {
  const SystemProcessInfo({
    required this.processId,
    required this.name,
    required this.cpuPercent,
    required this.memoryBytes,
    required this.user,
  });

  final int processId;
  final String name;
  final double cpuPercent;
  final int memoryBytes;
  final String user;
}

CpuTicks? _readCpuTicks() {
  try {
    final statFile = File('/proc/stat');
    if (!statFile.existsSync()) {
      return null;
    }

    final firstLine = statFile.readAsLinesSync().first;
    final values = firstLine
        .trim()
        .split(RegExp(r'\s+'))
        .skip(1)
        .map(int.tryParse)
        .whereType<int>()
        .toList();

    if (values.length < 4) {
      return null;
    }

    final idle = values[3] + (values.length > 4 ? values[4] : 0);
    final total = values.fold<int>(0, (sum, value) => sum + value);
    return CpuTicks(idle: idle, total: total);
  } catch (_) {
    return null;
  }
}

double _calculateCpuPercent(CpuTicks previous, CpuTicks current) {
  final totalDelta = current.total - previous.total;
  final idleDelta = current.idle - previous.idle;

  if (totalDelta <= 0) {
    return 0;
  }

  final busy = (totalDelta - idleDelta) / totalDelta * 100;
  return busy.clamp(0, 100).toDouble();
}

MemoryInfo _readRamInfo() {
  try {
    final memoryFile = File('/proc/meminfo');
    if (!memoryFile.existsSync()) {
      return const MemoryInfo(percent: 0, text: 'Bellek bilgisi yok');
    }

    final entries = <String, int>{};
    for (final line in memoryFile.readAsLinesSync()) {
      final parts = line.split(':');
      if (parts.length != 2) {
        continue;
      }
      final value = int.tryParse(parts[1].trim().split(RegExp(r'\s+')).first);
      if (value != null) {
        entries[parts[0]] = value;
      }
    }

    final totalKb = entries['MemTotal'] ?? 0;
    final availableKb =
        entries['MemAvailable'] ??
        ((entries['MemFree'] ?? 0) +
            (entries['Buffers'] ?? 0) +
            (entries['Cached'] ?? 0));

    if (totalKb <= 0) {
      return const MemoryInfo(percent: 0, text: 'Bellek okunamadı');
    }

    final usedKb = math.max(0, totalKb - availableKb);
    final percent = usedKb / totalKb * 100;
    return MemoryInfo(
      percent: percent.clamp(0, 100).toDouble(),
      text: '${_formatBytes(usedKb * 1024)} / ${_formatBytes(totalKb * 1024)}',
    );
  } catch (_) {
    return const MemoryInfo(percent: 0, text: 'Bellek okunamadı');
  }
}

Future<DiskInfo> _readDiskInfo() async {
  try {
    final result = await Process.run('df', ['-Pk', '/']);
    if (result.exitCode != 0) {
      return const DiskInfo(percent: 0, text: 'Disk bilgisi yok');
    }

    final lines = result.stdout
        .toString()
        .trim()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();

    if (lines.length < 2) {
      return const DiskInfo(percent: 0, text: 'Disk okunamadı');
    }

    final values = lines.last.trim().split(RegExp(r'\s+'));
    if (values.length < 6) {
      return const DiskInfo(percent: 0, text: 'Disk okunamadı');
    }

    final totalKb = int.tryParse(values[1]) ?? 0;
    final usedKb = int.tryParse(values[2]) ?? 0;
    final percent = totalKb <= 0 ? 0.0 : usedKb / totalKb * 100;

    return DiskInfo(
      percent: percent.clamp(0, 100).toDouble(),
      text: '${_formatBytes(usedKb * 1024)} / ${_formatBytes(totalKb * 1024)}',
    );
  } catch (_) {
    return const DiskInfo(percent: 0, text: 'Disk okunamadı');
  }
}

NetworkCounters _readNetworkCounters() {
  var receivedBytes = 0;
  var sentBytes = 0;
  final interfaces = <String>[];
  final defaultInterface = _readDefaultNetworkInterface();

  try {
    final file = File('/proc/net/dev');
    if (file.existsSync()) {
      for (final line in file.readAsLinesSync().skip(2)) {
        final separator = line.indexOf(':');
        if (separator <= 0) {
          continue;
        }

        final interfaceName = line.substring(0, separator).trim();
        if (interfaceName.isEmpty || interfaceName == 'lo') {
          continue;
        }
        if (defaultInterface.isNotEmpty && interfaceName != defaultInterface) {
          continue;
        }

        final values = line.substring(separator + 1).trim().split(RegExp(r'\s+'));
        if (values.length < 9) {
          continue;
        }

        final received = int.tryParse(values[0]) ?? 0;
        final sent = int.tryParse(values[8]) ?? 0;
        receivedBytes += received;
        sentBytes += sent;

        final operationalState = _readTextFile(
          '/sys/class/net/$interfaceName/operstate',
        );
        if (operationalState == 'up' || received > 0 || sent > 0) {
          interfaces.add(interfaceName);
        }
      }
    }
  } catch (_) {
    // Sıfır değerli sayaçlar güvenli yedek olarak döndürülür.
  }

  return NetworkCounters(
    interfaceName: interfaces.isEmpty ? 'Bağlantı yok' : interfaces.join(' + '),
    receivedBytes: receivedBytes,
    sentBytes: sentBytes,
    sampledAt: DateTime.now(),
  );
}

String _readDefaultNetworkInterface() {
  try {
    final routeFile = File('/proc/net/route');
    if (!routeFile.existsSync()) {
      return '';
    }
    for (final line in routeFile.readAsLinesSync().skip(1)) {
      final values = line.trim().split(RegExp(r'\s+'));
      if (values.length > 1 && values[1] == '00000000') {
        return values[0];
      }
    }
  } catch (_) {
    return '';
  }
  return '';
}

NetworkPerformance _calculateNetworkPerformance(
  NetworkCounters? previous,
  NetworkCounters current,
) {
  if (previous == null) {
    return NetworkPerformance(
      interfaceName: current.interfaceName,
      downloadBytesPerSecond: 0,
      uploadBytesPerSecond: 0,
      totalReceivedBytes: current.receivedBytes,
      totalSentBytes: current.sentBytes,
    );
  }

  final elapsed =
      current.sampledAt.difference(previous.sampledAt).inMicroseconds / 1000000;
  if (elapsed <= 0) {
    return NetworkPerformance(
      interfaceName: current.interfaceName,
      downloadBytesPerSecond: 0,
      uploadBytesPerSecond: 0,
      totalReceivedBytes: current.receivedBytes,
      totalSentBytes: current.sentBytes,
    );
  }

  final receivedDelta = math.max(0, current.receivedBytes - previous.receivedBytes);
  final sentDelta = math.max(0, current.sentBytes - previous.sentBytes);
  return NetworkPerformance(
    interfaceName: current.interfaceName,
    downloadBytesPerSecond: receivedDelta / elapsed,
    uploadBytesPerSecond: sentDelta / elapsed,
    totalReceivedBytes: current.receivedBytes,
    totalSentBytes: current.sentBytes,
  );
}

DiskIoCounters _readDiskIoCounters() {
  var readBytes = 0;
  var writeBytes = 0;
  var deviceCount = 0;

  try {
    final file = File('/proc/diskstats');
    if (file.existsSync()) {
      for (final line in file.readAsLinesSync()) {
        final values = line.trim().split(RegExp(r'\s+'));
        if (values.length < 10) {
          continue;
        }

        final deviceName = values[2];
        if (deviceName.startsWith('loop') ||
            deviceName.startsWith('ram') ||
            deviceName.startsWith('zram') ||
            deviceName.startsWith('dm-') ||
            deviceName.startsWith('md')) {
          continue;
        }

        if (File('/sys/class/block/$deviceName/partition').existsSync()) {
          continue;
        }

        final readSectors = int.tryParse(values[5]);
        final writtenSectors = int.tryParse(values[9]);
        if (readSectors == null || writtenSectors == null) {
          continue;
        }

        readBytes += readSectors * 512;
        writeBytes += writtenSectors * 512;
        deviceCount++;
      }
    }
  } catch (_) {
    // Sayaçlar desteklenmiyorsa sıfır değerleri kullanılır.
  }

  return DiskIoCounters(
    readBytes: readBytes,
    writeBytes: writeBytes,
    deviceCount: deviceCount,
    sampledAt: DateTime.now(),
  );
}

DiskIoPerformance _calculateDiskIoPerformance(
  DiskIoCounters? previous,
  DiskIoCounters current,
) {
  if (previous == null) {
    return DiskIoPerformance(
      readBytesPerSecond: 0,
      writeBytesPerSecond: 0,
      deviceCount: current.deviceCount,
    );
  }

  final elapsed =
      current.sampledAt.difference(previous.sampledAt).inMicroseconds / 1000000;
  if (elapsed <= 0) {
    return DiskIoPerformance(
      readBytesPerSecond: 0,
      writeBytesPerSecond: 0,
      deviceCount: current.deviceCount,
    );
  }

  final readDelta = math.max(0, current.readBytes - previous.readBytes);
  final writeDelta = math.max(0, current.writeBytes - previous.writeBytes);
  return DiskIoPerformance(
    readBytesPerSecond: readDelta / elapsed,
    writeBytesPerSecond: writeDelta / elapsed,
    deviceCount: current.deviceCount,
  );
}

Future<GpuPerformance> _readGpuPerformance(String fallbackName) async {
  try {
    final result = await Process.run('nvidia-smi', [
      '--query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total',
      '--format=csv,noheader,nounits',
    ]);
    if (result.exitCode == 0) {
      final line = result.stdout
          .toString()
          .split('\n')
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      final values = line.split(',').map((value) => value.trim()).toList();
      if (values.length >= 5) {
        final usage = double.tryParse(values[1]);
        final temperature = double.tryParse(values[2]);
        final memoryUsedMb = double.tryParse(values[3]);
        final memoryTotalMb = double.tryParse(values[4]);
        if (usage != null) {
          return GpuPerformance(
            available: true,
            name: values[0].isEmpty ? fallbackName : values[0],
            usagePercent: usage.clamp(0, 100).toDouble(),
            temperature: temperature,
            memoryUsedBytes: memoryUsedMb == null ? null : memoryUsedMb * 1024 * 1024,
            memoryTotalBytes: memoryTotalMb == null
                ? null
                : memoryTotalMb * 1024 * 1024,
            source: 'nvidia-smi',
          );
        }
      }
    }
  } catch (_) {
    // NVIDIA aracı yoksa sysfs ile devam edilir.
  }

  try {
    final drmDirectory = Directory('/sys/class/drm');
    if (drmDirectory.existsSync()) {
      for (final entity in drmDirectory.listSync()) {
        final name = entity.path.split('/').last;
        if (!RegExp(r'^card\d+$').hasMatch(name)) {
          continue;
        }

        final devicePath = '${entity.path}/device';
        final usage =
            _readNumberFile('$devicePath/gpu_busy_percent') ??
            _readNumberFile('$devicePath/gt_busy_percent');
        if (usage == null) {
          continue;
        }

        double? temperature;
        final hwmonDirectory = Directory('$devicePath/hwmon');
        if (hwmonDirectory.existsSync()) {
          for (final hwmonEntity in hwmonDirectory.listSync()) {
            final candidate = _readTemperatureValue(
              File('${hwmonEntity.path}/temp1_input'),
            );
            if (candidate != null) {
              temperature = candidate;
              break;
            }
          }
        }

        final vendorCode = _readTextFile('$devicePath/vendor').toLowerCase();
        final vendorName = switch (vendorCode) {
          '0x8086' => 'Intel GPU',
          '0x10de' => 'NVIDIA GPU',
          '0x1002' || '0x1022' => 'AMD GPU',
          _ => fallbackName,
        };

        return GpuPerformance(
          available: true,
          name: vendorName.isEmpty ? name : vendorName,
          usagePercent: usage.clamp(0, 100).toDouble(),
          temperature: temperature,
          memoryUsedBytes: null,
          memoryTotalBytes: null,
          source: 'sysfs',
        );
      }
    }
  } catch (_) {
    // Desteklenmeyen sürücü güvenli bir sonuç döndürür.
  }

  return GpuPerformance(
    available: false,
    name: fallbackName.isEmpty ? 'GPU kullanım sensörü yok' : fallbackName,
    usagePercent: 0,
    temperature: null,
    memoryUsedBytes: null,
    memoryTotalBytes: null,
    source: 'Desteklenmiyor',
  );
}

Future<List<SystemProcessInfo>> _readSystemProcesses() async {
  final result = await Process.run('ps', [
    '-eo',
    'pid=,comm=,pcpu=,rss=,user=',
    '--sort=-pcpu',
  ]);
  if (result.exitCode != 0) {
    throw const FormatException('ps çıktısı alınamadı');
  }

  final processes = <SystemProcessInfo>[];
  for (final line in result.stdout.toString().split('\n')) {
    final values = line.trim().split(RegExp(r'\s+'));
    if (values.length < 5) {
      continue;
    }

    final processId = int.tryParse(values[0]);
    final cpuPercent = double.tryParse(values[2].replaceAll(',', '.'));
    final memoryKb = int.tryParse(values[3]);
    if (processId == null || cpuPercent == null || memoryKb == null) {
      continue;
    }

    processes.add(
      SystemProcessInfo(
        processId: processId,
        name: values[1],
        cpuPercent: cpuPercent.clamp(0, 100).toDouble(),
        memoryBytes: memoryKb * 1024,
        user: values.sublist(4).join(' '),
      ),
    );
  }
  return processes;
}

BatteryInfo _readBatteryInfo() {
  const unavailable = BatteryInfo(
    available: false,
    percent: 0,
    status: 'Batarya bulunamadı',
    healthPercent: null,
    cycleCount: null,
    remainingTime: '—',
    model: '—',
  );

  try {
    final powerDirectory = Directory('/sys/class/power_supply');
    if (!powerDirectory.existsSync()) {
      return unavailable;
    }

    Directory? batteryDirectory;
    for (final directory in powerDirectory.listSync().whereType<Directory>()) {
      final type = _readTextFile('${directory.path}/type').toLowerCase();
      final name = directory.path.split('/').last.toUpperCase();
      if (type == 'battery' || name.startsWith('BAT')) {
        batteryDirectory = directory;
        break;
      }
    }

    if (batteryDirectory == null) {
      return unavailable;
    }

    final path = batteryDirectory.path;
    final percent = _readNumberFile('$path/capacity') ?? 0;
    final rawStatus = _readTextFile('$path/status');
    final status = _translateBatteryStatus(rawStatus);

    final full =
        _readNumberFile('$path/energy_full') ?? _readNumberFile('$path/charge_full');
    final design =
        _readNumberFile('$path/energy_full_design') ??
        _readNumberFile('$path/charge_full_design');
    final health = full != null && design != null && design > 0
        ? (full / design * 100).clamp(0, 100).toDouble()
        : null;

    final cycleValue = _readNumberFile('$path/cycle_count');
    final cycleCount = cycleValue?.round();
    final manufacturer = _readTextFile('$path/manufacturer');
    final modelName = _readTextFile('$path/model_name');
    final model = [
      manufacturer,
      modelName,
    ].where((value) => value.isNotEmpty).join(' ').trim();

    final now =
        _readNumberFile('$path/energy_now') ?? _readNumberFile('$path/charge_now');
    final rate =
        _readNumberFile('$path/power_now') ?? _readNumberFile('$path/current_now');
    final remainingTime = _calculateBatteryTime(
      rawStatus: rawStatus,
      now: now,
      full: full,
      rate: rate,
    );

    return BatteryInfo(
      available: true,
      percent: percent.clamp(0, 100).toDouble(),
      status: status,
      healthPercent: health,
      cycleCount: cycleCount,
      remainingTime: remainingTime,
      model: model.isEmpty ? batteryDirectory.path.split('/').last : model,
    );
  } catch (_) {
    return unavailable;
  }
}

TemperatureInfo _readTemperatureInfo() {
  final candidates = <_TemperatureCandidate>[];

  try {
    final thermalDirectory = Directory('/sys/class/thermal');
    if (thermalDirectory.existsSync()) {
      for (final entity in thermalDirectory.listSync()) {
        if (entity is! Directory ||
            !entity.path.split('/').last.startsWith('thermal_zone')) {
          continue;
        }

        final tempFile = File('${entity.path}/temp');
        final typeFile = File('${entity.path}/type');
        final value = _readTemperatureValue(tempFile);
        if (value == null) {
          continue;
        }

        final sensor = typeFile.existsSync()
            ? typeFile.readAsStringSync().trim()
            : 'thermal_zone';
        candidates.add(
          _TemperatureCandidate(
            value: value,
            sensor: sensor,
            priority: _temperatureSensorPriority(sensor),
          ),
        );
      }
    }

    final hwmonDirectory = Directory('/sys/class/hwmon');
    if (hwmonDirectory.existsSync()) {
      for (final hwmon in hwmonDirectory.listSync().whereType<Directory>()) {
        final nameFile = File('${hwmon.path}/name');
        final deviceName = nameFile.existsSync()
            ? nameFile.readAsStringSync().trim()
            : 'hwmon';

        for (final entity in hwmon.listSync().whereType<File>()) {
          final fileName = entity.path.split('/').last;
          if (!RegExp(r'^temp\d+_input$').hasMatch(fileName)) {
            continue;
          }

          final value = _readTemperatureValue(entity);
          if (value == null) {
            continue;
          }

          final index = RegExp(r'\d+').firstMatch(fileName)?.group(0) ?? '';
          final labelFile = File('${hwmon.path}/temp${index}_label');
          final label = labelFile.existsSync()
              ? labelFile.readAsStringSync().trim()
              : '';
          final sensor = label.isEmpty ? deviceName : '$deviceName • $label';

          candidates.add(
            _TemperatureCandidate(
              value: value,
              sensor: sensor,
              priority: _temperatureSensorPriority('$deviceName $label'),
            ),
          );
        }
      }
    }
  } catch (_) {
    return const TemperatureInfo(
      value: 0,
      text: 'Sıcaklık okunamadı',
      sensor: 'Sensör okuma hatası',
    );
  }

  if (candidates.isEmpty) {
    return const TemperatureInfo(
      value: 0,
      text: 'Sıcaklık bilgisi yok',
      sensor: 'Uyumlu sensör bulunamadı',
    );
  }

  candidates.sort((a, b) {
    final priorityComparison = b.priority.compareTo(a.priority);
    if (priorityComparison != 0) {
      return priorityComparison;
    }
    return b.value.compareTo(a.value);
  });

  final selected = candidates.first;
  return TemperatureInfo(
    value: selected.value,
    text: '${selected.value.toStringAsFixed(1)} °C',
    sensor: 'Sensör: ${selected.sensor}',
  );
}

List<TemperatureSensorReading> _readAllTemperatureSensors() {
  final readings = <TemperatureSensorReading>[];
  final seen = <String>{};

  void addReading(String label, double? temperature) {
    if (temperature == null) {
      return;
    }
    final normalizedLabel = label.trim().isEmpty ? 'Sıcaklık sensörü' : label.trim();
    final key = '$normalizedLabel:${temperature.toStringAsFixed(1)}';
    if (seen.add(key)) {
      readings.add(
        TemperatureSensorReading(label: normalizedLabel, temperature: temperature),
      );
    }
  }

  try {
    final hwmonDirectory = Directory('/sys/class/hwmon');
    if (hwmonDirectory.existsSync()) {
      for (final hwmonEntity in hwmonDirectory.listSync()) {
        final hwmon = Directory(hwmonEntity.path);
        if (!hwmon.existsSync()) {
          continue;
        }
        final deviceName = _readTextFile('${hwmon.path}/name');

        for (final entity in hwmon.listSync()) {
          final fileName = entity.path.split('/').last;
          final match = RegExp(r'^temp(\d+)_input$').firstMatch(fileName);
          if (match == null) {
            continue;
          }

          final index = match.group(1) ?? '';
          final sensorLabel = _readTextFile('${hwmon.path}/temp${index}_label');
          final label = [
            deviceName,
            sensorLabel,
          ].where((value) => value.isNotEmpty).join(' • ');
          addReading(
            label.isEmpty ? 'hwmon • temp$index' : label,
            _readTemperatureValue(File(entity.path)),
          );
        }
      }
    }

    final thermalDirectory = Directory('/sys/class/thermal');
    if (thermalDirectory.existsSync()) {
      for (final entity in thermalDirectory.listSync()) {
        final name = entity.path.split('/').last;
        if (!name.startsWith('thermal_zone')) {
          continue;
        }
        final type = _readTextFile('${entity.path}/type');
        addReading(
          type.isEmpty ? name : type,
          _readTemperatureValue(File('${entity.path}/temp')),
        );
      }
    }
  } catch (_) {
    return readings;
  }

  readings.sort((a, b) => b.temperature.compareTo(a.temperature));
  return readings;
}

List<FanReading> _readFanReadings() {
  final readings = <FanReading>[];

  try {
    final hwmonDirectory = Directory('/sys/class/hwmon');
    if (!hwmonDirectory.existsSync()) {
      return readings;
    }

    for (final hwmonEntity in hwmonDirectory.listSync()) {
      final hwmon = Directory(hwmonEntity.path);
      if (!hwmon.existsSync()) {
        continue;
      }
      final deviceName = _readTextFile('${hwmon.path}/name');

      for (final entity in hwmon.listSync()) {
        final fileName = entity.path.split('/').last;
        final match = RegExp(r'^fan(\d+)_input$').firstMatch(fileName);
        if (match == null) {
          continue;
        }

        final rpm = int.tryParse(_readTextFile(entity.path));
        if (rpm == null || rpm < 0) {
          continue;
        }
        final index = match.group(1) ?? '';
        final sensorLabel = _readTextFile('${hwmon.path}/fan${index}_label');
        final label = [
          deviceName,
          sensorLabel.isEmpty ? 'Fan $index' : sensorLabel,
        ].where((value) => value.isNotEmpty).join(' • ');
        readings.add(FanReading(label: label, rpm: rpm));
      }
    }
  } catch (_) {
    return readings;
  }

  return readings;
}

double? _readTemperatureValue(File file) {
  try {
    if (!file.existsSync()) {
      return null;
    }

    final rawValue = double.tryParse(file.readAsStringSync().trim());
    if (rawValue == null) {
      return null;
    }

    final degree = rawValue.abs() > 1000 ? rawValue / 1000 : rawValue;
    if (degree <= 0 || degree >= 150) {
      return null;
    }
    return degree;
  } catch (_) {
    return null;
  }
}

int _temperatureSensorPriority(String sensorName) {
  final sensor = sensorName.toLowerCase();

  if (sensor.contains('x86_pkg_temp') ||
      sensor.contains('coretemp') ||
      sensor.contains('k10temp') ||
      sensor.contains('zenpower') ||
      sensor.contains('cpu') ||
      sensor.contains('package')) {
    return 100;
  }
  if (sensor.contains('tctl') || sensor.contains('tdie') || sensor.contains('core')) {
    return 90;
  }
  if (sensor.contains('acpitz')) {
    return 60;
  }
  if (sensor.contains('nvme') ||
      sensor.contains('wifi') ||
      sensor.contains('iwlwifi')) {
    return 10;
  }
  return 30;
}

Future<SystemHardwareInfo> _readSystemHardwareInfo() async {
  final cpuModel = _readCpuModel();
  final deviceModel = _readDeviceModel();
  final storageModel = await _readStorageModel();
  final logicalThreads = Platform.numberOfProcessors;

  var kernel = Platform.operatingSystemVersion.trim();
  var architecture = 'x86_64';
  var gpuModel = _readGpuVendorFallback();

  try {
    final result = await Process.run('uname', ['-r']);
    final value = result.stdout.toString().trim();
    if (result.exitCode == 0 && value.isNotEmpty) {
      kernel = value;
    }
  } catch (_) {
    // Platform değeri yedek olarak kullanılır.
  }

  try {
    final result = await Process.run('uname', ['-m']);
    final value = result.stdout.toString().trim();
    if (result.exitCode == 0 && value.isNotEmpty) {
      architecture = value;
    }
  } catch (_) {
    // Hedef platform Pardus 25 x86_64.
  }

  try {
    final result = await Process.run('lspci', ['-mm']);
    if (result.exitCode == 0) {
      final graphicsLines = result.stdout
          .toString()
          .split('\n')
          .where(
            (line) =>
                line.contains('VGA compatible controller') ||
                line.contains('3D controller') ||
                line.contains('Display controller'),
          )
          .map(
            (line) =>
                line.replaceAll('"', '').replaceFirst(RegExp(r'^[^\s]+\s+'), '').trim(),
          )
          .where((line) => line.isNotEmpty)
          .toList();
      if (graphicsLines.isNotEmpty) {
        gpuModel = graphicsLines.join(' + ');
      }
    }
  } catch (_) {
    // pciutils yoksa sysfs üretici bilgisi gösterilir.
  }

  return SystemHardwareInfo(
    cpuModel: cpuModel,
    gpuModel: gpuModel,
    kernel: kernel.isEmpty ? 'Okunamadı' : kernel,
    architecture: architecture,
    deviceModel: deviceModel,
    storageModel: storageModel,
    logicalThreads: logicalThreads,
  );
}

String _readCpuModel() {
  try {
    final file = File('/proc/cpuinfo');
    if (!file.existsSync()) {
      return 'İşlemci bilgisi yok';
    }

    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('model name') ||
          line.startsWith('Hardware') ||
          line.startsWith('Processor')) {
        final separator = line.indexOf(':');
        if (separator >= 0) {
          final value = line.substring(separator + 1).trim();
          if (value.isNotEmpty) {
            return value;
          }
        }
      }
    }
  } catch (_) {
    return 'İşlemci okunamadı';
  }
  return 'İşlemci okunamadı';
}

String _readDeviceModel() {
  final vendor = _readTextFile('/sys/class/dmi/id/sys_vendor');
  final product = _readTextFile('/sys/class/dmi/id/product_name');
  final version = _readTextFile('/sys/class/dmi/id/product_version');
  final values = <String>[];

  for (final value in [vendor, product, version]) {
    if (value.isNotEmpty &&
        value.toLowerCase() != 'default string' &&
        !values.contains(value)) {
      values.add(value);
    }
  }

  return values.isEmpty ? 'Model bilgisi yok' : values.join(' ');
}

Future<String> _readStorageModel() async {
  try {
    final result = await Process.run('lsblk', ['-dn', '-o', 'NAME,MODEL,TYPE']);
    if (result.exitCode == 0) {
      final disks = <String>[];
      for (final line in result.stdout.toString().split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.endsWith(' disk')) {
          continue;
        }

        final withoutType = trimmed.substring(0, trimmed.length - 5).trim();
        final firstSpace = withoutType.indexOf(RegExp(r'\s+'));
        final model = firstSpace < 0 ? '' : withoutType.substring(firstSpace).trim();
        final name = firstSpace < 0
            ? withoutType
            : withoutType.substring(0, firstSpace).trim();

        if (model.isNotEmpty) {
          disks.add(model);
        } else if (name.isNotEmpty) {
          final sysfsModel = _readTextFile('/sys/class/block/$name/device/model');
          disks.add(sysfsModel.isEmpty ? name : sysfsModel);
        }
      }

      if (disks.isNotEmpty) {
        return disks.join(' + ');
      }
    }
  } catch (_) {
    // lsblk yoksa sysfs üzerinden devam edilir.
  }

  try {
    final blockDirectory = Directory('/sys/class/block');
    if (blockDirectory.existsSync()) {
      for (final directory in blockDirectory.listSync().whereType<Directory>()) {
        final name = directory.path.split('/').last;
        if (name.startsWith('loop') ||
            name.startsWith('ram') ||
            name.startsWith('zram') ||
            name.startsWith('dm-')) {
          continue;
        }

        final model = _readTextFile('${directory.path}/device/model');
        if (model.isNotEmpty) {
          return model;
        }
      }
    }
  } catch (_) {
    return 'SSD modeli okunamadı';
  }

  return 'SSD modeli okunamadı';
}

String _readGpuVendorFallback() {
  try {
    final drmDirectory = Directory('/sys/class/drm');
    if (!drmDirectory.existsSync()) {
      return 'Grafik birimi okunamadı';
    }

    final vendors = <String>{};
    for (final directory in drmDirectory.listSync().whereType<Directory>()) {
      final name = directory.path.split('/').last;
      if (!RegExp(r'^card\d+$').hasMatch(name)) {
        continue;
      }

      final vendorCode = _readTextFile('${directory.path}/device/vendor');
      final vendor = switch (vendorCode.toLowerCase()) {
        '0x8086' => 'Intel grafik birimi',
        '0x10de' => 'NVIDIA grafik birimi',
        '0x1002' => 'AMD grafik birimi',
        '0x1022' => 'AMD grafik birimi',
        _ => vendorCode.isEmpty ? '' : 'GPU $vendorCode',
      };
      if (vendor.isNotEmpty) {
        vendors.add(vendor);
      }
    }

    if (vendors.isNotEmpty) {
      return vendors.join(' + ');
    }
  } catch (_) {
    return 'Grafik birimi okunamadı';
  }
  return 'Grafik birimi okunamadı';
}

String _readOperatingSystemName() {
  try {
    final file = File('/etc/os-release');
    if (!file.existsSync()) {
      return Platform.operatingSystem;
    }

    final values = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      final separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      var value = line.substring(separator + 1).trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      values[line.substring(0, separator)] = value;
    }

    return values['PRETTY_NAME'] ?? values['NAME'] ?? Platform.operatingSystem;
  } catch (_) {
    return Platform.operatingSystem;
  }
}

String _readUptime() {
  try {
    final uptimeFile = File('/proc/uptime');
    if (!uptimeFile.existsSync()) {
      return '—';
    }

    final seconds =
        double.tryParse(
          uptimeFile.readAsStringSync().trim().split(RegExp(r'\s+')).first,
        )?.floor() ??
        0;
    final duration = Duration(seconds: math.max(0, seconds));
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);

    if (days > 0) {
      return '$days gün $hours saat';
    }
    if (hours > 0) {
      return '$hours saat $minutes dk';
    }
    return '$minutes dakika';
  } catch (_) {
    return '—';
  }
}

String _readTextFile(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) {
      return '';
    }
    return file.readAsStringSync().trim();
  } catch (_) {
    return '';
  }
}

double? _readNumberFile(String path) {
  final value = _readTextFile(path);
  return value.isEmpty ? null : double.tryParse(value);
}

String _translateBatteryStatus(String status) {
  switch (status.trim().toLowerCase()) {
    case 'charging':
      return 'Şarj oluyor';
    case 'discharging':
      return 'Bataryadan çalışıyor';
    case 'full':
      return 'Tam dolu';
    case 'not charging':
      return 'Şarj edilmiyor';
    case 'unknown':
    case '':
      return 'Durum bilinmiyor';
    default:
      return status;
  }
}

String _calculateBatteryTime({
  required String rawStatus,
  required double? now,
  required double? full,
  required double? rate,
}) {
  if (now == null || rate == null || rate <= 0) {
    return 'Süre hesaplanamadı';
  }

  final normalizedStatus = rawStatus.trim().toLowerCase();
  double hours;

  if (normalizedStatus == 'charging' && full != null && full > now) {
    hours = (full - now) / rate;
  } else if (normalizedStatus == 'discharging') {
    hours = now / rate;
  } else if (normalizedStatus == 'full') {
    return 'Tam dolu';
  } else {
    return 'Süre hesaplanamadı';
  }

  if (!hours.isFinite || hours <= 0 || hours > 240) {
    return 'Süre hesaplanamadı';
  }

  final duration = Duration(minutes: (hours * 60).round());
  final hourPart = duration.inHours;
  final minutePart = duration.inMinutes.remainder(60);
  final prefix = normalizedStatus == 'charging' ? 'Doluma' : 'Tahmini';

  if (hourPart > 0) {
    return '$prefix $hourPart sa $minutePart dk';
  }
  return '$prefix $minutePart dk';
}

IconData _batteryIcon(double percent, String status) {
  if (status == 'Şarj oluyor') {
    return Icons.battery_charging_full_rounded;
  }
  if (percent <= 15) {
    return Icons.battery_alert_rounded;
  }
  if (percent <= 35) {
    return Icons.battery_2_bar_rounded;
  }
  if (percent <= 60) {
    return Icons.battery_4_bar_rounded;
  }
  if (percent <= 85) {
    return Icons.battery_5_bar_rounded;
  }
  return Icons.battery_full_rounded;
}

String _formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  final digits = value >= 100 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String _formatSpeed(num bytesPerSecond) {
  return '${_formatBytes(math.max(0, bytesPerSecond))}/sn';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class _TemperatureCandidate {
  const _TemperatureCandidate({
    required this.value,
    required this.sensor,
    required this.priority,
  });

  final double value;
  final String sensor;
  final int priority;
}