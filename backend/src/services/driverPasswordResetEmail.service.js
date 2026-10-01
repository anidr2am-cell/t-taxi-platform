const nodemailer = require('nodemailer');
const config = require('../config/env');

class DriverPasswordResetEmailService {
  constructor({ smtp = config.smtp, transport = null } = {}) {
    this.smtp = smtp;
    this.transport = transport;
  }

  isConfigured() {
    return Boolean(this.smtp.host && (this.smtp.fromEmail || this.smtp.from));
  }

  async sendCode({ email, code, locale = 'ko' }) {
    if (!this.isConfigured()) throw new Error('PASSWORD_RESET_EMAIL_NOT_CONFIGURED');
    const transport = this.transport || nodemailer.createTransport({
      host: this.smtp.host,
      port: this.smtp.port,
      secure: Boolean(this.smtp.secure),
      auth: this.smtp.user ? { user: this.smtp.user, pass: this.smtp.password } : undefined,
    });
    const thai = String(locale).toLowerCase().startsWith('th');
    const subject = thai ? 'รหัสยืนยันสำหรับตั้งรหัสผ่าน T-Ride ใหม่' : 'T-Ride 기사 비밀번호 재설정 인증번호';
    const text = thai
      ? `รหัสยืนยันของคุณคือ ${code}\nรหัสนี้ใช้ได้ 10 นาที หากคุณไม่ได้ร้องขอ โปรดเพิกเฉยต่ออีเมลนี้`
      : `인증번호는 ${code}입니다.\n인증번호는 10분 동안 유효합니다. 본인이 요청하지 않았다면 이 메일을 무시해 주세요.`;
    const fromEmail = this.smtp.fromEmail || this.smtp.from;
    const from = this.smtp.fromName ? `"${this.smtp.fromName}" <${fromEmail}>` : fromEmail;
    await transport.sendMail({ from, to: email, subject, text });
  }
}

module.exports = DriverPasswordResetEmailService;
