import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/core/widgets/theme_toggle_button.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';
import 'package:medicoscope/models/detection_result.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';

class DetectionResultsScreen extends StatefulWidget {
  final DetectionResult result;
  final File imageFile;

  const DetectionResultsScreen({
    super.key,
    required this.result,
    required this.imageFile,
  });

  @override
  State<DetectionResultsScreen> createState() =>
      _DetectionResultsScreenState();
}

class _DetectionResultsScreenState extends State<DetectionResultsScreen> {
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    if (widget.result.hasBoundingBox) {
      _loadImageSize();
    }
  }

  Future<void> _loadImageSize() async {
    final bytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _imageSize = Size(
          frame.image.width.toDouble(),
          frame.image.height.toDouble(),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.darkBackgroundGradient
              : AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // 3D Model Background
              if (widget.result.model3dPath.isNotEmpty)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.3,
                    child: ModelViewer(
                      src: widget.result.model3dPath,
                      alt: '3D model of ${widget.result.className}',
                      autoRotate: true,
                      cameraControls: false,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),

              // Content
              Column(
                children: [
                  // App Bar
                  Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingMedium),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_ios),
                          color: AppTheme.textDark,
                        ),
                        Expanded(
                          child: Text(
                            AppStrings.get('detection_results', lang),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  // Theme toggle button
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AppTheme.spacingMedium,
                      right: AppTheme.spacingMedium,
                    ),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: const ThemeToggleButton(size: 36),
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(AppTheme.spacingLarge),
                      child: Column(
                        children: [
                          // Image Preview with optional bounding box
                          _buildImagePreview(),

                          const SizedBox(height: AppTheme.spacingXLarge),

                          // Detection Result Card
                          GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(
                                          AppTheme.spacingMedium),
                                      decoration: BoxDecoration(
                                        gradient: AppTheme.orangeGradient,
                                        borderRadius: BorderRadius.circular(
                                            AppTheme.radiusMedium),
                                      ),
                                      child: const Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                    ),
                                    const SizedBox(
                                        width: AppTheme.spacingMedium),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            AppStrings.get('detected_condition', lang),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: AppTheme.textGray,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(
                                              height: AppTheme.spacingXSmall),
                                          Text(
                                            widget.result.className,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.textDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: AppTheme.spacingLarge),

                                // Confidence
                                Container(
                                  padding: const EdgeInsets.all(
                                      AppTheme.spacingMedium),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryOrange
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(
                                        AppTheme.radiusMedium),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        AppStrings.get('confidence', lang),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppTheme.textGray,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        '${(widget.result.confidence * 100).toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.primaryOrange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: AppTheme.spacingLarge),

                                // Description
                                Text(
                                  AppStrings.get('description', lang),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textDark,
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spacingSmall),
                                Text(
                                  widget.result.description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.6,
                                    color: AppTheme.textGray,
                                  ),
                                ),
                              ],
                            ),
                          )
                              .animate()
                              .fadeIn(delay: 200.ms, duration: 600.ms)
                              .slideY(begin: 0.2, end: 0),

                          const SizedBox(height: AppTheme.spacingXLarge),

                          // 3D Model Viewer
                          if (widget.result.model3dPath.isNotEmpty) ...[
                            GlassCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(
                                        AppTheme.spacingMedium),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.view_in_ar_outlined,
                                          color: AppTheme.primaryOrange,
                                        ),
                                        const SizedBox(
                                            width: AppTheme.spacingSmall),
                                        Text(
                                          AppStrings.get('3d_visualization', lang),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: 300,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          AppTheme.radiusLarge),
                                      child: ModelViewer(
                                        src: widget.result.model3dPath,
                                        alt:
                                            '3D model of ${widget.result.className}',
                                        ar: true,
                                        arModes: const [
                                          'scene-viewer',
                                          'webxr',
                                          'quick-look'
                                        ],
                                        autoRotate: true,
                                        autoRotateDelay: 0,
                                        rotationPerSecond: '30deg',
                                        cameraControls: true,
                                        backgroundColor: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(
                                        AppTheme.spacingMedium),
                                    child: Text(
                                      AppStrings.get('rotate_zoom', lang),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textGray,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            )
                                .animate()
                                .fadeIn(delay: 400.ms, duration: 600.ms)
                                .slideY(begin: 0.2, end: 0),

                            const SizedBox(height: AppTheme.spacingLarge),
                          ],

                          // Disclaimer
                          Container(
                            padding:
                                const EdgeInsets.all(AppTheme.spacingMedium),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMedium),
                              border: Border.all(
                                color: Colors.amber.shade200,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amber.shade700,
                                ),
                                const SizedBox(width: AppTheme.spacingSmall),
                                Expanded(
                                  child: Text(
                                    AppStrings.get('ai_disclaimer', lang),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                              .animate()
                              .fadeIn(delay: 600.ms, duration: 600.ms),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final bool showBbox = widget.result.hasBoundingBox && _imageSize != null;
    final BoxFit imageFit = showBbox ? BoxFit.contain : BoxFit.cover;

    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;
        const containerHeight = 300.0;

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          child: Container(
            height: containerHeight,
            width: double.infinity,
            color: showBbox ? Colors.black : null,
            child: Stack(
              children: [
                // The image
                SizedBox(
                  height: containerHeight,
                  width: double.infinity,
                  child: Image.file(
                    widget.imageFile,
                    height: containerHeight,
                    width: double.infinity,
                    fit: imageFit,
                  ),
                ),

                // Bounding box overlay
                if (showBbox)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BoundingBoxPainter(
                        bboxX: widget.result.bboxX!,
                        bboxY: widget.result.bboxY!,
                        bboxWidth: widget.result.bboxWidth!,
                        bboxHeight: widget.result.bboxHeight!,
                        imageSize: _imageSize!,
                        containerWidth: containerWidth,
                        containerHeight: containerHeight,
                        label: widget.result.className,
                        confidence: widget.result.confidence,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .scale(begin: const Offset(0.9, 0.9));
  }
}

// ── Bounding Box Painter ─────────────────────────────────────────────────────

class _BoundingBoxPainter extends CustomPainter {
  final double bboxX; // normalized center_x (0-1)
  final double bboxY; // normalized center_y (0-1)
  final double bboxWidth; // normalized width (0-1)
  final double bboxHeight; // normalized height (0-1)
  final Size imageSize; // original image dimensions
  final double containerWidth;
  final double containerHeight;
  final String label;
  final double confidence;

  _BoundingBoxPainter({
    required this.bboxX,
    required this.bboxY,
    required this.bboxWidth,
    required this.bboxHeight,
    required this.imageSize,
    required this.containerWidth,
    required this.containerHeight,
    required this.label,
    required this.confidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Compute how BoxFit.contain scales the image within the container
    final double imageAspect = imageSize.width / imageSize.height;
    final double containerAspect = containerWidth / containerHeight;

    double displayWidth, displayHeight, offsetX, offsetY;

    if (imageAspect > containerAspect) {
      // Image is wider — width fills container, height has letterbox bars
      displayWidth = containerWidth;
      displayHeight = containerWidth / imageAspect;
      offsetX = 0;
      offsetY = (containerHeight - displayHeight) / 2;
    } else {
      // Image is taller — height fills container, width has pillarbox bars
      displayHeight = containerHeight;
      displayWidth = containerHeight * imageAspect;
      offsetX = (containerWidth - displayWidth) / 2;
      offsetY = 0;
    }

    // Convert normalized YOLO bbox (center_x, center_y, w, h) to pixel rect
    final double rectLeft =
        offsetX + (bboxX - bboxWidth / 2) * displayWidth;
    final double rectTop =
        offsetY + (bboxY - bboxHeight / 2) * displayHeight;
    final double rectW = bboxWidth * displayWidth;
    final double rectH = bboxHeight * displayHeight;

    final Rect rect = Rect.fromLTWH(rectLeft, rectTop, rectW, rectH);

    // Draw the bounding box rectangle
    final Paint boxPaint = Paint()
      ..color = const Color(0xFFFF6B35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final RRect rRect =
        RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rRect, boxPaint);

    // Draw corner accent brackets for visual emphasis
    final Paint cornerPaint = Paint()
      ..color = const Color(0xFFFF6B35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const double cornerLen = 16;

    // Top-left
    canvas.drawLine(
        Offset(rect.left, rect.top + cornerLen), rect.topLeft, cornerPaint);
    canvas.drawLine(
        rect.topLeft, Offset(rect.left + cornerLen, rect.top), cornerPaint);

    // Top-right
    canvas.drawLine(Offset(rect.right - cornerLen, rect.top), rect.topRight,
        cornerPaint);
    canvas.drawLine(
        rect.topRight, Offset(rect.right, rect.top + cornerLen), cornerPaint);

    // Bottom-left
    canvas.drawLine(Offset(rect.left, rect.bottom - cornerLen),
        rect.bottomLeft, cornerPaint);
    canvas.drawLine(rect.bottomLeft,
        Offset(rect.left + cornerLen, rect.bottom), cornerPaint);

    // Bottom-right
    canvas.drawLine(Offset(rect.right - cornerLen, rect.bottom),
        rect.bottomRight, cornerPaint);
    canvas.drawLine(rect.bottomRight,
        Offset(rect.right, rect.bottom - cornerLen), cornerPaint);

    // Draw label pill above the bounding box
    final String labelText =
        '$label ${(confidence * 100).toStringAsFixed(1)}%';
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final double labelBgWidth = textPainter.width + 12;
    final double labelBgHeight = textPainter.height + 8;

    // Position label above the box; if too close to top, put inside
    double labelY = rect.top - labelBgHeight - 4;
    if (labelY < 0) {
      labelY = rect.top + 4;
    }

    final Rect labelBgRect = Rect.fromLTWH(
      rect.left,
      labelY,
      labelBgWidth,
      labelBgHeight,
    );

    final Paint labelBgPaint = Paint()..color = const Color(0xFFFF6B35);

    canvas.drawRRect(
      RRect.fromRectAndRadius(labelBgRect, const Radius.circular(4)),
      labelBgPaint,
    );

    textPainter.paint(
      canvas,
      Offset(labelBgRect.left + 6, labelBgRect.top + 4),
    );
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return bboxX != oldDelegate.bboxX ||
        bboxY != oldDelegate.bboxY ||
        bboxWidth != oldDelegate.bboxWidth ||
        bboxHeight != oldDelegate.bboxHeight ||
        containerWidth != oldDelegate.containerWidth ||
        containerHeight != oldDelegate.containerHeight;
  }
}
