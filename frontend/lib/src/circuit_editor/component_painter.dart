import 'package:flutter/material.dart';
import 'dart:math' as math; // For PI, and potentially other math functions

//
// extension type const ComponentType(String name) {
//
//   static ComponentType $and = ComponentType()
//
// }
//
final class CircuitComponentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // TODO: implement paint
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // TODO: implement shouldRepaint
    throw UnimplementedError();
  }
}

// Define the types of nodes
enum NodeType {
  inputNode,
  outputNode,
  andNode,
  orNode,
  notNode,
  circuitNode; // Represents a nested circuit

  String get displayName {
    switch (this) {
      case NodeType.inputNode:
        return 'Input';
      case NodeType.outputNode:
        return 'Output';
      case NodeType.andNode:
        return 'AND';
      case NodeType.orNode:
        return 'OR';
      case NodeType.notNode:
        return 'NOT';
      case NodeType.circuitNode:
        return 'Circuit';
    }
  }

  // Optional: A way to get NodeType from a string if needed elsewhere
  static NodeType fromString(String typeString) {
    switch (typeString.toLowerCase()) {
      case 'input':
      case 'inputnode':
        return NodeType.inputNode;
      case 'output':
      case 'outputnode':
        return NodeType.outputNode;
      case 'and':
      case 'andnode':
        return NodeType.andNode;
      case 'or':
      case 'ornode':
        return NodeType.orNode;
      case 'not':
      case 'notnode':
        return NodeType.notNode;
      case 'circuit':
      case 'circuitnode':
        return NodeType.circuitNode;
      default:
        throw ArgumentError('Unknown NodeType string: $typeString');
    }
  }
}

// The Painter
class CircuitNodePainter extends CustomPainter {
  final NodeType nodeType;
  final String label; // Optional label for the node
  final Color nodeColor;
  final Color borderColor;
  final double strokeWidth;

  CircuitNodePainter({
    required this.nodeType,
    this.label = '',
    this.nodeColor = Colors.blueGrey,
    this.borderColor = Colors.black,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // Center of the canvas provided by 'size'
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCenter(center: center, width: size.width, height: size.height);

    switch (nodeType) {
      case NodeType.inputNode:
      case NodeType.outputNode:
        // Draw a circle
        final radius = math.min(size.width, size.height) / 2 - strokeWidth;
        canvas.drawCircle(center, radius, paint);
        canvas.drawCircle(center, radius, borderPaint);
        break;

      case NodeType.andNode:
        // Box with curved right side (like a D shape)
        final path = Path()
          ..moveTo(rect.left, rect.top)
          ..lineTo(rect.left, rect.bottom)
          ..lineTo(rect.center.dx, rect.bottom)
          ..arcToPoint(Offset(rect.center.dx, rect.top), radius: Radius.circular(rect.height / 2), clockwise: false)
          ..lineTo(rect.left, rect.top)
          ..close();
        canvas.drawPath(path, paint);
        canvas.drawPath(path, borderPaint);
        break;

      case NodeType.orNode:
        // Box with all ends curved (rounded rectangle)
        final rrect = RRect.fromRectAndRadius(
          rect,
          Radius.circular(math.min(size.width, size.height) * 0.25),
        ); // Adjust radius as needed
        canvas.drawRRect(rrect, paint);
        canvas.drawRRect(rrect, borderPaint);
        break;

      case NodeType.notNode:
        // Triangle (equilateral for simplicity, pointing right)
        final path = Path();
        // Pointing right:
        path.moveTo(rect.left, rect.top); // Top-left
        path.lineTo(rect.right, rect.center.dy); // Mid-right
        path.lineTo(rect.left, rect.bottom); // Bottom-left
        path.close();
        canvas.drawPath(path, paint);
        canvas.drawPath(path, borderPaint);
        // Optionally, add a small circle at the output for NOT gate symbol
        final circleRadius = math.min(size.width, size.height) * 0.1;
        canvas.drawCircle(Offset(rect.right + circleRadius + strokeWidth, center.dy), circleRadius, paint);
        canvas.drawCircle(Offset(rect.right + circleRadius + strokeWidth, center.dy), circleRadius, borderPaint);
        break;

      case NodeType.circuitNode:
        // Box with no curved edges (simple rectangle)
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect, borderPaint);
        break;
    }

    // Draw label if provided
    if (label.isNotEmpty) {
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: borderColor,
          fontSize: math.min(size.width, size.height) * 0.3,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(text: textSpan, textAlign: TextAlign.center, textDirection: TextDirection.ltr);
      textPainter.layout(minWidth: 0, maxWidth: size.width * 0.8); // Constrain label width
      final offset = Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2);
      textPainter.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(covariant CircuitNodePainter oldDelegate) {
    return oldDelegate.nodeType != nodeType ||
        oldDelegate.label != label ||
        oldDelegate.nodeColor != nodeColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

// Example Usage (how you might use this painter in a widget):
class CircuitNodeWidget extends StatelessWidget {
  final NodeType type;
  final String label;
  final Size size;

  const CircuitNodeWidget({
    super.key,
    required this.type,
    this.label = '',
    this.size = const Size(120, 80), // Default size
  });

  @override
  Widget build(BuildContext context) {
    String nodeSpecificLabel = label;
    // You might want to automatically set a label based on type if none is provided
    if (nodeSpecificLabel.isEmpty) {
      switch (type) {
        case NodeType.andNode:
          nodeSpecificLabel = 'AND';
          break;
        case NodeType.orNode:
          nodeSpecificLabel = 'OR';
          break;
        // Add other defaults as needed
        default:
          break;
      }
    }

    return CustomPaint(
      size: size,
      painter: CircuitNodePainter(
        nodeType: type,
        label: nodeSpecificLabel,
        nodeColor: _getNodeColor(type), // Helper to get color based on type
        borderColor: Colors.black,
      ),
    );
  }

  Color _getNodeColor(NodeType type) {
    // Return different colors based on type for better visual distinction
    switch (type) {
      case NodeType.inputNode:
        return Colors.lightGreenAccent;
      case NodeType.outputNode:
        return Colors.orangeAccent;
      case NodeType.andNode:
        return Colors.lightBlueAccent;
      case NodeType.orNode:
        return Colors.purpleAccent.shade100;
      case NodeType.notNode:
        return Colors.pinkAccent.shade100;
      case NodeType.circuitNode:
        return Colors.grey.shade400;
    }
  }
}
