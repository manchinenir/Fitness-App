/* =========================
 * functions/index.js
 * =======================*/

/* ----- imports ----- */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");
const express = require("express");
const cors = require("cors");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const axios = require("axios");

/* ----- init ----- */
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

const MAIL_FROM = { email: "bookings@archengineeringservices.com", name: "Flex Facility" };
const REPLY_TO = { email: "admin@archengineeringservices.com", name: "Flex Facility Support" };
const COMMON_HEADERS = {
  "List-Unsubscribe":
    "<mailto:admin@archengineeringservices.com>, <https://archengineeringservices.com/unsubscribe>",
  "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
};
const COMMON_TRACKING = { clickTracking: { enable: false }, openTracking: { enable: false } };

function sendTransactionalEmail({ to, subject, text, html, fromName }) {
  const mail = getSendGrid();
  return mail.send({
    to,
    from: { ...MAIL_FROM, name: fromName || MAIL_FROM.name },
    replyTo: REPLY_TO,
    subject,
    text,
    ...(html ? { html } : {}),
    headers: COMMON_HEADERS,
    trackingSettings: COMMON_TRACKING,
  });
}

/* =========================
   Helpers
========================= */
function safeRefId(ref) {
  if (!ref) return undefined;
  const s = String(ref).trim();
  return s.length <= 40 ? s : s.slice(0, 40);
}
function buildSquareAddress(addr = {}) {
  const out = {};
  if (addr.line1) out.address_line_1 = String(addr.line1);
  if (addr.line2) out.address_line_2 = String(addr.line2);
  if (addr.locality) out.locality = String(addr.locality);
  if (addr.adminArea) out.administrative_district_level_1 = String(addr.adminArea);
  if (addr.postalCode) out.postal_code = String(addr.postalCode);
  if (addr.country) out.country = String(addr.country);
  return Object.keys(out).length ? out : undefined;
}

/* =========================
   Square REST client (ENV-AWARE)
========================= */
function resolveSquareEnv(req) {
  const hdr = (req?.headers?.["x-square-env"] || "").toString().toLowerCase();
  if (hdr === "sandbox" || hdr === "production") return hdr;
  const cfgEnv = (functions.config()?.square?.env || "sandbox").toLowerCase();
  return cfgEnv === "production" ? "production" : "sandbox";
}

function getSquareConfig(req) {
  const env = resolveSquareEnv(req);
  const cfg = functions.config()?.square || {};

  const sandboxToken = (cfg.sandbox_token || "").trim();
  const prodToken = (cfg.prod_token || "").trim();

  const sandboxLocationId = (cfg.sandbox_location_id || cfg.location_id || "").trim();
  const prodLocationId = (cfg.prod_location_id || cfg.location_id || "").trim();

  const isProd = env === "production";
  const token = isProd ? prodToken : sandboxToken;
  const locationId = isProd ? prodLocationId : sandboxLocationId;
  const baseURL = isProd ? "https://connect.squareup.com" : "https://connect.squareupsandbox.com";

  if (!token) {
    const hint = isProd ? "prod_token" : "sandbox_token";
    throw new Error(`Square ${env} token not set. Run:\n  firebase functions:config:set square.${hint}="EAAA-..."`);
  }
  if (!locationId) {
    const hint = isProd ? "prod_location_id" : "sandbox_location_id";
    throw new Error(`Square ${env} location_id not set. Run:\n  firebase functions:config:set square.${hint}="LXXXX..."`);
  }

  return { env, isProd, baseURL, token, locationId };
}

function squareHttp(req) {
  const cfg = getSquareConfig(req);
  return axios.create({
    baseURL: cfg.baseURL,
    headers: {
      Authorization: `Bearer ${cfg.token}`,
      "Content-Type": "application/json",
      Accept: "application/json",
      "Square-Version": "2024-08-21",
    },
    timeout: 20000,
  });
}

/* =========================
   Square API wrappers
========================= */
async function ensureSquareCustomer({ req, email, given_name, family_name, referenceId }) {
  const http = squareHttp(req);
  try {
    if (email) {
      const { data } = await http.post("/v2/customers/search", {
        query: { filter: { email_address: { exact: email } } },
        limit: 1,
      });
      const c = (data.customers || [])[0];
      if (c) return c;
    }
  } catch (_) {}

  const payload = {
    email_address: email,
    given_name,
    family_name,
    ...(referenceId ? { reference_id: referenceId } : {}),
  };
  const { data } = await http.post("/v2/customers", payload);
  return data.customer;
}

async function squareCreateOrder({
  req,
  locationId,
  name,
  amountCents,
  currency = "USD",
  customerId,
  referenceId,
}) {
  const http = squareHttp(req);
  const { data } = await http.post("/v2/orders", {
    order: {
      location_id: locationId,
      ...(customerId ? { customer_id: customerId } : {}),
      ...(referenceId ? { reference_id: referenceId } : {}),
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

async function squareCreatePayment({
  req,
  sourceId,
  amountCents,
  currency = "USD",
  idempotencyKey,
  locationId,
  verificationToken,
  orderId,
  customerId,
  note,
  referenceId,
  buyerEmail,
  billingAddress,
}) {
  const cfg = getSquareConfig(req);
  const http = squareHttp(req);
  const body = {
    source_id: sourceId,
    idempotency_key: idempotencyKey,
    amount_money: { amount: Number(amountCents), currency },
    location_id: locationId || cfg.locationId,
    ...(verificationToken ? { verification_token: verificationToken } : {}),
    ...(orderId ? { order_id: orderId } : {}),
    ...(customerId ? { customer_id: customerId } : {}),
    ...(note ? { note } : {}),
    ...(referenceId ? { reference_id: referenceId } : {}),
    ...(buyerEmail ? { buyer_email_address: buyerEmail } : {}),
    ...(billingAddress ? { billing_address: billingAddress } : {}),
  };
  const { data } = await http.post("/v2/payments", body);
  return data;
}

/* ---------- create link/invoice helpers ---------- */
async function squareCreateInvoice({ req, locationId, orderId, customerId, title, description }) {
  const http = squareHttp(req);
  const { data } = await http.post("/v2/invoices", {
    invoice: {
      location_id: locationId,
      order_id: orderId,
      title,
      description,
      primary_recipient: { customer_id: customerId },
      payment_requests: [{ request_type: "BALANCE" }],
    },
    idempotency_key:
      typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex"),
  });
  return data.invoice;
}
async function squarePublishInvoice({ req, invoiceId, version }) {
  const http = squareHttp(req);
  const idempotency_key =
    typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex");
  const { data } = await http.post(`/v2/invoices/${invoiceId}/publish`, { idempotency_key, version });
  return data.invoice;
}
async function squareCreateQuickPayLink({ req, name, amountCents, currency = "USD", locationId }) {
  const http = squareHttp(req);
  const idempotency_key =
    typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex");

  const { data } = await http.post("/v2/online-checkout/payment-links", {
    idempotency_key,
    quick_pay: {
      name,
      price_money: { amount: Number(amountCents), currency },
      location_id: locationId,
      payment_note: name,
    },
  });
  return data.payment_link;
}

/* ---------- write client_purchases on success ---------- */
async function createClientPurchaseFromPayment({ buyer, planName, amountCents, refId, payment }) {
  const db = admin.firestore();

  // Prefer explicit userId from buyer; fallback by email lookup
  let userId = buyer.userId || null;
  if (!userId && buyer.email) {
    const snap = await db.collection("users").where("email", "==", buyer.email).limit(1).get();
    if (!snap.empty) userId = snap.docs[0].id;
  }
  if (!userId) {
    console.warn("⚠️ No userId found for purchase, skipping client_purchases write");
    return;
  }

  const planId = buyer.planId || null;
  const totalSessions = Number(buyer.sessions || 0);
  const priceDollars = buyer.price != null ? Number(buyer.price) : Number(amountCents) / 100;

  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  const purchaseRef = db.collection("client_purchases").doc();

  const clientName = ((buyer.firstName || "") + " " + (buyer.lastName || "")).trim();

  const purchaseData = {
    purchaseId: purchaseRef.id,
    docId: purchaseRef.id,
    userId,
    clientName,
    planId,
    planName: buyer.planName || planName || "Training Plan",
    planCategory: buyer.planCategory || "",
    price: priceDollars,
    sessions: totalSessions,
    totalSessions: totalSessions,
    remainingSessions: totalSessions,
    bookedSessions: 0,
    usedSessions: 0,
    availableSessions: totalSessions,
    description: buyer.description || "",
    isActive: true,
    status: "active",
    purchaseDate: nowTs,
    createdAt: nowTs,
    updatedAt: nowTs,
    paymentMethod: "square",
    paymentStatus: (payment && payment.status) || "COMPLETED",
    isRepurchase: false,
    referenceId: refId || null,
    paymentId: payment?.id || null,
    email: buyer.email || "",
  };

  await purchaseRef.set(purchaseData);
  console.log("✅ client_purchases created:", purchaseRef.id);
}

/* =========================
   EMAIL TRIGGERS (unchanged)
========================= */
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

    await Promise.all(
      bookedEmails.map((email) =>
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `Booking Confirmed – ${trainer}`,
          text:
            `Hi,\n\nYour session is confirmed.\n\n` +
            `Date: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\n` +
            `Please arrive 5 minutes early.\n\n— Flex Facility Team`,
        }).catch((err) => console.error(`Error sending booking (onCreate) to ${email}:`, err))
      )
    );
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

    const tasks = [];

    const isReschedule = before.is_reschedule === true || after.is_reschedule === true;
    if (isReschedule && newlyBooked.length === 1 && cancelled.length === 1) {
      const email = newlyBooked[0];
      await sendTransactionalEmail({
        to: email,
        fromName: "Flex Facility Bookings",
        subject: `Rescheduled – ${trainer}`,
        text:
          `Hi,\n\nYour session has been rescheduled.\n\n` +
          `New Date: ${slotDate}\nNew Time: ${slotTime}\nTrainer: ${trainer}\n\n` +
          `Please arrive 5 minutes early.\n\n— Flex Facility Team`,
      });
      if (after.is_reschedule) {
        await change.after.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });
      }
      return;
    }

    for (const email of newlyBooked) {
      tasks.push(
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `Booking Confirmed – ${trainer}`,
          text:
            `Hi,\n\nYour session is confirmed.\n\n` +
            `Date: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\n` +
            `Please arrive 5 minutes early.\n\n— Flex Facility Team`,
        })
      );
    }

    for (const email of cancelled) {
      tasks.push(
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `Booking Cancelled – ${trainer}`,
          text:
            `Hi,\n\nYour session has been cancelled.\n\n` +
            `Date: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\n` +
            `If this was a mistake, you can rebook in the app.\n\n— Flex Facility Team`,
        })
      );
    }

    if (tasks.length) await Promise.all(tasks);
  });

/* =========================
   EXPRESS: /checkout & /process-payment
========================= */
const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

app.get("/health", (req, res) => {
  let squareConfigured = false;
  let env = "sandbox";
  try {
    const cfg = getSquareConfig(req);
    squareConfigured = !!cfg.token;
    env = cfg.env;
  } catch (_) {
    squareConfigured = false;
  }
  res.json({ ok: true, function: "api", squareConfigured, env });
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
    const {
      token,
      amountCents,
      currency = "USD",
      locationId,
      verificationToken,

      planName = "Fitness Plan",
      buyer = {},          // includes userId, planId, sessions, price, email, first/last
      billingDetails = {}, // line1, line2, locality, adminArea, postalCode, country
      referenceId,
    } = req.body || {};

    if (!token || !amountCents) {
      return res.status(400).json({ ok: false, error: "Missing card token or amount." });
    }

    const cfg = getSquareConfig(req);
    const env = cfg.env || "sandbox";

    const sandboxToken = (functions.config()?.square?.sandbox_token || "").trim();
    const prodToken = (functions.config()?.square?.prod_token || "").trim();

    const sandboxLocationId = (functions.config()?.square?.sandbox_location_id || functions.config()?.square?.location_id || "").trim();
    const prodLocationId = (functions.config()?.square?.prod_location_id || functions.config()?.square?.location_id || "").trim();

    const isProd = env === "production";
    const tokenToUse = isProd ? prodToken : sandboxToken;
    const locId = locationId || (isProd ? prodLocationId : sandboxLocationId);

    if (!tokenToUse) throw new Error(`Square ${env} token missing in functions config`);
    if (!locId) throw new Error(`Square ${env} locationId missing in functions config`);

    // Create/find customer
    let customerId;
    try {
      const customer = await ensureSquareCustomer({
        req,
        email: buyer.email,
        given_name: buyer.firstName,
        family_name: buyer.lastName,
        referenceId: safeRefId(referenceId),
      });
      customerId = customer.id;
    } catch (e) {
      console.warn("ensureSquareCustomer warning:", e?.response?.data || e.message);
    }

    const refId = safeRefId(referenceId);
    const idempotencyKey =
      typeof crypto.randomUUID === "function" ? crypto.randomUUID() : crypto.randomBytes(16).toString("hex");

    // Create order
    let orderId;
    try {
      const order = await squareCreateOrder({
        req,
        locationId: locId,
        name: planName || "Training Plan",
        amountCents: Math.round(Number(amountCents)),
        currency,
        customerId,
        referenceId: refId,
      });
      orderId = order.id;
    } catch (e) {
      console.warn("squareCreateOrder warning:", e?.response?.data || e.message);
    }

    // Charge
    const result = await squareCreatePayment({
      req,
      sourceId: token.id || token,
      amountCents: Math.round(Number(amountCents)),
      currency,
      idempotencyKey,
      locationId: locId,
      verificationToken,
      orderId,
      customerId,
      referenceId: refId,
      note: `${(buyer.firstName || "")} ${(buyer.lastName || "")} – ${planName}`,
      buyerEmail: buyer?.email,
      billingAddress: buildSquareAddress(billingDetails),
    });

    // Email receipt (best effort)
    if (buyer?.email) {
      try {
        const dollars = (Number(amountCents) / 100).toFixed(2);
        await sendTransactionalEmail({
          to: buyer.email,
          fromName: "Flex Facility Billing",
          subject: `Payment Successful – ${planName}`,
          text: `Hi ${(buyer.firstName || "")} ${(buyer.lastName || "")},\n\nYour payment for "${planName}" was successful.\nAmount: $${dollars}\n${refId ? `Reference: ${refId}\n` : ""}\nThank you,\nFlex Facility`,
        });
      } catch (e) {
        console.error("SendGrid error:", e?.response?.data || e.message);
      }
    }

    // Write client_purchases so the app shows the plan as ACTIVE
    try {
      await createClientPurchaseFromPayment({
        buyer,
        planName,
        amountCents: Number(amountCents),
        refId,
        payment: result.payment,
      });
    } catch (e) {
      console.error("createClientPurchaseFromPayment error:", e.message || e);
    }

    return res.json({ ok: true, paymentId: result.payment?.id, result });
  } catch (e) {
    console.error("process-payment error:", e?.response?.data || e);
    let clientMessage = "Payment failed. Please check your card details or try another card.";
    if (e.response?.data?.errors?.length) {
      const sqErr = e.response.data.errors[0];
      clientMessage = sqErr.detail || sqErr.message || clientMessage;
    } else if (typeof e.message === "string" && e.message.trim().length && e.message.length < 200) {
      clientMessage = e.message;
    }
    return res.status(400).json({ ok: false, error: clientMessage });
  }
});

/* =========================
   Invoices & Pay link
========================= */
/* =========================
   Create & Publish Invoice
   + create client_purchases so plan becomes ACTIVE
========================= */
app.post("/create-invoice", async (req, res) => {
  try {
    const cfg = getSquareConfig(req);
    const { plan = {}, customer = {} } = req.body || {};

    const name = plan.name || "Fitness Plan";
    const price = Number(plan.price || 0);
    const amountCents = Math.round(price * 100);
    const description = plan.description || "";

    const email = customer.email || "customer@example.com";
    const given_name = customer.given_name || "";
    const family_name = customer.family_name || "";

    // 1) Create / find Square customer
    const cust = await ensureSquareCustomer({
      req,
      email,
      given_name,
      family_name,
      referenceId: safeRefId(plan.referenceId || req.body.referenceId),
    });

    // 2) Create Square order for the invoice
    const order = await squareCreateOrder({
      req,
      locationId: cfg.locationId,
      name,
      amountCents,
      currency: "USD",
      customerId: cust.id,
      referenceId: safeRefId(plan.referenceId || req.body.referenceId),
    });

    // 3) Create & publish invoice
    const draft = await squareCreateInvoice({
      req,
      locationId: cfg.locationId,
      orderId: order.id,
      customerId: cust.id,
      title: name,
      description,
    });

    const published = await squarePublishInvoice({
      req,
      invoiceId: draft.id,
      version: draft.version,
    });

    // 4) ALSO create client_purchases so the plan shows as ACTIVE in the app
    try {
      // Build a "buyer" object similar to checkout.html
      const buyer = {
        userId: req.body.userId || plan.userId || null,
        planId: plan.docId || plan.id || null,
        planName: plan.name || name,
        planCategory: plan.category || "",
        sessions: plan.sessions || 0,
        price: plan.price || price,
        description: plan.description || description,

        firstName: given_name,
        lastName: family_name,
        email: email,
      };

      const refId = safeRefId(plan.referenceId || req.body.referenceId);

      await createClientPurchaseFromPayment({
        buyer,
        planName: name,
        amountCents,
        refId,
        payment: null, // no direct payment object since this is invoice-based
      });
    } catch (err) {
      console.error("createClientPurchaseFromPayment (invoice) error:", err.message || err);
      // We do NOT fail the invoice API just because Firestore write failed
    }

    return res.json({ ok: true, invoice: published });
  } catch (e) {
    const msg = e.response?.data ? JSON.stringify(e.response.data) : e.message || String(e);
    console.error("create-invoice error:", msg);
    res.status(500).json({ ok: false, error: msg });
  }
});

/* =========================
   Create/Send Pay Link
========================= */

app.post("/payment-link/email", async (req, res) => {
  try {
    // Only used if we need to create a link:
    const cfg = getSquareConfig(req);

    const {
      planName,
      amountCents,            // required if publicUrl not provided
      recipientEmail,
      recipientName = "",
      publicUrl,              // optional: if provided, we email this directly
    } = req.body || {};

    if (!planName || !recipientEmail) {
      return res.status(400).json({ ok: false, error: "Missing planName or recipientEmail" });
    }

    // Determine which URL to send
    let url = (publicUrl || "").trim();
    if (!url) {
      if (!amountCents) {
        return res.status(400).json({
          ok: false,
          error: "amountCents required when publicUrl is not provided",
        });
      }
      // Create a Square Quick Pay link
      const link = await squareCreateQuickPayLink({
        req,
        name: planName,
        amountCents: Number(amountCents),
        currency: "USD",
        locationId: cfg.locationId,
      });
      url = link.url;
    }

    const safeName = recipientName ? ` ${recipientName}` : "";

    const html = `
      <div style="font-family:Arial,Helvetica,sans-serif;color:#222;line-height:1.6">
        <h2 style="color:#1C2D5E;">Complete your payment — ${planName}</h2>
        <p>Hi${safeName},</p>
        <p>Your secure payment link for <b>${planName}</b> is ready.</p>
        <p>
          <a href="${url}"
             style="display:inline-block;padding:10px 16px;background:#2563eb;color:#fff;text-decoration:none;border-radius:6px;">
            Pay Now
          </a>
        </p>
        ${
          amountCents
            ? `<p>Amount: <b>$${(Number(amountCents) / 100).toFixed(2)}</b></p>`
            : ""
        }
        <p>If the button doesn’t work, copy and paste this URL:</p>
        <p style="word-break:break-all"><a href="${url}">${url}</a></p>
        <p style="margin-top:20px;color:#555;font-size:14px;">
          Need help? Email <a href="mailto:${REPLY_TO.email}">${REPLY_TO.email}</a>.
        </p>
      </div>
    `;

    await sendTransactionalEmail({
      to: recipientEmail,
      fromName: "Flex Facility Billing",
      subject: `Payment link – ${planName}`,
      text:
        `Hi${safeName},\n\n` +
        `Please complete your payment for "${planName}" using this secure link:\n${url}\n\n` +
        `Thank you,\nFlex Facility`,
      html,
    });

    return res.json({ ok: true, url });
  } catch (e) {
    const msg = e.response?.data ? JSON.stringify(e.response.data) : e.message || String(e);
    console.error("payment-link/email error:", msg);
    res.status(500).json({ ok: false, error: msg });
  }
});

// Mount Express
exports.api = functions.https.onRequest(app);

