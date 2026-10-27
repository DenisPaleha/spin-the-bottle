import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/player.dart';

class BottleWheel extends StatelessWidget {
  final List<Player> players;
  final double currentAngle;
  final int? winningPlayerIndex;

  const BottleWheel({
    super.key,
    required this.players,
    required this.currentAngle,
    this.winningPlayerIndex,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _WheelPainter(
              players: players,
              winningIndex: winningPlayerIndex,
            ),
          ),
          Transform.rotate(
            angle: currentAngle,
            child: _buildBottle(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottle() {
    return Container(
      width: 44,
      height: 154,
      decoration: BoxDecoration(
        color: const Color(0xFF3E2723), // Темное стекло
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(10),
          bottom: Radius.circular(22),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Горлышко
          Container(
            width: 14,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF271510),
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),
          // Золотистая этикетка
          Expanded(
            child: Center(
              child: Container(
                width: 32,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: Text(
                    '★',
                    style: TextStyle(
                      color: Color(0xFF3E2723),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<Player> players;
  final int? winningIndex;

  _WheelPainter({
    required this.players,
    this.winningIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (players.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    // Оставляем запас 24 пикселя по краям, чтобы увеличенный сектор не обрезался
    final baseRadius = math.min(size.width, size.height) / 2 - 24;
    final sweepAngle = (2 * math.pi) / players.length;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    // 1. Первый проход: рисуем все обычные секторы без рамок
    for (int i = 0; i < players.length; i++) {
      if (winningIndex == i) continue; // Победителя нарисуем поверх вторым слоем

      final startAngle = i * sweepAngle - (math.pi / 2);
      fillPaint.color = players[i].color;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: baseRadius),
        startAngle,
        sweepAngle,
        true,
        fillPaint,
      );

      _drawPlayerName(
        canvas,
        players[i].name,
        center,
        baseRadius * 0.65,
        startAngle + sweepAngle / 2,
      );
    }

    // 2. Второй проход: рисуем сектор победителя (увеличенный радиус, наплыв поверх соседей)
    if (winningIndex != null && winningIndex! >= 0 && winningIndex! < players.length) {
      final int i = winningIndex!;
      final startAngle = i * sweepAngle - (math.pi / 2);
      final elevatedRadius = baseRadius + 14; // Выдвижение на 14 пикселей

      // Тень под сектором победителя для эффекта глубины
      final shadowPaint = Paint()
        ..color = Colors.black45
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: elevatedRadius),
        startAngle,
        sweepAngle,
        true,
        shadowPaint,
      );

      // Сам увеличенный сектор
      fillPaint.color = players[i].color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: elevatedRadius),
        startAngle,
        sweepAngle,
        true,
        fillPaint,
      );

      _drawPlayerName(
        canvas,
        players[i].name,
        center,
        elevatedRadius * 0.66,
        startAngle + sweepAngle / 2,
      );
    }
  }

  void _drawPlayerName(
      Canvas canvas,
      String name,
      Offset center,
      double textRadius,
      double angle,
      ) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 8),
            Shadow(color: Colors.black87, blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final x = center.dx + textRadius * math.cos(angle) - textPainter.width / 2;
    final y = center.dy + textRadius * math.sin(angle) - textPainter.height / 2;

    textPainter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    return oldDelegate.players != players || oldDelegate.winningIndex != winningIndex;
  }
}