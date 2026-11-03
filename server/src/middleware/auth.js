const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const User = require('../models/User');

const auth = async (req, res, next) => {
  try {
    const header = req.header('Authorization');
    if (!header || !header.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'No token provided' });
    }

    const token = header.replace('Bearer ', '');
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const user = await User.findById(decoded.userId);

    if (!user) {
      return res.status(401).json({ message: 'User not found' });
    }

    // Opt-in revocation check (non-breaking). Only when SESSION_ENFORCEMENT is
    // enabled AND a session row exists for this token do we honour its revoked
    // flag — so existing tokens without a session row keep working.
    if (process.env.SESSION_ENFORCEMENT === 'true') {
      try {
        const Session = require('../models/Session');
        const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
        const session = await Session.findOne({ tokenHash });
        if (session && session.revoked) {
          return res.status(401).json({ message: 'Session revoked' });
        }
        if (session) {
          session.lastUsedAt = new Date();
          await session.save();
        }
      } catch (_) { /* never block auth on a session-store hiccup */ }
    }

    req.user = user;
    req.token = token;
    next();
  } catch (error) {
    res.status(401).json({ message: 'Invalid or expired token' });
  }
};

module.exports = auth;
