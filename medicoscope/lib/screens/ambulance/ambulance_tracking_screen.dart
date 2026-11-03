import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:medicoscope/core/theme/app_theme.dart';
import 'package:medicoscope/models/ambulance_booking_model.dart';
import 'package:medicoscope/services/ambulance_service.dart';

class AmbulanceTrackingScreen extends StatefulWidget {
  final AmbulanceBooking booking;

  const AmbulanceTrackingScreen({super.key, required this.booking});

  @override
  State<AmbulanceTrackingScreen> createState() => _AmbulanceTrackingScreenState();
}

class _AmbulanceTrackingScreenState extends State<AmbulanceTrackingScreen>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late List<LatLng> _routePoints;
  int _currentStepIndex = 0;
  Timer? _simulationTimer;
  late double _distanceKmRemaining;
  late int _etaMinutesRemaining;
  bool _hasArrived = false;
  late AnimationController _pulseAnimCtrl;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    _pulseAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    final hospLatLng = LatLng(
      widget.booking.hospitalLatitude,
      widget.booking.hospitalLongitude,
    );
    final patLatLng = LatLng(
      widget.booking.patientLatitude,
      widget.booking.patientLongitude,
    );

    _routePoints = AmbulanceService.generateRouteCoordinates(
      start: hospLatLng,
      end: patLatLng,
      steps: 30,
    );

    _distanceKmRemaining = const Distance().as(
      LengthUnit.Kilometer,
      hospLatLng,
      patLatLng,
    );
    if (_distanceKmRemaining < 0.5) _distanceKmRemaining = 2.4;
    _etaMinutesRemaining = widget.booking.initialEtaMinutes;

    _startAmbulanceSimulation();
  }

  void _startAmbulanceSimulation() {
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) {
      if (_currentStepIndex < _routePoints.length - 1) {
        setState(() {
          _currentStepIndex++;
          final progressRatio = _currentStepIndex / (_routePoints.length - 1);
          _distanceKmRemaining =
              (1.0 - progressRatio) * (widget.booking.initialEtaMinutes * 0.4);
          _etaMinutesRemaining = ((1.0 - progressRatio) *
                  widget.booking.initialEtaMinutes)
              .ceil();

          if (_etaMinutesRemaining <= 0) _etaMinutesRemaining = 1;
        });

        // Gently keep map centered between moving ambulance and patient
        final currentPos = _routePoints[_currentStepIndex];
        _mapController.move(currentPos, _mapController.camera.zoom);
      } else {
        timer.cancel();
        setState(() {
          _hasArrived = true;
          _distanceKmRemaining = 0.0;
          _etaMinutesRemaining = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _pulseAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:${clean.isNotEmpty ? clean : "108"}');
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  void _confirmCancel() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Emergency Ambulance?'),
        content: const Text(
          'Are you sure you want to cancel the dispatched ambulance? Only cancel if you are safe and medical assistance is no longer required.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Dispatched'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              _simulationTimer?.cancel();
              Navigator.pop(ctx);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ambulance mission has been cancelled.'),
                  backgroundColor: Colors.blueGrey,
                ),
              );
            },
            child: const Text('Yes, Cancel Ambulance'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentAmbPos = _routePoints[_currentStepIndex];
    final patientPos = LatLng(
      widget.booking.patientLatitude,
      widget.booking.patientLongitude,
    );
    final hospitalPos = LatLng(
      widget.booking.hospitalLatitude,
      widget.booking.hospitalLongitude,
    );

    return Scaffold(
      body: Stack(
        children: [
          // 1. Live Interactive Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentAmbPos,
              initialZoom: 14.5,
              minZoom: 11.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.medicoscope.aegis',
              ),
              PolylineLayer(
                polylines: [
                  // Full planned route in background
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5.0,
                    color: const Color(0xFFFF3B30).withValues(alpha: 0.35),
                  ),
                  // Active route driven so far
                  Polyline(
                    points: _routePoints.sublist(0, _currentStepIndex + 1),
                    strokeWidth: 6.0,
                    color: const Color(0xFFFF3B30),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // Hospital Marker
                  Marker(
                    point: hospitalPos,
                    width: 50,
                    height: 50,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.local_hospital_rounded,
                        color: Color(0xFF4CAF50),
                        size: 30,
                      ),
                    ),
                  ),

                  // Patient GPS Location Marker
                  Marker(
                    point: patientPos,
                    width: 60,
                    height: 60,
                    child: AnimatedBuilder(
                      animation: _pulseAnimCtrl,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF2196F3).withValues(
                              alpha: 0.2 + (_pulseAnimCtrl.value * 0.2),
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF2196F3),
                              ),
                              child: const Icon(
                                Icons.person_pin_circle,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Moving Ambulance Marker
                  Marker(
                    point: currentAmbPos,
                    width: 65,
                    height: 65,
                    child: AnimatedBuilder(
                      animation: _pulseAnimCtrl,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 55,
                              height: 55,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFF3B30).withValues(
                                  alpha: 0.3 + (_pulseAnimCtrl.value * 0.3),
                                ),
                              ),
                            ),
                            Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFF3B30),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.emergency_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Top Header Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: isDark ? AppTheme.darkTextLight : AppTheme.textDark,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: (isDark ? AppTheme.darkCard : Colors.white)
                            .withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shield_outlined,
                              color: Color(0xFFFF3B30), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _hasArrived
                                  ? 'AMBULANCE ARRIVED [SIMULATION]'
                                  : 'AMBULANCE EN ROUTE [SIMULATION]',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: Color(0xFFFF3B30),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom Real-Time Telemetry Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1B1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 25,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ETA and Distance Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hasArrived ? 'ARRIVED' : '$_etaMinutesRemaining MINS',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFFF3B30),
                            ),
                          ),
                          Text(
                            _hasArrived
                              ? 'Paramedics outside your location'
                              : 'ESTIMATED ARRIVAL TIME',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: isDark ? AppTheme.darkTextDim : AppTheme.textGray,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.near_me_outlined,
                                color: Color(0xFFFF3B30), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '${_distanceKmRemaining.toStringAsFixed(1)} km away',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFF3B30),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Hospital & Crew Details Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.local_hospital,
                                  color: Color(0xFF4CAF50), size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.booking.hospitalName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? AppTheme.darkTextLight
                                          : AppTheme.textDark,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${widget.booking.vehicleNumber} • ${widget.booking.paramedicName}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: isDark
                                          ? AppTheme.darkTextDim
                                          : AppTheme.textGray,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.sensors, size: 14, color: Color(0xFFFF3B30)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Alert: ${widget.booking.criticalAlert}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFF3B30),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Action Buttons: Call Dispatch & Cancel Ambulance
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.phone_in_talk, size: 18),
                          label: const Text(
                            'Call Dispatch (108)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: () => _makeCall(widget.booking.driverPhone),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF3B30),
                          side: const BorderSide(color: Color(0xFFFF3B30)),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _confirmCancel,
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

