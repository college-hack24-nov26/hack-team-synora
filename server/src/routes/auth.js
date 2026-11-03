const crypto = require('crypto');
const express = require('express');
const { body, validationResult } = require('express-validator');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const Patient = require('../models/Patient');
const Doctor = require('../models/Doctor');
const Session = require('../models/Session');
const auth = require('../middleware/auth');
const generateUniqueCode = require('../utils/generateCode');

const router = express.Router();

// Record a server-side session for an issued token (enables later revocation).
// Best-effort: a session-store failure must never block login/registration.
async function recordSession(userId, token, deviceId) {
  try {
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    await Session.create({ userId, tokenHash, deviceId: deviceId || '' });
  } catch (_) { /* non-fatal */ }
}

// POST /api/auth/register
router.post('/register', [
  body('email').isEmail().withMessage('Valid email is required'),
  body('password').isLength({ min: 6 }).withMessage('Password must be at least 6 characters'),
  body('name').trim().notEmpty().withMessage('Name is required'),
  // 'admin' is intentionally NOT self-registerable — admins are provisioned
  // out-of-band (seed/invite). Allowing it here would let anyone mint an admin.
  body('role').isIn(['patient', 'doctor']).withMessage('Role must be patient or doctor'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ message: errors.array()[0].msg });
    }

    const { email, password, name, phone, role } = req.body;

    const existingUser = await User.findOne({ email });
    if (existingUser) {
      return res.status(400).json({ message: 'Email already registered' });
    }

    const uniqueCode = await generateUniqueCode();

    const user = new User({ email, password, name, phone, role, uniqueCode });
    await user.save();

    // Create role-specific profile
    if (role === 'patient') {
      const { dateOfBirth, bloodGroup, emergencyContactName, emergencyContactPhone, emergencyContactRelationship } = req.body;
      await Patient.create({
        userId: user._id,
        dateOfBirth: dateOfBirth || '',
        bloodGroup: bloodGroup || '',
        emergencyContact: {
          name: emergencyContactName || '',
          phone: emergencyContactPhone || '',
          relationship: emergencyContactRelationship || '',
        },
      });
    } else if (role === 'doctor') {
      const { specialization, licenseNumber, hospital, yearsOfExperience } = req.body;
      if (!specialization || !licenseNumber) {
        await User.findByIdAndDelete(user._id);
        return res.status(400).json({ message: 'Specialization and license number are required for doctors' });
      }
      await Doctor.create({
        userId: user._id,
        specialization,
        licenseNumber,
        hospital: hospital || '',
        yearsOfExperience: yearsOfExperience || 0,
      });
    }

    const token = jwt.sign(
      { userId: user._id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );
    await recordSession(user._id, token, req.body.deviceId);

    res.status(201).json({
      token,
      user: user.toPublicJSON(),
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ message: 'Server error during registration' });
  }
});

// POST /api/auth/login
router.post('/login', [
  body('email').isEmail().withMessage('Valid email is required'),
  body('password').notEmpty().withMessage('Password is required'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ message: errors.array()[0].msg });
    }

    const { email, password } = req.body;

    const user = await User.findOne({ email });
    if (!user) {
      return res.status(401).json({ message: 'Invalid email or password' });
    }

    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ message: 'Invalid email or password' });
    }

    const token = jwt.sign(
      { userId: user._id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );
    await recordSession(user._id, token, req.body.deviceId);

    res.json({
      token,
      user: user.toPublicJSON(),
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ message: 'Server error during login' });
  }
});

// POST /api/auth/logout — revoke the current token's session (real logout).
router.post('/logout', auth, async (req, res) => {
  try {
    const tokenHash = crypto.createHash('sha256').update(req.token).digest('hex');
    await Session.updateOne({ tokenHash }, { $set: { revoked: true } });
    res.json({ status: 'logged_out' });
  } catch (error) {
    res.status(500).json({ message: 'Logout failed' });
  }
});

module.exports = router;
