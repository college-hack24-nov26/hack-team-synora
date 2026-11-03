import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/constants/api_constants.dart';
import 'package:medicoscope/services/api_service.dart';
import 'package:medicoscope/services/detection_service.dart';
import 'package:medicoscope/models/detection_record.dart';
import 'package:medicoscope/screens/reports/report_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';

class DoctorReportsScreen extends StatefulWidget {
  const DoctorReportsScreen({super.key});

  @override
  State<DoctorReportsScreen> createState() => _DoctorReportsScreenState();
}

class _DoctorReportsScreenState extends State<DoctorReportsScreen> {
  List<_PatientReport> _allReports = [];
  bool _isLoading = true;
  String _selectedCategory = 'all';
  bool _groupByPatient = false;

  final _categories = [
    {'key': 'all', 'labelKey': 'all'},
    {'key': 'skin', 'labelKey': 'skin'},
    {'key': 'heart_sound', 'labelKey': 'heart_sound_cat'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.token == null) return;

    try {
      final api = ApiService(token: authProvider.token);
      final detectionService = DetectionService(authProvider.token!);

      // Fetch linked patients
      final patientsResponse = await api.get(ApiConstants.doctorPatients);
      final patients = List<Map<String, dynamic>>.from(
        patientsResponse['patients'] ?? [],
      );

      final reports = <_PatientReport>[];

      // Fetch detection records for each patient
      for (final patient in patients) {
        final patientId = patient['userId']?.toString() ?? '';
        final patientName = patient['name'] ?? 'Unknown';
        if (patientId.isEmpty) continue;

        final records = await detectionService.getPatientRecords(patientId);
        for (final record in records) {
          reports.add(_PatientReport(
            patientName: patientName,
            record: record,
          ));
        }
      }

      // Sort by newest first
      reports.sort((a, b) => b.record.timestamp.compareTo(a.record.timestamp));

      if (mounted) {
        setState(() {
          _allReports = reports;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_PatientReport> get _filteredReports {
    if (_selectedCategory == 'all') return _allReports;
    return _allReports
        .where((r) => r.record.category == _selectedCategory)
        .toList();
  }

  // Group reports by patient name
  Map<String, List<_PatientReport>> get _groupedReports {
    final grouped = <String, List<_PatientReport>>{};
    for (final report in _filteredReports) {
      grouped.putIfAbsent(report.patientName, () => []).add(report);
    }
    return grouped;
  }

  // Summary stats
  int get _totalPatients =>
      _allReports.map((r) => r.patientName).toSet().length;

  Map<String, int> get _categoryCounts {
    final counts = <String, int>{};
    for (final report in _allReports) {
      counts[report.record.category] =
          (counts[report.record.category] ?? 0) + 1;
    }
    return counts;
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'skin':
        return Icons.face_outlined;
      case 'chest':
        return Icons.monitor_heart_outlined;
      case 'brain':
        return Icons.psychology_outlined;
      case 'heart_sound':
        return Icons.favorite_outline;
      default:
        return Icons.description_outlined;
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'skin':
        return const Color(0xFFFF6B35);
      case 'chest':
        return const Color(0xFF667EEA);
      case 'brain':
        return const Color(0xFFF5576C);
      case 'heart_sound':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _categoryLabel(String category, String lang) {
    switch (category) {
      case 'skin':
        return AppStrings.get('skin', lang);
      case 'chest':
        return AppStrings.get('chest', lang);
      case 'brain':
        return AppStrings.get('brain', lang);
      case 'heart_sound':
        return AppStrings.get('heart', lang);
      default:
        return category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final lang = Provider.of<LocaleProvider>(context).languageCode;
    final filtered = _filteredReports;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.darkBackgroundGradient
              : AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios),
                      color:
                          isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.get('patient_reports', lang),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                          Text(
                            AppStrings.get('detection_records_subtitle', lang),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextGray
                                  : AppTheme.textGray,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Group by patient toggle
                    GestureDetector(
                      onTap: () =>
                          setState(() => _groupByPatient = !_groupByPatient),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _groupByPatient
                              ? AppTheme.primaryOrange
                              : isDark
                                  ? AppTheme.darkCard
                                  : Colors.white,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSmall),
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: Icon(
                          Icons.people_outline,
                          size: 20,
                          color: _groupByPatient
                              ? Colors.white
                              : isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Summary Stats Row
              if (!_isLoading && _allReports.isNotEmpty)
                _buildSummaryStats(isDark, lang),

              // Category filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMedium),
                child: Row(
                  children: _categories.map((cat) {
                    final key = cat['key']!;
                    final isSelected = _selectedCategory == key;
                    final count = key == 'all'
                        ? _allReports.length
                        : (_categoryCounts[key] ?? 0);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _selectedCategory = key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryOrange
                                : isDark
                                    ? AppTheme.darkCard
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primaryOrange
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                    )
                                  ]
                                : AppTheme.cardShadow,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppStrings.get(cat['labelKey']!, lang),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : isDark
                                          ? AppTheme.darkTextLight
                                          : AppTheme.textDark,
                                ),
                              ),
                              if (count > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.white.withOpacity(0.3)
                                        : AppTheme.primaryOrange
                                            .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? Colors.white
                                          : AppTheme.primaryOrange,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: AppTheme.spacingMedium),

              // Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.description_outlined,
                                  size: 56,
                                  color: isDark
                                      ? AppTheme.darkTextDim
                                      : AppTheme.textLight,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  AppStrings.get('no_reports_found', lang),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppTheme.darkTextGray
                                        : AppTheme.textGray,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedCategory == 'all'
                                      ? AppStrings.get(
                                          'records_appear_here', lang)
                                      : AppStrings.get(
                                          'no_reports_found', lang),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? AppTheme.darkTextDim
                                        : AppTheme.textLight,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchReports,
                            child: _groupByPatient
                                ? _buildGroupedList(isDark, lang)
                                : _buildFlatList(filtered, isDark, lang),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryStats(bool isDark, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLarge, vertical: AppTheme.spacingSmall),
      child: GlassCard(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _statItem(
              icon: Icons.people_outline,
              value: '$_totalPatients',
              label: AppStrings.get('patients', lang),
              color: const Color(0xFF4ECDC4),
              isDark: isDark,
            ),
            _statItem(
              icon: Icons.description_outlined,
              value: '${_allReports.length}',
              label: AppStrings.get('total_reports', lang),
              color: AppTheme.primaryOrange,
              isDark: isDark,
            ),
            _statItem(
              icon: Icons.warning_amber_rounded,
              value: '${_allReports.where((r) => r.record.confidence >= 0.8).length}',
              label: AppStrings.get('high_confidence', lang),
              color: const Color(0xFFF5576C),
              isDark: isDark,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.1, end: 0);
  }

  Widget _statItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
          ),
        ),
      ],
    );
  }

  Widget _buildFlatList(
      List<_PatientReport> filtered, bool isDark, String lang) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingLarge,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final report = filtered[index];
        return _ReportCard(
          report: report,
          isDark: isDark,
          categoryIcon: _categoryIcon(report.record.category),
          categoryColor: _categoryColor(report.record.category),
          categoryLabel: _categoryLabel(report.record.category, lang),
          animationDelay: index * 50,
        );
      },
    );
  }

  Widget _buildGroupedList(bool isDark, String lang) {
    final grouped = _groupedReports;
    final patientNames = grouped.keys.toList();

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLarge),
      itemCount: patientNames.length,
      itemBuilder: (context, pIndex) {
        final name = patientNames[pIndex];
        final reports = grouped[name]!;
        final catBreakdown = <String, int>{};
        for (final r in reports) {
          catBreakdown[r.record.category] =
              (catBreakdown[r.record.category] ?? 0) + 1;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient header card
            GlassCard(
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        AppTheme.primaryOrange.withOpacity(0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryOrange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppTheme.darkTextLight
                                : AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: catBreakdown.entries.map((e) {
                            final color = _categoryColor(e.key);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_categoryLabel(e.key, lang)}: ${e.value}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${reports.length}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(
                    delay: Duration(milliseconds: pIndex * 100),
                    duration: 400.ms)
                .slideY(begin: 0.05, end: 0),

            const SizedBox(height: 4),

            // Reports under this patient
            ...reports.asMap().entries.map((entry) {
              final index = entry.key;
              final report = entry.value;
              return _ReportCard(
                report: report,
                isDark: isDark,
                categoryIcon: _categoryIcon(report.record.category),
                categoryColor: _categoryColor(report.record.category),
                categoryLabel:
                    _categoryLabel(report.record.category, lang),
                animationDelay: pIndex * 100 + index * 50 + 50,
              );
            }),

            const SizedBox(height: AppTheme.spacingMedium),
          ],
        );
      },
    );
  }
}

class _PatientReport {
  final String patientName;
  final DetectionRecord record;

  _PatientReport({required this.patientName, required this.record});
}

class _ReportCard extends StatelessWidget {
  final _PatientReport report;
  final bool isDark;
  final IconData categoryIcon;
  final Color categoryColor;
  final String categoryLabel;
  final int animationDelay;

  const _ReportCard({
    required this.report,
    required this.isDark,
    required this.categoryIcon,
    required this.categoryColor,
    required this.categoryLabel,
    required this.animationDelay,
  });

  @override
  Widget build(BuildContext context) {
    final record = report.record;

    final dateStr =
        '${record.timestamp.day}/${record.timestamp.month}/${record.timestamp.year}';

    // Confidence display
    final confStr = record.category == 'heart_sound'
        ? '${record.confidence.toStringAsFixed(0)} BPM'
        : '${(record.confidence * 100).toStringAsFixed(1)}%';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReportDetailScreen(
                patientName: report.patientName,
                record: record,
              ),
            ),
          );
        },
        child: GlassCard(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: categoryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  categoryIcon,
                  color: categoryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.className,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color:
                            isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      report.patientName,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: categoryColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      categoryLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: categoryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    confStr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          isDark ? AppTheme.darkTextDim : AppTheme.textLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
            delay: Duration(milliseconds: animationDelay), duration: 300.ms)
        .slideY(begin: 0.05, end: 0);
  }
}
