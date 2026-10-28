import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/player.dart';
import 'services/bluetooth_service.dart';
import 'widgets/bottle_wheel.dart';
import 'widgets/player_input_dialog.dart';

enum GameState {
  setup,
  ready,
  spinning,
  evaluating,
  cooldown,
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  static const String _prefsPlayersKey = 'saved_players_names';

  late final BluetoothService _bluetoothService;
  late final AudioPlayer _audioPlayer;

  GameState _gameState = GameState.setup;
  String _bleStatus = "Поиск эфира...";
  String _appVersion = '';

  List<Player> _players = [];
  int? _winningIndex;

  bool _isBleCalibrated = false; // Защита от огромного первого пакета
  int _basePulses = 0;
  int _currentPulses = 0;
  int? _lastPacketPulses;

  Timer? _safetyTimeoutTimer;
  Timer? _cooldownTimer;
  int _cooldownSecondsRemaining = 15;

  // Непрерывный тикер для свободного физического вращения
  late final Ticker _physicsTicker;
  double _bottleAngle = 0.0;
  double _angularVelocity = 0.0; // рад/с
  double _targetVelocity = 0.0;

  // Анимация фиксации на победителе и возврата на 12 часов
  AnimationController? _settleAnimController;
  Animation<double>? _settleAnimation;

  @override
  void initState() {
    super.initState();

    _audioPlayer = AudioPlayer();
    _loadAppVersion();

    // Тикер обновляет угол вращения каждый кадр экрана (60/120 fps)
    _physicsTicker = createTicker((elapsed) {
      if (_gameState == GameState.spinning) {
        // Плавная интерполяция текущей скорости к целевой
        _angularVelocity += (_targetVelocity - _angularVelocity) * 0.08;
        setState(() {
          _bottleAngle = (_bottleAngle + _angularVelocity * 0.016) % (2 * math.pi);
        });
      }
    });
    _physicsTicker.start();

    _bluetoothService = BluetoothService(
      onStatusChanged: (status) {
        if (mounted) setState(() => _bleStatus = status);
      },
      onDataReceived: (inboundValue) {
        _handleInboundPulses(inboundValue);
      },
    );

    _loadSavedPlayers();
    _bluetoothService.start();
  }

  @override
  void dispose() {
    _physicsTicker.dispose();
    _bluetoothService.dispose();
    _audioPlayer.dispose();
    _safetyTimeoutTimer?.cancel();
    _cooldownTimer?.cancel();
    _settleAnimController?.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'v ${packageInfo.version}';
      });
    }
  }

  Future<void> _loadSavedPlayers() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? savedNames = prefs.getStringList(_prefsPlayersKey);

    if (savedNames != null && savedNames.length >= 2) {
      final restoredPlayers = _buildPlayersFromNames(savedNames);
      if (mounted) {
        setState(() {
          _players = restoredPlayers;
          _gameState = GameState.ready;
        });
      }
    }
  }

  Future<void> _savePlayersToStorage(List<Player> players) async {
    final prefs = await SharedPreferences.getInstance();
    final names = players.map((p) => p.name).toList();
    await prefs.setStringList(_prefsPlayersKey, names);
  }

  List<Player> _buildPlayersFromNames(List<String> names) {
    const List<Color> palette = [
      Colors.green,
      Colors.redAccent,
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.amber,
    ];

    final int count = names.length;
    List<Color> assignedColors = [];

    for (int i = 0; i < count; i++) {
      Color candidate = palette[i % palette.length];

      if (i == count - 1 && count > 1) {
        final Color firstColor = assignedColors[0];
        final Color prevColor = assignedColors[i - 1];

        if (candidate == firstColor || candidate == prevColor) {
          for (Color c in palette) {
            if (c != firstColor && c != prevColor) {
              candidate = c;
              break;
            }
          }
        }
      }
      assignedColors.add(candidate);
    }

    return List.generate(count, (index) {
      return Player(
        id: index.toString(),
        name: names[index],
        color: assignedColors[index],
      );
    });
  }

  /// Тап по колесу: звук «Дзинь», мгновенный сброс кулдауна, 2 оборота и парковка на 12 часах
  Future<void> _onWheelTapped() async {
    // Разрешаем тап как в режиме ожидания, так и во время 15-секундного кулдауна
    if (_gameState != GameState.ready && _gameState != GameState.cooldown) return;

    // Сбрасываем таймер ожидания раунда
    _cooldownTimer?.cancel();

    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('glass.mp3'));
    } catch (_) {}

    _basePulses = _currentPulses;
    _lastPacketPulses = null;
    _angularVelocity = 0.0;
    _targetVelocity = 0.0;

    final double start = _bottleAngle;
    final double norm = start % (2 * math.pi);
    final double target = start + (4 * math.pi) + ((2 * math.pi) - norm);

    _settleAnimController?.dispose();
    _settleAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _settleAnimation = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _settleAnimController!, curve: Curves.easeOutCubic),
    )..addListener(() {
      setState(() {
        _bottleAngle = _settleAnimation!.value;
      });
    });

    _settleAnimController!.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _bottleAngle = 0.0;
        _winningIndex = null;
        _gameState = GameState.ready; // Сразу готовы к новому запуску спиннера
      });
    });
  }

  void _handleInboundPulses(int inboundValue) {
    if (!mounted) return;

    _currentPulses = inboundValue;

    // Первичная калибровка при холодном старте
    if (!_isBleCalibrated) {
      _basePulses = _currentPulses;
      _lastPacketPulses = _currentPulses;
      _isBleCalibrated = true;
      return;
    }

    // Состояние готовности: ждем физического запуска спиннера
    if (_gameState == GameState.ready) {
      if (_players.length >= 2 && _currentPulses > _basePulses) {
        setState(() {
          _gameState = GameState.spinning;
          _winningIndex = null;
          _lastPacketPulses = _currentPulses;
          _angularVelocity = 28.0;
          _targetVelocity = 28.0;
        });
        _armSafetyTimeout();
      } else {
        _basePulses = _currentPulses;
      }
      return;
    }

    // Состояние вращения
    if (_gameState == GameState.spinning) {
      final totalDelta = _currentPulses - _basePulses;
      if (totalDelta <= 0) return;

      // МГНОВЕННАЯ ОСТАНОВКА: пришел дубликат пакета -> спиннер встал
      if (_lastPacketPulses != null && _currentPulses == _lastPacketPulses) {
        _safetyTimeoutTimer?.cancel();
        _onSpinnerStopped();
        return;
      }

      // Вычисляем дельту импульсов между соседними пакетами для контроля скорости
      final int stepDelta = (_lastPacketPulses != null)
          ? (_currentPulses - _lastPacketPulses!)
          : totalDelta;

      if (stepDelta >= 20) {
        _targetVelocity = 28.0; // Максимальная скорость
      } else if (stepDelta >= 10) {
        _targetVelocity = 16.0; // Средний темп
      } else if (stepDelta >= 4) {
        _targetVelocity = 7.0;  // Заметное замедление
      } else {
        _targetVelocity = 2.5;  // Финальный выбег по инерции
      }

      setState(() {
        _lastPacketPulses = _currentPulses;
      });

      // Страховочный таймер держим только на случай потери радиосвязи в полете
      _armSafetyTimeout();
    }
  }

  void _armSafetyTimeout() {
    _safetyTimeoutTimer?.cancel();
    _safetyTimeoutTimer = Timer(const Duration(milliseconds: 3200), () {
      if (_gameState == GameState.spinning) {
        _onSpinnerStopped();
      }
    });
  }

  void _onSpinnerStopped() {
    if (!mounted) return;
    _safetyTimeoutTimer?.cancel();
    _targetVelocity = 0.0;

    final totalDelta = _currentPulses - _basePulses;

    setState(() {
      _gameState = GameState.evaluating;
    });

    if (totalDelta < 21) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Крутите сильнее! Всего $totalDelta об. (нужно ≥ 21)'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      setState(() {
        _gameState = GameState.ready;
        _basePulses = _currentPulses;
        _lastPacketPulses = null;
        _angularVelocity = 0.0;
      });
      return;
    }

    // Расчет сектора победителя
    final int count = _players.length;
    final int winIdx = totalDelta % count;
    final double sweep = (2 * math.pi) / count;
    final double targetSectorAngle = (winIdx * sweep) + (sweep / 2);

    final double start = _bottleAngle;
    final double norm = start % (2 * math.pi);
    double diff = targetSectorAngle - norm;
    if (diff < 0) {
      diff += 2 * math.pi;
    }

    // Если угол до сектора совсем крошечный, даем один красивый круг на затухание
    final double crawlAngle = (diff < 0.4) ? (diff + 2 * math.pi) : diff;
    final double finalTarget = start + crawlAngle;

    // Время доползания подстраивается под оставшийся угол (без рывка)
    final int durationMs = (1000 + (crawlAngle / (2 * math.pi) * 1200)).round();

    _settleAnimController?.dispose();
    _settleAnimController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    _settleAnimation = Tween<double>(begin: start, end: finalTarget).animate(
      CurvedAnimation(parent: _settleAnimController!, curve: Curves.easeOutQuad),
    )..addListener(() {
      setState(() {
        _bottleAngle = _settleAnimation!.value;
      });
    });

    _settleAnimController!.forward().then((_) {
      if (!mounted) return;
      setState(() {
        _bottleAngle = targetSectorAngle;
        _winningIndex = winIdx;
        _startCooldownTimer();
      });
    });
  }

  void _startCooldownTimer() {
    setState(() {
      _gameState = GameState.cooldown;
      _cooldownSecondsRemaining = 15;
    });

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _cooldownSecondsRemaining--;
        if (_cooldownSecondsRemaining <= 0) {
          timer.cancel();
          _gameState = GameState.ready;
          _basePulses = _currentPulses;
          _lastPacketPulses = null;
          _winningIndex = null;
          _angularVelocity = 0.0;
        }
      });
    });
  }

  Future<void> _openPlayerDialog() async {
    final result = await showDialog<List<Player>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlayerInputDialog(initialPlayers: _players),
    );

    if (result != null && result.length >= 2) {
      await _savePlayersToStorage(result);
      setState(() {
        _players = result;
        _gameState = GameState.ready;
        _winningIndex = null;
        _lastPacketPulses = null;
        _basePulses = _currentPulses;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Spin the Bottle',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_appVersion.isNotEmpty)
              Text(
                _appVersion,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'Настроить игроков',
            onPressed: (_gameState == GameState.ready || _gameState == GameState.setup)
                ? _openPlayerDialog
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                _bleStatus,
                style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Center(
                child: _players.isEmpty
                    ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.people_outline, size: 80, color: Colors.grey),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _openPlayerDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить участников'),
                    ),
                  ],
                )
                    : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GestureDetector(
                    onTap: _onWheelTapped,
                    behavior: HitTestBehavior.opaque,
                    child: BottleWheel(
                      players: _players,
                      currentAngle: _bottleAngle,
                      winningPlayerIndex: _winningIndex,
                    ),
                  ),
                ),
              ),
            ),
            // Фиксированная высота блока: колесо никогда не скачет
            SizedBox(
              height: 96,
              child: Center(child: _buildBottomStatusArea()),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatusArea() {
    if (_players.length < 2) return const SizedBox.shrink();

    switch (_gameState) {
      case GameState.ready:
        return const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Крутите спиннер!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'или нажмите на диск для сброса',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        );

      case GameState.spinning:
        final currentDelta = math.max(0, _currentPulses - _basePulses);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Вращается...',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Оборотов: $currentDelta',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        );

      case GameState.evaluating:
      case GameState.cooldown:
        final winnerName = (_winningIndex != null && _winningIndex! < _players.length)
            ? _players[_winningIndex!].name
            : '';

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_winningIndex != null) ...[
              Text(
                'Выбрано: $winnerName! 🎉',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _players[_winningIndex!].color,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              'Следующий раунд через: $_cooldownSecondsRemaining с',
              style: const TextStyle(fontSize: 15, color: Colors.blueGrey),
            ),
          ],
        );

      case GameState.setup:
        return const SizedBox.shrink();
    }
  }
}