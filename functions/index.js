const functions = require("firebase-functions");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");

admin.initializeApp();
sgMail.setApiKey(functions.config().sendgrid.key);

// BOOKING CONFIRMATIONS
exports.notifiesBookingEmails = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;

    const beforeEmails = before.booked_emails || [];
    const afterEmails = after.booked_emails || [];

    // ✅ Handle first-time bookings or rebookings after cancellation
    let newEmails = [];
    if (beforeEmails.length === 0 && afterEmails.length > 0) {
      newEmails = afterEmails;
    } else {
      newEmails = afterEmails.filter(email => !beforeEmails.includes(email));
    }

    if (newEmails.length > 0) {
      const slotTime = after.time;
      const slotDate = after.date.toDate().toLocaleDateString();
      const trainer = after.trainer_name || "your trainer";

      const sendPromises = newEmails.map((email) =>
        sgMail
          .send({
            to: email,
            from: { email: "archengservices2022@gmail.com", name: "Flex Facility Bookings" },
            subject: `Booking Confirmed with ${trainer}`,
            text: `Hi there,\n\nYour booking with trainer ${trainer} has been confirmed!\n\n📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nThanks,\nFlex Facility Team`,
          })
          .then(() => console.log(`✅ Booking confirmation email sent to: ${email}`))
          .catch((error) => console.error(`❌ Error sending confirmation to ${email}:`, error))
      );

      await Promise.all(sendPromises);
    } else {
      console.log("ℹ️ No new bookings detected. Skipping confirmation emails.");
    }
    return;
  });
// ✅ BOOKING CONFIRMATIONS onCreate (first-time slot with booking)
exports.notifyBookingOnCreate = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const bookedEmails = data.booked_emails || [];

    if (bookedEmails.length === 0) {
      console.log("ℹ️ No emails on first-time booking creation.");
      return;
    }

    const slotTime = data.time;
    const slotDate = data.date.toDate().toLocaleDateString();
    const trainer = data.trainer_name || "your trainer";

    const sendPromises = bookedEmails.map((email) =>
      sgMail
        .send({
          to: email,
          from: { email: "archengservices2022@gmail.com", name: "Flex Facility Bookings" },
          subject: `Booking Confirmed with ${trainer}`,
          text: `Hi there,\n\nYour booking with trainer ${trainer} has been confirmed!\n\n📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nThanks,\nFlex Facility Team`,
        })
        .then(() => console.log(`✅ Booking confirmation email (onCreate) sent to: ${email}`))
        .catch((error) => console.error(`❌ Error sending confirmation (onCreate) to ${email}:`, error))
    );

    await Promise.all(sendPromises);
  });

// CANCELLATIONS
exports.notifiesCancellationEmails = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;

    const beforeEmails = before.booked_emails || [];
    const afterEmails = after.booked_emails || [];

    const cancelledEmails = beforeEmails.filter((email) => !afterEmails.includes(email));

    if (cancelledEmails.length > 0) {
      const slotTime = before.time;
      const slotDate = before.date.toDate().toLocaleDateString();
      const trainer = before.trainer_name || "your trainer";

      const sendPromises = cancelledEmails.map((email) =>
        sgMail
          .send({
            to: email,
            from: { email: "archengservices2022@gmail.com", name: "Flex Facility Bookings" },
            subject: `Booking Cancelled with ${trainer}`,
            text: `Hi there,\n\nYour booking with trainer ${trainer} has been cancelled.\n\n📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nIf this was a mistake, please rebook.\n\nThanks,\nFlex Facility Team`,
          })
          .then(() => console.log(`Cancellation email sent to: ${email}`))
          .catch((error) => console.error(`Error sending cancellation to ${email}:`, error))
      );

      await Promise.all(sendPromises);
    } else {
      console.log("No cancellations detected. Skipping cancellation emails.");
    }
    return;
  });
