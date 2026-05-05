class AppLinks {
  AppLinks._();

  static const String appleStore =
      'https://apps.apple.com/us/app/flex-facility/id6755446262';

  static String playStoreReferral(String referralCode) {
    return 'https://play.google.com/store/apps/details?id=com.yourfitnessapp&referrer=referral_code%3D$referralCode';
  }
}
