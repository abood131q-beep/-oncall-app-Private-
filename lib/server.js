const express = require('express');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const db = require('./database');

const app = express();
const server = http.createServer(app);

// ===== Socket.IO =====
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] }
});

app.use(cors({ origin: '*', methods: ['GET', 'POST', 'PUT', 'DELETE'] }));
app.use(express.json());

// ===== Helper =====
const dbGet = (sql, params = []) => new Promise((resolve, reject) => {
  db.get(sql, params, (err, row) => err ? reject(err) : resolve(row));
});
const dbAll = (sql, params = []) => new Promise((resolve, reject) => {
  db.all(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
});
const dbRun = (sql, params = []) => new Promise((resolve, reject) => {
  db.run(sql, params, function(err) { err ? reject(err) : resolve(this); });
});

// ===== حساب المسافة والأجرة =====
function getDistanceKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat/2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng/2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function calculateFare(distanceKm, durationMinutes = 0) {
  const fare = 1.0 + (distanceKm * 0.250) + (durationMinutes * 0.020);
  return Math.round(fare * 1000) / 1000;
}

function formatTrip(t) {
  if (!t) return null;
  return {
    ...t,
    route: JSON.parse(t.route || '[]'),
    estimatedFare: t.estimated_fare,
    finalFare: t.final_fare,
    pickupLat: t.pickup_lat,
    pickupLng: t.pickup_lng,
    driverLat: t.driver_lat,
    driverLng: t.driver_lng,
    destLat: t.dest_lat,
    destLng: t.dest_lng,
  };
}

// ===== Socket.IO Events =====
io.on('connection', (socket) => {
  console.log('🔌 Client connected:', socket.id);

  // السائق ينضم لغرفة رحلته
  socket.on('driver:join', ({ tripId, driverPhone }) => {
    socket.join(`trip:${tripId}`);
    socket.join(`driver:${driverPhone}`);
    console.log(`🚕 Driver joined trip:${tripId}`);
  });

  // الراكب ينضم لغرفة رحلته
  socket.on('passenger:join', ({ tripId, userPhone }) => {
    socket.join(`trip:${tripId}`);
    socket.join(`passenger:${userPhone}`);
    console.log(`👤 Passenger joined trip:${tripId}`);
  });

  // ===== تحديث موقع السائق REALTIME =====
  socket.on('driver:location', async ({ tripId, lat, lng }) => {
    try {
      const trip = await dbGet('SELECT * FROM trips WHERE id = ?', [Number(tripId)]);
      if (!trip) return;

      let route = JSON.parse(trip.route || '[]');
      if (trip.status === 'in_progress') {
        route.push({ lat, lng, time: Date.now() });
      }

      await dbRun(
        'UPDATE trips SET driver_lat = ?, driver_lng = ?, route = ? WHERE id = ?',
        [lat, lng, JSON.stringify(route), tripId]
      );

      if (trip.driver_id) {
        await dbRun('UPDATE taxis SET lat = ?, lng = ? WHERE id = ?', [lat, lng, trip.driver_id]);
      }

      // إحصائيات مباشرة
      let liveStats = null;
      if (trip.status === 'in_progress' && route.length > 1) {
        let totalDist = 0;
        for (let i = 1; i < route.length; i++) {
          totalDist += getDistanceKm(route[i-1].lat, route[i-1].lng, route[i].lat, route[i].lng);
        }
        let durationMin = 0;
        if (trip.start_time) {
          const diffMs = Date.now() - Number(trip.start_time);
          if (diffMs > 0 && diffMs < 86400000) durationMin = Math.round(diffMs / 60000);
        }
        liveStats = {
          distanceKm: Math.round(totalDist * 1000) / 1000,
          durationMinutes: durationMin,
          currentFare: calculateFare(totalDist, durationMin),
        };
      }

      // ✅ إرسال للراكب مباشرة عبر Socket
      io.to(`trip:${tripId}`).emit('driver:moved', {
        tripId, lat, lng, liveStats, status: trip.status
      });

    } catch (e) {
      console.error('driver:location error:', e.message);
    }
  });

  socket.on('disconnect', () => {
    console.log('🔌 Client disconnected:', socket.id);
  });
});

// ===== REST API =====

app.get('/', (req, res) => res.send('On Call Backend 🚀 (Socket.IO)'));
app.get('/test', (req, res) => res.json({ success: true, message: 'API Works' }));

// ===== تسجيل دخول الراكب =====
app.post('/login', async (req, res) => {
  try {
    const { phone, name } = req.body;
    if (!phone) return res.status(400).json({ success: false, message: 'رقم الهاتف مطلوب' });
    let user = await dbGet('SELECT * FROM users WHERE phone = ?', [phone]);
    if (!user) {
      const result = await dbRun('INSERT INTO users (phone, name, balance) VALUES (?, ?, 0)', [phone, name || 'راكب']);
      user = await dbGet('SELECT * FROM users WHERE id = ?', [result.lastID]);
    }
    res.json({ success: true, user });
  } catch (err) {
    res.status(500).json({ success: false, message: 'خطأ في السيرفر' });
  }
});

// ===== تسجيل دخول السائق =====
app.post('/driver/login', async (req, res) => {
  try {
    const { phone } = req.body;
    if (!phone) return res.status(400).json({ success: false, message: 'رقم الهاتف مطلوب' });
    let driver = await dbGet('SELECT * FROM drivers WHERE phone = ?', [phone]);
    if (!driver) {
      const result = await dbRun('INSERT INTO drivers (phone, name, car_name, status) VALUES (?, ?, ?, ?)', [phone, 'سائق جديد', '', 'offline']);
      driver = await dbGet('SELECT * FROM drivers WHERE id = ?', [result.lastID]);
    }
    res.json({ success: true, driver });
  } catch (err) {
    res.status(500).json({ success: false, message: 'خطأ في السيرفر' });
  }
});

// ===== حالة السائق =====
app.post('/driver/status', async (req, res) => {
  try {
    const { phone, isOnline } = req.body;
    await dbRun('UPDATE drivers SET status = ? WHERE phone = ?', [isOnline ? 'online' : 'offline', phone]);
    const driver = await dbGet('SELECT * FROM drivers WHERE phone = ?', [phone]);
    if (driver) await dbRun('UPDATE taxis SET status = ? WHERE driver_id = ?', [isOnline ? 'online' : 'offline', driver.id]);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== الرصيد =====
app.get('/balance/:phone', async (req, res) => {
  try {
    const user = await dbGet('SELECT balance FROM users WHERE phone = ?', [req.params.phone]);
    if (!user) return res.status(404).json({ success: false, message: 'المستخدم غير موجود' });
    res.json({ success: true, balance: user.balance });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.post('/balance/add', async (req, res) => {
  try {
    const { phone, amount } = req.body;
    await dbRun('UPDATE users SET balance = balance + ? WHERE phone = ?', [Number(amount), phone]);
    const user = await dbGet('SELECT balance FROM users WHERE phone = ?', [phone]);
    res.json({ success: true, balance: user.balance });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== السكوترات =====
app.get('/scooters', async (req, res) => {
  try {
    res.json(await dbAll('SELECT * FROM scooters'));
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.post('/scooter/rent', async (req, res) => {
  try {
    const { scooterId, phone } = req.body;
    const scooter = await dbGet('SELECT * FROM scooters WHERE id = ?', [Number(scooterId)]);
    const user = await dbGet('SELECT * FROM users WHERE phone = ?', [phone]);
    if (!scooter) return res.status(404).json({ success: false, message: 'السكوتر غير موجود' });
    if (!user) return res.status(404).json({ success: false, message: 'المستخدم غير موجود' });
    if (scooter.status !== 'available') return res.status(400).json({ success: false, message: 'السكوتر غير متاح' });
    if (user.balance < 1) return res.status(400).json({ success: false, message: 'الرصيد غير كاف' });
    await dbRun('UPDATE scooters SET status = ? WHERE id = ?', ['riding', scooterId]);
    await dbRun('UPDATE users SET balance = balance - 1 WHERE phone = ?', [phone]);
    const updated = await dbGet('SELECT balance FROM users WHERE phone = ?', [phone]);
    res.json({ success: true, message: 'تم استئجار السكوتر', balance: updated.balance });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.post('/scooter/return', async (req, res) => {
  try {
    const { scooterId } = req.body;
    await dbRun('UPDATE scooters SET status = ? WHERE id = ?', ['available', scooterId]);
    res.json({ success: true, message: 'تم إرجاع السكوتر' });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== التاكسيات =====
app.get('/taxis', async (req, res) => {
  try {
    res.json(await dbAll('SELECT * FROM taxis'));
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== طلب تاكسي =====
app.post('/taxi/request', async (req, res) => {
  try {
    const { pickup, destination, phone, pickupLat, pickupLng, destLat, destLng } = req.body;
    if (!pickup || !destination) return res.status(400).json({ success: false, message: 'بيانات الرحلة ناقصة' });

    const driver = await dbGet(`
      SELECT t.* FROM taxis t
      LEFT JOIN (SELECT driver_id, COUNT(*) as c FROM trips WHERE status IN ('accepted','arrived','in_progress') GROUP BY driver_id) tc ON t.id = tc.driver_id
      WHERE t.status = 'online'
      ORDER BY COALESCE(tc.c, 0) ASC, RANDOM() LIMIT 1
    `);

    let estimatedFare = 1.0;
    if (pickupLat != null && pickupLng != null && destLat != null && destLng != null) {
      estimatedFare = calculateFare(getDistanceKm(pickupLat, pickupLng, destLat, destLng));
    }

    const result = await dbRun(`
      INSERT INTO trips (user_phone, driver_name, driver_id, pickup, destination,
        pickup_lat, pickup_lng, dest_lat, dest_lng, driver_lat, driver_lng,
        status, estimated_fare, route)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'waiting_driver', ?, '[]')
    `, [phone || null, driver ? driver.name : null, driver ? driver.id : null,
        pickup, destination, pickupLat || null, pickupLng || null,
        destLat || null, destLng || null,
        driver ? driver.lat : null, driver ? driver.lng : null, estimatedFare]);

    if (driver) await dbRun("UPDATE taxis SET status = 'busy' WHERE id = ?", [driver.id]);

    const trip = await dbGet('SELECT * FROM trips WHERE id = ?', [result.lastID]);
    const formatted = formatTrip(trip);

    // ✅ إشعار السائق فوراً عبر Socket
    if (driver) {
      io.emit('new:trip', formatted);
    }

    res.json({ success: true, trip: formatted, driver: driver || null });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, message: 'خطأ في السيرفر' });
  }
});

// ===== جميع الرحلات =====
app.get('/taxi/trips', async (req, res) => {
  try {
    const { driver_phone } = req.query;
    let trips;
    if (driver_phone) {
      const driver = await dbGet('SELECT * FROM drivers WHERE phone = ?', [driver_phone]);
      if (driver) {
        trips = await dbAll(`SELECT * FROM trips WHERE status = 'waiting_driver' OR driver_name = ? ORDER BY created_at DESC`, [driver.name]);
      } else {
        trips = await dbAll("SELECT * FROM trips WHERE status = 'waiting_driver' ORDER BY created_at DESC");
      }
    } else {
      trips = await dbAll('SELECT * FROM trips ORDER BY created_at DESC');
    }
    res.json(trips.map(formatTrip));
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.get('/taxi/requests', async (req, res) => {
  try {
    const trips = await dbAll("SELECT * FROM trips WHERE status = 'waiting_driver' ORDER BY created_at DESC");
    res.json(trips.map(formatTrip));
  } catch (err) {
    res.status(500).json([]);
  }
});

// ===== رحلات الراكب =====
app.get('/taxi/trips/passenger/:phone', async (req, res) => {
  try {
    const trips = await dbAll('SELECT * FROM trips WHERE user_phone = ? ORDER BY created_at DESC', [req.params.phone]);
    res.json(trips.map(formatTrip));
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== تغيير حالة الرحلة =====
app.put('/taxi/trips/:id/status', async (req, res) => {
  try {
    const tripId = Number(req.params.id);
    const { status, driver_phone } = req.body;
    const validStatuses = ['waiting_driver', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled'];
    if (!validStatuses.includes(status)) return res.status(400).json({ success: false, message: 'الحالة غير صحيحة' });

    const trip = await dbGet('SELECT * FROM trips WHERE id = ?', [tripId]);
    if (!trip) return res.status(404).json({ success: false, message: 'الرحلة غير موجودة' });

    if (status === 'accepted' && driver_phone) {
      const driver = await dbGet('SELECT * FROM drivers WHERE phone = ?', [driver_phone]);
      if (driver) {
        const taxi = await dbGet('SELECT * FROM taxis WHERE driver_id = ?', [driver.id]);
        await dbRun('UPDATE trips SET status = ?, driver_id = ?, driver_name = ?, driver_lat = ?, driver_lng = ? WHERE id = ?',
          [status, driver.id, driver.name, taxi ? taxi.lat : null, taxi ? taxi.lng : null, tripId]);
        if (taxi) await dbRun("UPDATE taxis SET status = 'busy' WHERE id = ?", [taxi.id]);
      } else {
        await dbRun('UPDATE trips SET status = ? WHERE id = ?', [status, tripId]);
      }
    } else if (status === 'in_progress') {
      await dbRun('UPDATE trips SET status = ?, start_time = ?, route = ? WHERE id = ?', [status, Date.now(), '[]', tripId]);
    } else if (status === 'completed') {
      const route = JSON.parse(trip.route || '[]');
      let totalDistKm = 0;
      for (let i = 1; i < route.length; i++) {
        totalDistKm += getDistanceKm(route[i-1].lat, route[i-1].lng, route[i].lat, route[i].lng);
      }
      if (totalDistKm < 0.1 && trip.pickup_lat && trip.dest_lat) {
        totalDistKm = getDistanceKm(trip.pickup_lat, trip.pickup_lng, trip.dest_lat, trip.dest_lng);
      }
      let durationMinutes = 0;
      if (trip.start_time) {
        const diffMs = Date.now() - Number(trip.start_time);
        if (diffMs > 0 && diffMs < 86400000) durationMinutes = Math.max(1, Math.round(diffMs / 60000));
      }
      const finalFare = totalDistKm > 0.1 ? calculateFare(totalDistKm, durationMinutes)
        : durationMinutes > 0 ? Math.round((1.0 + durationMinutes * 0.050) * 1000) / 1000
        : trip.estimated_fare || 1.0;

      await dbRun('UPDATE trips SET status = ?, end_time = CURRENT_TIMESTAMP, final_fare = ?, total_distance = ?, duration_minutes = ? WHERE id = ?',
        [status, finalFare, Math.round(totalDistKm * 1000) / 1000, durationMinutes, tripId]);

      if (trip.user_phone) {
        const user = await dbGet('SELECT balance FROM users WHERE phone = ?', [trip.user_phone]);
        if (user && user.balance >= finalFare) {
          await dbRun('UPDATE users SET balance = balance - ? WHERE phone = ?', [finalFare, trip.user_phone]);
        }
      }
      if (trip.driver_id) await dbRun("UPDATE taxis SET status = 'online' WHERE id = ?", [trip.driver_id]);
    } else if (status === 'cancelled') {
      await dbRun('UPDATE trips SET status = ? WHERE id = ?', [status, tripId]);
      if (trip.driver_id) await dbRun("UPDATE taxis SET status = 'online' WHERE id = ?", [trip.driver_id]);
    } else {
      await dbRun('UPDATE trips SET status = ? WHERE id = ?', [status, tripId]);
    }

    const updated = await dbGet('SELECT * FROM trips WHERE id = ?', [tripId]);
    const formatted = formatTrip(updated);

    // ✅ إشعار جميع المتصلين بتغيير الحالة فوراً
    io.to(`trip:${tripId}`).emit('trip:updated', formatted);

    // إشعار الراكب بقبول السائق
    if (status === 'accepted' && updated.user_phone) {
      io.to(`passenger:${updated.user_phone}`).emit('trip:accepted', formatted);
    }

    res.json({ success: true, trip: formatted });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false });
  }
});

// ===== تقييم الرحلة =====
app.post('/taxi/trips/:id/rate', async (req, res) => {
  try {
    const { rating } = req.body;
    if (!rating || rating < 1 || rating > 5) return res.status(400).json({ success: false });
    await dbRun('UPDATE trips SET rating = ? WHERE id = ?', [rating, req.params.id]);
    res.json({ success: true, message: 'شكراً على تقييمك' });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== تحديث موقع السائق (HTTP fallback) =====
app.post('/taxi/update-location', async (req, res) => {
  try {
    const { tripId, lat, lng } = req.body;
    const trip = await dbGet('SELECT * FROM trips WHERE id = ?', [Number(tripId)]);
    if (!trip) return res.status(404).json({ success: false });

    let route = JSON.parse(trip.route || '[]');
    if (trip.status === 'in_progress') route.push({ lat, lng, time: Date.now() });

    await dbRun('UPDATE trips SET driver_lat = ?, driver_lng = ?, route = ? WHERE id = ?',
      [lat, lng, JSON.stringify(route), tripId]);
    if (trip.driver_id) await dbRun('UPDATE taxis SET lat = ?, lng = ? WHERE id = ?', [lat, lng, trip.driver_id]);

    let liveStats = null;
    if (trip.status === 'in_progress' && route.length > 1) {
      let totalDist = 0;
      for (let i = 1; i < route.length; i++) {
        totalDist += getDistanceKm(route[i-1].lat, route[i-1].lng, route[i].lat, route[i].lng);
      }
      let durationMin = 0;
      if (trip.start_time) {
        const diffMs = Date.now() - Number(trip.start_time);
        if (diffMs > 0 && diffMs < 86400000) durationMin = Math.round(diffMs / 60000);
      }
      liveStats = {
        distanceKm: Math.round(totalDist * 1000) / 1000,
        durationMinutes: durationMin,
        currentFare: calculateFare(totalDist, durationMin),
      };
    }

    // إرسال عبر Socket أيضاً
    io.to(`trip:${tripId}`).emit('driver:moved', { tripId, lat, lng, liveStats, status: trip.status });

    res.json({ success: true, liveStats });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== جلب موقع السائق =====
app.get('/taxi/trips/:id/location', async (req, res) => {
  try {
    const trip = await dbGet('SELECT * FROM trips WHERE id = ?', [Number(req.params.id)]);
    if (!trip) return res.status(404).json({ success: false });

    const route = JSON.parse(trip.route || '[]');
    let distanceKm = 0;
    for (let i = 1; i < route.length; i++) {
      distanceKm += getDistanceKm(route[i-1].lat, route[i-1].lng, route[i].lat, route[i].lng);
    }
    let durationMinutes = 0;
    if (trip.start_time) {
      const diffMs = Date.now() - Number(trip.start_time);
      if (diffMs > 0 && diffMs < 86400000) durationMinutes = Math.round(diffMs / 60000);
    }

    res.json({
      success: true,
      driverLat: trip.driver_lat,
      driverLng: trip.driver_lng,
      driverName: trip.driver_name,
      pickupLat: trip.pickup_lat,
      pickupLng: trip.pickup_lng,
      destLat: trip.dest_lat,
      destLng: trip.dest_lng,
      status: trip.status,
      route,
      estimatedFare: trip.estimated_fare,
      finalFare: trip.final_fare,
      liveStats: trip.status === 'in_progress' ? {
        distanceKm: Math.round(distanceKm * 1000) / 1000,
        durationMinutes,
        currentFare: calculateFare(distanceKm, durationMinutes),
      } : null,
    });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== جلب رحلة واحدة =====
app.get('/taxi/trips/:id', async (req, res) => {
  try {
    const trip = await dbGet('SELECT * FROM trips WHERE id = ?', [Number(req.params.id)]);
    if (!trip) return res.status(404).json({ success: false });
    res.json({ success: true, trip: formatTrip(trip) });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== Google Places Proxy =====
app.get('/places/autocomplete', async (req, res) => {
  try {
    const { input, lat, lng } = req.query;
    if (!input) return res.json({ predictions: [] });
    const apiKey = 'AIzaSyCFrnw402eLxZFqMFqwpCmk9cM4071OL74';
    const location = lat && lng ? `&location=${lat},${lng}&radius=50000` : '&location=29.3759,47.9774&radius=50000';
    const url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(input)}&language=ar&components=country:kw${location}&key=${apiKey}`;
    const response = await fetch(url);
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.json({ predictions: [] });
  }
});

app.get('/places/details', async (req, res) => {
  try {
    const { place_id } = req.query;
    if (!place_id) return res.json({ result: null });
    const apiKey = 'AIzaSyCFrnw402eLxZFqMFqwpCmk9cM4071OL74';
    const url = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${place_id}&fields=name,formatted_address,geometry&language=ar&key=${apiKey}`;
    const response = await fetch(url);
    const data = await response.json();
    res.json(data);
  } catch (err) {
    res.json({ result: null });
  }
});

// ===== لوحة المشرف =====
app.get('/admin/stats', async (req, res) => {
  try {
    const totalTrips = await dbGet('SELECT COUNT(*) as c FROM trips');
    const totalDrivers = await dbGet('SELECT COUNT(*) as c FROM drivers');
    const totalUsers = await dbGet('SELECT COUNT(*) as c FROM users');
    const revenue = await dbGet("SELECT SUM(final_fare) as total FROM trips WHERE status = 'completed'");
    const activeTrips = await dbGet("SELECT COUNT(*) as c FROM trips WHERE status IN ('accepted','arrived','in_progress')");
    const onlineDrivers = await dbGet("SELECT COUNT(*) as c FROM drivers WHERE status = 'online'");
    res.json({
      totalTrips: totalTrips.c, totalDrivers: totalDrivers.c,
      totalUsers: totalUsers.c, totalRevenue: revenue.total || 0,
      activeTrips: activeTrips.c, onlineDrivers: onlineDrivers.c,
    });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.get('/admin/trips', async (req, res) => {
  try {
    const trips = await dbAll('SELECT * FROM trips ORDER BY created_at DESC LIMIT 100');
    res.json(trips.map(formatTrip));
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.get('/admin/drivers', async (req, res) => {
  try {
    res.json(await dbAll('SELECT * FROM drivers ORDER BY created_at DESC'));
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.get('/admin/users', async (req, res) => {
  try {
    res.json(await dbAll('SELECT * FROM users ORDER BY created_at DESC'));
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

// ===== Reset =====
app.delete('/taxi/trips', async (req, res) => {
  try {
    await dbRun('DELETE FROM trips');
    await dbRun("UPDATE taxis SET status = 'online'");
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.post('/scooters/reset', async (req, res) => {
  try {
    await dbRun("UPDATE scooters SET status = 'available'");
    await dbRun("UPDATE taxis SET status = 'online'");
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false });
  }
});

app.use((req, res) => res.status(404).json({ success: false, message: 'الصفحة غير موجودة' }));

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`✅ Server + Socket.IO running on port ${PORT}`));
