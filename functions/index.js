const functions = require("firebase-functions");
const admin = require("firebase-admin");
const sgMail = require("@sendgrid/mail");

admin.initializeApp();
sgMail.setApiKey(functions.config().sendgrid.key);

// ✅ SEND EMAIL ON CREATE — First time a slot is created with bookings
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

// ✅ SEND EMAIL ON UPDATE — handles new bookings and cancellations
exports.handleBookingAndCancellation = functions
  .runWith({ memory: "256MB", timeoutSeconds: 60 })
  .firestore.document("trainer_slots/{slotId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return;

    const beforeEmails = before.booked_emails || [];
    const afterEmails = after.booked_emails || [];

    const newlyBooked = afterEmails.filter(email => !beforeEmails.includes(email));
    const cancelled = beforeEmails.filter(email => !afterEmails.includes(email));

    const slotTime = after.time || before.time;
    const slotDate = (after.date || before.date).toDate().toLocaleDateString();
    const trainer = after.trainer_name || before.trainer_name || "your trainer";

    const sendTasks = [];

    // Check if this is a reschedule by looking for the flag
    const isReschedule = after.is_reschedule === true;

    // If reschedule, we should have exactly one new booking and one cancellation
    if (isReschedule && newlyBooked.length === 1 && cancelled.length === 1) {
      const email = newlyBooked[0];
      sendTasks.push(
        sgMail.send({
          to: email,
          from: { email: "bookings@archengineeringservices.com", name: "Flex Facility Bookings" },
          subject: `🔁 Rescheduled – ${trainer}`,
          text: `Hi there,\n\n🔁 Your session with ${trainer} has been rescheduled.\n\n📅 New Date: ${slotDate}\n⏰ New Time: ${slotTime}\n\nPlease arrive 5 minutes early.\n\nThanks,\nFlex Facility Team`,
        }).then(() => console.log(`✅ Reschedule email sent to: ${email}`))
          .catch((err) => console.error(`❌ Reschedule email error for ${email}:`, err))
      );
    
      // Clear the flag and return to avoid duplicate booking confirmation email
      await change.after.ref.update({ is_reschedule: admin.firestore.FieldValue.delete() });
      console.log("ℹ️ Cleared is_reschedule flag after reschedule");
      return; // ✅ THIS LINE STOPS FURTHER BOOKING EMAIL
    }
    
    else {
      // Handle normal bookings
      newlyBooked.forEach(email => {
        sendTasks.push(
          sgMail.send({
            to: email,
            from: { email: "bookings@archengineeringservices.com", name: "Flex Facility Bookings" },
            subject: `✅ Booking Confirmed – ${trainer}`,
            text: `Hi there,\n\n🎉 Your session with ${trainer} is confirmed!\n\n📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nPlease arrive 5 minutes early.\n\nThanks,\nFlex Facility Team`,
          }).then(() => console.log(`✅ Booking confirmation email sent to: ${email}`))
            .catch((err) => console.error(`❌ Booking confirmation error for ${email}:`, err))
        );
      });

      // Handle cancellations
      cancelled.forEach(email => {
        sendTasks.push(
          sgMail.send({
            to: email,
            from: { email: "bookings@archengineeringservices.com", name: "Flex Facility Bookings" },
            subject: `❌ Booking Cancelled – ${trainer}`,
            text: `Hi there,\n\nYour session with ${trainer} has been cancelled.\n\n📅 Date: ${slotDate}\n⏰ Time: ${slotTime}\n\nIf this was a mistake, you can rebook through the app.\n\nThanks,\nFlex Facility Team`,
          }).then(() => console.log(`✅ Cancellation email sent to: ${email}`))
            .catch((err) => console.error(`❌ Cancellation email error for ${email}:`, err))
        );
      });
    }

    if (sendTasks.length > 0) {
      await Promise.all(sendTasks);
    } else {
      console.log("ℹ️ No booking/cancellation changes. No emails sent.");
    }
  });