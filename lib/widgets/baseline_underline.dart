import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Draws each line of a plain text child at a consistent distance below its
/// alphabetic baseline, independent of the selected font's underline metrics.
///
/// The child should contain a single text paragraph without inline widgets.
/// Its native text decoration should be disabled. This widget does not add
/// padding or participate in text measurement, wrapping, or baseline selection.
class BaselineUnderline extends SingleChildRenderObjectWidget {
  const BaselineUnderline({
    super.key,
    required this.color,
    this.offset = 2,
    this.thickness = 1,
    required super.child,
  }) : assert(offset >= 0),
       assert(thickness > 0);

  final Color color;
  final double offset;
  final double thickness;

  @override
  RenderBaselineUnderline createRenderObject(BuildContext context) =>
      RenderBaselineUnderline(color, offset, thickness);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBaselineUnderline renderObject,
  ) {
    renderObject
      ..color = color
      ..offset = offset
      ..thickness = thickness;
  }
}

class RenderBaselineUnderline extends RenderProxyBox {
  RenderBaselineUnderline(this._color, [this._offset = 2, this._thickness = 1]);

  final TextPainter _linePainter = TextPainter();

  Color get color => _color;
  Color _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  double get offset => _offset;
  double _offset;
  set offset(double value) {
    assert(value >= 0 && value.isFinite);
    if (_offset == value) return;
    _offset = value;
    markNeedsPaint();
  }

  double get thickness => _thickness;
  double _thickness;
  set thickness(double value) {
    assert(value > 0 && value.isFinite);
    if (_thickness == value) return;
    _thickness = value;
    markNeedsPaint();
  }

  RenderParagraph? _paragraph(RenderObject? object) {
    if (object is RenderParagraph) return object;
    RenderParagraph? result;
    object?.visitChildren((child) {
      result ??= _paragraph(child);
    });
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final paragraph = _paragraph(child);
    if (paragraph == null || paragraph.childCount != 0) return;

    // Copy the final RenderParagraph configuration, including inherited locale,
    // accessibility overrides and the actual layout constraints. This painter
    // is only for the already-wrapped line geometry; it never sizes the child.
    _linePainter
      ..text = paragraph.text
      ..textAlign = paragraph.textAlign
      ..textDirection = paragraph.textDirection
      ..textScaler = paragraph.textScaler
      ..maxLines = paragraph.maxLines
      ..ellipsis = paragraph.overflow == TextOverflow.ellipsis ? '\u2026' : null
      ..locale = paragraph.locale
      ..strutStyle = paragraph.strutStyle
      ..textWidthBasis = paragraph.textWidthBasis
      ..textHeightBehavior = paragraph.textHeightBehavior
      ..layout(
        minWidth: paragraph.constraints.minWidth,
        maxWidth:
            paragraph.softWrap || paragraph.overflow == TextOverflow.ellipsis
            ? paragraph.constraints.maxWidth
            : double.infinity,
      );

    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.transform(paragraph.getTransformTo(this).storage);
    if (paragraph.overflow != TextOverflow.visible) {
      canvas.clipRect(Offset.zero & paragraph.size);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    for (final line in _linePainter.computeLineMetrics()) {
      if (line.width <= 0) continue;
      final y = line.baseline + this.offset;
      canvas.drawLine(
        Offset(line.left, y),
        Offset(line.left + line.width, y),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  void dispose() {
    _linePainter.dispose();
    super.dispose();
  }
}
