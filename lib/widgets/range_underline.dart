import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Paints selected UTF-16 ranges below a paragraph's alphabetic baseline.
///
/// Ranges refer to the final paragraph text, where each inline widget occupies
/// one replacement character. This wrapper preserves its child's measurement,
/// wrapping, semantics and baseline, including paragraphs containing ruby.
class RangeUnderline extends SingleChildRenderObjectWidget {
  const RangeUnderline({
    super.key,
    required this.ranges,
    required this.color,
    this.offset = 2,
    this.thickness = 1,
    required super.child,
  }) : assert(offset >= 0 && offset < double.infinity),
       assert(thickness > 0 && thickness < double.infinity);

  final List<TextRange> ranges;
  final Color color;
  final double offset;
  final double thickness;

  @override
  RenderRangeUnderline createRenderObject(BuildContext context) =>
      RenderRangeUnderline(ranges, color, offset, thickness);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRangeUnderline renderObject,
  ) {
    renderObject
      ..ranges = ranges
      ..color = color
      ..offset = offset
      ..thickness = thickness;
  }
}

class RenderRangeUnderline extends RenderProxyBox {
  RenderRangeUnderline(
    List<TextRange> ranges,
    this._color, [
    this._offset = 2,
    this._thickness = 1,
  ]) : _ranges = List.unmodifiable(ranges);

  final TextPainter _linePainter = TextPainter();
  RenderParagraph? _paintParagraph;
  List<ui.LineMetrics> _paintLines = const [];
  double _paintBaselineShift = 0;
  double _paintScale = 1;

  List<TextRange> get ranges => _ranges;
  List<TextRange> _ranges;
  set ranges(List<TextRange> value) {
    if (listEquals(_ranges, value)) return;
    _ranges = List.unmodifiable(value);
    markNeedsPaint();
  }

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

  List<PlaceholderDimensions> _placeholders(RenderParagraph paragraph) => [
    for (
      RenderBox? child = paragraph.firstChild;
      child != null;
      child = paragraph.childAfter(child)
    )
      if ((child.parentData! as TextParentData).span case final span?)
        PlaceholderDimensions(
          size: child.size,
          alignment: span.alignment,
          baseline: span.baseline,
          baselineOffset: span.alignment == PlaceholderAlignment.baseline
              ? child.getDryBaseline(child.constraints, span.baseline!)
              : null,
        )
      else
        PlaceholderDimensions.empty,
  ];

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintParagraph = null;
    _paintLines = const [];
    final paragraph = _paragraph(child);
    if (paragraph == null) {
      super.paint(context, offset);
      return;
    }

    // Reuse the final paragraph configuration and already-laid-out widget
    // dimensions solely to locate line baselines. Never lay out real children.
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
      ..setPlaceholderDimensions(_placeholders(paragraph))
      ..layout(
        minWidth: paragraph.constraints.minWidth,
        maxWidth:
            paragraph.softWrap || paragraph.overflow == TextOverflow.ellipsis
            ? paragraph.constraints.maxWidth
            : double.infinity,
      );
    final lines = _linePainter.computeLineMetrics();
    if (lines.isEmpty) {
      super.paint(context, offset);
      return;
    }
    // WidgetSpan aligns to the paragraph's public alphabetic baseline. Native
    // line metrics may retain a fractional value that this baseline rounds.
    final firstBaseline = identical(child, paragraph)
        ? paragraph.getDistanceToBaseline(
            TextBaseline.alphabetic,
            onlyReal: true,
          )
        : paragraph.getDryBaseline(
            paragraph.constraints,
            TextBaseline.alphabetic,
          );
    final baselineShift =
        (firstBaseline ?? lines.first.baseline) - lines.first.baseline;

    // A plain paragraph scales font sizes itself; a ruby paragraph is inside
    // an already-scaled WidgetSpan and has no local text scaling. Match both.
    final fontSize = paragraph.text.style?.fontSize ?? 14;
    final scale = fontSize == 0
        ? 1.0
        : paragraph.textScaler.scale(fontSize) / fontSize;
    // Publish the enclosing line geometry before painting ruby descendants.
    // A native placeholder can round its own baseline by half a pixel; all
    // fragments of the same outer line must use one underline anchor.
    _paintParagraph = paragraph;
    _paintLines = lines;
    _paintBaselineShift = baselineShift;
    _paintScale = scale;
    super.paint(context, offset);
    if (_ranges.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness * scale
      ..strokeCap = StrokeCap.butt;
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.transform(paragraph.getTransformTo(this).storage);
    if (paragraph.overflow != TextOverflow.visible) {
      canvas.clipRect(Offset.zero & paragraph.size);
    }
    final textLength = paragraph.text.toPlainText().length;
    for (final range in _ranges) {
      if (range.start < 0 ||
          range.end > textLength ||
          range.end <= range.start) {
        continue;
      }
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      )) {
        if (box.right <= box.left) continue;
        final line = _lineForBox(lines, box);
        if (line == null) continue;
        final y =
            _enclosingBaseline(paragraph, box) ??
            line.baseline + baselineShift + this.offset * scale;
        canvas.drawLine(Offset(box.left, y), Offset(box.right, y), paint);
      }
    }
    canvas.restore();
  }

  double? _enclosingBaseline(RenderParagraph paragraph, ui.TextBox box) {
    for (
      RenderObject? ancestor = parent;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      if (ancestor is! RenderRangeUnderline) continue;
      final enclosing = ancestor._paintParagraph;
      if (enclosing == null) continue;
      final bounds = MatrixUtils.transformRect(
        paragraph.getTransformTo(enclosing),
        box.toRect(),
      );
      final line = ancestor._paintLines
          .where(
            (line) =>
                line.baseline >= bounds.top - .01 &&
                line.baseline <= bounds.bottom + .01,
          )
          .firstOrNull;
      if (line == null) continue;
      final point = enclosing.localToGlobal(
        Offset(
          0,
          line.baseline +
              ancestor._paintBaselineShift +
              ancestor.offset * ancestor._paintScale,
        ),
      );
      return paragraph.globalToLocal(point).dy;
    }
    return null;
  }

  ui.LineMetrics? _lineForBox(List<ui.LineMetrics> lines, ui.TextBox box) {
    // Selection boxes use glyph bounds; their alphabetic baseline lies inside
    // those bounds even when adjacent runs select different fallback fonts.
    for (final line in lines) {
      if (line.baseline >= box.top - .01 && line.baseline <= box.bottom + .01) {
        return line;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _linePainter.dispose();
    super.dispose();
  }
}
