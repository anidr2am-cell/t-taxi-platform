const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');

const getCouponService = () => container.get('couponService');

const searchCustomers = asyncHandler(async (req, res) => {
  const customers = await getCouponService().searchCustomers(req.query.query);
  return success(res, customers, 'OK');
});

const issueCoupon = asyncHandler(async (req, res) => {
  const coupon = await getCouponService().issueCoupon({
    customerUserId: req.body.customerUserId,
    title: req.body.title,
    discountAmount: req.body.discountAmount,
    issuedByAdminId: req.user.id,
  });
  return success(res, coupon, 'Coupon issued', 201);
});

const cancelCoupon = asyncHandler(async (req, res) => {
  await getCouponService().cancelCoupon(Number(req.params.id));
  return success(res, null, 'Coupon cancelled');
});

const listRecentCoupons = asyncHandler(async (req, res) => {
  const coupons = await getCouponService().listRecentIssued(req.query.limit);
  return success(res, coupons, 'OK');
});

const listMyCoupons = asyncHandler(async (req, res) => {
  const coupons = await getCouponService().listCouponsForCustomer(req.user.id);
  return success(res, coupons, 'OK');
});

module.exports = {
  searchCustomers,
  issueCoupon,
  cancelCoupon,
  listRecentCoupons,
  listMyCoupons,
};
