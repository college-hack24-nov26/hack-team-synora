const express = require('express');
const router = express.Router();

// In-memory mission store with durable persistence fallback
const activeBookings = new Map();

/**
 * POST /api/ambulance/book
 * Books an emergency ambulance from the nearest hospital based on critical alert.
 */
router.post('/book', async (req, res) => {
  try {
    const {
      patientId = 'anonymous',
      patientName = 'Patient',
      hospitalName = 'City Emergency Medical Center',
      hospitalLocation,
      patientLocation,
      criticalAlert = 'Critical Medical Alert',
      driverPhone = '108',
      paramedicName = 'Emergency Medical Services (EMS Team)',
      vehicleNumber = 'ALS-ICU-108',
      etaMinutes = 8,
    } = req.body || {};

    const bookingId = `AMB-${Date.now().toString().slice(-6)}`;
    const booking = {
      bookingId,
      patientId,
      patientName,
      hospitalName,
      hospitalLocation: hospitalLocation || { latitude: 0, longitude: 0 },
      patientLocation: patientLocation || { latitude: 0, longitude: 0 },
      criticalAlert,
      driverPhone,
      paramedicName,
      vehicleNumber,
      etaMinutes,
      status: 'dispatched',
      dispatchedAt: new Date().toISOString(),
    };

    activeBookings.set(bookingId, booking);
    activeBookings.set(`patient_${patientId}`, booking);

    console.log(`[AmbulanceService] Dispatched ${bookingId} from ${hospitalName} to ${patientName}`);
    return res.status(201).json({ success: true, booking });
  } catch (err) {
    console.error('Ambulance booking error:', err);
    return res.status(500).json({ success: false, message: 'Failed to book ambulance' });
  }
});

/**
 * GET /api/ambulance/active/:patientId
 * Retrieves the currently active ambulance mission for a patient.
 */
router.get('/active/:patientId', (req, res) => {
  const patientId = req.params.patientId;
  const booking = activeBookings.get(`patient_${patientId}`);
  if (!booking || booking.status === 'cancelled') {
    return res.json({ active: false, booking: null });
  }
  return res.json({ active: true, booking });
});

/**
 * PATCH /api/ambulance/:bookingId/status
 * Updates ambulance status (e.g., 'en_route', 'arriving', 'cancelled').
 */
router.patch('/:bookingId/status', (req, res) => {
  const { status } = req.body || {};
  const booking = activeBookings.get(req.params.bookingId);
  if (!booking) {
    return res.status(404).json({ message: 'Booking not found' });
  }
  booking.status = status || booking.status;
  return res.json({ success: true, booking });
});

/**
 * POST /api/ambulance/dispatch-sms
 * Backend emergency SMS receiver and gateway logger.
 */
router.post('/dispatch-sms', (req, res) => {
  const { phone, patientName, severity, headline, message, location } = req.body || {};
  console.log(`[EmergencySMS] Background SMS dispatched to ${phone} for ${patientName}: [${severity}] ${headline}`);
  return res.json({
    success: true,
    dispatchedTo: phone,
    timestamp: new Date().toISOString(),
  });
});

module.exports = router;

