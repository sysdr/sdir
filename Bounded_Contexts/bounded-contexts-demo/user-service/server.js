const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// User Schema - Owned by User Context
const userSchema = new mongoose.Schema({
  userId: { type: String, unique: true, required: true },
  email: { type: String, unique: true, required: true },
  firstName: String,
  lastName: String,
  preferences: {
    newsletter: { type: Boolean, default: true },
    notifications: { type: Boolean, default: true }
  },
  createdAt: { type: Date, default: Date.now }
});

const User = mongoose.model('User', userSchema);

// Connect to User Context Database
mongoose.connect(process.env.MONGODB_URI || 'mongodb://mongo-user:27017/userdb')
  .then(() => console.log('User Service: Connected to MongoDB'))
  .catch(err => console.error('User Service: MongoDB connection error:', err));

// User Context API Endpoints
app.get('/health', (req, res) => {
  res.json({ service: 'user-service', status: 'healthy', context: 'User Management' });
});

app.post('/users', async (req, res) => {
  try {
    const { email, firstName, lastName, preferences } = req.body;
    const userId = require('uuid').v4();
    
    const user = new User({
      userId,
      email,
      firstName,
      lastName,
      preferences: preferences || {}
    });
    
    await user.save();
    console.log(`User Context: Created user ${userId}`);
    
    res.status(201).json({ 
      userId, 
      email, 
      firstName, 
      lastName,
      message: 'User created in User Context' 
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

app.get('/users/:userId', async (req, res) => {
  try {
    const user = await User.findOne({ userId: req.params.userId });
    if (!user) {
      return res.status(404).json({ error: 'User not found in User Context' });
    }
    res.json(user);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.put('/users/:userId/preferences', async (req, res) => {
  try {
    const user = await User.findOneAndUpdate(
      { userId: req.params.userId },
      { preferences: req.body },
      { new: true }
    );
    console.log(`User Context: Updated preferences for ${req.params.userId}`);
    res.json({ message: 'Preferences updated', preferences: user.preferences });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/users', async (req, res) => {
  try {
    const users = await User.find().select('-_id userId email firstName lastName createdAt');
    res.json({ users, context: 'User Management', total: users.length });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`🧑 User Service (User Management Context) running on port ${PORT}`);
});
