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

const MAIL_FROM = { email: "no-reply@archengineeringservices.com", name: "Flex Facility" };
const REPLY_TO = { email: "admin@archengineeringservices.com", name: "Flex Facility Support" };
const COMMON_HEADERS = {
  "List-Unsubscribe":
    "<mailto:admin@archengineeringservices.com>, <https://archengineeringservices.com/unsubscribe>",
  "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
};
const COMMON_TRACKING = { clickTracking: { enable: false }, openTracking: { enable: false } };


const LOGO_URL = "https://firebasestorage.googleapis.com/v0/b/flex-facility-app-b55aa.appspot.com/o/logo.png?alt=media&token=e0a6f925-77c0-4d85-88f4-fb9b640e913c";


const BRAND_COLORS = {
  primary: "#1C2D5E",
  blue: "#2563eb",
  green: "#16a34a",
  red: "#dc2626",
  lightBg: "#f5f7fb",
  cardBg: "#ffffff",
};

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

/* ========= Email HTML builders ========= */

/** Booking / reschedule / cancel HTML */
function buildBookingEmailHtml({
  heading,
  statusColor,
  slotDate,
  slotTime,
  trainer,
  introText,
  extraNote,
}) {
  const dateLine = slotDate || "";
  const timeLine = slotTime || "";
  const trainerName = trainer || "your trainer";

  return `
  <div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">
      <tr>
        <td style="padding:24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">
            <tr>
              <td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">
                <img src="${LOGO_URL}" alt="Flex Facility" width="120" style="display:block;margin-bottom:16px;" />
                <div style="display:flex;align-items:center;gap:8px;font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">
                  <span style="display:inline-block;width:12px;height:12px;border-radius:999px;background:${statusColor};"></span>
                  <span>${heading}</span>
                </div>
                <p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">
                  ${introText}
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding:16px 24px 8px 24px;">
                <p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">
                  Session details
                </p>
                <table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">
                  <tr>
                    <td style="padding:4px 0;width:90px;color:#6b7280;">Date</td>
                    <td style="padding:4px 0;">${dateLine}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:90px;color:#6b7280;">Time</td>
                    <td style="padding:4px 0;">${timeLine}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:90px;color:#6b7280;">Trainer</td>
                    <td style="padding:4px 0;">${trainerName}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:90px;color:#6b7280;">Location</td>
                    <td style="padding:4px 0;">Flex Facility</td>
                  </tr>
                </table>
              </td>
            </tr>

            <tr>
              <td style="padding:8px 24px 16px 24px;">
                <p style="margin:8px 0 0 0;font-size:13px;color:#4b5563;line-height:1.6;">
                  ${extraNote ||
                    "Need to make a change? You can manage your session directly from the Flex Facility app."}
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding:16px 24px 20px 24px;border-top:1px solid #e5e7eb;">
                <p style="margin:0;font-size:12px;color:#9ca3af;">
                  Thank you for training with Flex Facility.
                </p>
              </td>
            </tr>
          </table>

          <p style="margin-top:16px;font-size:11px;color:#9ca3af;text-align:center;">
            © ${new Date().getFullYear()} Flex Facility • All rights reserved
          </p>
        </td>
      </tr>
    </table>
  </div>
  `;
}

/** Payment success HTML */
function buildPaymentSuccessHtml({ firstName, lastName, planName, amount, referenceId }) {
  const name = `${firstName || ""} ${lastName || ""}`.trim() || "";
  const greeting = name ? `Hi ${name},` : "Hi,";

  return `
  <div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">
      <tr>
        <td style="padding:24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">
            <tr>
              <td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">
                <img src="${LOGO_URL}" alt="Flex Facility" width="120" style="display:block;margin-bottom:16px;" />
                <div style="display:flex;align-items:center;gap:8px;font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">
                  <span style="display:inline-block;width:12px;height:12px;border-radius:999px;background:${BRAND_COLORS.green};"></span>
                  <span>Your payment was successful</span>
                </div>
                <p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">
                  ${greeting}<br/>
                  Thank you for your payment. Your plan is now active.
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding:16px 24px 8px 24px;">
                <p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">
                  Order summary
                </p>
                <table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">
                  <tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Plan</td>
                    <td style="padding:4px 0;">${planName}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Total charged</td>
                    <td style="padding:4px 0;font-weight:600;">$${amount}</td>
                  </tr>
                  ${
                    referenceId
                      ? `<tr>
                          <td style="padding:4px 0;width:120px;color:#6b7280;">Reference</td>
                          <td style="padding:4px 0;">${referenceId}</td>
                        </tr>`
                      : ""
                  }
                </table>
              </td>
            </tr>

            <tr>
              <td style="padding:8px 24px 16px 24px;">
                <p style="margin:8px 0 0 0;font-size:13px;color:#4b5563;line-height:1.6;">
                  You can view and manage your sessions any time from the Flex Facility app.
                </p>
              </td>
            </tr>

            <tr>
              <td style="padding:16px 24px 20px 24px;border-top:1px solid #e5e7eb;">
                <p style="margin:0;font-size:12px;color:#9ca3af;">
                  Need help? Reply to this email or contact <a href="mailto:${REPLY_TO.email}" style="color:${BRAND_COLORS.primary};text-decoration:none;">${REPLY_TO.email}</a>.
                </p>
              </td>
            </tr>
          </table>

          <p style="margin-top:16px;font-size:11px;color:#9ca3af;text-align:center;">
            © ${new Date().getFullYear()} Flex Facility • All rights reserved
          </p>
        </td>
      </tr>
    </table>
  </div>
  `;
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
    const snap = await db
      .collection("users")
      .where("email", "==", buyer.email)
      .limit(1)
      .get();
    if (!snap.empty) userId = snap.docs[0].id;
  }
  if (!userId) {
    console.warn("⚠️ No userId found for purchase, skipping client_purchases / subscription write");
    return;
  }

  const planId = buyer.planId || null;
  const totalSessions = Number(buyer.sessions || 0);
  const priceDollars =
    buyer.price != null ? Number(buyer.price) : Number(amountCents || 0) / 100;

  const clientName = ((buyer.firstName || "") + " " + (buyer.lastName || "")).trim();

  // 🔎 Decide if this is the PDF workouts subscription plan
  const isPdfSubscription =
    buyer.planId === "pdf_subscription_monthly" ||
    buyer.planName === "PDF Workouts Monthly Subscription" ||
    planName === "PDF Workouts Monthly Subscription" ||
    buyer.isPdf === true ||
    buyer.type === "pdf";

  const nowTs = admin.firestore.FieldValue.serverTimestamp();

  // ✅ 1) Normal plans → write to client_purchases (for Active Plans dashboard)
  if (!isPdfSubscription) {
    const purchaseRef = db.collection("client_purchases").doc();

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
  } else {
    console.log("📘 PDF subscription purchase detected – skipping client_purchases for user:", userId);
  }

  // ✅ 2) PDF subscription → create entries used only by PDF workouts page
  if (isPdfSubscription) {
    try {
      console.log("📘 Creating/Updating PDF subscription for user:", userId);

      // 30 days from now
      const nowDate = new Date();
      const endDate = new Date(nowDate.getTime() + 30 * 24 * 60 * 60 * 1000);

      const nowTsServer = admin.firestore.FieldValue.serverTimestamp();
      const startTs = admin.firestore.Timestamp.fromDate(nowDate);
      const endTs = admin.firestore.Timestamp.fromDate(endDate);

      const userName = clientName;
      const userEmail = buyer.email || "";

      // client_subscriptions (read by PDFWorkoutsTab)
      const subRef = db.collection("client_subscriptions").doc();
      await subRef.set({
        userId,
        userName,
        userEmail,
        planName:
          buyer.planName ||
          planName ||
          "PDF Workouts Monthly Subscription",
        price: priceDollars,
        purchaseDate: startTs,
        startDate: startTs,
        endDate: endTs,
        isActive: true,
        status: "active",
        paymentMethod: "square",
        paymentStatus: (payment && payment.status) || "COMPLETED",
        timezone: "server",
        createdAt: nowTsServer,
        type: "pdf",
        isPdf: true,
      });

      // mirror to pdf_subscribers (for admin listing)
      await db.collection("pdf_subscribers").doc(subRef.id).set({
        userId,
        userName,
        userEmail,
        startDate: startTs,
        endDate: endTs,
        isActive: true,
        status: "active",
        createdAt: nowTsServer,
      });

      console.log("✅ PDF subscription created for user:", userId);
    } catch (err) {
      console.error("❌ Error creating PDF subscription:", err.message || err);
    }
  }
}


/* =========================
   EMAIL TRIGGERS
========================= */

/**
 * Booking created (new session)
 */
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
    const trainerEmail = data.trainer_email || data.trainerEmail || null;

    const plainText =
      `Hi,\n\nYour session is confirmed.\n\n` +
      `Date: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\n` +
      `Please arrive 5 minutes early.\n\n— Flex Facility Team`;

    const html = buildBookingEmailHtml({
      heading: "Your session has been scheduled",
      statusColor: BRAND_COLORS.blue,
      slotDate,
      slotTime,
      trainer,
      introText:
        "Your training session has been scheduled. Below are the details so you can add it to your calendar.",
      extraNote: "Please arrive 5 minutes early and bring a water bottle and towel.",
    });

    // Send to clients
    await Promise.all(
      bookedEmails.map((email) =>
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `Your session has been scheduled – ${trainer}`,
          text: plainText,
          html,
        }).catch((err) => console.error(`Error sending booking (onCreate) to ${email}:`, err))
      )
    );

    // Optional trainer notification
    if (trainerEmail) {
      const trainerText =
        `Hi ${trainer},\n\nA new session has been booked.\n\n` +
        `Date: ${slotDate}\nTime: ${slotTime}\nClient(s): ${bookedEmails.join(", ")}\n\n` +
        `— Flex Facility`;
      const trainerHtml = buildBookingEmailHtml({
        heading: "New session booked",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText: "A new client session has been booked in your schedule.",
        extraNote: `Client emails: ${bookedEmails.join(", ")}`,
      });

      await sendTransactionalEmail({
        to: trainerEmail,
        fromName: "Flex Facility Bookings",
        subject: `New session booked – ${slotDate} ${slotTime}`,
        text: trainerText,
        html: trainerHtml,
      }).catch((err) => console.error(`Error sending trainer booking email to ${trainerEmail}:`, err));
    }
  });

/**
 * Booking updated (newly booked, cancelled, or rescheduled)
 */
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
    const trainerEmail = after.trainer_email || before.trainer_email || after.trainerEmail || before.trainerEmail || null;

    const tasks = [];

    const isReschedule = before.is_reschedule === true || after.is_reschedule === true;
    if (isReschedule && newlyBooked.length === 1 && cancelled.length === 1) {
      const email = newlyBooked[0];

      const text =
        `Hi,\n\nYour session has been rescheduled.\n\n` +
        `New Date: ${slotDate}\nNew Time: ${slotTime}\nTrainer: ${trainer}\n\n` +
        `Please arrive 5 minutes early.\n\n— Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been rescheduled",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText:
          "Your session has been successfully rescheduled. Here are your updated session details.",
        extraNote: "If this time no longer works, you can reschedule again from the Flex Facility app.",
      });

      await sendTransactionalEmail({
        to: email,
        fromName: "Flex Facility Bookings",
        subject: `Your session has been rescheduled – ${trainer}`,
        text,
        html,
      });

      if (trainerEmail) {
        const trainerText =
          `Hi ${trainer},\n\nA client session has been rescheduled.\n\n` +
          `New Date: ${slotDate}\nNew Time: ${slotTime}\nClient: ${email}\n\n` +
          `— Flex Facility`;
        const trainerHtml = buildBookingEmailHtml({
          heading: "Session rescheduled",
          statusColor: BRAND_COLORS.blue,
          slotDate,
          slotTime,
          trainer,
          introText: "One of your sessions has been rescheduled.",
          extraNote: `Client email: ${email}`,
        });

        await sendTransactionalEmail({
          to: trainerEmail,
          fromName: "Flex Facility Bookings",
          subject: `Session rescheduled – ${slotDate} ${slotTime}`,
          text: trainerText,
          html: trainerHtml,
        }).catch((err) =>
          console.error(`Error sending trainer reschedule email to ${trainerEmail}:`, err)
        );
      }

      if (after.is_reschedule) {
        await change.after.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });
      }
      return;
    }

    // Newly booked
    for (const email of newlyBooked) {
      const text =
        `Hi,\n\nYour session is confirmed.\n\n` +
        `Date: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\n` +
        `Please arrive 5 minutes early.\n\n— Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been scheduled",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText:
          "Your training session has been scheduled. Below are the details so you can add it to your calendar.",
        extraNote: "Please arrive 5 minutes early and bring a water bottle and towel.",
      });

      tasks.push(
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `Your session has been scheduled – ${trainer}`,
          text,
          html,
        })
      );
    }

    // Cancelled
    for (const email of cancelled) {
      const text =
        `Hi,\n\nYour session has been cancelled.\n\n` +
        `Date: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\n` +
        `If this was a mistake, you can rebook in the app.\n\n— Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been cancelled",
        statusColor: BRAND_COLORS.red,
        slotDate,
        slotTime,
        trainer,
        introText:
          "Your upcoming session has been cancelled. If this was a mistake, you can rebook a new time from the Flex Facility app.",
        extraNote: "You will not be charged for this cancelled session.",
      });

      tasks.push(
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `Your session has been cancelled – ${trainer}`,
          text,
          html,
        })
      );
    }

    // Trainer notifications for cancellations / new bookings
    if (trainerEmail && (newlyBooked.length || cancelled.length)) {
      const bookedList = newlyBooked.length ? `Booked: ${newlyBooked.join(", ")}\n` : "";
      const cancelledList = cancelled.length ? `Cancelled: ${cancelled.join(", ")}\n` : "";

      const trainerText =
        `Hi ${trainer},\n\nChanges have been made to your schedule.\n\n` +
        `Date: ${slotDate}\nTime: ${slotTime}\n\n` +
        bookedList +
        cancelledList +
        `\n— Flex Facility`;

      const trainerHtml = buildBookingEmailHtml({
        heading: "Schedule updated",
        statusColor: newlyBooked.length ? BRAND_COLORS.blue : BRAND_COLORS.red,
        slotDate,
        slotTime,
        trainer,
        introText: "There have been changes to your client bookings for this time slot.",
        extraNote: `${bookedList.replace(/\n/g, " ")} ${cancelledList.replace(/\n/g, " ")}`.trim() ||
          "You can view your full schedule in the Flex Facility dashboard.",
      });

      tasks.push(
        sendTransactionalEmail({
          to: trainerEmail,
          fromName: "Flex Facility Bookings",
          subject: `Schedule updated – ${slotDate} ${slotTime}`,
          text: trainerText,
          html: trainerHtml,
        }).catch((err) =>
          console.error(`Error sending trainer schedule update email to ${trainerEmail}:`, err)
        )
      );
    }

    if (tasks.length) await Promise.all(tasks);
  });

/* =========================
   EXPRESS APP
========================= */
const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

/* =========================
   AUTH EMAILS: verify + reset
========================= */

const AUTH_CONTINUE_URL = "https://flexfacility.app";

// Send email verification link
app.post("/auth/send-verification-email", async (req, res) => {
  try {
    const { email, displayName } = req.body || {};
    if (!email) {
      return res.status(400).json({ ok: false, error: "Missing email" });
    }

    const actionCodeSettings = {
      url: AUTH_CONTINUE_URL,
      handleCodeInApp: false,
    };

    const link = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);

    const safeName = displayName ? ` ${displayName}` : "";

    const html = `
      <div style="font-family:Arial,Helvetica,sans-serif;color:#222;line-height:1.6">
        <h2 style="color:#1C2D5E;">Verify your email</h2>
        <p>Hi${safeName},</p>
        <p>Thanks for creating your Flex Facility account. Please confirm your email by clicking the button below:</p>
        <p>
          <a href="${link}"
             style="display:inline-block;padding:10px 16px;background:#1C2D5E;color:#fff;text-decoration:none;border-radius:6px;">
            Verify Email
          </a>
        </p>
        <p>If the button doesn’t work, copy and paste this link into your browser:</p>
        <p style="word-break:break-all"><a href="${link}">${link}</a></p>
        <p style="margin-top:20px;color:#555;font-size:14px;">
          If you didn’t create this account, you can ignore this email.
        </p>
      </div>
    `;

    await sendTransactionalEmail({
      to: email,
      fromName: "Flex Facility",
      subject: "Verify your email address",
      text:
        `Hi${safeName},\n\n` +
        `Please verify your email address by opening this link:\n${link}\n\n` +
        `If you didn't create this account, you can ignore this email.\n\n` +
        `– Flex Facility`,
      html,
    });

    return res.json({ ok: true });
  } catch (e) {
    console.error("send-verification-email error:", e.message || e);
    return res
      .status(500)
      .json({ ok: false, error: "Failed to send verification email" });
  }
});

// Send password reset link
app.post("/auth/send-password-reset", async (req, res) => {
  try {
    const { email } = req.body || {};
    if (!email) {
      return res.status(400).json({ ok: false, error: "Missing email" });
    }

    const actionCodeSettings = {
      url: AUTH_CONTINUE_URL,
      handleCodeInApp: false,
    };

    const link = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);

    const html = `
      <div style="font-family:Arial,Helvetica,sans-serif;color:#222;line-height:1.6">
        <h2 style="color:#1C2D5E;">Reset your password</h2>
        <p>We received a request to reset your Flex Facility password.</p>
        <p>
          <a href="${link}"
             style="display:inline-block;padding:10px 16px;background:#1C2D5E;color:#fff;text-decoration:none;border-radius:6px;">
            Reset Password
          </a>
        </p>
        <p>If you didn’t request this, you can safely ignore this email.</p>
        <p style="margin-top:20px;color:#555;font-size:14px;">
          Thank you,<br/>Flex Facility
        </p>
      </div>
    `;

    await sendTransactionalEmail({
      to: email,
      fromName: "Flex Facility",
      subject: "Reset your Flex Facility password",
      text:
        `We received a request to reset your Flex Facility password.\n\n` +
        `You can reset it using this link:\n${link}\n\n` +
        `If you didn't request this, you can ignore this email.\n\n` +
        `– Flex Facility`,
      html,
    });

    return res.json({ ok: true });
  } catch (e) {
    console.error("send-password-reset error:", e.message || e);
    return res
      .status(500)
      .json({ ok: false, error: "Failed to send reset email" });
  }
});

/* =========================
   Existing API routes
========================= */

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

/* =========================
   Card /process-payment (plan active immediately)
========================= */
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

    const sandboxLocationId =
      (functions.config()?.square?.sandbox_location_id || functions.config()?.square?.location_id || "").trim();
    const prodLocationId =
      (functions.config()?.square?.prod_location_id || functions.config()?.square?.location_id || "").trim();

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

        const plainText =
          `Hi ${(buyer.firstName || "")} ${(buyer.lastName || "")},\n\n` +
          `Your payment for "${planName}" was successful.\n` +
          `Amount: $${dollars}\n` +
          `${refId ? `Reference: ${refId}\n` : ""}\n` +
          `Thank you,\nFlex Facility`;

        const html = buildPaymentSuccessHtml({
          firstName: buyer.firstName,
          lastName: buyer.lastName,
          planName,
          amount: dollars,
          referenceId: refId,
        });

        await sendTransactionalEmail({
          to: buyer.email,
          fromName: "Flex Facility Billing",
          subject: `Payment Successful – ${planName}`,
          text: plainText,
          html,
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
   Invoices (plan active on webhook)
========================= */

// Create & publish invoice, save metadata; DO NOT activate plan yet
app.post("/create-invoice", async (req, res) => {
  try {
    const cfg = getSquareConfig(req);
    const db = admin.firestore();

    const { plan = {}, customer = {}, userId } = req.body || {};

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

    // 4) Save metadata for webhook
    const metaRef = db.collection("invoice_metadata").doc(published.id);
    const metaData = {
      invoiceId: published.id,
      userId: userId || plan.userId || null,
      planId: plan.docId || plan.id || null,
      planName: plan.name || name,
      planCategory: plan.category || "",
      sessions: plan.sessions || 0,
      price: price, // dollars
      description,
      email,
      firstName: given_name,
      lastName: family_name,
      referenceId: safeRefId(plan.referenceId || req.body.referenceId) || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      processed: false,
    };

    await metaRef.set(metaData);

    // Return invoice to client (includes public_url)
    return res.json({ ok: true, invoice: published });
  } catch (e) {
    const msg = e.response?.data ? JSON.stringify(e.response.data) : e.message || String(e);
    console.error("create-invoice error:", msg);
    res.status(500).json({ ok: false, error: msg });
  }
});

// Webhook: called by Square when invoice is paid -> activate plan
// Webhook: called by Square when invoice is paid -> activate plan
app.post("/square-webhook", async (req, res) => {
  try {
    const eventType = req.body.type || req.body.event_type;
    const dataObject = req.body.data && req.body.data.object;
    const invoice = dataObject && dataObject.invoice;

    if (!eventType || !invoice) {
      console.warn("square-webhook: missing eventType or invoice in payload");
      return res.status(200).send("ignored");
    }

    console.log("square-webhook event:", eventType, "invoiceId:", invoice.id);

    if (eventType !== "invoice.payment_made" && eventType !== "invoice.paid") {
      return res.status(200).send("ignored event type");
    }

    const invoiceId = invoice.id;
    const db = admin.firestore();
    const metaRef = db.collection("invoice_metadata").doc(invoiceId);
    const metaSnap = await metaRef.get();  // ✅ fixed line

    if (!metaSnap.exists) {
      console.warn("square-webhook: no invoice_metadata for", invoiceId);
      return res.status(200).send("no metadata");
    }

    const meta = metaSnap.data() || {};

    if (meta.processed) {
      console.log("square-webhook: invoice already processed", invoiceId);
      return res.status(200).send("already processed");
    }

    // Build buyer object
    const buyer = {
      userId: meta.userId || null,
      planId: meta.planId || null,
      planName: meta.planName || "Training Plan",
      planCategory: meta.planCategory || "",
      sessions: meta.sessions || 0,
      price: meta.price || 0,
      description: meta.description || "",
      firstName: meta.firstName || "",
      lastName: meta.lastName || "",
      email: meta.email || "",
    };

    const amountCents = Math.round(Number(meta.price || 0) * 100);

    // Create client_purchases entry so plan is ACTIVE in app
    await createClientPurchaseFromPayment({
      buyer,
      planName: meta.planName,
      amountCents,
      refId: meta.referenceId || invoiceId,
      payment: null,
    });

    await metaRef.update({
      processed: true,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log("square-webhook: plan activated for invoice", invoiceId);
    return res.status(200).send("ok");
  } catch (e) {
    console.error("square-webhook error:", e.response?.data || e);
    return res.status(500).send("error");
  }
});


/* =========================
   Create/Send Pay Link
========================= */

app.post("/payment-link/email", async (req, res) => {
  try {
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
