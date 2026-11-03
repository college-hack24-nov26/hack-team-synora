import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/core/providers/auth_provider.dart';
import 'package:medicoscope/core/widgets/glass_card.dart';
import 'package:medicoscope/services/appointment_response_service.dart';
import 'package:medicoscope/services/mental_health_service.dart';
import 'package:medicoscope/services/vitals_service.dart';
import 'package:provider/provider.dart';
import 'package:medicoscope/core/theme/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:medicoscope/core/locale/locale_provider.dart';
import 'package:medicoscope/core/locale/app_strings.dart';


enum NotificationModality {
  all,
  skinCancer,
  cardiac,
  anemia,
  respiratory,
  retinopathy,
  vitals,
  mindSpace,
  appointments,
}

class ModalityMeta {
  final String label;
  final IconData icon;
  final Color color;

  const ModalityMeta({
    required this.label,
    required this.icon,
    required this.color,
  });
}

const Map<NotificationModality, ModalityMeta> _modalityMetadata = {
  NotificationModality.all: ModalityMeta(
    label: 'All Modalities',
    icon: Icons.all_inbox_rounded,
    color: Color(0xFF6366F1),
  ),
  NotificationModality.skinCancer: ModalityMeta(
    label: 'Skin Care / Derm',
    icon: Icons.coronavirus_outlined,
    color: Color(0xFFE65100),
  ),
  NotificationModality.cardiac: ModalityMeta(
    label: 'Cardiac / Heart',
    icon: Icons.favorite_rounded,
    color: Color(0xFFD32F2F),
  ),
  NotificationModality.anemia: ModalityMeta(
    label: 'Anemia / Pallor',
    icon: Icons.bloodtype_rounded,
    color: Color(0xFFC2185B),
  ),
  NotificationModality.respiratory: ModalityMeta(
    label: 'Respiratory',
    icon: Icons.air_rounded,
    color: Color(0xFF0097A7),
  ),
  NotificationModality.retinopathy: ModalityMeta(
    label: 'Retinopathy',
    icon: Icons.visibility_rounded,
    color: Color(0xFF7B1FA2),
  ),
  NotificationModality.vitals: ModalityMeta(
    label: 'Vitals & Telemetry',
    icon: Icons.monitor_heart_rounded,
    color: Color(0xFF00897B),
  ),
  NotificationModality.mindSpace: ModalityMeta(
    label: 'MindSpace',
    icon: Icons.psychology_rounded,
    color: Color(0xFF5C6BC0),
  ),
  NotificationModality.appointments: ModalityMeta(
    label: 'Appointments',
    icon: Icons.event_available_rounded,
    color: Color(0xFF7C4DFF),
  ),
};

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Mental health state
  List<Map<String, dynamic>> _mentalNotifications = [];
  bool _mentalLoading = true;
  String? _mentalExpandedId;

  // Vitals alerts state
  List<Map<String, dynamic>> _vitalsAlerts = [];
  bool _vitalsLoading = true;
  String? _vitalsExpandedId;

  Timer? _refreshTimer;
  NotificationModality _selectedModality = NotificationModality.all;
  String _selectedUrgency = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchMentalNotifications();
    _fetchVitalsAlerts();
    // Auto-refresh vitals alerts every 10 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchVitalsAlerts(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchMentalNotifications() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.id ?? '';
    final token = authProvider.token ?? '';

    try {
      final notifications = await MentalHealthService.getNotifications(
        doctorId: userId,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _mentalNotifications = notifications;
        _mentalLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _mentalLoading = false);
    }
  }

  Future<void> _fetchVitalsAlerts({bool silent = false}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.id ?? '';

    try {
      final alerts = await VitalsService.getDoctorAlerts(doctorId: userId);
      if (!mounted) return;
      setState(() {
        _vitalsAlerts = alerts;
        if (!silent) _vitalsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) setState(() => _vitalsLoading = false);
    }
  }

  Future<void> _markMentalAsRead(String id) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await MentalHealthService.markAsRead(
        notificationId: id,
        token: authProvider.token ?? '',
      );
      setState(() {
        for (final n in _mentalNotifications) {
          if (n['id'] == id) {
            n['read'] = true;
            break;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _markVitalsAsRead(String id) async {
    try {
      await VitalsService.markAlertRead(alertId: id);
      setState(() {
        for (final a in _vitalsAlerts) {
          if (a['id'] == id) {
            a['read'] = true;
            break;
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _deleteVitalsAlert(String id) async {
    try {
      await VitalsService.deleteAlert(alertId: id);
      setState(() {
        _vitalsAlerts.removeWhere((a) => a['id'] == id);
      });
    } catch (_) {}
  }

  Future<void> _deleteMentalNotification(String id) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await MentalHealthService.deleteNotification(
        notificationId: id,
        token: authProvider.token ?? '',
      );
      setState(() {
        _mentalNotifications.removeWhere((n) => n['id'] == id);
      });
    } catch (_) {}
  }

  void _confirmDelete(String title, VoidCallback onDelete) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: const Text('Are you sure you want to delete this?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─── Appointment request handling ──────────────────────────────────────

  /// True when a doctor-side notification is an incoming booking request.
  /// Detects via the `source` field or the clinical-report body marker.
  bool _isAppointmentRequest(Map<String, dynamic> n) {
    final source = n['source']?.toString() ?? '';
    final report = n['report']?.toString() ?? '';
    if (source == 'appointment_request') return true;
    return report.startsWith('APPOINTMENT REQUEST');
  }

  /// Extracts the preferred slot from the clinical report text.
  DateTime? _extractPreferredSlot(String report) {
    final m = RegExp(
            r'Preferred slot:\s*(\d{1,2})/(\d{1,2})/(\d{4})\s+at\s+(\d{1,2}):(\d{2})')
        .firstMatch(report);
    if (m == null) return null;
    try {
      return DateTime(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
      );
    } catch (_) {
      return null;
    }
  }

  Widget _buildAppointmentActions(
      Map<String, dynamic> n, bool isDark, String lang) {
    final report = n['report']?.toString() ?? '';
    final slot = _extractPreferredSlot(report);
    final patientId = n['patient_id']?.toString() ?? '';
    final patientName = n['patient_name']?.toString() ?? 'Patient';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (slot != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF7C4DFF).withOpacity(0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_outlined,
                    color: Color(0xFF7C4DFF), size: 16),
                const SizedBox(width: 6),
                Text(
                  'Requested for ${_fmtSlot(slot)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7C4DFF),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _confirmAppointment(
                  notificationId: n['id']?.toString() ?? '',
                  patientId: patientId,
                  patientName: patientName,
                  slot: slot ?? DateTime.now().add(const Duration(days: 1)),
                ),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Confirm'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _rescheduleAppointment(
                  notificationId: n['id']?.toString() ?? '',
                  patientId: patientId,
                  patientName: patientName,
                  originalSlot:
                      slot ?? DateTime.now().add(const Duration(days: 1)),
                ),
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: const Text('Reschedule'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF9800),
                  side: const BorderSide(color: Color(0xFFFF9800)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmAppointment({
    required String notificationId,
    required String patientId,
    required String patientName,
    required DateTime slot,
  }) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final doctor = auth.user;
    if (doctor == null) return;

    // Optional note from doctor.
    final note = await _askForNote('Confirm appointment',
        'Any message for the patient? (optional)');
    if (!mounted) return;

    await AppointmentResponseService.confirm(
      patientId: patientId,
      patientName: patientName,
      doctorId: doctor.id,
      doctorName: doctor.name,
      originalSlot: slot,
      note: note ?? '',
    );

    await _deleteMentalNotification(notificationId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Confirmation sent to $patientName for ${_fmtSlot(slot)}'),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
  }

  Future<void> _rescheduleAppointment({
    required String notificationId,
    required String patientId,
    required String patientName,
    required DateTime originalSlot,
  }) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final doctor = auth.user;
    if (doctor == null) return;

    // Ask doctor for a new slot.
    final picked = await showDatePicker(
      context: context,
      initialDate: originalSlot,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(originalSlot),
    );
    if (time == null || !mounted) return;
    final newSlot = DateTime(
        picked.year, picked.month, picked.day, time.hour, time.minute);

    final note = await _askForNote(
        'Reschedule appointment', 'Reason for rescheduling? (optional)');
    if (!mounted) return;

    await AppointmentResponseService.reschedule(
      patientId: patientId,
      patientName: patientName,
      doctorId: doctor.id,
      doctorName: doctor.name,
      originalSlot: originalSlot,
      newSlot: newSlot,
      note: note ?? '',
    );

    await _deleteMentalNotification(notificationId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Reschedule proposal sent to $patientName for ${_fmtSlot(newSlot)}'),
        backgroundColor: const Color(0xFFFF9800),
      ),
    );
  }

  Future<String?> _askForNote(String title, String hint) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  String _fmtSlot(DateTime d) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    final mi = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month]}, $h:$mi $ap';
  }

  Color _urgencyColor(String urgency) {
    switch (urgency.toLowerCase()) {
      case 'high':
      case 'critical':
        return const Color(0xFFFF5252);
      case 'medium':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF4CAF50);
    }
  }


  NotificationModality _classifyItem(Map<String, dynamic> item) {
    final source = (item['source'] ?? '').toString().toLowerCase();
    final report = (item['report'] ?? item['clinicalReport'] ?? item['message'] ?? '').toString().toLowerCase();
    final transcript = (item['transcript'] ?? '').toString().toLowerCase();
    final combined = '$source $report $transcript';

    if (source == 'appointment_request' || report.startsWith('appointment request') || combined.contains('preferred slot')) {
      return NotificationModality.appointments;
    }
    if (source.contains('skin') || combined.contains('skin lesion') || combined.contains('melanoma') || combined.contains('carcinoma') || combined.contains('skin cancer')) {
      return NotificationModality.skinCancer;
    }
    if (source.contains('heart') || source.contains('cardio') || combined.contains('heart sound') || combined.contains('auscultation') || combined.contains('murmur') || combined.contains('arrhythmia') || combined.contains('ecg')) {
      return NotificationModality.cardiac;
    }
    if (source.contains('anemia') || source.contains('pallor') || combined.contains('conjunctival') || combined.contains('hemoglobin') || combined.contains('pallor')) {
      return NotificationModality.anemia;
    }
    if (source.contains('respiratory') || combined.contains('respiratory') || combined.contains('lung sound') || combined.contains('crackles') || combined.contains('wheez') || combined.contains('fev1')) {
      return NotificationModality.respiratory;
    }
    if (source.contains('retin') || combined.contains('retinopathy') || combined.contains('fundus') || combined.contains('macular') || combined.contains('retinal')) {
      return NotificationModality.retinopathy;
    }
    if (source.contains('vital') || item.containsKey('vital_type') || combined.contains('blood pressure') || combined.contains('spo2') || combined.contains('heart rate') || combined.contains('tachycardia') || combined.contains('hypertension')) {
      return NotificationModality.vitals;
    }
    if (source.contains('mindspace') || combined.contains('mindspace') || combined.contains('voice acoustic') || combined.contains('phq')) {
      return NotificationModality.mindSpace;
    }
    return NotificationModality.all;
  }

  String _formatReadableTimestamp(dynamic rawDate) {
    if (rawDate == null || rawDate.toString().isEmpty) return 'Recent';
    try {
      DateTime dt;
      if (rawDate is DateTime) {
        dt = rawDate.toLocal();
      } else {
        dt = DateTime.parse(rawDate.toString()).toLocal();
      }
      final now = DateTime.now();
      final diff = now.difference(dt);

      String rel;
      if (diff.inSeconds < 45) {
        rel = 'Just now';
      } else if (diff.inMinutes < 60) {
        rel = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        rel = '${diff.inHours}h ago';
      } else {
        rel = '${diff.inDays}d ago';
      }

      final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      final mi = dt.minute.toString().padLeft(2, '0');
      final se = dt.second.toString().padLeft(2, '0');

      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      final datePart = (dt.year == now.year && dt.month == now.month && dt.day == now.day)
          ? 'Today'
          : '${dt.day} ${months[dt.month - 1]} ${dt.year}';

      return '$datePart • $h:$mi:$se $ap ($rel)';
    } catch (_) {
      return rawDate.toString();
    }
  }

  String _exactTimestamp(dynamic rawDate) {
    if (rawDate == null || rawDate.toString().isEmpty) return 'N/A';
    try {
      DateTime dt;
      if (rawDate is DateTime) {
        dt = rawDate.toLocal();
      } else {
        dt = DateTime.parse(rawDate.toString()).toLocal();
      }
      final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      final mi = dt.minute.toString().padLeft(2, '0');
      final se = dt.second.toString().padLeft(2, '0');
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $h:$mi:$se $ap IST';
    } catch (_) {
      return rawDate.toString();
    }
  }

  Widget _buildModalityBadge(NotificationModality mod, bool isDark) {
    final meta = _modalityMetadata[mod] ?? _modalityMetadata[NotificationModality.all]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: meta.color.withOpacity(isDark ? 0.25 : 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: meta.color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 12, color: meta.color),
          const SizedBox(width: 4),
          Text(
            meta.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: meta.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalityFilterBar(bool isDark) {
    final allItems = [..._mentalNotifications, ..._vitalsAlerts];
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium, vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: NotificationModality.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mod = NotificationModality.values[index];
          final meta = _modalityMetadata[mod]!;
          final isSelected = _selectedModality == mod;

          final count = mod == NotificationModality.all
              ? allItems.length
              : allItems.where((i) => _classifyItem(i) == mod).length;

          return InkWell(
            onTap: () {
              setState(() {
                _selectedModality = mod;
                if (mod == NotificationModality.vitals) {
                  _tabController.animateTo(0);
                } else if (mod != NotificationModality.all) {
                  _tabController.animateTo(1);
                }
              });
            },
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? meta.color
                    : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? meta.color : (isDark ? Colors.white12 : Colors.black12),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    meta.icon,
                    size: 14,
                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    meta.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withOpacity(0.25)
                            : meta.color.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? Colors.white : meta.color,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _timeAgo(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().toUtc().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      AppStrings.get('notifications', lang),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color:
                            isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
              ),

              _buildModalityFilterBar(isDark),

              // Tab bar
              Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingLarge,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor:
                      isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.monitor_heart_outlined, size: 16),
                          const SizedBox(width: 6),
                          Text(AppStrings.get('vitals_tab', lang)),
                          if (_vitalsAlerts
                              .where((a) => !(a['read'] ?? false))
                              .isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFF5252),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${_vitalsAlerts.where((a) => !(a['read'] ?? false)).length}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.psychology_outlined, size: 16),
                          const SizedBox(width: 6),
                          Text(AppStrings.get('mental_health_tab', lang)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacingMedium),

              // Tab views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildVitalsTab(isDark, lang),
                    _buildMentalHealthTab(isDark, lang),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVitalsTab(bool isDark, String lang) {
    if (_vitalsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_vitalsAlerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.monitor_heart_outlined,
              size: 64,
              color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.get('no_vitals_alerts', lang),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.get('vitals_alerts_appear', lang),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchVitalsAlerts,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLarge,
        ),
        itemCount: _vitalsAlerts.length,
        itemBuilder: (context, index) {
          final a = _vitalsAlerts[index];
          final isExpanded = _vitalsExpandedId == a['id'];
          final severity = a['severity'] ?? 'high';
          final isUnread = !(a['read'] ?? false);
          final emergencyNotified = a['emergency_notified'] ?? false;
          final doctorNotified = a['doctor_notified'] ?? false;

          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingMedium),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _vitalsExpandedId = isExpanded ? null : a['id'];
                });
                if (isUnread) {
                  _markVitalsAsRead(a['id']);
                }
              },
              child: GlassCard(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                borderRadius: AppTheme.radiusMedium,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _urgencyColor(severity),
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            a['patient_name'] ?? 'Unknown Patient',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  isUnread ? FontWeight.w800 : FontWeight.w600,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _urgencyColor(severity).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            severity.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _urgencyColor(severity),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildModalityBadge(_classifyItem(a), isDark),
                        const SizedBox(width: 8),
                        Text(
                          _formatReadableTimestamp(a['created_at'] ?? a['timestamp']),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTheme.darkTextDim
                                : AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Alert message preview
                    Text(
                      a['message'] ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            isDark ? AppTheme.darkTextGray : AppTheme.textGray,
                      ),
                      maxLines: isExpanded ? null : 1,
                      overflow: isExpanded ? null : TextOverflow.ellipsis,
                    ),

                    if (isExpanded) ...[
                      const SizedBox(height: 12),
                      Divider(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      const SizedBox(height: 8),
                      // Vital details
                      _buildDetailRow(
                        isDark,
                        Icons.favorite,
                        AppStrings.get('vital', lang),
                        '${a['vital'] ?? 'N/A'}',
                      ),
                      _buildDetailRow(
                        isDark,
                        Icons.speed,
                        AppStrings.get('current', lang),
                        '${a['current_value'] ?? 'N/A'}',
                      ),
                      _buildDetailRow(
                        isDark,
                        Icons.trending_up,
                        AppStrings.get('predicted', lang),
                        '${a['predicted_value'] ?? 'N/A'}',
                      ),
                      _buildDetailRow(
                        isDark,
                        Icons.location_on,
                        AppStrings.get('location', lang),
                        a['location'] ?? 'Unknown',
                      ),
                      if (a['maps_url'] != null &&
                          (a['maps_url'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: GestureDetector(
                            onTap: () => launchUrl(Uri.parse(a['maps_url'])),
                            child: Row(
                              children: [
                                Icon(Icons.map,
                                    size: 14,
                                    color: isDark
                                        ? AppTheme.darkTextDim
                                        : AppTheme.textLight),
                                const SizedBox(width: 8),
                                Text(
                                  '${AppStrings.get('location', lang)}: ',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  AppStrings.get('open_maps', lang),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF667EEA),
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      _buildDetailRow(
                        isDark,
                        Icons.schedule_rounded,
                        'Real Timestamp',
                        _exactTimestamp(a['created_at'] ?? a['timestamp']),
                      ),
                      _buildDetailRow(
                        isDark,
                        Icons.access_time,
                        AppStrings.get('time', lang),
                        a['timestamp'] ?? '',
                      ),

                      const SizedBox(height: 10),
                      // Notification status badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (doctorNotified)
                            _buildStatusChip(
                              Icons.check_circle,
                              AppStrings.get('doctor_notified', lang),
                              const Color(0xFF4CAF50),
                            ),
                          if (emergencyNotified)
                            _buildStatusChip(
                              Icons.emergency,
                              AppStrings.get('emergency_notified', lang),
                              const Color(0xFFFF5252),
                            ),
                          if (a['emergency_contact_name'] != null &&
                              (a['emergency_contact_name'] as String)
                                  .isNotEmpty)
                            _buildStatusChip(
                              Icons.person,
                              a['emergency_contact_name'],
                              isDark ? Colors.white54 : Colors.black54,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => _confirmDelete(
                            AppStrings.get('delete_alert', lang),
                            () => _deleteVitalsAlert(a['id']),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF5252).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.delete_outline,
                                    size: 14, color: Color(0xFFFF5252)),
                                const SizedBox(width: 4),
                                Text(
                                  AppStrings.get('delete', lang),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFFF5252),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (!isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          AppStrings.get('tap_for_details', lang),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.darkTextDim
                                : AppTheme.textLight,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(
                delay: (index * 100).ms,
                duration: 400.ms,
              );
        },
      ),
    );
  }

  Widget _buildDetailRow(
    bool isDark,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMentalHealthTab(bool isDark, String lang) {
    if (_mentalLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_mentalNotifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_outlined,
              size: 64,
              color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.get('no_mental_alerts', lang),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? AppTheme.darkTextGray : AppTheme.textGray,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.get('mental_alerts_appear', lang),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextDim : AppTheme.textLight,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchMentalNotifications,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLarge,
        ),
        itemCount: _mentalNotifications.length,
        itemBuilder: (context, index) {
          final n = _mentalNotifications[index];
          final isExpanded = _mentalExpandedId == n['id'];
          final urgency = n['urgency'] ?? 'Low';
          final isUnread = !(n['read'] ?? false);

          return Padding(
            padding: const EdgeInsets.only(
              bottom: AppTheme.spacingMedium,
            ),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _mentalExpandedId = isExpanded ? null : n['id'];
                });
                if (isUnread) {
                  _markMentalAsRead(n['id']);
                }
              },
              child: GlassCard(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                borderRadius: AppTheme.radiusMedium,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _urgencyColor(urgency),
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            n['patient_name'] ?? 'Unknown',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  isUnread ? FontWeight.w800 : FontWeight.w600,
                              color: isDark
                                  ? AppTheme.darkTextLight
                                  : AppTheme.textDark,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _urgencyColor(urgency).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            urgency,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _urgencyColor(urgency),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildModalityBadge(_classifyItem(n), isDark),
                        const SizedBox(width: 8),
                        Text(
                          _formatReadableTimestamp(n['created_at'] ?? n['timestamp']),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTheme.darkTextDim
                                : AppTheme.textLight,
                          ),
                        ),
                      ],
                    ),
                    if (isExpanded) ...[
                      const SizedBox(height: 12),
                      Divider(
                        color: isDark ? Colors.white12 : Colors.black12,
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        isDark,
                        Icons.schedule_rounded,
                        'Real Timestamp',
                        _exactTimestamp(n['created_at'] ?? n['timestamp']),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.get('clinical_report', lang),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextGray
                              : AppTheme.textGray,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        n['report'] ??
                            AppStrings.get('no_report_available', lang),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: isDark
                              ? AppTheme.darkTextLight
                              : AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_isAppointmentRequest(n))
                        _buildAppointmentActions(n, isDark, lang)
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => _confirmDelete(
                              AppStrings.get('delete_alert', lang),
                              () => _deleteMentalNotification(n['id']),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFFFF5252).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.delete_outline,
                                      size: 14, color: Color(0xFFFF5252)),
                                  const SizedBox(width: 4),
                                  Text(
                                    AppStrings.get('delete', lang),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFFF5252),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                    if (!isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          AppStrings.get('tap_clinical_report', lang),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppTheme.darkTextDim
                                : AppTheme.textLight,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(
                delay: (index * 100).ms,
                duration: 400.ms,
              );
        },
      ),
    );
  }
}
