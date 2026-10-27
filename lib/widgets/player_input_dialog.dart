import 'package:flutter/material.dart';
import '../models/player.dart';

class PlayerInputDialog extends StatefulWidget {
  final List<Player> initialPlayers;

  const PlayerInputDialog({
    super.key,
    this.initialPlayers = const [],
  });

  @override
  State<PlayerInputDialog> createState() => _PlayerInputDialogState();
}

class _PlayerInputDialogState extends State<PlayerInputDialog> {
  final TextEditingController _nameController = TextEditingController();
  final List<String> _playerNames = [];

  // 6 базовых сочных цветов (Lego / филамент)
  static const List<Color> _palette = [
    Colors.green,        // 0: Зеленый
    Colors.redAccent,    // 1: Красный
    Colors.blue,         // 2: Синий
    Colors.orange,       // 3: Оранжевый
    Colors.purple,       // 4: Фиолетовый
    Colors.amber,        // 5: Желтый
  ];

  @override
  void initState() {
    super.initState();
    _playerNames.addAll(widget.initialPlayers.map((p) => p.name));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Назначает цвета всем игрокам так, чтобы ни у кого из соседей по кругу
  /// (включая первого и последнего) цвет не совпадал.
  List<Player> _buildBalancedPlayers() {
    final int count = _playerNames.length;
    if (count == 0) return [];

    List<Color> assignedColors = [];

    for (int i = 0; i < count; i++) {
      Color candidate = _palette[i % _palette.length];

      // Проверка для самого последнего участника: он граничит и с (count - 2), и с 0
      if (i == count - 1 && count > 1) {
        final Color firstColor = assignedColors[0];
        final Color prevColor = assignedColors[i - 1];

        // Если цвет совпадает с первым или предыдущим - берем первый подходящий из палитры
        if (candidate == firstColor || candidate == prevColor) {
          for (Color c in _palette) {
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
        name: _playerNames[index],
        color: assignedColors[index],
      );
    });
  }

  void _addPlayer() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _playerNames.add(name);
      _nameController.clear();
    });
  }

  void _removePlayer(int index) {
    setState(() {
      _playerNames.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayers = _buildBalancedPlayers();

    return AlertDialog(
      title: const Text('Участники игры'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Имя игрока',
                      hintText: 'Введите имя',
                    ),
                    onSubmitted: (_) => _addPlayer(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.blue, size: 32),
                  onPressed: _addPlayer,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: currentPlayers.isEmpty
                  ? const Center(
                child: Text(
                  'Добавьте минимум 2 игроков',
                  style: TextStyle(color: Colors.grey),
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                itemCount: currentPlayers.length,
                itemBuilder: (context, index) {
                  final player = currentPlayers[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: player.color,
                      radius: 12,
                    ),
                    title: Text(
                      player.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => _removePlayer(index),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: currentPlayers.length >= 2
              ? () => Navigator.of(context).pop(currentPlayers)
              : null,
          child: const Text('Готово'),
        ),
      ],
    );
  }
}