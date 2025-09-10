/* =========================
 * functions/index.js
 * =======================*/

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
        'SendGrid API key missing/invalid. Set:\n' +
          '  firebase functions:config:set sendgrid.key="SG.xxxxxx"'
      );
    }
    sgMail.setApiKey(key);
    _sgReady = true;
  }
  return sgMail;
}

// Shared "from"
const MAIL_FROM = {
  email: "bookings@archengineeringservices.com",
  name: "Flex Facility",
};

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
    // prod: https://connect.squareup.com
    baseURL: "https://connect.squareupsandbox.com",
    token,
    locationId,
  };
}

function squareHttp() {
  const cfg = getSquareConfig();
  return axios.create({
    baseURL: cfg.baseURL,
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
      // Optionally pin API version:
      // "Square-Version": "2024-08-21",
    },
    timeout: 20000,
  });
}

async function squareCreatePayment({
  sourceId,
  amountCents,
  currency = "USD",
  idempotencyKey,
  locationId,
}) {
  const cfg = getSquareConfig();
  const http = squareHttp();
  const body = {
    source_id: sourceId,
    idempotency_key: idempotencyKey,
    amount_money: { amount: Number(amountCents), currency },
    location_id: locationId || cfg.locationId,
  };
  const { data } = await http.post("/v2/payments", body);
  return data;
}

/* ---------- helpers for Invoices & Links ---------- */

async function ensureSquareCustomer({ email, given_name, family_name }) {
  const http = squareHttp();

  // try find existing
  try {
    const { data } = await http.post("/v2/customers/search", {
      query: { filter: { email_address: { exact: email } } },
      limit: 1,
    });
    const c = (data.customers || [])[0];
    if (c) return c;
  } catch (_) {
    // ignore search errors; we'll fallback to create
  }

  // create
  const { data } = await http.post("/v2/customers", {
    email_address: email,
    given_name,
    family_name,
  });
  return data.customer;
}

async function squareCreateOrder({
  locationId,
  name,
  amountCents,
  currency = "USD",
}) {
  const http = squareHttp();
  const { data } = await http.post("/v2/orders", {
    order: {
      location_id: locationId,
      line_items: [
        {
          name,
          quantity: "1",
          base_price_money: { amount: Number(amountCents), currency },
        },
      ],
    },
  });
  return data.order;
}

async function squareCreateInvoice({
  locationId,
  orderId,
  customerId,
  title,
  description,
}) {
  const http = squareHttp();
  const { data } = await http.post("/v2/invoices", {
    invoice: {
      location_id: locationId,
      order_id: orderId,
      title,
      description,
      primary_recipient: { customer_id: customerId },
      payment_requests: [
        {
          request_type: "BALANCE",
          // due_date: new Date().toISOString().slice(0, 10), // optional
        },
      ],
    },
    idempotency_key:
      typeof crypto.randomUUID === "function"
        ? crypto.randomUUID()
        : crypto.randomBytes(16).toString("hex"),
  });
  return data.invoice;
}

async function squarePublishInvoice({ invoiceId, version }) {
  const http = squareHttp();
  const idempotency_key =
    typeof crypto.randomUUID === "function"
      ? crypto.randomUUID()
      : crypto.randomBytes(16).toString("hex");
  const { data } = await http.post(`/v2/invoices/${invoiceId}/publish`, {
    idempotency_key,
    version,
  });
  return data.invoice;
}

async function squareCreateQuickPayLink({
  name,
  amountCents,
  currency = "USD",
  locationId,
}) {
  const http = squareHttp();
  const idempotency_key =
    typeof crypto.randomUUID === "function"
      ? crypto.randomUUID()
      : crypto.randomBytes(16).toString("hex");

  const { data } = await http.post("/v2/online-checkout/payment-links", {
    idempotency_key,
    quick_pay: {
      name,
      price_money: { amount: Number(amountCents), currency },
      location_id: locationId,
      payment_note: name,
    },
  });
  return data.payment_link; // { id, url, long_url, ... }
}

/* =========================
   EMAIL FUNCTIONS (bookings)
========================= */

// SEND BOOKING EMAIL ON CREATE
exports.notifyBookingOnCreate = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onCreate(async (snap) => {
    const data = snap.data();
    const bookedEmails = data.booked_emails || [];
    if (bookedEmails.length === 0) return;

    const slotTime = data.time;
    const slotDate = data.date.toDate().toLocaleDateString();
    const trainer = data.trainer_name || "your trainer";

    const mail = getSendGrid();
    await Promise.all(
      bookedEmails.map((email) =>
        mail
          .send({
            to: email,
            from: { ...MAIL_FROM, name: "Flex Facility Bookings" },
            subject: `✅ Booking Confirmed – ${trainer}`,
            text: `Hi there,\n\n🎉 Your session with ${trainer} is confirmed!\n\n📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nPlease arrive 5 minutes early.\n\nThanks,\nFlex Facility Team`,
          })
          .catch((err) =>
            console.error(`❌ Error sending booking (onCreate) to ${email}:`, err)
          )
      )
    );
  });

// SEND BOOKING/RESCHEDULE/CANCEL ON UPDATE
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
    const isReschedule =
      before.is_reschedule === true || after.is_reschedule === true;
    if (isReschedule && newlyBooked.length === 1 && cancelled.length === 1) {
      const email = newlyBooked[0];
      await mail.send({
        to: email,
        from: { ...MAIL_FROM, name: "Flex Facility Bookings" },
        subject: `🔁 Rescheduled – ${trainer}`,
        text:
          `Hi there,\n\n🔁 Your session with ${trainer} has been rescheduled.\n\n` +
          `📅 New Date: ${slotDate}\n⏰ New Time: ${slotTime}\n\nPlease arrive 5 minutes early.\n\nThanks,\nFlex Facility Team`,
      });
      if (after.is_reschedule) {
        await change.after.ref.update({
          is_reschedule: admin.firestore.FieldValue.delete(),
        });
      }
      return;
    }

    for (const email of newlyBooked) {
      tasks.push(
        mail.send({
          to: email,
          from: { ...MAIL_FROM, name: "Flex Facility Bookings" },
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
          from: { ...MAIL_FROM, name: "Flex Facility Bookings" },
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
      .send(
        "<html><body><h3>Square Checkout</h3><p>templates/checkout.html not found.</p></body></html>"
      );
  }
});

// Direct card charge (if you tokenize in a webview)
app.post("/process-payment", async (req, res) => {
  try {
    const { token, amountCents, currency = "USD", locationId } = req.body;
    if (!amountCents || !token) {
      return res
        .status(400)
        .json({ ok: false, error: "Missing token or amount" });
    }

    const idempotencyKey =
      typeof crypto.randomUUID === "function"
        ? crypto.randomUUID()
        : crypto.randomBytes(16).toString("hex");

    const result = await squareCreatePayment({
      sourceId: token.id || token,
      amountCents,
      currency,
      idempotencyKey,
      locationId,
    });

    return res.json({ ok: true, paymentId: result.payment?.id, result });
  } catch (e) {
    const errMsg = e.response?.data
      ? JSON.stringify(e.response.data)
      : e.message || "Payment error";
    console.error("process-payment error:", errMsg);
    return res.status(500).json({ ok: false, error: errMsg });
  }
});

/* =========================
   Create & Publish Invoice (returns public_url)
   Body:
   {
     plan: { name, price, sessions, description },
     customer: { email, given_name, family_name }
   }
========================= */
app.post("/create-invoice", async (req, res) => {
  try {
    const cfg = getSquareConfig();
    const { plan = {}, customer = {} } = req.body || {};
    const name = plan.name || "Fitness Plan";
    const price = Number(plan.price || 0);
    const amountCents = Math.round(price * 100);
    const description = plan.description || "";

    const email = customer.email || "customer@example.com";
    const given_name = customer.given_name || "";
    const family_name = customer.family_name || "";

    // 1) ensure customer
    const cust = await ensureSquareCustomer({
      email,
      given_name,
      family_name,
    });

    // 2) create order
    const order = await squareCreateOrder({
      locationId: cfg.locationId,
      name,
      amountCents,
      currency: "USD",
    });

    // 3) create invoice (DRAFT)
    const draft = await squareCreateInvoice({
      locationId: cfg.locationId,
      orderId: order.id,
      customerId: cust.id,
      title: name,
      description,
    });

    // 4) publish to get public_url
    const published = await squarePublishInvoice({
      invoiceId: draft.id,
      version: draft.version,
    });

    return res.json({ ok: true, invoice: published });
  } catch (e) {
    const msg =
      e.response?.data ? JSON.stringify(e.response.data) : e.message || String(e);
    console.error("create-invoice error:", msg);
    res.status(500).json({ ok: false, error: msg });
  }
});

/* =========================
   Create/Send Pay Link
   Body:
   {
     planName: "Semi Private Day Pass",
     amountCents: 4000,
     recipientEmail: "amila@example.com",
     recipientName: "Amila",
     publicUrl?: "https://square.link/..." // optional: if provided we email this instead of creating a quick link
   }
========================= */
app.post("/payment-link/email", async (req, res) => {
  try {
    const cfg = getSquareConfig();
    const {
      planName,
      amountCents,
      recipientEmail,
      recipientName = "",
      publicUrl,
    } = req.body || {};
    if (!planName || !recipientEmail) {
      return res
        .status(400)
        .json({ ok: false, error: "Missing planName or recipientEmail" });
    }

    // Use provided hosted-invoice URL or create a quick pay link
    let url = (publicUrl || "").trim();
    if (!url) {
      if (!amountCents) {
        return res
          .status(400)
          .json({ ok: false, error: "amountCents required when publicUrl is not provided" });
      }
      const link = await squareCreateQuickPayLink({
        name: planName,
        amountCents: Number(amountCents),
        currency: "USD",
        locationId: cfg.locationId,
      });
      url = link.url;
    }

    // Send email
    const mail = getSendGrid();
    const safeName = recipientName ? ` ${recipientName}` : "";
    const html = `
      <div style="font-family:Arial,Helvetica,sans-serif;line-height:1.5;color:#111">
        <h2 style="margin:0 0 12px">Payment link – ${planName}</h2>
        <p>Hi${safeName},</p>
        <p>Please use the secure button below to complete your payment for <b>${planName}</b>.</p>
        <p style="margin:24px 0">
          <a href="${url}" style="background:#1c2d5e;color:#fff;padding:12px 18px;border-radius:6px;text-decoration:none;display:inline-block">Pay Now</a>
        </p>
        <p>If the button doesn’t work, copy and paste this URL into your browser:</p>
        <p><a href="${url}">${url}</a></p>
        <p style="color:#555">Thank you!<br/>Flex Facility</p>
      </div>
    `;

    await mail.send({
      to: recipientEmail,
      from: { ...MAIL_FROM, name: "Flex Facility Billing" },
      subject: `Payment link – ${planName}`,
      text:
        `Hi${safeName},\n\n` +
        `Please complete your payment for "${planName}" using this secure link:\n` +
        `${url}\n\nThanks,\nFlex Facility`,
      html,
    });

    return res.json({ ok: true, url });
  } catch (e) {
    const msg =
      e.response?.data ? JSON.stringify(e.response.data) : e.message || String(e);
    console.error("payment-link/email error:", msg);
    res.status(500).json({ ok: false, error: msg });
  }
});

// Mount Express
exports.api = functions.https.onRequest(app);
