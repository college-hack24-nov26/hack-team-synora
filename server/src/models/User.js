const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
  email: {
    type: String,
    required: [true, 'Email is required'],
    unique: true,
    lowercase: true,
    trim: true,
  },
  password: {
    type: String,
    required: [true, 'Password is required'],
    minlength: 6,
  },
  name: {
    type: String,
    required: [true, 'Name is required'],
    trim: true,
  },
  phone: {
    type: String,
    trim: true,
  },
  role: {
    type: String,
    enum: ['patient', 'doctor', 'admin'],
    required: [true, 'Role is required'],
  },
  uniqueCode: {
    type: String,
    unique: true,
  },
  // User-centric UI preferences, applied on login so theme/language follow the
  // account across devices instead of living only in on-device storage.
  preferences: {
    theme: { type: String, default: 'system' },     // 'light' | 'dark' | 'system'
    language: { type: String, default: 'en' },
  },
}, {
  timestamps: true,
});

userSchema.pre('save', async function (next) {
  if (!this.isModified('password')) return next();
  const salt = await bcrypt.genSalt(10);
  this.password = await bcrypt.hash(this.password, salt);
  next();
});

userSchema.methods.comparePassword = async function (candidatePassword) {
  return bcrypt.compare(candidatePassword, this.password);
};

userSchema.methods.toPublicJSON = function () {
  return {
    id: this._id,
    email: this.email,
    name: this.name,
    phone: this.phone,
    role: this.role,
    uniqueCode: this.uniqueCode,
    preferences: this.preferences || { theme: 'system', language: 'en' },
    createdAt: this.createdAt,
  };
};

module.exports = mongoose.model('User', userSchema);
