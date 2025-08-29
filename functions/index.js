const functions = require("firebase-functions");
const nodemailer = require("nodemailer");

// Configure your Gmail credentials here
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "your_email@gmail.com", // Your Gmail
    pass: "your_app_password"     // Gmail App Password
  }
});

exports.notifyTrainerClient = functions.https.onCall(async (data) => {
  const {
    action,
    userName,
    email,
    time,
    date,
    trainerName
  } = data;

  const subject = action === "book" ? "🎉 Booking Confirmed" : "❌ Booking Cancelled";
  const text = `
Hello ${userName},

Your ${action === "book" ? "booking" : "cancellation"} was successfully processed.

Trainer: ${trainerName}
Date: ${date}
Time: ${time}

Thank you,
Flex Facility Team
`;

  try {
    await transporter.sendMail({
      from: '"Flex Facility" <your_email@gmail.com>',
      to: email,
      subject,
      text
    });

    return { success: true };
  } catch (error) {
    console.error("Failed to send email:", error);
    throw new functions.https.HttpsError("internal", "Email failed");
  }
});
