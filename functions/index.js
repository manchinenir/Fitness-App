/* =========================
 * functions/index.js
 * =======================*/

/* ----- imports ----- */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const { Resend } = require("resend");
const express = require("express");
const cors = require("cors");
const rateLimit = require("express-rate-limit");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const axios = require("axios");

/* ----- init ----- */
admin.initializeApp();

/* =========================
   Resend (lazy init)
========================= */
let _resend = null;
function getResend() {
  if (!_resend) {
    const key = functions.config()?.resend?.key;
    if (!key || typeof key !== "string" || !key.startsWith("re_")) {
      throw new Error(
        'Resend API key missing/invalid. Set:\n' +
          '  firebase functions:config:set resend.key="re_xxxxxx"'
      );
    }
    _resend = new Resend(key);
  }
  return _resend;
}

const MAIL_FROM = { email: "no-reply@archengineeringservices.com", name: "Flex Facility" };
const REPLY_TO = { email: "admin@archengineeringservices.com", name: "Flex Facility Support" };
const COMMON_HEADERS = {
  "List-Unsubscribe":
    "<mailto:admin@archengineeringservices.com>, <https://archengineeringservices.com/unsubscribe>",
  "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
};

const LOGO_URL = "https://firebasestorage.googleapis.com/v0/b/flex-facility-app-b55aa.firebasestorage.app/o/logo.png?alt=media&token=e0a6f925-77c0-4d85-88f4-f89b640e913c";


function getLogoImgSrc() {
  return LOGO_URL;
}


const BRAND_COLORS = {
  primary: "#1C2D5E",
  blue: "#2563eb",
  green: "#16a34a",
  red: "#dc2626",
  lightBg: "#f5f7fb",
  cardBg: "#ffffff",
};

function sendTransactionalEmail({ to, subject, text, html, fromName }) {
  const resend = getResend();
  const fromStr = `${fromName || MAIL_FROM.name} <${MAIL_FROM.email}>`;

  return resend.emails.send({
    from: fromStr,
    to: Array.isArray(to) ? to : [to],
    reply_to: REPLY_TO.email,
    subject,
    ...(text ? { text } : {}),
    ...(html ? { html } : {}),
    headers: COMMON_HEADERS,
  });
}

// For verification & password reset — no List-Unsubscribe so iCloud/Yahoo don't drop it
function sendCriticalEmail({ to, subject, text, html, fromName }) {
  const resend = getResend();
  const fromStr = `${fromName || MAIL_FROM.name} <${MAIL_FROM.email}>`;

  return resend.emails.send({
    from: fromStr,
    to: Array.isArray(to) ? to : [to],
    reply_to: REPLY_TO.email,
    subject,
    ...(text ? { text } : {}),
    ...(html ? { html } : {}),
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
  const logoImgSrc = getLogoImgSrc();

  return `
  <div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">
      <tr>
        <td style="padding:24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">
            <tr>
              <td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">
                <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />
                <div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">
                  ${heading}
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
            (c) ${new Date().getFullYear()} Flex Facility  All rights reserved
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
  const logoImgSrc = getLogoImgSrc();

  return `
  <div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">
      <tr>
        <td style="padding:24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">
            <tr>
              <td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">
                <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />
                <div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">
                  Your payment was successful
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
            (c) ${new Date().getFullYear()} Flex Facility  All rights reserved
          </p>
        </td>
      </tr>
    </table>
  </div>
  `;
}

/** Trainer payment notification HTML */
function buildTrainerPaymentHtml({ clientName, clientEmail, planName, amount, referenceId }) {
  const logoImgSrc = getLogoImgSrc();
  return `
  <div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">
    <table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">
      <tr>
        <td style="padding:24px;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">
            <tr>
              <td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">
                <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />
                <div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.green};">
                  New Payment Received
                </div>
                <p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">
                  Hi Kenny,<br/>A client has just completed a payment on Flex Facility.
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:16px 24px 8px 24px;">
                <p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">
                  Client details
                </p>
                <table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">
                  <tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Name</td>
                    <td style="padding:4px 0;font-weight:600;">${clientName}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Email</td>
                    <td style="padding:4px 0;">${clientEmail}</td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:8px 24px 8px 24px;border-top:1px solid #f3f4f6;">
                <p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">
                  Payment details
                </p>
                <table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">
                  <tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Plan</td>
                    <td style="padding:4px 0;">${planName}</td>
                  </tr>
                  <tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Amount paid</td>
                    <td style="padding:4px 0;font-weight:600;color:${BRAND_COLORS.green};">$${amount}</td>
                  </tr>
                  ${referenceId ? `<tr>
                    <td style="padding:4px 0;width:120px;color:#6b7280;">Reference</td>
                    <td style="padding:4px 0;">${referenceId}</td>
                  </tr>` : ""}
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:16px 24px 20px 24px;border-top:1px solid #e5e7eb;">
                <p style="margin:0;font-size:12px;color:#9ca3af;">
                  You can view this client in the Flex Facility admin dashboard.
                </p>
              </td>
            </tr>
          </table>
          <p style="margin-top:16px;font-size:11px;color:#9ca3af;text-align:center;">
            (c) ${new Date().getFullYear()} Flex Facility  All rights reserved
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
    console.warn("  No userId found for purchase, skipping client_purchases / subscription write");
    return;
  }

  const planId = buyer.planId || null;
  const totalSessions = Number(buyer.sessions || 0);
  const priceDollars =
    buyer.price != null ? Number(buyer.price) : Number(amountCents || 0) / 100;

  const clientName = ((buyer.firstName || "") + " " + (buyer.lastName || "")).trim();

  //   Decide if this is the PDF workouts subscription plan
  const isPdfSubscription =
    buyer.planId === "pdf_subscription_monthly" ||
    buyer.planName === "PDF Workouts Monthly Subscription" ||
    planName === "PDF Workouts Monthly Subscription" ||
    buyer.isPdf === true ||
    buyer.type === "pdf";

  const nowTs = admin.firestore.FieldValue.serverTimestamp();

  //  1) Normal plans   write to client_purchases (for Active Plans dashboard)
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
    console.log(" client_purchases created:", purchaseRef.id);
  } else {
    console.log("PDF subscription purchase detected - skipping client_purchases for user:", userId);
  }

  //  2) PDF subscription   create entries used only by PDF workouts page
  if (isPdfSubscription) {
    try {
      console.log("Creating/Updating PDF subscription for user:", userId);

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

      console.log(" PDF subscription created for user:", userId);
    } catch (err) {
      console.error("  Error creating PDF subscription:", err.message || err);
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
    const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
    const bookedNames = data.booked_names || [];
    const isReschedule = data.is_reschedule === true;

    // Clean up flag if present
    if (isReschedule) {
      await snap.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });
    }

    // Build "Name (email)" pairs for trainer-facing emails
    const clientList = bookedEmails.map((email, i) => {
      const name = bookedNames[i] || email;
      return `${name} (${email})`;
    });

    // Send to clients  personalized per client
    await Promise.all(
      bookedEmails.map((email, i) => {
        const clientName = bookedNames[i] || "there";
        const subject = isReschedule
          ? `[RESCHEDULED] ${slotDate} ${slotTime}`
          : `[BOOKING CONFIRMED] ${slotDate} ${slotTime}`;
        const heading = isReschedule ? "Your session has been rescheduled" : "Your session has been scheduled";
        const introText = isReschedule
          ? `Hi ${clientName},<br/>Your session has been successfully rescheduled. Here are your updated session details.`
          : `Hi ${clientName},<br/>Your training session has been scheduled. Below are the details so you can add it to your calendar.`;
        const extraNote = isReschedule
          ? "If this time no longer works, you can reschedule again from the Flex Facility app."
          : "Please arrive 5 minutes early and bring a water bottle and towel.";
        const plainText = isReschedule
          ? `Hi ${clientName},\n\nYour session has been rescheduled.\n\nNew Date: ${slotDate}\nNew Time: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n Flex Facility Team`
          : `Hi ${clientName},\n\nYour session is confirmed.\n\nDate: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n Flex Facility Team`;
        const html = buildBookingEmailHtml({
          heading,
          statusColor: BRAND_COLORS.blue,
          slotDate,
          slotTime,
          trainer,
          introText,
          extraNote,
        });
        return sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject,
          text: plainText,
          html,
        }).catch((err) => console.error(`Error sending booking (onCreate) to ${email}:`, err));
      })
    );



    // Trainer notification - always send to Kenny
    const trainerSubject = isReschedule
      ? `[TRAINER RESCHEDULED] ${slotDate} ${slotTime}`
      : `[TRAINER BOOKING] ${slotDate} ${slotTime}`;
    const trainerHeading = isReschedule ? "Session rescheduled" : "New session booked";
    const trainerIntro = isReschedule
      ? "One of your sessions has been rescheduled."
      : "A new client session has been booked in your schedule.";
    const trainerText = `Hi ${trainer},\n\n${isReschedule ? "A client session has been rescheduled." : "A new session has been booked."}\n\nDate: ${slotDate}\nTime: ${slotTime}\nClient(s):\n${clientList.map((c) => `   ${c}`).join("\n")}\n\n Flex Facility`;
    const trainerHtml = buildBookingEmailHtml({
      heading: trainerHeading,
      statusColor: BRAND_COLORS.blue,
      slotDate,
      slotTime,
      trainer,
      introText: trainerIntro,
      extraNote: `Client(s): ${clientList.join(", ")}`,
    });

    await sendTransactionalEmail({
      to: trainerEmail,
      fromName: "Flex Facility Bookings",
      subject: trainerSubject,
      text: trainerText,
      html: trainerHtml,
    }).catch((err) => console.error(`Error sending trainer booking email to ${trainerEmail}:`, err));


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
    const beforeNames = before.booked_names || [];
    const afterNames = after.booked_names || [];
    const newlyBooked = afterEmails.filter((e) => !beforeEmails.includes(e));
    const cancelled = beforeEmails.filter((e) => !afterEmails.includes(e));
    const beforeBy = before.booked_by || [];
    const afterBy  = after.booked_by  || [];
    const newlyBookedUids = afterBy.filter((uid) => !beforeBy.includes(uid));

    // Helper to build "Name (email)" string
    const clientLabel = (email, emailArr, nameArr) => {
      const idx = emailArr.indexOf(email);
      const name = idx >= 0 && nameArr[idx] ? nameArr[idx] : email;
      return `${name} (${email})`;
    };

    const slotTime = after.time || before.time;
    const slotDate = (after.date || before.date).toDate().toLocaleDateString();
    const trainer = after.trainer_name || before.trainer_name || "your trainer";
    const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();

    const tasks = [];

    // If the old slot was flagged as a reschedule cancel, skip all email sending for it
    if (after.is_reschedule_cancel === true) {
      await change.after.ref.update({ is_reschedule_cancel: admin.firestore.FieldValue.delete() });
      return;
    }

    const isReschedule = before.is_reschedule === true || after.is_reschedule === true;
    if (isReschedule && newlyBooked.length === 1 && cancelled.length === 1) {
      // Both added and removed on same doc (old path  keep existing logic)

      const email = newlyBooked[0];
      const rescheduleClientName = (() => { const idx = afterEmails.indexOf(email); return idx >= 0 && afterNames[idx] ? afterNames[idx] : "there"; })();

      const text = `Hi ${rescheduleClientName},\n\nYour session has been rescheduled.\n\nNew Date: ${slotDate}\nNew Time: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been rescheduled",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText: `Hi ${rescheduleClientName},<br/>Your session has been successfully rescheduled. Here are your updated session details.`,
        extraNote: "If this time no longer works, you can reschedule again from the Flex Facility app.",
      });

      await sendTransactionalEmail({
        to: email,
        fromName: "Flex Facility Bookings",
        subject: `[RESCHEDULED] ${slotDate} ${slotTime}`,
        text,
        html,
      });

      if (trainerEmail) {
        const clientInfo = clientLabel(email, afterEmails, afterNames);
        const trainerText = `Hi ${trainer},

A client session has been rescheduled.

New Date: ${slotDate}
New Time: ${slotTime}
Client: ${clientInfo}

 Flex Facility`;
        const trainerHtml = buildBookingEmailHtml({
          heading: "Session rescheduled",
          statusColor: BRAND_COLORS.blue,
          slotDate,
          slotTime,
          trainer,
          introText: "One of your sessions has been rescheduled.",
          extraNote: `Client: ${clientInfo}`,
        });

        await sendTransactionalEmail({
          to: trainerEmail,
          fromName: "Flex Facility Bookings",
          subject: `[TRAINER RESCHEDULED] ${slotDate} ${slotTime}`,
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

    // New path: is_reschedule flag on new slot (email only added here, cancel handled separately)
    if (after.is_reschedule === true && newlyBooked.length >= 1) {
      await change.after.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });

      for (const email of newlyBooked) {
        const clientName = (() => { const idx = afterEmails.indexOf(email); return idx >= 0 && afterNames[idx] ? afterNames[idx] : "there"; })();
        const text = `Hi ${clientName},\n\nYour session has been rescheduled.\n\nNew Date: ${slotDate}\nNew Time: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n Flex Facility Team`;
        const html = buildBookingEmailHtml({
          heading: "Your session has been rescheduled",
          statusColor: BRAND_COLORS.blue,
          slotDate,
          slotTime,
          trainer,
          introText: `Hi ${clientName},<br/>Your session has been successfully rescheduled. Here are your updated session details.`,
          extraNote: "If this time no longer works, you can reschedule again from the Flex Facility app.",
        });
        await sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `[RESCHEDULED] ${slotDate} ${slotTime}`,
          text,
          html,
        }).catch((err) => console.error(`Error sending rescheduled email to ${email}:`, err));
      }

      // Trainer notification
      const reschedLabels = newlyBooked.map((e) => clientLabel(e, afterEmails, afterNames));
      const trainerText = `Hi ${trainer},\n\nA client session has been rescheduled.\n\nNew Date: ${slotDate}\nNew Time: ${slotTime}\nClient: ${reschedLabels.join(", ")}\n\n Flex Facility`;
      const trainerHtml = buildBookingEmailHtml({
        heading: "Session rescheduled",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText: "One of your sessions has been rescheduled.",
        extraNote: `Client: ${reschedLabels.join(", ")}`,
      });
      await sendTransactionalEmail({
        to: trainerEmail,
        fromName: "Flex Facility Bookings",
        subject: `[TRAINER RESCHEDULED] ${slotDate} ${slotTime}`,
        text: trainerText,
        html: trainerHtml,
      }).catch((err) => console.error(`Error sending trainer reschedule email:`, err));

      return;
    }

    // Newly booked
    const slotTimestamp = (after.date || before.date).toDate();
    const minsUntilSession = Math.round((slotTimestamp.getTime() - Date.now()) / 60000);
    const isLastMinuteBooking = minsUntilSession >= 0 && minsUntilSession <= 90;

    for (const email of newlyBooked) {
      const bookedClientName = (() => { const idx = afterEmails.indexOf(email); return idx >= 0 && afterNames[idx] ? afterNames[idx] : "there"; })();
      const text = `Hi ${bookedClientName},\n\nYour session is confirmed.\n\nDate: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\nPlease arrive 5 minutes early.\n\n- Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been scheduled",
        statusColor: BRAND_COLORS.blue,
        slotDate,
        slotTime,
        trainer,
        introText: `Hi ${bookedClientName},<br/>Your training session has been scheduled. Below are the details so you can add it to your calendar.`,
        extraNote: "Please arrive 5 minutes early and bring a water bottle and towel.",
      });

      tasks.push(
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `[BOOKING CONFIRMED] ${slotDate} ${slotTime}`,
          text,
          html,
        })
      );


    }

    // Trainer notification for newly booked clients (non-reschedule)
    if (newlyBooked.length > 0) {
      const newLabels = newlyBooked.map((e) => clientLabel(e, afterEmails, afterNames));
      tasks.push(
        sendTransactionalEmail({
          to: trainerEmail,
          fromName: "Flex Facility Bookings",
          subject: `[TRAINER BOOKING] ${slotDate} ${slotTime}`,
          text: `Hi ${trainer},\n\nA new session has been booked.\n\nDate: ${slotDate}\nTime: ${slotTime}\nClient(s): ${newLabels.join(", ")}\n\n- Flex Facility`,
          html: buildBookingEmailHtml({
            heading: "New session booked",
            statusColor: BRAND_COLORS.blue,
            slotDate,
            slotTime,
            trainer,
            introText: "A client has just booked a session.",
            extraNote: `Client(s): ${newLabels.join(", ")}`,
          }),
        }).catch((err) => console.error(`Error sending trainer new booking email:`, err))
      );
    }

    // Cancelled
    for (const email of cancelled) {
      const cancelledClientName = (() => { const idx = beforeEmails.indexOf(email); return idx >= 0 && beforeNames[idx] ? beforeNames[idx] : "there"; })();
      const text = `Hi ${cancelledClientName},\n\nYour session has been cancelled.\n\nDate: ${slotDate}\nTime: ${slotTime}\nTrainer: ${trainer}\n\nIf this was a mistake, you can rebook in the app.\n\n Flex Facility Team`;

      const html = buildBookingEmailHtml({
        heading: "Your session has been cancelled",
        statusColor: BRAND_COLORS.red,
        slotDate,
        slotTime,
        trainer,
        introText: `Hi ${cancelledClientName},<br/>Your upcoming session has been cancelled. If this was a mistake, you can rebook a new time from the Flex Facility app.`,
        extraNote: "You will not be charged for this cancelled session.",
      });

      tasks.push(
        sendTransactionalEmail({
          to: email,
          fromName: "Flex Facility Bookings",
          subject: `[CANCELLED] ${cancelledClientName} - ${slotDate} ${slotTime}`,
          text,
          html,
        })
      );

      // Notify Kenny about the cancellation
      const clientInfo = clientLabel(email, beforeEmails, beforeNames);
      const trainerCancelText = `Hi ${trainer},\n\nA client has cancelled their session.\n\nDate: ${slotDate}\nTime: ${slotTime}\nClient: ${clientInfo}\n\n Flex Facility`;
      const trainerCancelHtml = buildBookingEmailHtml({
        heading: "Session cancelled by client",
        statusColor: BRAND_COLORS.red,
        slotDate,
        slotTime,
        trainer,
        introText: "A client has cancelled their upcoming session.",
        extraNote: `Client: ${clientInfo}`,
      });
      tasks.push(
        sendTransactionalEmail({
          to: trainerEmail,
          fromName: "Flex Facility Bookings",
          subject: `[TRAINER CANCELLED] ${slotDate} ${slotTime}`,
          text: trainerCancelText,
          html: trainerCancelHtml,
        }).catch((err) => console.error(`Error sending trainer cancel email:`, err))
      );
    }



    if (tasks.length) await Promise.all(tasks);
  });

/* =========================
   EXPRESS APP
========================= */
const ALLOWED_ORIGINS = [
  "https://flex-facility-app-b55aa.web.app",
  "https://flex-facility-app-b55aa.firebaseapp.com",
  "https://us-central1-flex-facility-app-b55aa.cloudfunctions.net",
];

const app = express();
app.use(cors({
  origin: (origin, callback) => {
    // Allow non-browser clients (Flutter mobile app) and whitelisted web origins
    if (!origin || ALLOWED_ORIGINS.includes(origin)) return callback(null, true);
    callback(new Error("Not allowed by CORS"));
  },
  credentials: true,
}));
app.use(express.json());

const authLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: "Too many requests. Please wait a minute and try again." },
});

const paymentLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: false, error: "Too many requests. Please wait a minute and try again." },
});

/* =========================
   AUTH EMAILS: verify + reset
========================= */

const AUTH_CONTINUE_URL = "https://flex-facility-app-b55aa.web.app/email-verified.html";
const AUTH_RESET_CONTINUE_URL = "https://flex-facility-app-b55aa.web.app/password-reset-complete.html";

// Send email verification link
/* =========================
   AUTH EMAILS: verify + reset
========================= */

// Send email verification link
app.post("/auth/send-verification-email", authLimiter, async (req, res) => {
    try {
        const { email, displayName } = req.body || {};
        if (!email) {
            return res.status(400).json({ ok: false, error: "Missing email" });
        }

        const actionCodeSettings = {
      url: AUTH_CONTINUE_URL,
      handleCodeInApp: false,
        };

    // Generate Firebase action link and convert it to our hosted verification page URL.
        const link = await admin.auth().generateEmailVerificationLink(email, actionCodeSettings);
    let verifyUrl = link;
    try {
      const parsed = new URL(link);
      const mode = parsed.searchParams.get("mode") || "verifyEmail";
      const oobCode = parsed.searchParams.get("oobCode") || "";
      const apiKey = parsed.searchParams.get("apiKey") || "";

      if (oobCode && apiKey) {
      verifyUrl = `${AUTH_CONTINUE_URL}?mode=${encodeURIComponent(mode)}&oobCode=${encodeURIComponent(oobCode)}&apiKey=${encodeURIComponent(apiKey)}`;
      }
    } catch (parseErr) {
      console.warn("Unable to map Firebase verify link to custom page:", parseErr.message || parseErr);
    }
       
        const safeName = displayName ? ` ${displayName}` : "";
    const logoImgSrc = getLogoImgSrc();
       
        const emailHtml = `
            <div style="font-family:Arial,Helvetica,sans-serif;background:#f5f7fb;padding:20px;">
                <div style="max-width:600px;margin:auto;background:#ffffff;padding:20px;border-radius:10px;">
          <div style="text-align:center;margin-bottom:12px;">
            <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:inline-block;border-radius:50%;object-fit:cover;" />
          </div>
                    <h2 style="color:#1C2D5E;">Welcome to Flex Facility</h2>
                    <p>Hi${safeName},</p>
                    <p>Please verify your email address by clicking the button below:</p>
                    <div style="text-align:center;margin:25px 0;">
            <a href="${verifyUrl}"
                           style="background:#2563eb;color:#ffffff;padding:12px 20px;
                           text-decoration:none;border-radius:6px;font-weight:bold;">
                           Verify Email Address
                        </a>
                    </div>
                </div>
            </div>
        `;

    await sendCriticalEmail({
            to: email,
            fromName: "Flex Facility",
            subject: "Verify your Flex Facility email address",
      text: `Hi${safeName},\n\nPlease tap the Verify Email Address button in this email to verify your account.\n\n`,
            html: emailHtml,
    });

        return res.json({ ok: true });
    } catch (e) {
        console.error("send-verification-email error:", e.message || e);
        return res.status(500).json({ ok: false, error: e.message });
    }
});

app.post("/auth/send-password-reset-email", authLimiter, async (req, res) => {
  try {
    const { email, displayName } = req.body || {};
    if (!email) {
      return res.status(400).json({ ok: false, error: "Missing email" });
    }

    const actionCodeSettings = {
      url: AUTH_RESET_CONTINUE_URL,
      handleCodeInApp: false,
    };

    const resetLink = await admin.auth().generatePasswordResetLink(email, actionCodeSettings);
    const safeName = displayName ? ` ${displayName}` : "";
    const logoImgSrc = getLogoImgSrc();

    const emailHtml = `
      <div style="font-family:Arial,Helvetica,sans-serif;background:#f5f7fb;padding:20px;">
        <div style="max-width:600px;margin:auto;background:#ffffff;padding:20px;border-radius:10px;">
          <div style="text-align:center;margin-bottom:12px;">
            <img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:inline-block;border-radius:50%;object-fit:cover;" />
          </div>
          <h2 style="color:#1C2D5E;">Reset your password</h2>
          <p>Hi${safeName},</p>
          <p>Please reset your password by clicking the button below:</p>
          <div style="text-align:center;margin:25px 0;">
            <a href="${resetLink}"
               style="background:#2563eb;color:#ffffff;padding:12px 20px;
               text-decoration:none;border-radius:6px;font-weight:bold;">
               Reset Password
            </a>
          </div>
        </div>
      </div>
    `;

    await sendCriticalEmail({
      to: email,
      fromName: "Flex Facility",
      subject: "Reset your Flex Facility password",
      text: `Hi${safeName},\n\nPlease tap the Reset Password button in this email to reset your password.\n\n`,
      html: emailHtml,
    });

    return res.json({ ok: true });
  } catch (e) {
    console.error("send-password-reset-email error:", e.message || e);
    return res.status(500).json({ ok: false, error: e.message });
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
app.post("/process-payment", paymentLimiter, async (req, res) => {
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

    const parsedAmount = Math.round(Number(amountCents));
    if (!Number.isFinite(parsedAmount) || parsedAmount <= 0 || parsedAmount > 1000000) {
      return res.status(400).json({ ok: false, error: "Invalid payment amount." });
    }

    // If a planId is provided, verify the amount matches the plan price in Firestore
    if (buyer.planId) {
      try {
        const planSnap = await admin.firestore().collection("plans").doc(buyer.planId).get();
        if (planSnap.exists) {
          const planData = planSnap.data() || {};
          const expectedCents = Math.round(Number(planData.price || 0) * 100);
          if (expectedCents > 0 && Math.abs(parsedAmount - expectedCents) > 1) {
            console.warn(`process-payment: amount mismatch planId=${buyer.planId} expected=${expectedCents} got=${parsedAmount}`);
            return res.status(400).json({ ok: false, error: "Payment amount does not match plan price." });
          }
        }
      } catch (e) {
        console.warn("process-payment: plan price validation warning:", e.message);
      }
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
      note: `${buyer.firstName || ""} ${buyer.lastName || ""} - ${planName}`,
      buyerEmail: buyer?.email,
      billingAddress: buildSquareAddress(billingDetails),
    });

    // Email receipt (best effort)
    if (buyer?.email) {
      try {
        const dollars = (Number(amountCents) / 100).toFixed(2);

        const plainText = `Hi ${buyer.firstName || ""} ${buyer.lastName || ""},

      Your payment for "${planName}" was successful.
      Amount: $${dollars}
      ${refId ? `Reference: ${refId}\n` : ""}
      Thank you,
      Flex Facility`;

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
          subject: `Payment Successful - ${planName}`,
          text: plainText,
          html,
        });
      } catch (e) {
        console.error("SendGrid error:", e?.response?.data || e.message);
      }
    }

    // Notify trainer of new payment
    try {
      const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
      const dollars = (Number(amountCents) / 100).toFixed(2);
      const clientFullName = `${buyer.firstName || ""} ${buyer.lastName || ""}`.trim() || buyer.email || "Unknown";
      await sendTransactionalEmail({
        to: trainerEmail,
        fromName: "Flex Facility Billing",
        subject: `[PAYMENT RECEIVED] ${clientFullName} - ${planName}`,
        text: `Hi Kenny,\n\nA new payment has been received.\n\nClient: ${clientFullName}\nEmail: ${buyer.email || "no email"}\nPlan: ${planName}\nAmount: $${dollars}\n${refId ? `Reference: ${refId}\n` : ""}\n- Flex Facility`,
        html: buildTrainerPaymentHtml({
          clientName: clientFullName,
          clientEmail: buyer.email || "no email",
          planName,
          amount: dollars,
          referenceId: refId,
        }),
      });
    } catch (e) {
      console.error("Trainer payment notify error:", e?.response?.data || e.message);
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
    // Log only the message - never the full object which may contain tokens
    console.error("process-payment error:", e?.response?.data?.errors?.[0]?.code || e.message || "unknown");
    let clientMessage = "Payment failed. Please check your card details or try another card.";
    if (e.response?.data?.errors?.length) {
      const sqErr = e.response.data.errors[0];
      clientMessage = sqErr.detail || sqErr.message || clientMessage;
    }
    return res.status(400).json({ ok: false, error: clientMessage });
  }
});

/* =========================
   Invoices (plan active on webhook)
========================= */

// Create & publish invoice, save metadata; DO NOT activate plan yet
app.post("/create-invoice", paymentLimiter, async (req, res) => {
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
    // Verify Square HMAC-SHA256 signature to reject forged webhook calls
    const sigKey = (functions.config()?.square?.webhook_signature_key || "").trim();
    if (sigKey) {
      const squareSig = req.headers["x-square-signature"] || "";
      const webhookUrl = `https://us-central1-flex-facility-app-b55aa.cloudfunctions.net/api/square-webhook`;
      const payload = JSON.stringify(req.body);
      const expected = crypto
        .createHmac("sha256", sigKey)
        .update(webhookUrl + payload)
        .digest("base64");
      if (squareSig !== expected) {
        console.warn("square-webhook: invalid signature - request rejected");
        return res.status(403).json({ ok: false, error: "Invalid webhook signature" });
      }
    }

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
    const metaSnap = await metaRef.get();  //  fixed line

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

app.post("/payment-link/email", paymentLimiter, async (req, res) => {
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
        <h2 style="color:#1C2D5E;">Complete your payment  ${planName}</h2>
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
        <p>If the button doesnt work, copy and paste this URL:</p>
        <p style="word-break:break-all"><a href="${url}">${url}</a></p>
        <p style="margin-top:20px;color:#555;font-size:14px;">
          Need help? Email <a href="mailto:${REPLY_TO.email}">${REPLY_TO.email}</a>.
        </p>
      </div>
    `;

    await sendTransactionalEmail({
      to: recipientEmail,
      fromName: "Flex Facility Billing",
      subject: `Payment link " ${planName}`,
      text: `Hi${safeName},\n\nPlease complete your payment for "${planName}" using this secure link:\n${url}\n\nThank you,\nFlex Facility`,
      html,
    });

    return res.json({ ok: true, url });
  } catch (e) {
    const msg = e.response?.data ? JSON.stringify(e.response.data) : e.message || String(e);
    console.error("payment-link/email error:", msg);
    res.status(500).json({ ok: false, error: msg });
  }
});
// Add this endpoint BEFORE the existing routes
// Serve verification page from templates
app.get("/verify-email", (req, res) => {
    const templatePath = path.join(__dirname, "templates", "verify-email.html");
   
    if (fs.existsSync(templatePath)) {
        res.set("Content-Type", "text/html; charset=utf-8");
        res.status(200).send(fs.readFileSync(templatePath, "utf8"));
    } else {
        // Fallback if template doesn't exist
        res.set("Content-Type", "text/html; charset=utf-8");
        res.status(200).send(`
            <!DOCTYPE html>
            <html>
            <head>
                <title>Email Verification - Flex Facility</title>
                <meta charset="UTF-8">
            </head>
            <body>
                <div style="text-align: center; padding: 50px;">
                    <h2>Email Verification</h2>
                    <p>Processing your verification...</p>
                    <script>
                        const urlParams = new URLSearchParams(window.location.search);
                        const mode = urlParams.get('mode');
                        const oobCode = urlParams.get('oobCode');
                        const apiKey = urlParams.get('apiKey');
                       
                        if (mode === 'verifyEmail' && oobCode) {
                            fetch('/api/verify-email-handler', {
                                method: 'POST',
                                headers: {'Content-Type': 'application/json'},
                                body: JSON.stringify({mode, oobCode, apiKey})
                            })
                            .then(res => res.json())
                            .then(data => {
                                if (data.success) {
                                    window.location.href = 'https://flex-facility-app-b55aa.web.app/signin?verified=true';
                                } else {
                                    window.location.href = 'https://flex-facility-app-b55aa.web.app/signin?error=verification_failed';
                                }
                            })
                            .catch(() => {
                                window.location.href = 'https://flex-facility-app-b55aa.web.app/signin?error=network_error';
                            });
                        }
                    </script>
                </div>
            </body>
            </html>
        `);
    }
});

// POST handler for actual verification
app.post("/verify-email-handler", async (req, res) => {
    try {
        const { mode, oobCode, apiKey } = req.body;
       
        if (mode !== 'verifyEmail' || !oobCode) {
            return res.status(400).json({
                success: false,
                error: "Invalid verification request"
            });
        }
       
        // Get Web API Key from config or use the one from request
        let webApiKey = apiKey;
        if (!webApiKey) {
            try {
                webApiKey = functions.config()?.firebase?.web_api_key;
            } catch(e) {
                // If not set in config, you need to add it
                console.error("Web API Key not configured. Run: firebase functions:config:set firebase.web_api_key=\"YOUR_KEY\"");
            }
        }
       
        if (!webApiKey) {
            return res.status(400).json({
                success: false,
                error: "Service configuration error"
            });
        }
       
        // Call Firebase Auth REST API to verify the email
        const response = await axios.post(
          `https://identitytoolkit.googleapis.com/v1/accounts:update?key=${webApiKey}`,
            {
                oobCode: oobCode
            }
        );
       
        console.log("Email verified successfully:", response.data);
       
        return res.json({
            success: true,
            message: "Email verified successfully"
        });
       
    } catch (error) {
        console.error("Email verification error:", error.response?.data || error.message);
       
        let errorMessage = "Verification failed";
        if (error.response?.data?.error?.message) {
            const fbError = error.response.data.error.message;
            if (fbError === "INVALID_OOB_CODE") {
                errorMessage = "The verification link has expired or is invalid";
            } else if (fbError === "OPERATION_NOT_ALLOWED") {
                errorMessage = "Email verification is not enabled";
            } else {
                errorMessage = fbError;
            }
        }
       
        return res.status(400).json({
            success: false,
            error: errorMessage
        });
    }
});
// Mount Express
exports.api = functions.https.onRequest(app);

// Notify trainer when a new client signs up
exports.onNewUserSignup = functions.auth.user().onCreate(async (user) => {
  try {
    const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
    const clientEmail = user.email || "Unknown";
    const clientName = user.displayName || clientEmail.split("@")[0];
    const signupTime = new Date().toLocaleString("en-US", { timeZone: "America/Chicago" });
    const logoImgSrc = getLogoImgSrc();

    await sendTransactionalEmail({
      to: trainerEmail,
      fromName: "Flex Facility",
      subject: `New Client Signed Up - ${clientName}`,
      text:
        `Hi,\n\nA new client has signed up for Flex Facility.\n\n` +
        `Name: ${clientName}\nEmail: ${clientEmail}\nSigned up: ${signupTime}\n\n- Flex Facility`,
      html:
        `<div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">` +
        `<table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">` +
        `<tr><td style="padding:24px;">` +
        `<table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">` +
        `<tr><td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">` +
        `<img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />` +
        `<div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">New Client Signed Up</div>` +
        `<p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">A new client has joined Flex Facility.</p>` +
        `</td></tr>` +
        `<tr><td style="padding:16px 24px 8px 24px;">` +
        `<p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">Client details</p>` +
        `<table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">` +
        `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Name</td><td style="padding:4px 0;"><strong>${clientName}</strong></td></tr>` +
        `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Email</td><td style="padding:4px 0;"><strong>${clientEmail}</strong></td></tr>` +
        `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Signed up</td><td style="padding:4px 0;"><strong>${signupTime}</strong></td></tr>` +
        `</table>` +
        `</td></tr>` +
        `<tr><td style="padding:16px 24px 24px 24px;">` +
        `<p style="margin:0;font-size:14px;color:#4b5563;">You can view their profile in the Flex Facility admin dashboard.</p>` +
        `<p style="margin:16px 0 0 0;font-size:14px;color:#4b5563;">- Flex Facility</p>` +
        `</td></tr></table></td></tr></table></div>`,
    });
    console.log(`New signup notification sent to trainer for user: ${clientEmail}`);
  } catch (e) {
    console.error("Failed to send new signup notification:", e.message);
  }
});

/**
 * Scheduled session reminder  runs every hour.
 * Finds slots starting in about 30 minutes and sends email + push notification
 * to every booked client who has an FCM token saved.
 */
exports.sendSessionReminders = functions
  .runWith({ memory: "256MB", timeoutSeconds: 120 })
  .pubsub.schedule("every 15 minutes")
  .onRun(async () => {
    const db = admin.firestore();
    const now = new Date();

    // Window: 25-40 min from now. Non-overlapping with consecutive 15-min runs so each
    // slot gets exactly one reminder at ~30 min before session time.
    const windowStart = new Date(now.getTime() + 25 * 60 * 1000);
    const windowEnd   = new Date(now.getTime() + 40 * 60 * 1000);

    const slotsSnap = await db.collection("trainer_slots")
      .where("date", ">=", admin.firestore.Timestamp.fromDate(windowStart))
      .where("date", "<=", admin.firestore.Timestamp.fromDate(windowEnd))
      .get();

    if (slotsSnap.empty) {
      console.log("No upcoming slots in reminder window.");
      return null;
    }

    for (const slotDoc of slotsSnap.docs) {
      const slot = slotDoc.data();

      // Skip cancelled slots entirely
      if (slot.status === "cancelled" || slot.cancelled === true) continue;

      const bookedEmails = slot.booked_emails || [];
      const bookedBy = slot.booked_by || [];
      const statusByUser = slot.status_by_user || {};
      const slotTime     = slot.time || "";
      const slotDate     = slot.date.toDate().toLocaleDateString("en-US", {
        weekday: "long", month: "long", day: "numeric"
      });
      const trainer      = slot.trainer_name || "your trainer";
      const reminderTimeLabel = "30 minutes";
      // Send reminder email and push to each booked client
      for (let i = 0; i < bookedEmails.length; i++) {
        const email = bookedEmails[i];
        const uid = bookedBy[i];
        if (!email || !uid) continue;

        // Skip individually cancelled clients
        if (statusByUser[uid] === "Cancelled") continue;
        try {
          // Send email
          const logoImgSrc = getLogoImgSrc();
          await sendTransactionalEmail({
            to: email,
            fromName: "Flex Facility",
            subject: `[REMINDER] Upcoming Session - ${slotTime} on ${slotDate}`,
            text:
              `Hi,\n\nThis is a reminder that your training session with ${trainer} is coming up ${reminderTimeLabel}.\n\n` +
              `Date: ${slotDate}\nTime: ${slotTime}\n\n` +
              `Please make sure to arrive on time.\n\n- Flex Training`,
            html:
              `<div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">` +
              `<table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">` +
              `<tr><td style="padding:24px;">` +
              `<table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">` +
              `<tr><td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">` +
              `<img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />` +
              `<div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">Session Reminder</div>` +
              `<p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">This is a reminder that your training session with <strong>${trainer}</strong> is coming up <strong>${reminderTimeLabel}</strong>.</p>` +
              `</td></tr>` +
              `<tr><td style="padding:16px 24px 8px 24px;">` +
              `<p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">Session details</p>` +
              `<table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">` +
              `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Date</td><td style="padding:4px 0;"><strong>${slotDate}</strong></td></tr>` +
              `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Time</td><td style="padding:4px 0;"><strong>${slotTime}</strong></td></tr>` +
              `</table>` +
              `</td></tr>` +
              `<tr><td style="padding:16px 24px 24px 24px;">` +
              `<p style="margin:0;font-size:14px;color:#4b5563;">Please make sure to arrive on time.</p>` +
              `<p style="margin:16px 0 0 0;font-size:14px;color:#4b5563;">- Flex Training</p>` +
              `</td></tr></table></td></tr></table></div>`,
          });
          console.log(`Reminder email sent to ${email} for slot ${slotDoc.id}`);
          // Send push notification if user has fcm_token
          const userDoc = await db.collection("users").doc(uid).get();
          const userData = userDoc.exists ? userDoc.data() : null;
          const fcmToken = userData && userData.fcm_token;
          if (fcmToken) {
            const pushTitle = "Session Reminder";
            const pushBody = `Your session with ${trainer} is in 30 minutes.`;
            await admin.messaging().send({
              token: fcmToken,
              notification: {
                title: pushTitle,
                body: pushBody,
              },
              android: {
                priority: "high",
                notification: {
                  channelId: "session_reminders",
                  priority: "high",
                  sound: "default",
                },
              },
              apns: {
                payload: {
                  aps: {
                    sound: "default",
                    badge: 1,
                    contentAvailable: true,
                  },
                },
                headers: {
                  "apns-priority": "10",
                },
              },
              data: {
                slotId: slotDoc.id,
                type: "reminder",
              },
            });
            console.log(`Reminder push sent to ${email} (${uid}) for slot ${slotDoc.id}`);
          }
        } catch (e) {
          console.error(`Failed to send reminder to ${email} (${uid}):`, e);
        }
      }

      // Send reminder to trainer if there are booked clients
      if (bookedEmails.length > 0) {
        try {
          const trainerEmail = (functions.config()?.trainer?.email || "Kenny@flextraining.co").trim();
          const clientNames = (slot.booked_names || []).join(", ") || "clients";
          const logoImgSrc = getLogoImgSrc();
          await sendTransactionalEmail({
            to: trainerEmail,
            fromName: "Flex Facility",
            subject: `[REMINDER] Upcoming Session - ${slotTime} on ${slotDate}`,
            text:
              `Hi ${trainer},\n\nThis is a reminder that you have a session coming up in 30 minutes.\n\n` +
              `Date: ${slotDate}\nTime: ${slotTime}\nClients: ${clientNames}\n\n- Flex Facility`,
            html:
              `<div style="background:${BRAND_COLORS.lightBg};padding:24px 0;font-family:Arial,Helvetica,sans-serif;color:#111827;">` +
              `<table align="center" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto;">` +
              `<tr><td style="padding:24px;">` +
              `<table width="100%" cellpadding="0" cellspacing="0" style="background:${BRAND_COLORS.cardBg};border-radius:16px;box-shadow:0 4px 16px rgba(15,23,42,0.08);overflow:hidden;">` +
              `<tr><td style="padding:20px 24px 12px 24px;border-bottom:1px solid #e5e7eb;">` +
              `<img src="${logoImgSrc}" alt="Flex Facility" width="100" style="display:block;margin-bottom:16px;border-radius:50%;object-fit:cover;" />` +
              `<div style="font-size:18px;font-weight:600;color:${BRAND_COLORS.primary};">Session Reminder</div>` +
              `<p style="margin:10px 0 0 0;font-size:14px;color:#4b5563;line-height:1.6;">Hi <strong>${trainer}</strong>, you have a session coming up in <strong>30 minutes</strong>.</p>` +
              `</td></tr>` +
              `<tr><td style="padding:16px 24px 8px 24px;">` +
              `<p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.08em;">Session details</p>` +
              `<table cellpadding="0" cellspacing="0" width="100%" style="font-size:14px;color:#111827;">` +
              `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Date</td><td style="padding:4px 0;"><strong>${slotDate}</strong></td></tr>` +
              `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Time</td><td style="padding:4px 0;"><strong>${slotTime}</strong></td></tr>` +
              `<tr><td style="padding:4px 0;width:90px;color:#6b7280;">Clients</td><td style="padding:4px 0;"><strong>${clientNames}</strong></td></tr>` +
              `</table>` +
              `</td></tr>` +
              `<tr><td style="padding:16px 24px 24px 24px;">` +
              `<p style="margin:0;font-size:14px;color:#4b5563;">Please make sure to be ready on time.</p>` +
              `<p style="margin:16px 0 0 0;font-size:14px;color:#4b5563;">- Flex Facility</p>` +
              `</td></tr></table></td></tr></table></div>`,
          });
          console.log(`Trainer reminder sent to ${trainerEmail} for slot ${slotDoc.id}`);
        } catch (e) {
          console.error("Failed to send trainer reminder:", e.message);
        }
      }
    }

    return null;
  });

/* =========================
   AI Fitness Coach (Callable)
   Set key: firebase functions:config:set anthropic.key="sk-ant-..."
========================= */
exports.aiChat = functions
  .runWith({ memory: "512MB", timeoutSeconds: 90 })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login required.");
    }

    const messages = data && data.messages;
    if (!Array.isArray(messages) || messages.length === 0) {
      throw new functions.https.HttpsError("invalid-argument", "messages array is required.");
    }

    const apiKey = (functions.config()?.anthropic?.key || "").trim();
    if (!apiKey) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Anthropic API key not configured. Run:\n  firebase functions:config:set anthropic.key=\"sk-ant-...\""
      );
    }

    const systemPrompt =
      "You are an expert personal fitness coach AI assistant for Flex Facility gym. " +
      "Help clients with workout programming, exercise technique, nutrition guidance, recovery strategies, and goal setting. " +
      "Keep responses concise, motivating, and practical. Prioritize safety — always recommend consulting a doctor for medical concerns. " +
      "Use an encouraging, coach-like tone.";

    // Limit history to last 20 messages and cap content length to avoid excessive tokens
    const trimmed = messages.slice(-20).map((m) => ({
      role: String(m.role) === "user" ? "user" : "assistant",
      content: String(m.content).slice(0, 4000),
    }));

    const response = await axios.post(
      "https://api.anthropic.com/v1/messages",
      {
        model: "claude-haiku-4-5-20251001",
        max_tokens: 1024,
        system: systemPrompt,
        messages: trimmed,
      },
      {
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        timeout: 80000,
      }
    );

    const reply =
      (response.data &&
        response.data.content &&
        response.data.content[0] &&
        response.data.content[0].text) ||
      "";
    return { reply };
  });