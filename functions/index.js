// ----- imports -----
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");
const express = require("express");
const cors = require("cors");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const axios = require("axios");

// ----- init -----
admin.initializeApp();

/* =========================
   SendGrid (lazy init)
========================= */
let _sgReady = false;
function getSendGrid() {
  if (!_sgReady) {
    const key = functions.config()?.sendgrid?.key;
    if (!key || typeof key !== "string" || !key.startsWith("SG.")) {
      throw new Error(
        'SendGrid API key missing/invalid. Set:\n  firebase functions:config:set sendgrid.key="SG.xxxxxx"'
      );
    }
    sgMail.setApiKey(key);
    _sgReady = true;
  }
  return sgMail;
}

/* =========================
   Square REST client (no SDK)
========================= */
function getSquareConfig() {
  const token = (functions.config()?.square?.sandbox_token || "").trim();
  const locationId = (functions.config()?.square?.location_id || "").trim();
  if (!token) {
    throw new Error(
      'Square sandbox token not set. Run:\n' +
      '  firebase functions:config:set square.sandbox_token="EAAA-..." square.location_id="YOUR_LOCATION_ID"'
    );
  }
  return {
    baseURL: "https://connect.squareupsandbox.com", // change to https://connect.squareup.com for production
    token,
    locationId,
  };
}

async function squareCreatePayment({ sourceId, amountCents, currency = "USD", idempotencyKey, locationId }) {
  const cfg = getSquareConfig();
  const client = axios.create({
    baseURL: cfg.baseURL,
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
      // Optionally pin API version:
      // "Square-Version": "2024-08-21",
    },
    timeout: 15000,
  });

  const body = {
    source_id: sourceId,
    idempotency_key: idempotencyKey,
    amount_money: { amount: Number(amountCents), currency },
    location_id: locationId || cfg.locationId,
  };

  const { data } = await client.post("/v2/payments", body);
  return data;
}

/* =========================
   EMAIL FUNCTIONS
========================= */
sgMail.setApiKey(functions.config().sendgrid.key);

// ✅ SEND EMAIL ON CREATE
exports.notifyBookingOnCreate = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const bookedEmails = data.booked_emails || [];

    if (bookedEmails.length === 0) {
      console.log("ℹ️ No emails to send on create.");
      return;
    }

    const slotTime = data.time;
    const slotDate = data.date.toDate().toLocaleDateString();
    const trainer = data.trainer_name || "your trainer";

    const sendPromises = bookedEmails.map((email) =>
      sgMail.send({
        to: email,
        from: { email: "bookings@archengineeringservices.com", name: "Flex Facility Bookings" },
        subject: `✅ Booking Confirmed – ${trainer}`,
        text: `Hi there,\n\n🎉 Your session with ${trainer} is confirmed!\n\n📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nPlease arrive 5 minutes early.\n\nThanks,\nFlex Facility Team`,
      }).then(() => console.log(`✅ Booking email (onCreate) sent to: ${email}`))
        .catch((err) => console.error(`❌ Error sending booking (onCreate) to ${email}:`, err))
    );

    await Promise.all(sendPromises);
  });
exports.handleBookingAndCancellation = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;

    const beforeEmails = before.booked_emails || [];
    const afterEmails = after.booked_emails || [];
    const newlyBooked = afterEmails.filter((e) => !beforeEmails.includes(e));
    const cancelled = beforeEmails.filter((e) => !afterEmails.includes(e));

    const slotTime = after.time || before.time;
    const slotDate = (after.date || before.date).toDate().toLocaleDateString();
    const trainer = after.trainer_name || before.trainer_name || "your trainer";

    const mail = getSendGrid();
    const tasks = [];

    // Reschedule
    const isReschedule = before.is_reschedule === true || after.is_reschedule === true;
    if (isReschedule && newlyBooked.length === 1 && cancelled.length === 1) {
      const email = newlyBooked[0];
      await mail.send({
        to: email,
        from: { email: "bookings@archengineeringservices.com", name: "Flex Facility Bookings" },
        subject: `🔁 Rescheduled – ${trainer}`,
        text:
          `Hi there,\n\n🔁 Your session with ${trainer} has been rescheduled.\n\n` +
          `📅 New Date: ${slotDate}\n⏰ New Time: ${slotTime}\n\nPlease arrive 5 minutes early.\n\nThanks,\nFlex Facility Team`,
      });
      if (after.is_reschedule) {
        await change.after.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });
      }
      return;
    }

    for (const email of newlyBooked) {
      tasks.push(
        mail.send({
          to: email,
          from: { email: "bookings@archengineeringservices.com", name: "Flex Facility Bookings" },
          subject: `✅ Booking Confirmed – ${trainer}`,
          text:
            `Hi there,\n\n🎉 Your session with ${trainer} is confirmed!\n\n` +
            `📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nPlease arrive 5 minutes early.\n\nThanks,\nFlex Facility Team`,
        })
      );
    }

    for (const email of cancelled) {
      tasks.push(
        mail.send({
          to: email,
          from: { email: "bookings@archengineeringservices.com", name: "Flex Facility Bookings" },
          subject: `❌ Booking Cancelled – ${trainer}`,
          text:
            `Hi there,\n\nYour session with ${trainer} has been cancelled.\n\n` +
            `📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nIf this was a mistake, you can rebook through the app.\n\nThanks,\nFlex Facility Team`,
        })
      );
    }

    if (tasks.length) await Promise.all(tasks);
  });

/* =========================
   SQUARE CHECKOUT API (Express)
========================= */
const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

app.get("/health", (_req, res) => {
  let squareConfigured = false;
  try {
    const cfg = getSquareConfig();
    squareConfigured = !!cfg.token;
  } catch (_) {
    squareConfigured = false;
  }
  res.json({ ok: true, function: "api", squareConfigured });
});

app.get("/checkout", (_req, res) => {
  const filePath = path.join(__dirname, "templates", "checkout.html");
  if (fs.existsSync(filePath)) {
    res.set("Content-Type", "text/html; charset=utf-8");
    res.status(200).send(fs.readFileSync(filePath, "utf8"));
  } else {
    res
      .status(200)
      .send("<html><body><h3>Square Checkout</h3><p>templates/checkout.html not found.</p></body></html>");
  }
});

app.post("/process-payment", async (req, res) => {
  try {
    const { token, amountCents, currency = "USD", locationId } = req.body;
    if (!amountCents || !token) {
      return res.status(400).json({ ok: false, error: "Missing token or amount" });
    }

    const idempotencyKey =
      typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex");

    const result = await squareCreatePayment({
      sourceId: token.id || token, // accept object or string
      amountCents,
      currency,
      idempotencyKey,
      locationId,
    });

    return res.json({ ok: true, paymentId: result.payment?.id, result });
  } catch (e) {
    const errMsg = e.response?.data ? JSON.stringify(e.response.data) : (e.message || "Payment error");
    console.error("process-payment error:", errMsg);
    return res.status(500).json({ ok: false, error: errMsg });
  }
});

// Mount Express
exports.api = functions.https.onRequest(app);
