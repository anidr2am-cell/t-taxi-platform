function adminHomeBannerImageUrl(bannerId) {
  return `/api/v1/admin/home-banners/${bannerId}/image`;
}

function publicHomeBannerImageUrl(bannerId) {
  return `/api/v1/public/home-banners/${bannerId}/image`;
}

module.exports = {
  adminHomeBannerImageUrl,
  publicHomeBannerImageUrl,
};
