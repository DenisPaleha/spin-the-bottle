import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/player.dart';
import 'services/bluetooth_service.dart';
import 'widgets/bottle_wheel.dart';
import 'widgets/player_input_dialog.dart';

enum GameState {
  setup,        // Ввод игроков
  ready,        // Ждем нажатия "Пуск"
  waitingSpin,  // "Крутите!" (ждем начала вращения)
  spinning,     // Спиннер вращается
  evaluating,   // Остановка и показ результата
  cooldown,     // 15 секунд отдыха перед новым раундом
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  static const String _prefsPlayersKey = 'saved_players_names';

  late final BluetoothService _bluetoothService;

  GameState _gameState = GameState.setup;
  String _bleStatus = "Поиск эфира...";

  List<Player> _players = [];
  int? _winningIndex;

  int _basePulses = 0;        // Импульсы на момент нажатия "Пуск"
  int _currentPulses = 0;     // Текущие входящие импульсы
  int? _lastPacketPulses;     // Предыдущий пакет для детекции остановки

  Timer? _safetyTimeoutTimer;
  Timer? _cooldownTimer;
  int _cooldownSecondsRemaining = 15;

  late AnimationController _bottleAnimController;
  late Animation<double> _bottleAnimation;
  double _currentBottleAngle = 0.0;

  @override
  void initState() {
    super.initState();

    _bottleAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _bottleAnimation = CurvedAnimation(
      parent: _bottleAnimController,
      curve: Curves.easeOutCubic,
    );

    _bottleAnimation.addListener(() {
      setState(() {
        _currentBottleAngle = _bottleAnimation.value;
      });
    });

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
    _bluetoothService.dispose();
    _safetyTimeoutTimer?.cancel();
    _cooldownTimer?.cancel();
    _bottleAnimController.dispose();
    super.dispose();
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

  void _handleInboundPulses(int inboundValue) {
    if (!mounted) return;

    _currentPulses = inboundValue;

    if (_gameState != GameState.waitingSpin && _gameState != GameState.spinning) {
      return;
    }

    final totalDelta = _currentPulses - _basePulses;
    if (totalDelta <= 0) return;

    if (_gameState == GameState.waitingSpin) {
      setState(() {
        _gameState = GameState.spinning;
        _lastPacketPulses = _currentPulses;
      });
      _armSafetyTimeout();
      return;
    }

    if (_gameState == GameState.spinning) {
      if (_lastPacketPulses != null && _currentPulses == _lastPacketPulses) {
        _safetyTimeoutTimer?.cancel();
        _onSpinnerStopped();
      } else {
        setState(() {
          _lastPacketPulses = _currentPulses;
        });
        _armSafetyTimeout();
      }
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
        _lastPacketPulses = null;
      });
      return;
    }

    final int count = _players.length;
    final int winIdx = totalDelta % count;
    final double sweep = (2 * math.pi) / count;
    final double targetSectorAngle = (winIdx * sweep) + (sweep / 2);

    final double finalAngle = _currentBottleAngle +
        (4 * math.pi) +
        (targetSectorAngle - (_currentBottleAngle % (2 * math.pi)));

    _bottleAnimation = Tween<double>(
      begin: _currentBottleAngle,
      end: finalAngle,
    ).animate(CurvedAnimation(parent: _bottleAnimController, curve: Curves.easeOutCubic));

    _bottleAnimController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      setState(() {
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
          _lastPacketPulses = null;
          _winningIndex = null;
        }
      });
    });
  }

  void _onStartButtonPressed() {
    setState(() {
      _basePulses = _currentPulses;
      _lastPacketPulses = null;
      _winningIndex = null;
      _gameState = GameState.waitingSpin;
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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spin the Bottle'),
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
              padding: const EdgeInsets.all(8.0),
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
                  child: BottleWheel(
                    players: _players,
                    currentAngle: _currentBottleAngle,
                    winningPlayerIndex: _winningIndex,
                  ),
                ),
              ),
            ),
            _buildBottomControls(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    if (_players.length < 2) return const SizedBox.shrink();

    switch (_gameState) {
      case GameState.ready:
        return ElevatedButton(
          onPressed: _onStartButtonPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: const Text(
            'ПУСК',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        );

      case GameState.waitingSpin:
      case GameState.spinning:
        final currentDelta = math.max(0, _currentPulses - _basePulses);
        return Column(
          children: [
            Text(
              _gameState == GameState.waitingSpin ? 'Крутите!' : 'Вращается...',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.deepOrange,
              ),
            ),
            const SizedBox(height: 8),
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
              const SizedBox(height: 8),
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