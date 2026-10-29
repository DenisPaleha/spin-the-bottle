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

  static const List<Color> _palette = [
    Colors.green,
    Colors.redAccent,
    Colors.blue,
    Colors.orange,
    Colors.purple,
    Colors.amber,
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

  List<Player> _buildBalancedPlayers() {
    final int count = _playerNames.length;
    if (count == 0) return [];

    List<Color> assignedColors = [];

    for (int i = 0; i < count; i++) {
      Color candidate = _palette[i % _palette.length];

      if (i == count - 1 && count > 1) {
        final Color firstColor = assignedColors[0];
        final Color prevColor = assignedColors[i - 1];

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
      _playerNames.insert(0, name);
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
      title: const Text('Players'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Player Name',
                        hintText: 'Enter name',
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
              const SizedBox(height: 12),
              if (currentPlayers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'Add at least 2 players',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: currentPlayers.length,
                  itemBuilder: (context, index) {
                    final player = currentPlayers[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: currentPlayers.length >= 2
              ? () => Navigator.of(context).pop(currentPlayers)
              : null,
          child: const Text('Done'),
        ),
      ],
    );
  }
}