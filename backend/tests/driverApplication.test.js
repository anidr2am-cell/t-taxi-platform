process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const DriverApplicationService = require('../src/services/driverApplication.service');
const ERROR_CODES = require('../src/constants/errorCodes');

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function validInput(overrides = {}) {
  return {
    fullName: 'Driver Kim',
    password: 'strongpass123',
    passwordConfirm: 'strongpass123',
    phone: '+66123456789',
    phoneCountryCode: '+66',
    countryCode: 'th',
    locale: 'ko',
    drivingLicenseNumber: 'DL-12345',
    drivingLicenseCountry: 'TH',
    drivingLicenseExpiryDate: '2030-01-01',
    yearsOfDrivingExperience: 5,
    vehicleOwnershipType: 'OWNED',
    vehicleTypeCode: 'sedan',
    vehicleMake: 'Toyota',
    vehicleModel: 'Camry',
    vehicleYear: 2022,
    vehicleColor: 'White',
    vehiclePlateNumber: ' ab-1234 ',
    serviceAreas: ['Bangkok', 'Pattaya'],
    languages: ['ko', 'en'],
    notes: 'Available airport transfers',
    personalDataConsent: true,
    driverTermsConsent: true,
    ...overrides,
  };
}

function createPool(calls) {
  const conn = {
    async beginTransaction() { calls.begin += 1; },
    async commit() { calls.commit += 1; },
    async rollback() { calls.rollback += 1; },
    release() { calls.release += 1; },
  };
  return { async getConnection() { return conn; } };
}

function clone(row) {
  return row ? JSON.parse(JSON.stringify(row)) : null;
}

class MemoryDriverApplicationRepository {
  constructor() {
    this.applications = [];
    this.users = [];
    this.driverVehicles = [];
    this.drivers = [];
    this.auditLogs = [];
    this.notifications = [];
    this.vehicleTypes = [{ id: 11, code: 'SEDAN', name: 'Sedan' }];
    this.lastCreate = null;
  }

  async create(_conn, data) {
    this.lastCreate = data;
    const row = {
      id: this.applications.length + 1,
      application_number: data.applicationNumber,
      status: 'PENDING',
      email: data.email,
      password_hash: data.passwordHash,
      full_name: data.fullName,
      phone: data.phone,
      phone_country_code: data.phoneCountryCode,
      country_code: data.countryCode,
      locale: data.locale,
      driving_license_number: data.drivingLicenseNumber,
      driving_license_country: data.drivingLicenseCountry,
      driving_license_expiry_date: data.drivingLicenseExpiryDate,
      years_of_driving_experience: data.yearsOfDrivingExperience,
      vehicle_ownership_type: data.vehicleOwnershipType,
      vehicle_type_code: data.vehicleTypeCode,
      vehicle_make: data.vehicleMake,
      vehicle_model: data.vehicleModel,
      vehicle_year: data.vehicleYear,
      vehicle_color: data.vehicleColor,
      vehicle_plate_number: data.vehiclePlateNumber,
      service_areas: JSON.stringify(data.serviceAreas),
      languages: JSON.stringify(data.languages ?? []),
      notes: data.notes,
      personal_data_consent_at: '2026-07-03 10:00:00',
      driver_terms_consent_at: '2026-07-03 10:00:00',
      status_lookup_token_hash: data.statusLookupTokenHash,
      rejection_reason: null,
      admin_note: null,
      submitted_at: '2026-07-03 10:00:00',
      reviewed_at: null,
      reviewed_by: null,
      approved_user_id: null,
      approved_driver_id: null,
      approved_at: null,
      approved_by: null,
      rejected_at: null,
      rejected_by: null,
      resubmitted_from_application_id: data.resubmittedFromApplicationId ?? null,
      created_at: '2026-07-03 10:00:00',
      updated_at: '2026-07-03 10:00:00',
    };
    this.applications.push(row);
    return row.id;
  }

  async findById(id) {
    return clone(this.applications.find((row) => row.id === Number(id)));
  }

  async findByIdForUpdate(_conn, id) {
    return this.findById(id);
  }

  async findByNumber(applicationNumber) {
    return clone(this.applications.find((row) => row.application_number === applicationNumber));
  }

  async findByNumberForUpdate(_conn, applicationNumber) {
    return this.findByNumber(applicationNumber);
  }

  async findPendingByEmailForUpdate(_conn, email) {
    return clone(this.applications.find((row) => row.email === email && row.status === 'PENDING'));
  }

  async findPendingByPlateForUpdate(_conn, plate) {
    return clone(this.applications.find(
      (row) => row.vehicle_plate_number === plate && row.status === 'PENDING',
    ));
  }

  async findApprovedByEmail(email) {
    return clone(this.applications.find((row) => row.email === email && row.status === 'APPROVED'));
  }

  async findActiveUserByEmailForUpdate(_conn, email) {
    return clone(this.users.find((row) => row.email === email && row.deleted_at == null));
  }

  async findVehicleByPlateForUpdate(_conn, plate) {
    return clone(this.driverVehicles.find((row) => row.plate_number === plate));
  }

  async findVehicleTypeByCode(_conn, code) {
    return clone(this.vehicleTypes.find((row) => row.code === code));
  }

  async listAdmin() {
    return { items: [], total: 0 };
  }

  async insertDriverUser(_conn, application) {
    const id = this.users.length + 100;
    this.users.push({
      id,
      email: application.email,
      password_hash: application.password_hash,
      role: 'DRIVER',
      is_active: 1,
    });
    return id;
  }

  async insertDriver(_conn, application, vehicleTypeId, userId) {
    const id = this.drivers.length + 200;
    this.drivers.push({
      id,
      user_id: userId,
      name: application.full_name,
      phone: application.phone,
      license_number: application.driving_license_number,
      status: 'OFFLINE',
      primary_vehicle_type_id: vehicleTypeId,
      is_online: 0,
      is_active: 1,
    });
    return id;
  }

  async insertDriverVehicle(_conn, application, driverId, vehicleTypeId) {
    const id = this.driverVehicles.length + 300;
    this.driverVehicles.push({
      id,
      driver_id: driverId,
      vehicle_type_id: vehicleTypeId,
      plate_number: application.vehicle_plate_number,
      is_primary: 1,
      is_active: 1,
    });
    return id;
  }

  async approve(_conn, applicationId, data) {
    const row = this.applications.find((item) => item.id === applicationId);
    row.status = 'APPROVED';
    row.password_hash = null;
    row.rejection_reason = null;
    row.reviewed_by = data.reviewedBy;
    row.reviewed_at = '2026-07-03 11:00:00';
    row.approved_at = '2026-07-03 11:00:00';
    row.approved_by = data.reviewedBy;
    row.approved_user_id = data.approvedUserId;
    row.approved_driver_id = data.approvedDriverId;
  }

  async reject(_conn, applicationId, data) {
    const row = this.applications.find((item) => item.id === applicationId);
    row.status = 'REJECTED';
    row.rejection_reason = data.rejectionReason;
    row.admin_note = data.adminNote;
    row.reviewed_by = data.reviewedBy;
    row.reviewed_at = '2026-07-03 11:00:00';
    row.rejected_at = '2026-07-03 11:00:00';
    row.rejected_by = data.reviewedBy;
  }

  async insertAuditLog(_conn, log) {
    this.auditLogs.push(log);
  }

  async insertAdminNotification(_conn, adminUserId, application) {
    const idempotencyKey = `driver-application-submitted:${application.id}:${adminUserId}`;
    if (this.notifications.some((row) => row.idempotencyKey === idempotencyKey)) return;
    this.notifications.push({
      adminUserId,
      eventId: `driver-application-${application.id}`,
      idempotencyKey,
      title: '드라이버 신규 가입 요청',
      body: `${application.full_name || '신규 기사'}님의 신규 기사 가입 요청이 접수되었습니다.`,
      payload: {
        applicationId: application.id,
        applicationNumber: application.application_number,
        route: `/admin/driver-applications/${application.id}`,
      },
    });
  }
}

function createHarness() {
  const calls = { begin: 0, commit: 0, rollback: 0, release: 0 };
  const repository = new MemoryDriverApplicationRepository();
  const userRepository = {
    async findActiveByRoles(roles) {
      return [
        { id: 7, role: 'ADMIN' },
        { id: 8, role: 'SUPER_ADMIN' },
      ].filter((user) => roles.includes(user.role));
    },
  };
  const service = new DriverApplicationService(
    createPool(calls),
    repository,
    null,
    userRepository,
  );
  return { calls, repository, service };
}

function uploadFile(field, filename, mimetype = 'image/jpeg') {
  return {
    fieldname: field,
    originalname: filename,
    filename: `stored-${filename}`,
    mimetype,
    path: `/tmp/${filename}`,
    size: 10,
  };
}

describe('Driver application public routes', () => {
  beforeEach(() => {
    container.register('driverApplicationService', () => ({
      async submit() {
        return {
          applicationNumber: 'DA260703A1B2C3D4',
          status: 'PENDING',
          statusToken: 'raw-status-token',
          submittedAt: '2026-07-03 10:00:00',
        };
      },
      async status() {
        return {
          applicationNumber: 'DA260703A1B2C3D4',
          status: 'PENDING',
          submittedAt: '2026-07-03 10:00:00',
          reviewedAt: null,
          rejectionReason: null,
        };
      },
    }));
  });

  test('POST /api/v1/driver-applications is mounted without auth', async () => {
    const res = await request(app)
      .post('/api/v1/driver-applications')
      .send(validInput())
      .expect(201);

    assert.equal(res.body.success, true);
    assert.equal(res.body.data.status, 'PENDING');
    assert.equal(res.body.data.statusToken, 'raw-status-token');
    assert.ok(!('passwordHash' in res.body.data));
    assert.ok(!('statusTokenHash' in res.body.data));
  });

  test('JSON application accepts phone and password without email', async () => {
    const res = await request(app)
      .post('/api/v1/driver-applications')
      .send(validInput({ email: undefined }))
      .expect(201);

    assert.equal(res.body.success, true);
  });

  test('JSON application treats blank email as omitted', async () => {
    const res = await request(app)
      .post('/api/v1/driver-applications')
      .send(validInput({ email: '' }))
      .expect(201);

    assert.equal(res.body.success, true);
  });

  test('JSON application rejects explicitly invalid email', async () => {
    const res = await request(app)
      .post('/api/v1/driver-applications')
      .send(validInput({ email: 'not-an-email' }))
      .expect(400);

    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
    assert.equal(res.body.errors[0].field, 'email');
  });

  test('JSON application still requires phone password and confirmation', async () => {
    for (const field of ['phone', 'password', 'passwordConfirm']) {
      const input = validInput();
      delete input[field];
      const res = await request(app)
        .post('/api/v1/driver-applications')
        .send(input)
        .expect(400);

      assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
      assert.equal(res.body.errors[0].field, field);
    }
  });

  test('submit rejects false consent before service call', async () => {
    const res = await request(app)
      .post('/api/v1/driver-applications')
      .send(validInput({ personalDataConsent: false }))
      .expect(400);

    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  });

  test('multipart invalid file type reports field and file name', async () => {
    const res = await request(app)
      .post('/api/v1/driver-applications')
      .field('applicantName', 'Driver Kim')
      .field('phone', '+66123456789')
      .field('password', 'strongpass123')
      .field('passwordConfirmation', 'strongpass123')
      .field('licenseNumber', 'DL12345')
      .field('licenseExpiryDate', '2030-01-01')
      .field('bankName', 'Kasikorn')
      .field('bankAccountNumber', '1234567890')
      .field('bankAccountHolder', 'Driver Kim')
      .field('lineId', '@driver')
      .field('primaryServiceArea', 'Bangkok')
      .field('vehicleTypeId', '11')
      .attach('lineQr', Buffer.from('bad'), {
        filename: 'line.exe',
        contentType: 'application/octet-stream',
      })
      .expect(400);

    assert.equal(res.body.error_code, ERROR_CODES.INVALID_FILE_TYPE);
    assert.equal(res.body.errors[0].field, 'lineQr');
    assert.equal(res.body.errors[0].fileName, 'line.exe');
  });

  test('multipart application accepts phone and password without email', async () => {
    const res = await request(app)
      .post('/api/v1/driver-applications')
      .field('applicantName', 'Driver Kim')
      .field('phone', '+66123456789')
      .field('password', 'strongpass123')
      .field('passwordConfirmation', 'strongpass123')
      .field('licenseNumber', 'DL12345')
      .field('licenseExpiryDate', '2030-01-01')
      .field('bankName', 'Kasikorn')
      .field('bankAccountNumber', '1234567890')
      .field('bankAccountHolder', 'Driver Kim')
      .field('lineId', '@driver')
      .field('primaryServiceArea', 'Bangkok')
      .field('vehicleTypeId', '11')
      .field('vehiclePlateNumber', 'AB1234')
      .field('serviceAreas', 'Bangkok')
      .field('personalDataConsent', 'true')
      .field('driverTermsConsent', 'true')
      .attach('lineQr', Buffer.from('qr'), { filename: 'line.png', contentType: 'image/png' })
      .attach('vehiclePhotos', Buffer.from('car1'), { filename: 'car1.jpg', contentType: 'image/jpeg' })
      .attach('vehiclePhotos', Buffer.from('car2'), { filename: 'car2.jpg', contentType: 'image/jpeg' })
      .attach('vehiclePhotos', Buffer.from('car3'), { filename: 'car3.jpg', contentType: 'image/jpeg' })
      .attach('insuranceCertificate', Buffer.from('pdf'), { filename: 'insurance.pdf', contentType: 'application/pdf' })
      .attach('vehicleRegistration', Buffer.from('pdf'), { filename: 'registration.pdf', contentType: 'application/pdf' })
      .attach('taxCertificate', Buffer.from('pdf'), { filename: 'tax.pdf', contentType: 'application/pdf' })
      .expect(201);

    assert.equal(res.body.success, true);
  });
});

describe('Driver application admin routes', () => {
  beforeEach(() => {
    container.register('driverApplicationService', () => ({
      async listAdmin() {
        return { page: 1, pageSize: 20, total: 0, items: [] };
      },
      async approve() {
        return {
          applicationNumber: 'DA260703A1B2C3D4',
          status: 'APPROVED',
          approvedUserId: 100,
          approvedDriverId: 200,
          vehicleId: 300,
        };
      },
    }));
  });

  test('admin list requires ADMIN or SUPER_ADMIN', async () => {
    await request(app).get('/api/v1/admin/driver-applications').expect(401);

    const driver = await request(app)
      .get('/api/v1/admin/driver-applications')
      .set('Authorization', `Bearer ${sign('DRIVER', 9)}`);
    assert.equal(driver.status, 403);

    const admin = await request(app)
      .get('/api/v1/admin/driver-applications')
      .set('Authorization', `Bearer ${sign('ADMIN')}`)
      .expect(200);
    assert.equal(admin.body.data.total, 0);
  });
});

describe('DriverApplicationService', () => {
  test('file validation allows supported image MIME types for image fields', () => {
    const { service } = createHarness();

    assert.doesNotThrow(() => service.validateFile(uploadFile('lineQr', 'line.jpg', 'image/jpeg'), {
      imageOnly: true,
      field: 'lineQr',
    }));
    assert.doesNotThrow(() => service.validateFile(uploadFile('vehiclePhotos', 'car.png', 'image/png'), {
      imageOnly: true,
      field: 'vehiclePhotos',
    }));
    assert.doesNotThrow(() => service.validateFile(uploadFile('vehiclePhotos', 'car.webp', 'image/webp'), {
      imageOnly: true,
      field: 'vehiclePhotos',
    }));
  });

  test('file validation allows pdf only for document fields', () => {
    const { service } = createHarness();

    assert.doesNotThrow(() => service.validateFile(uploadFile('insuranceCertificate', 'insurance.pdf', 'application/pdf'), {
      imageOnly: false,
      field: 'insuranceCertificate',
    }));
    assert.throws(
      () => service.validateFile(uploadFile('vehiclePhotos', 'car.pdf', 'application/pdf'), {
        imageOnly: true,
        field: 'vehiclePhotos',
      }),
      (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE
        && err.errors[0].field === 'vehiclePhotos'
        && err.errors[0].fileName === 'car.pdf',
    );
  });

  test('file validation allows generic MIME when extension matches field policy', () => {
    const { service } = createHarness();

    assert.doesNotThrow(() => service.validateFile(uploadFile('lineQr', 'line.JPG', ''), {
      imageOnly: true,
      field: 'lineQr',
    }));
    assert.doesNotThrow(() => service.validateFile(uploadFile('vehiclePhotos', 'car.PNG', 'application/octet-stream'), {
      imageOnly: true,
      field: 'vehiclePhotos',
    }));
    assert.doesNotThrow(() => service.validateFile(uploadFile('taxCertificate', 'tax.PDF', 'application/octet-stream'), {
      imageOnly: false,
      field: 'taxCertificate',
    }));
  });

  test('file validation blocks unsafe or mismatched extensions', () => {
    const { service } = createHarness();
    for (const filename of ['driver.exe', 'script.js', 'page.html', 'vector.svg']) {
      assert.throws(
        () => service.validateFile(uploadFile('insuranceCertificate', filename, 'application/octet-stream'), {
          imageOnly: false,
          field: 'insuranceCertificate',
        }),
        (err) => err.errorCode === ERROR_CODES.INVALID_FILE_TYPE
          && err.errors[0].field === 'insuranceCertificate'
          && err.errors[0].fileName === filename,
      );
    }
  });

  test('submit hashes password, stores only token hash, and returns raw status token once', async () => {
    const { calls, repository, service } = createHarness();

    const result = await service.submit(validInput());

    assert.equal(result.status, 'PENDING');
    assert.match(result.applicationNumber, /^DA[0-9A-F]{14}$/);
    assert.ok(result.statusToken.length >= 32);
    assert.equal(calls.commit, 1);
    assert.equal(calls.rollback, 0);

    const stored = repository.applications[0];
    assert.equal(stored.email, 'driver+66123456789@driver.local');
    assert.equal(stored.vehicle_type_code, 'SEDAN');
    assert.equal(stored.vehicle_plate_number, 'AB-1234');
    assert.notEqual(stored.password_hash, 'strongpass123');
    assert.equal(await bcrypt.compare('strongpass123', stored.password_hash), true);
    assert.notEqual(stored.status_lookup_token_hash, result.statusToken);
    assert.equal(stored.status_lookup_token_hash.length, 64);
  });

  test('submit creates admin notifications for new driver applications', async () => {
    const { repository, service } = createHarness();

    const result = await service.submit(validInput({ fullName: 'Driver Park' }));

    assert.equal(repository.notifications.length, 2);
    assert.deepEqual(
      repository.notifications.map((row) => row.adminUserId),
      [7, 8],
    );
    assert.equal(repository.notifications[0].title, '드라이버 신규 가입 요청');
    assert.equal(
      repository.notifications[0].body,
      'Driver Park님의 신규 기사 가입 요청이 접수되었습니다.',
    );
    assert.equal(repository.notifications[0].payload.applicationNumber, result.applicationNumber);
    assert.equal(repository.notifications[0].payload.route, '/admin/driver-applications/1');

    await repository.insertAdminNotification(null, 7, {
      id: 1,
      application_number: result.applicationNumber,
      full_name: 'Driver Park',
    });
    assert.equal(repository.notifications.length, 2);
  });

  test('submit blocks duplicate pending phone and rolls back', async () => {
    const { calls, service } = createHarness();
    await service.submit(validInput());

    await assert.rejects(
      () => service.submit(validInput({ vehiclePlateNumber: 'ZZ-9999' })),
      (err) => err.statusCode === 409,
    );
    assert.equal(calls.rollback, 1);
  });

  test('submit keeps optional legacy email when provided', async () => {
    const { repository, service } = createHarness();
    await service.submit(validInput({ email: ' Driver.Local@Example.com ' }));

    assert.equal(repository.applications[0].email, 'driver.local@example.com');
  });

  test('submit blocks duplicate pending email when legacy email is provided', async () => {
    const { calls, service } = createHarness();
    await service.submit(validInput({ email: 'driver.local@example.com' }));

    await assert.rejects(
      () => service.submit(validInput({
        email: 'driver.local@example.com',
        phone: '+66999999999',
        vehiclePlateNumber: 'ZZ-9999',
      })),
      (err) => err.statusCode === 409,
    );
    assert.equal(calls.rollback, 1);
  });

  test('status lookup requires application number and token, and omits admin note/hash', async () => {
    const { service, repository } = createHarness();
    const submitted = await service.submit(validInput());

    const status = await service.status({
      applicationNumber: submitted.applicationNumber,
      token: submitted.statusToken,
    });
    assert.equal(status.status, 'PENDING');
    assert.ok(!('adminNote' in status));
    assert.ok(!('statusLookupTokenHash' in status));

    await repository.reject(null, 1, {
      reviewedBy: 7,
      rejectionReason: 'Missing document',
      adminNote: 'Internal note',
    });
    const rejected = await service.status({
      applicationNumber: submitted.applicationNumber,
      token: submitted.statusToken,
    });
    assert.equal(rejected.rejectionReason, 'Missing document');

    await assert.rejects(
      () => service.status({ applicationNumber: submitted.applicationNumber, token: 'wrong-token-value' }),
      (err) => err.statusCode === 404,
    );
  });

  test('admin detail omits password and status token hashes', async () => {
    const { service } = createHarness();
    await service.submit(validInput());

    const detail = await service.getAdminDetail(1);

    assert.equal(detail.applicationNumber.startsWith('DA'), true);
    assert.ok(!('passwordHash' in detail));
    assert.ok(!('password_hash' in detail));
    assert.ok(!('statusTokenHash' in detail));
    assert.ok(!('status_lookup_token_hash' in detail));
  });

  test('reject marks application rejected without creating user or driver', async () => {
    const { repository, service } = createHarness();
    const submitted = await service.submit(validInput());

    const result = await service.reject(1, {
      rejectionReason: 'License expired',
      adminNote: 'Needs current license',
    }, { id: 7, role: 'ADMIN' });

    assert.equal(result.status, 'REJECTED');
    assert.equal(repository.applications[0].status, 'REJECTED');
    assert.equal(repository.applications[0].rejection_reason, 'License expired');
    assert.equal(repository.applications[0].rejected_at, '2026-07-03 11:00:00');
    assert.equal(repository.applications[0].rejected_by, 7);
    assert.equal(repository.users.length, 0);
    assert.equal(repository.drivers.length, 0);
    assert.equal(repository.applications[0].application_number, submitted.applicationNumber);
    assert.equal(repository.auditLogs[0].action, 'driver_application.rejected');
  });

  test('resubmit only from rejected application creates a new pending row and keeps old row', async () => {
    const { repository, service } = createHarness();
    const submitted = await service.submit(validInput());

    await assert.rejects(
      () => service.resubmit(submitted.applicationNumber, submitted.statusToken, validInput({
        email: 'new@example.com',
        vehiclePlateNumber: 'NEW-1',
      })),
      (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
    );

    await service.reject(1, { rejectionReason: 'Retry with updated docs' }, { id: 7, role: 'ADMIN' });
    const resubmitted = await service.resubmit(
      submitted.applicationNumber,
      submitted.statusToken,
      validInput({ vehiclePlateNumber: 'NEW-1' }),
    );

    assert.equal(repository.applications.length, 2);
    assert.equal(repository.applications[0].status, 'REJECTED');
    assert.equal(repository.applications[1].status, 'PENDING');
    assert.equal(repository.applications[1].resubmitted_from_application_id, 1);
    assert.notEqual(resubmitted.applicationNumber, submitted.applicationNumber);
    assert.notEqual(resubmitted.statusToken, submitted.statusToken);
  });

  test('approve creates user, profile driver, vehicle, audit log, and clears application password hash', async () => {
    const { repository, service } = createHarness();
    await service.submit(validInput());

    const result = await service.approve(1, { adminNote: 'Approved for MVP' }, { id: 7, role: 'ADMIN' });

    assert.equal(result.status, 'APPROVED');
    assert.equal(repository.users.length, 1);
    assert.equal(repository.users[0].role, 'DRIVER');
    assert.equal(repository.users[0].is_active, 1);
    assert.equal(repository.drivers.length, 1);
    assert.equal(repository.drivers[0].status, 'OFFLINE');
    assert.equal(repository.drivers[0].is_online, 0);
    assert.equal(repository.driverVehicles.length, 1);
    assert.equal(repository.driverVehicles[0].is_primary, 1);
    assert.equal(repository.applications[0].status, 'APPROVED');
    assert.equal(repository.applications[0].password_hash, null);
    assert.equal(repository.applications[0].approved_user_id, result.approvedUserId);
    assert.equal(repository.applications[0].approved_driver_id, result.approvedDriverId);
    assert.equal(repository.applications[0].approved_at, '2026-07-03 11:00:00');
    assert.equal(repository.applications[0].approved_by, 7);
    assert.equal(repository.auditLogs[0].action, 'driver_application.approved');

    await assert.rejects(
      () => service.approve(1, { adminNote: 'Again' }, { id: 7, role: 'ADMIN' }),
      (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
    );
  });
});
