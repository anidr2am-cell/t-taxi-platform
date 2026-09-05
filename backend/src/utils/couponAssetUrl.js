function customerCouponImageUrl(couponId) {
  return `/api/v1/customer/coupons/${couponId}/image`;
}

function adminCouponTemplateImageUrl(templateId) {
  return `/api/v1/admin/coupon-templates/${templateId}/image`;
}

module.exports = {
  customerCouponImageUrl,
  adminCouponTemplateImageUrl,
};
