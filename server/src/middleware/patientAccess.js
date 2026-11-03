const Doctor = require('../models/Doctor');

/**
 * patientAccess — authorization guard for any route that exposes a specific
 * patient's medical data via a :patientId (or configurable) route param.
 *
 * Closes the IDOR class of bugs: without this, any authenticated user could
 * read another patient's vitals, detections, episodes, ledger, etc. by
 * guessing/iterating ids.
 *
 * Allows the request through iff:
 *   - admin                          (full access), or
 *   - patient AND patientId === self (own records only), or
 *   - doctor  AND patientId ∈ that doctor's linkedPatients.
 *
 * Must run AFTER the `auth` middleware (needs req.user). Usage:
 *   router.get('/:patientId', auth, patientAccess(), handler)
 *   router.get('/x/:pid',     auth, patientAccess('pid'), handler)
 */
function patientAccess(param = 'patientId') {
  return async (req, res, next) => {
    try {
      if (!req.user) {
        return res.status(401).json({ message: 'Authentication required' });
      }
      const patientId = req.params[param];
      if (!patientId) {
        return res.status(400).json({ message: `Missing ${param}` });
      }

      if (req.user.role === 'admin') return next();

      if (req.user.role === 'patient') {
        if (patientId === req.user._id.toString()) return next();
        return res.status(403).json({ message: 'Not authorized for this patient' });
      }

      if (req.user.role === 'doctor') {
        const doctor = await Doctor.findOne({ userId: req.user._id })
          .select('linkedPatients')
          .lean();
        const linked = (doctor?.linkedPatients || []).map((id) => id.toString());
        if (linked.includes(patientId)) return next();
        return res.status(403).json({ message: 'Patient not linked to this doctor' });
      }

      return res.status(403).json({ message: 'Not authorized' });
    } catch (err) {
      console.error('patientAccess error:', err.message);
      return res.status(500).json({ message: 'Authorization check failed' });
    }
  };
}

module.exports = patientAccess;
